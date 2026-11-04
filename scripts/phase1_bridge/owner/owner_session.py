"""Offline same-job owner kernel; a reviewed entry/controller must bind runtime.

No CLI automatically discovers credentials or starts a VM. The entry supplies
the exact controller, channel, packager, job key and pinned Root public key.
"""
from dataclasses import dataclass, replace
from datetime import datetime, timezone
import contextlib
import copy
import hashlib
import os
from pathlib import Path
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'protocol'))
import review_protocol as protocol
import grants
from command_transport import ChannelRefused


class OwnerRefused(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise OwnerRefused(code)


@dataclass(frozen=True)
class Budget:
    work_seconds: int = 5400
    cleanup_seconds: int = 600
    hold_seconds: int = 300
    poll_seconds: int = 5

    def validate(self):
        require(type(self.work_seconds) is int and 600 <= self.work_seconds <= 5400
                and type(self.cleanup_seconds) is int and 60 <= self.cleanup_seconds <= 600
                and type(self.hold_seconds) is int and 30 <= self.hold_seconds <= 360
                and type(self.poll_seconds) is int and 2 <= self.poll_seconds <= 20,
                'owner_budget_invalid')


class Clock:
    def monotonic(self): return time.monotonic()
    def utc(self): return datetime.now(timezone.utc)
    def wait(self, event, seconds): event.wait(seconds)


@dataclass(frozen=True)
class OwnerResult:
    reason_code: str
    collected: bool
    cleanup_confirmed: bool
    runtime_ended: bool
    phase1_accepted: bool = False


class OwnerSession:
    def __init__(self, *, root, controller, channel, packager, job_key,
                 root_public, checkpoint_io, budget=Budget(), clock=None):
        budget.validate()
        self.root = Path(root)
        self.controller, self.channel, self.packager = controller, channel, packager
        self.job_key, self.root_public, self.io = job_key, root_public, checkpoint_io
        self.budget, self.clock = budget, clock or Clock()
        self._stop = threading.Event()
        self._authority = None
        self._input_context = None
        self._cleanup_used = False
        self._seed = None
        self._known_property = None
        self._context = None
        self._previous_result_sha = '0' * 64
        self._started = self.clock.monotonic()
        self.work_deadline = self._started + budget.work_seconds
        self.total_deadline = self.work_deadline + budget.cleanup_seconds
        self.cleanup_deadline = None
        self.ledger = protocol.ConsumeLedger(self.root / 'command-ledger')

    @property
    def active_authority(self):
        return self._authority

    @property
    def current_input_context(self):
        return self._input_context

    @property
    def current_context(self):
        # Keep this independent from the authority object: the adapter compares
        # its own active owner admission against the authority's bound context.
        return self._input_context if self._authority is not None else self._context

    def request_stop(self, *_):
        # Safe as an idempotent SIGTERM/SIGINT handler; never raise into cleanup.
        if self._stop.is_set():
            return
        self._stop.set()
        if self._authority is not None:
            self._authority.revoke()

    @contextlib.contextmanager
    def _using(self, authority, context):
        require(self._authority is None, 'one_owner_authority_required')
        require(isinstance(context, protocol.Context) and context == authority.context,
                'independent_input_context_required')
        self._authority = authority
        self._input_context = context
        try:
            yield
        finally:
            authority.revoke()
            self._authority = None
            self._input_context = None

    def _work_current(self):
        require(not self._stop.is_set(), 'owner_stop_requested')
        require(self.clock.monotonic() < self.work_deadline, 'owner_work_deadline')

    def _fixture_summary(self):
        value = self.controller.fixture_summary()
        require(type(value) is dict and set(value) == {'fixture', 'baseline'}, 'minimal_fixture_summary_required')
        selected = copy.deepcopy(value)
        fixture, baseline = selected['fixture'], selected['baseline']
        if self._seed is None:
            self._seed = copy.deepcopy(selected)
        else:
            expected = self._seed['fixture']
            require(all(fixture.get(key) == expected.get(key) for key in ['draft_uuid', 'tag', 'actor_id'])
                    and baseline == self._seed['baseline'], 'original_fixture_and_baseline_required')
        property_id = fixture.get('property_id')
        if property_id is not None:
            require(type(property_id) is int and property_id > 0, 'positive_property_identity_required')
            if self._known_property is None:
                require(self.controller.validate_promoted_identity(property_id) is True,
                        'fresh_promoted_pair_pin_required')
                self._known_property = property_id
            else:
                require(property_id == self._known_property, 'same_promoted_property_required')
        elif self._known_property is not None:
            require(self.controller.fixture_removed_confirmed() is True, 'promoted_link_disappeared_unproven')
        return selected

    def _seal(self, *, kind, phase, cursor, stage, evidence, summary=None):
        seq = self.packager.max_allocated + 1
        if kind == 'terminal_checkpoint':
            seq = max(1, seq)
        if summary is None:
            fixture = baseline = None
        else:
            fixture, baseline = summary['fixture'], summary['baseline']
        return self.packager.seal(seq=seq, kind=kind, phase=phase, cursor=cursor,
            fixture=fixture, baseline=baseline, stage=stage, evidence=evidence,
            prev_result_sha=self._previous_result_sha,
            created_utc=self.clock.utc().strftime('%Y-%m-%dT%H:%M:%SZ'))

    def _upload(self, sealed, *, cleanup=False):
        limit = self.cleanup_deadline if cleanup else self.work_deadline
        deadline = min(limit, self.clock.monotonic() + 120)
        require(self.io.announce_and_wait(sealed, deadline, self._stop,
                                       cleanup=cleanup) is True, 'checkpoint_upload_not_confirmed')

    def _initial_context(self):
        identity = self.packager.identity
        return protocol.Context(identity['repo'], identity['run_id'], identity['run_attempt'],
            identity['source_sha'], identity['toolbundle_sha'], 1, 'C1', 'INITIAL_C1',
            os.urandom(32).hex(), '0' * 64,
            self._previous_result_sha)

    def _one_command(self, sealed, snapshot):
        context = sealed.held_context
        if type(context) is dict:
            require(set(context) == set(protocol.CONTEXT_KEYS), 'held_protocol_context_required')
            context = protocol.Context(**context)
        require(isinstance(context, protocol.Context), 'held_protocol_context_required')
        self._context = context
        wait_deadline = min(self.work_deadline, self.clock.monotonic() + self.budget.hold_seconds)
        while True:
            self._work_current()
            require(self.clock.monotonic() < wait_deadline, 'root_review_wait_expired')
            raw = self.channel.poll(context.seq)
            self._work_current()
            require(self.clock.monotonic() < wait_deadline, 'root_review_wait_expired')
            if raw is None:
                self.clock.wait(self._stop, min(self.budget.poll_seconds,
                                wait_deadline - self.clock.monotonic()))
                continue
            received_utc, received_mono = self.clock.utc(), self.clock.monotonic()
            try:
                validated = protocol.validate_command(raw, context, self.root_public,
                    self.job_key, received_utc, forbidden_values=self.controller.private_aliases())
                envelope = protocol.parse_json(raw, protocol.MAX_ENVELOPE_BYTES)
            except protocol.Refused:
                # No reservation or input occurred. A new valid signed envelope
                # may replace an invalid/unconsumed command at this fixed path.
                self.io.status('COMMAND_REFUSED', context.seq)
                self.clock.wait(self._stop, self.budget.poll_seconds)
                continue

            def dispatch(op, review):
                if op in {'reject', 'finish'}:
                    self.request_stop()
                    return True
                self._work_current()
                require(self.clock.monotonic() < wait_deadline, 'root_review_wait_expired')
                authority = grants.issue_verified(validated=validated, context=context,
                    issued_utc=envelope['issued_utc'], received_utc=received_utc,
                    received_monotonic=received_mono, work_deadline=self.work_deadline,
                    utc_clock=self.clock.utc, monotonic_clock=self.clock.monotonic)
                with self._using(authority, context):
                    return self.controller.advance(review) is True

            receipt = protocol.receive(raw, context=context, root_public=self.root_public,
                job_key=self.job_key, ledger=self.ledger, now=received_utc,
                fresh_scene_check=lambda review: self.controller.fresh_scene_matches(review, snapshot),
                dispatch=dispatch, forbidden_values=self.controller.private_aliases())
            require(receipt.status == 'executed' and receipt.outcome == 'completed',
                    'segment_not_confirmed')
            self._previous_result_sha = hashlib.sha256(protocol.canonical({
                'status': receipt.status, 'seq': receipt.seq, 'command_sha': receipt.command_sha,
                'outcome': receipt.outcome})).hexdigest()
            return validated.op

    def run(self):
        reason, collected = 'OWNER_STAGE_FAILED', False
        cleanup_confirmed, runtime_ended = False, False
        runtime_receipt = {'vm_created': None, 'relay_created': None,
                           'vm_exit_code': None, 'relay_exit_code': None,
                           'owned_process_group_absence_observed': False,
                           'all_created_processes_observed_ended': False}
        try:
            self._work_current()
            # VM boot only. Installation/startup/public-feed input is admitted
            # below under one distinct source-plan lease, never a Root review.
            self.controller.prepare_runtime()
            self._work_current()
            self._context = self._initial_context()
            initial_authority = grants.issue_initial(context=self._context,
                start_monotonic=self.clock.monotonic(), work_deadline=self.work_deadline,
                monotonic_clock=self.clock.monotonic)
            with self._using(initial_authority, self._context):
                require(self.controller.prepare_initial_native() is True,
                        'fresh_native_public_network_not_proven')
                self._work_current()
                initial_authority.require_current(self._context)
                self.controller.bootstrap_fixture()
                summary = self._fixture_summary()
                self.controller.quiesce_for_checkpoint()
                initial = self._seal(kind='fixture_checkpoint', phase='C1', cursor='PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP',
                    stage={'report_scope': 'API title bootstrap already occurred; checkpoint precedes initial C1 native edits'},
                    evidence=[], summary=summary)
                self._upload(initial)
                self._work_current()
                initial_authority.require_current(self._context)
                require(self.controller.initial_c1() is True, 'initial_c1_not_collected')
            while True:
                self._work_current()
                if self.controller.finished() is True:
                    reason, collected = 'COLLECTED_PENDING_ROOT_ACCEPTANCE', True
                    break
                self.controller.quiesce_for_checkpoint()
                summary = self._fixture_summary()
                snapshot = self.controller.snapshot()
                require(type(snapshot) is dict and set(snapshot) == {'phase', 'cursor', 'stage', 'evidence'},
                        'fixed_stage_snapshot_required')
                sealed = self._seal(kind='review_checkpoint', summary=summary, **snapshot)
                self._upload(sealed)
                op = self._one_command(sealed, snapshot)
                if op in {'reject', 'finish'}:
                    reason = 'ROOT_REJECTED' if op == 'reject' else 'ROOT_FINISHED_EARLY'
                    break
        except BaseException:
            # Never print a callback exception, traceback, command or auth value.
            reason = 'OWNER_STOP_REQUESTED' if self._stop.is_set() else 'OWNER_STAGE_FAILED'
        finally:
            self.request_stop()
            self.cleanup_deadline = min(self.total_deadline,
                                        self.clock.monotonic() + self.budget.cleanup_seconds)
            cleanup_context = replace(self._context, phase='C5', cursor='OWNER_CLEANUP') if self._context else None
            try:
                require(not self._cleanup_used, 'cleanup_single_attempt_required')
                self._cleanup_used = True
                if cleanup_context is not None:
                    lease = grants.issue_cleanup(context=cleanup_context,
                        cleanup_deadline=self.cleanup_deadline, uncertain=self.controller.uncertain() is True,
                        utc_clock=self.clock.utc, monotonic_clock=self.clock.monotonic)
                    with self._using(lease, cleanup_context):
                        self.controller.stop_writers(deadline=self.cleanup_deadline)
                        cleanup_confirmed = self.controller.cleanup_once(deadline=self.cleanup_deadline) is True
                else:
                    # Before any signed checkpoint the controller's fixed
                    # source-plan teardown can only stop owned processes and
                    # clean its known partial bootstrap; no phase extension.
                    self.controller.stop_writers(deadline=self.cleanup_deadline)
                    cleanup_confirmed = self.controller.cleanup_once(deadline=self.cleanup_deadline) is True
            except BaseException:
                cleanup_confirmed = False
            try:
                observed = self.controller.close_runtime(deadline=self.cleanup_deadline)
                if type(observed) is dict:
                    for key in ['vm_created', 'relay_created']:
                        value = observed.get(key)
                        runtime_receipt[key] = value if type(value) is bool else None
                    for key in ['vm_exit_code', 'relay_exit_code']:
                        value = observed.get(key)
                        runtime_receipt[key] = value if type(value) is int else None
                    runtime_receipt['owned_process_group_absence_observed'] = observed.get('owned_process_group_absence_observed') is True
                    flags_observed = all(type(runtime_receipt[key]) is bool for key in ['vm_created', 'relay_created'])
                    codes_match = all((runtime_receipt[kind + '_created'] is False and runtime_receipt[kind + '_exit_code'] is None)
                        or (runtime_receipt[kind + '_created'] is True and type(runtime_receipt[kind + '_exit_code']) is int)
                        for kind in ['vm', 'relay'])
                    group_ended = runtime_receipt['vm_created'] is False or runtime_receipt['owned_process_group_absence_observed'] is True
                    runtime_ended = (observed.get('all_created_processes_observed_ended') is True
                                     and flags_observed and codes_match and group_ended)
                    runtime_receipt['all_created_processes_observed_ended'] = runtime_ended
            except BaseException:
                runtime_ended = False
            try:
                terminal_summary = copy.deepcopy(self._seed)
                if terminal_summary is not None:
                    terminal_summary['fixture']['property_id'] = self._known_property
                terminal = self._seal(kind='terminal_checkpoint', phase='C5', cursor='OWNER_TERMINAL',
                    stage={'report_scope': reason, 'postconditions': {
                        'collected': collected, 'cleanup_confirmed': cleanup_confirmed,
                        'runtime': runtime_receipt, 'phase1_accepted': False}}, evidence=[],
                    summary=terminal_summary)
                self._upload(terminal, cleanup=True)
            except BaseException:
                reason = 'TERMINAL_CHECKPOINT_UNPROVEN'
            try:
                self.controller.clear_private_state()
            except BaseException:
                reason = 'PRIVATE_STATE_CLEAR_UNPROVEN'
            finally:
                self.job_key.close()
                self.channel.close()
                self.ledger.close()
                self.packager.close()
        return OwnerResult(reason, collected, cleanup_confirmed, runtime_ended)


if __name__ == '__main__':
    # The final reviewed entry must construct the fixed real controller and call
    # OwnerSession.run. A generic proposal must never accidentally start work.
    raise SystemExit('AQER_OWNER_ENTRY_NOT_WIRED')
