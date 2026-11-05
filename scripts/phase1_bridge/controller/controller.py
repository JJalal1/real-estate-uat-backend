"""Dependency-injected same-job controller; import performs no runtime work.

Signed command authority is issued by OwnerSession, never by this module.
Original phase executors perform all native actions and acceptance predicates.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import threading
import time
import uuid

from ci_remote_evidence import C4_EXTRA, frames_wire, fresh_remote_review, video_wire
from bounded_api import BoundedApiFactory, DeadlineTransport, read_public_with_retry


class ControllerRefused(RuntimeError):
    """Fixed codes only; do not export raw Python exceptions or tracebacks."""


def need(ok, code):
    if not ok:
        raise ControllerRefused(code) from None


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(',', ':'), allow_nan=False).encode()).hexdigest()


class CountOnlyActions(list):
    """Checked delivery counts, never a contact/auth selected-node hash log."""
    def __init__(self, values=()):
        super().__init__()
        for value in values: self.append(value)

    def append(self, value):
        need(type(value) is dict and value.get('kind') in {'click', 'set', 'scroll'}
             and type(value.get('authenticated')) is bool,
             'fixed_native_action_receipt_required')
        projected = {'kind': value['kind']}
        if 'delivery' in value:
            need(value['delivery'] in {'pointer_swipe', 'pointer_focus', 'pointer_tap',
                                      'semantic_text', 'semantic_action'}, 'fixed_native_delivery_required')
            projected['delivery'] = value['delivery']
        if 'native_pointer_events' in value:
            need(type(value['native_pointer_events']) is int and value['native_pointer_events'] in {0,2,14},
                 'fixed_native_event_count_required')
            projected['native_pointer_events'] = value['native_pointer_events']
        super().append(projected)


def exclusive(method):
    def guarded(self, *args, **kwargs):
        need(self._transaction.acquire(blocking=False), 'controller_transaction_inflight')
        try:
            return method(self, *args, **kwargs)
        finally:
            self._transaction.release()
    return guarded


C4_FILES = {cursor: 'C4_ROOT_' + cursor + '.json' for cursor in C4_EXTRA}
C4_FILES['C1_REVIEW'] = 'C4_ROOT_C1_REVIEW.json'
ROOT_KEYS = {'review_completed_utc', 'checkpoint_binding_sha256'}
C1_FAILURE_CODES = frozenset({
    'private_c1_home_capture_refused', 'actual_broker_home_required',
    'unique_visible_broker_home_anchor_required', 'actual_home_anchor_identity_required',
    'visible_home_anchor_bounds_required', 'fixed_initial_c1_home_scope_required',
    'initial_source_home_capture_only', 'fixed_initial_home_capture_name_required',
    'initial_home_capture_already_exists', 'owned_home_capture_directory_required',
    'unique_actual_home_console_png_required', 'broker_home_binding_changed_during_capture',
    'home_png_destination_write_refused', 'private_home_png_write_unconfirmed',
    'host_capture_directory_rejected', 'host_console_command_not_confirmed',
    'host_capture_fresh_tree_invalid', 'host_png_invalid', 'host_png_crc_invalid',
    'host_png_dimensions_or_structure_invalid', 'actual_visible_loaded_basics_required',
    'unique_visible_basics_anchor_required', 'actual_basics_anchor_identity_required',
    'visible_basics_anchor_bounds_required', 'private_c1_basics_capture_refused',
    'basics_binding_changed_during_capture', 'private_or_contact_capture_refused',
    'authenticated_editor_capture_required', 'authentication_capture_refused',
    'native_named_add_not_stable', 'native_owned_saved_fixture_not_observed',
    'native_owned_editor_title_not_observed', 'native_owned_editor_title_mismatch',
    'native_basic_editor_context_changed', 'native_basic_editor_purpose_not_observed',
    'deadline_helper_preflight_refused', 'owner_input_authority_refused',
    'instrumentation_completion_uncertain', 'actual_c1_case_pass_required',
    'scrollable_native_container_missing', 'named_native_control_not_found',
    'expected_native_state_not_observed', 'native_owned_editor_title_ambiguous',
    'fixed_native_journey_stage_required', 'safe_basic_editor_anchor_not_observed',
    'native_owned_editor_title_not_stable',
    'genuine_os_photo_selection_not_observed', 'genuine_os_picker_return_not_observed',
    'private_transition_during_os_picker', 'fresh_os_picker_tree_unavailable', 'os_picker_bounds_invalid',
    'native_broker_home_not_observed', 'fixed_initial_navigation_target_required',
    'host_webm_file_invalid', 'host_webm_ebml_invalid', 'host_webm_probe_failed',
    'host_webm_stream_or_duration_invalid', 'tainted_host_video_discarded',
    'host_video_name_already_exists', 'host_record_stop_unconfirmed_abort_ui',
    'c1_monthly_rent_readback_scope_required', 'c1_monthly_rent_not_exactly_blank',
})
C1_FAILURE_STAGES = frozenset({'manual_entry', 'selected_fixture', 'editor_wait', 'editor_ready',
    'purpose', 'type', 'title', 'location_step', 'location_confirm', 'governorate', 'city',
    'specifications_step', 'floor_select', 'bedrooms', 'bathrooms', 'parking_select', 'facade_select',
    'photo_select', 'photo_picker_open', 'photo_file_select', 'photo_final_select',
    'photo_app_return', 'photo_count_wait', 'photo_capture', 'photo_next_dispatch', 'final_actions_wait',
    'rent_blank_check', 'draft_save', 'restore_startup',
    'restore_specs', 'restore_bedrooms', 'restore_bathrooms', 'restore_photo', 'restore_location',
    'restore_title', 'restore_options_wait', 'restore_rent_blank_check', 'editor_basics_loaded', 'editor_title_settle',
    'editor_title_seek', 'editor_basics_return', 'home_wait', 'home_dispatch', 'add_stable_wait', 'add_dispatch'})
HOME_DIAGNOSTIC_NAMES = frozenset({'C1-before-add-home.png', 'C1-restore-before-add-home.png'})
HOME_DIAGNOSTIC_SCOPE = 'authenticated_broker_marketplace_before_add'
HOME_DIAGNOSTIC_KEYS = frozenset({'file', 'bytes', 'sha256', 'width', 'height', 'capture',
    'authenticated_editor_only', 'authenticated_broker_home_only', 'capture_scope',
    'privacy_before_and_after', 'home_binding_unchanged'})
GUEST_STAGES = {'broker_login_for_submit', 'broker_login_for_reason', 'support_login', 'regular_login',
                'stop_writers_for_pin', 'stop_writers_for_cleanup'}
LOGIN_STAGES = {'broker_login_for_submit', 'broker_login_for_reason', 'support_login', 'regular_login'}
API_STAGES = {'pin_promotion', 'cleanup'}
NONIMAGE_RENT = {'complete_rent', 'navigate_previous_to_specs', 'back_gaps_to_completion', 'full_save'}


class Controller:
    def __init__(self, *, probe, c4, c2, dispatcher, fixture_api_class,
                 public_reference_reader, boot_runtime, close_runtime,
                 authority_getter, context_getter, work_deadline_getter,
                 monotonic_clock=time.monotonic, wait=time.sleep,
                 api_transport=None, app='com.aqer.yemen.uat', entry_mode='c4_then_c2'):
        callbacks = (public_reference_reader, boot_runtime, close_runtime, authority_getter,
                     context_getter, work_deadline_getter, monotonic_clock, wait)
        need(all(callable(f) for f in callbacks), 'controller_callbacks_required')
        self.probe, self.c4, self.c2, self.dispatcher = probe, c4, c2, dispatcher
        need(entry_mode in {'c4_then_c2', 'c2_only'}, 'fixed_controller_entry_mode_required')
        self._entry_mode = entry_mode
        probe._root_c2_entry_mode = entry_mode
        self._reference, self._boot, self._close = public_reference_reader, boot_runtime, close_runtime
        self._authority, self._context = authority_getter, context_getter
        self._work_deadline, self._mono, self._wait = work_deadline_getter, monotonic_clock, wait
        self.app = app
        self._transaction = threading.RLock()
        self._api_limit = None
        self._api_mode = None
        self._transport = api_transport or DeadlineTransport(deadline_getter=self._api_deadline,
                                                            monotonic_clock=self._mono)
        # Even injected transports must expose this binding: it is not optional
        # for bootstrap, public reference or normal C2/cleanup API sessions.
        need(getattr(self._transport, 'deadline_getter', None) == self._api_deadline,
             'controller_bound_api_transport_required')
        self._api_factory = BoundedApiFactory(fixture_api_class, self._transport)
        self._booted = self._boot_attempted = self._native_attempted = False
        self._native_ready = self._bootstrap_used = self._initial_used = False
        self._root_preflight_done = False
        self._advance_failed = self._cleanup_used = self._stop_used = False
        self._writers_stopped = self._native_logout = self._removed = False
        self._cleanup_receipt = self._runtime_receipt = self._snapshot = None
        self._close_used = False
        self._promotion_pin = None
        self._promotion_pin_at = None
        probe.report['actions'] = CountOnlyActions(probe.report.get('actions', []))
        probe.report['native_action_hashes_recorded'] = False
        probe.report['scope'] = ('Same-job C1 collection with signed C4/C2 continuation; '
                                 'actual executor records define progress')
        probe.report['limitations'] = [
            'C4/C2 require actual Root media review and original executor postconditions',
            'API36 KVM functional evidence, not a physical handset/performance claim']
        if entry_mode == 'c2_only':
            probe.report['scope'] = 'Same-job native C1 fixture preparation with signed C2 continuation only'
            probe.report['c2_entry_mode'] = 'standard_editor'
            probe.report['current_run_c4_executed'] = False
            probe.report['limitations'][0] = 'C2 requires actual current fixture and stage reviews; prior C4 acceptance is separate'
        # Exact same module identity as the installed RAM KnownRoleMemory.
        probe._root_extension_dispatch_v2_modules = {'C4': c4, 'C2': c2}

    def __repr__(self):
        return '<Controller exclusive one-shot phase owner>'

    def _guard(self, kind, category='media_write'):
        authority, context = self._authority(), self._context()
        need(authority is not None and authority.authority_kind == kind,
             'controller_authority_scope_required')
        if kind == 'OWNER_CLEANUP':
            need(context.phase == 'C5' and context.cursor == 'OWNER_CLEANUP',
                 'fixed_owner_cleanup_required')
            category = 'app_stop'  # Fixed API cleanup scope, never generic UI/media.
        need(authority.require_input(context, category) is True, 'controller_authority_expired')
        return authority

    def _api_deadline(self):
        need(self._api_mode in {'source', 'advance', 'cleanup'} and self._api_limit is not None,
             'fixed_api_scope_required')
        kind = {'source': 'SOURCE_PLAN_ONLY', 'advance': 'ROOT_VERIFIED', 'cleanup': 'OWNER_CLEANUP'}[self._api_mode]
        self._guard(kind)
        need(self._mono() < self._api_limit, 'api_scope_deadline_expired')
        return self._api_limit

    @contextlib.contextmanager
    def _api_scope(self, mode, deadline=None):
        need(self._api_mode is None, 'serialized_api_scope_required')
        limit = self._work_deadline() if deadline is None else deadline
        authority = self._authority()
        need(authority is not None and type(authority.monotonic_deadline) in (int, float),
             'actual_authority_deadline_required')
        limit = min(limit, authority.monotonic_deadline)
        need(type(limit) in (int, float) and self._mono() < limit, 'bounded_api_deadline_required')
        self._api_mode, self._api_limit = mode, limit
        try:
            self._api_deadline()
            yield
        finally:
            self._api_mode = self._api_limit = None

    def _within(self, deadline):
        need(type(deadline) in (int, float) and self._mono() < deadline, 'controller_deadline_expired')

    @exclusive
    def prepare_runtime(self):
        need(not self._boot_attempted, 'runtime_boot_already_consumed')
        self._boot_attempted = True
        # This callback boots only the owned VM; no install, UI or API work.
        self._boot(deadline=self._work_deadline())
        self._booted = True

    @exclusive
    def prepare_initial_native(self):
        need(self._booted and not self._native_attempted and not self._bootstrap_used,
             'initial_native_order_required')
        self._native_attempted = True
        self._guard('SOURCE_PLAN_ONLY')
        p = self.probe
        p.case_phase('C1-native-network')
        for stage, callback in [('install', p.validate_and_install),
                                ('display', p.configure_host_display),
                                ('startup', p.startup),
                                ('helper_clock_preflight', p.preflight_deadline_helper)]:
            p.report['initial_native_readiness_stage'] = stage
            p.save()
            callback()
        p.report['initial_native_readiness_stage'] = 'public_reference'
        p.save()
        # Same actual published-card prerequisite as the source collector, with
        # bounded transport injected before the first public HTTP operation.
        with self._api_scope('source'):
            def public_diagnostic(value):
                p.report.setdefault('public_reference_attempts', []).append(value)
                p.save()
            references = read_public_with_retry(self._reference, self._transport,
                diagnostic=public_diagnostic, wait=self._wait)
            need(type(references) is list and 0 < len(references) <= 50, 'actual_public_reference_required')
            p.report['initial_native_readiness_stage'] = 'native_public_card'
            p.save()
            until = min(self._work_deadline(), self._mono() + 60)
            scrolls = 0
            while self._mono() < until:
                self._guard('SOURCE_PLAN_ONLY')
                rows = p.nodes()
                matches = [row for row in references if p.matching(rows, row['title'])]
                if matches:
                    p.mark('C1-native-network', 'PASS', real_published_card_observed=True,
                        public_reference_count=len(references), public_reference_sha256=digest(references),
                        visible_match_count=len(matches), visible_match_sha256=digest(matches),
                        default_network=True, host_reference_is_not_native_network_trace=True,
                        acceptance_scope='prerequisite only')
                    self._native_ready = True
                    return True
                if scrolls < 4:
                    p.scroll()
                    scrolls += 1
                self._wait(min(1, max(0, until - self._mono())))
        return False

    @exclusive
    def bootstrap_fixture(self):
        need(self._native_ready and not self._bootstrap_used, 'network_before_single_bootstrap_required')
        self._bootstrap_used = True
        self._guard('SOURCE_PLAN_ONLY')
        p = self.probe
        p.case_phase('C1-api-empty-fixture')
        p.require_preauth_runtime()
        p.fixture_api = self._api_factory(p.access['phones']['broker'], p.access['otp'], p.env['GITHUB_RUN_ID'])
        try:
            with self._api_scope('source'):
                p.fixture_api.bootstrap()
        finally:
            state = p.fixture_api.state
            if state:
                p.fixture_possible = state.get('creation_request_sent') is True
                p.report['fixture_key'], p.report['fixture_tag'] = state.get('key'), state.get('tag')
            p.report['api_bootstrap'] = p.fixture_api.last_receipt
            p.save()
        state = p.fixture_api.state
        need(type(state) is dict and state.get('created_confirmed') is True,
             'actual_confirmed_title_bootstrap_required')
        receipt = p.fixture_api.last_receipt or {}
        need(receipt.get('status') == 'PASS' and receipt.get('fresh_session_cleaned') is True
             and receipt.get('identity', {}).get('actor_id') == 28
             and receipt.get('identity', {}).get('account_type') == 'broker',
             'actual_bootstrap_identity_and_revocation_required')
        p.bootstrap_title = state['title']
        p.title = 'اختبار استعادة المسودة ' + state['tag']
        p.report['fixture_title'] = p.title
        p.mark('C1-api-empty-fixture', 'PASS', native_creation_claim=False,
            bootstrap_fields=['synthetic_title_label_only'], property_created=False,
            photos_uploaded=False, facts_entered=False, api_session_logged_out=True)
        self.fixture_summary()  # Validate fixed identity/baseline before native edits.

    @exclusive
    def initial_c1(self):
        need(self._native_ready and self._bootstrap_used and not self._initial_used,
             'single_initial_c1_required')
        self._initial_used = True
        self._guard('SOURCE_PLAN_ONLY')
        if self.probe.adapter is None:
            self.probe.start_session()  # Reopen admission after fixture0 ACK, not a new lease.
        for case, method in [('C1-auth', self.probe.login), ('C1-photo-save', self.probe.create_and_save),
                             ('C1-force-stop-restore', self.probe.restore)]:
            self._guard('SOURCE_PLAN_ONLY')
            self.probe.case_phase(case)
            try:
                method()
            except BaseException as failure:
                candidate = failure.args[0] if type(failure.args) is tuple and len(failure.args) == 1 else None
                code = candidate if type(candidate) is str and candidate in C1_FAILURE_CODES else 'controller_phase_failed'
                stage = self.probe.report.get('native_journey_stages', {}).get(case)
                self.probe.report.setdefault('initial_c1_failure_before_cleanup', {
                    'case': case, 'code': code,
                    'stage': stage if type(stage) is str and stage in C1_FAILURE_STAGES else None})
                self.probe.save()
                raise
            need(any(row.get('id') == case and row.get('status') == 'PASS'
                     for row in self.probe.report.get('cases', [])), 'actual_c1_case_pass_required')
        self.probe.hold_after_initial_c1()
        need({row.get('file') for row in self.probe.report.get('videos', [])} == {
            'C1-create-photo.webm', 'C1-restored-facts.webm'}, 'both_actual_c1_host_clips_required')
        self._media(['C1-restored-title.png', 'C1-restored-complete-photo.png',
                     'C1-create-photo.webm', 'C1-restored-facts.webm'])
        self.probe.preflight_deadline_helper()
        self.quiesce_for_checkpoint()
        return True

    def _state(self):
        value = getattr(getattr(self.probe, 'fixture_api', None), 'state', None)
        need(type(value) is dict, 'original_fixture_state_required')
        return value

    def fixture_summary(self):
        state = self._state()
        key, tag = state.get('key'), state.get('tag')
        try:
            valid = type(key) is str and str(uuid.UUID(key)) == key
        except (ValueError, AttributeError):
            valid = False
        need(valid and state.get('actor_id') == 28 and type(tag) is str
             and re.fullmatch(r'AQER-C1-[a-f0-9]{12}', tag), 'fixed_original_fixture_identity_required')
        baseline = state.get('baseline')
        need(type(baseline) is dict and set(baseline) == {'properties', 'drafts'}, 'fixed_baseline_required')
        reduced = {}
        for kind, count in [('properties', 25), ('drafts', 7)]:
            rows = baseline[kind]
            need(type(rows) is dict and len(rows) == count and all(type(v) is str
                and re.fullmatch(r'[a-f0-9]{64}', v) for v in rows.values()), 'fixed_baseline_digests_required')
            if kind == 'properties':
                need(all(type(k) is str and re.fullmatch(r'[1-9][0-9]{0,18}', k) for k in rows),
                     'baseline_property_identity_required')
            else:
                try:
                    valid = all(type(k) is str and str(uuid.UUID(k)) == k for k in rows)
                except (ValueError, AttributeError): valid = False
                need(valid and key not in rows, 'baseline_draft_identity_required')
            reduced[kind] = {'count': count, 'sha256': digest(rows)}
        executor = getattr(self.probe, '_root_c2_executor_v2', None)
        property_id = getattr(executor, 'property_id', None)
        need(property_id is None or type(property_id) is int and property_id > 0, 'promoted_identity_invalid')
        return {'fixture': {'draft_uuid': key, 'tag': tag, 'actor_id': 28, 'property_id': property_id},
                'baseline': reduced}

    def private_aliases(self):
        return tuple(sorted(value for value in self.probe.private_values if type(value) is str and value))

    def _c4_state(self):
        key, tag, title = self.c4.identity(self.probe)
        result = self.probe.report.setdefault(self.c4.KEY, {'schema': 1, 'cursor': 'C1_REVIEW',
            'fixture_key': key, 'fixture_tag': tag, 'title': title,
            'accepted': False, 'inflight': None, 'uncertain': False})
        need((result.get('fixture_key'), result.get('fixture_tag'), result.get('title')) == (key, tag, title),
             'same_c4_fixture_required')
        return result

    def _position(self):
        if self._entry_mode == 'c2_only':
            self._c1_entry_checks()
        else:
            c4 = self._c4_state()
            if c4.get('accepted') is not True:
                return 'C4', c4['cursor'], c4['cursor']
        executor = getattr(self.probe, '_root_c2_executor_v2', None)
        if executor is None:
            if self._entry_mode == 'c2_only':
                return 'C2', 'CONFIGURE_C2_FROM_C1', 'CONFIGURE_C2_FROM_C1'
            return 'C2', 'CONFIGURE_C2', 'CONFIGURE_C2'
        need(type(executor.cursor) is int and 0 <= executor.cursor <= len(self.c2.STAGES), 'c2_cursor_invalid')
        if executor.cursor == len(self.c2.STAGES): return 'C2', 'C2_COLLECTED', 'C2_COLLECTED'
        stage = self.c2.STAGES[executor.cursor]
        return 'C2', 'C2_' + str(executor.cursor) + '_' + stage.upper(), stage

    def _c1_entry_checks(self):
        p = self.probe
        need(self._initial_used and p.report.get('held_after_c1_restore_for_root_review') is True
             and self.c4.KEY not in p.report, 'actual_c1_only_entry_required')
        cases = p.report.get('cases', [])
        need(all(any(row.get('id') == name and row.get('status') == 'PASS' for row in cases)
                 for name in ('C1-photo-save', 'C1-force-stop-restore')),
             'actual_c1_fixture_cases_required')
        checks = p.report.get('c1_monthly_rent_blank_checks')
        need(type(checks) is dict and set(checks) == {'before_save', 'after_reopen'}
             and checks['before_save'] is True and checks['after_reopen'] is True,
             'actual_c1_blank_rent_checks_required')
        return dict(checks)

    def _media(self, names):
        p, result = self.probe, []
        all_rows = p.report.get('frames', []) + p.report.get('videos', [])
        for name in sorted(set(names)):
            need(type(name) is str and re.fullmatch(r'C[12]-[A-Za-z0-9_-]{1,120}\.(?:png|webm)', name),
                 'fixed_safe_media_basename_required')
            rows = [row for row in all_rows if row.get('file') == name]
            need(len(rows) == 1, 'unique_actual_media_receipt_required')
            row = rows[0]
            need(row.get('capture') in {'official_emulator_console_host_png', 'official_emulator_console_host_webm'},
                 'actual_host_console_provenance_required')
            if name.endswith('.png'):
                receipts = [r for r in p.report.get('c2_v2_safe_frames', []) if r.get('file') == name]
                need(row.get('authenticated_editor_only') is True or len(receipts) == 1
                     and receipts[0].get('privacy_before_and_after') is True,
                     'actual_safe_capture_predicate_required')
            else:
                need(row.get('authentication_frames') is False, 'actual_non_auth_clip_required')
            path = Path(p.out) / name
            need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 64 * 1024 * 1024,
                 'actual_media_file_required')
            info = path.stat()
            need(info.st_nlink == 1 and info.st_uid == os.geteuid()
                 and stat.S_IMODE(info.st_mode) == 0o600 and info.st_size > 0,
                 'actual_owned_private_media_required')
            need(hashlib.sha256(path.read_bytes()).hexdigest() == row.get('sha256'), 'actual_media_digest_changed')
            result.append({'file': name, 'sha256': row['sha256'], 'kind': name.rsplit('.', 1)[-1], 'capture': row['capture']})
        return result

    @contextlib.contextmanager
    def _read_session(self):
        need(not self.uncertain(), 'uncertain_runtime_no_scene_reads')
        opened = self.probe.adapter is None
        if opened: self.probe.start_session()
        try:
            yield
        finally:
            if opened and self.probe.adapter is not None:
                self.probe.stop_session('read_only_checkpoint_observation')

    def _safe_scene(self):
        rows = self.probe._capture_full_rows()
        need(not self.probe._capture_rows_private(rows), 'full_tree_private_scene_refused')
        return self.c4.scene([row for row in rows if row.get('visible')])

    def _nonimage_check(self, phase, stage):
        """Ephemeral checks only: never hash/persist contact/profile/auth rows."""
        p = self.probe
        if phase == 'C4':
            if stage == 'SAVE': self.c4.blank_rent(p)
            elif stage == 'REOPEN':
                need(self._c4_state().get('explicit_native_account_draft_save_delivered') is True,
                     'actual_explicit_save_required')
            return
        executor = getattr(p, '_root_c2_executor_v2', None)
        if executor is None: return
        if stage in API_STAGES:
            executor._guest()
            need(p.adapter is None, 'native_writers_closed_before_api')
            return
        if stage in LOGIN_STAGES:
            # APP may have been force-stopped for the preceding API stage.
            # Do not start it or run an APP-only snapshot outside a grant.
            # Original signed login calls startup and rechecks actual guest UI.
            executor._guest()
            need(p.adapter is None, 'login_boundary_admission_must_be_closed')
            return
        if stage in GUEST_STAGES:
            executor._guest()
            names = self.c2._names(p.nodes())
            need('تسجيل الدخول أو إنشاء حساب' in names and 'تسجيل الخروج' not in names
                 and not names & self.c2.roles.AUTH_LABELS, 'actual_guest_gate_required')
            return
        if stage == 'regular_isolation':
            need(executor._regular_account_semantics() == executor.regular_account_witness,
                 'actual_regular_nonimage_witness_changed')
            return
        if stage in {'navigate_previous_to_specs', 'back_gaps_to_completion'}:
            executor._actor('broker')
            previous = {'navigate_previous_to_specs':'complete_rent',
                        'back_gaps_to_completion':'return_next_step3'}[stage]
            receipts = p.report.get('c2_segmented_execution', [])
            last = receipts[-1] if type(receipts) is list and receipts else None
            preview = executor.rent_sai_readback
            need(type(last) is dict and last.get('status') == 'STAGE_COMPLETED'
                 and last.get('completed') == previous and last.get('next_stage') == stage
                 and last.get('cursor') == executor.cursor
                 and type(preview) is dict
                 and preview.get('kind') == 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW'
                 and type(preview.get('fallback_notice')) is str
                 and bool(preview['fallback_notice'])
                 and preview.get('recording_stopped') is True
                 and (stage != 'back_gaps_to_completion' or executor.rent_sai_recheck == preview),
                 'immediately_preceding_rent_sai_readback_required')
            # The preceding stage ended with actual rate/fallback readback.
            # Rent may now be above the viewport; observations must never seek.
            rows = p.nodes()
            names = self.c2._names(rows)
            standard = getattr(executor, 'entry_mode', None) == 'standard_editor'
            mode_control = 'خيارات المسودة' if standard else 'العودة إلى النواقص'
            control = 'السابق' if stage == 'navigate_previous_to_specs' else mode_control
            need({'نسبة السعي %', preview['fallback_notice'], mode_control} <= names
                 and any(row.get('enabled') is True for row in p.matching(rows, control))
                 and not names & self.c2.roles.AUTH_LABELS,
                 'actual_reviewed_rent_navigation_surface_required')
            return
        if stage == 'full_save':
            executor._actor('broker')
            # Returning to completion hides already completed rent/SAI inputs.
            # Bind their preceding serialized recheck, then observe this page.
            preview = executor.rent_sai_readback
            need(type(preview) is dict and bool(preview)
                 and executor.rent_sai_recheck == preview,
                 'same_actual_preview_required_before_completion_save')
            names = self.c2._names(p.nodes())
            expected = ({'خيارات المسودة', 'إرسال للمراجعة', 'نسبة السعي %', preview['fallback_notice']}
                        if getattr(executor, 'entry_mode', None) == 'standard_editor'
                        else {'أكمل الناقص فقط', 'خيارات المسودة'})
            need(expected <= names
                 and not names & self.c2.roles.AUTH_LABELS,
                 'actual_completion_save_surface_required')
            return
        if stage in NONIMAGE_RENT:
            executor._actor('broker')
            if stage == 'complete_rent':
                value = p.field('الإيجار الشهري بالريال اليمني *', seek=False).get('text')
                need(type(value) is str and not value.strip(),
                     'actual_blank_rent_required')
            else:
                need(executor._rent_sai_preview() == executor.rent_sai_readback,
                     'actual_nonimage_rent_sai_changed')
            return
        # Fixed actor/guest checks in original executor run again before input.
        # This readback retains no labels, nodes, hashes or auth captures.
        names = self.c2._names(p.nodes())
        need(not names & self.c2.roles.AUTH_LABELS, 'unexpected_auth_surface_refused')

    def _c1_acceptance_media_names(self):
        """Keep fixed Home diagnostics private; never admit them as editor proof."""
        names, excluded = [], set()
        for row in self.probe.report.get('frames', []):
            need(type(row) is dict, 'actual_frame_receipt_required')
            name = row.get('file')
            need(type(name) is str, 'actual_frame_basename_required')
            candidate = (name in HOME_DIAGNOSTIC_NAMES or row.get('capture_scope') == HOME_DIAGNOSTIC_SCOPE
                         or row.get('authenticated_broker_home_only') is True)
            if candidate:
                need(set(row) == HOME_DIAGNOSTIC_KEYS and name in HOME_DIAGNOSTIC_NAMES
                     and name not in excluded and row['capture_scope'] == HOME_DIAGNOSTIC_SCOPE
                     and row['capture'] == 'official_emulator_console_host_png'
                     and row['authenticated_editor_only'] is False
                     and row['authenticated_broker_home_only'] is True
                     and row['privacy_before_and_after'] is True and row['home_binding_unchanged'] is True
                     and type(row['width']) is int and row['width'] == 540
                     and type(row['height']) is int and row['height'] == 960
                     and type(row['bytes']) is int and 32 <= row['bytes'] <= 32 * 1024 * 1024
                     and type(row['sha256']) is str and re.fullmatch(r'[a-f0-9]{64}', row['sha256']) is not None,
                     'malformed_home_diagnostic_not_acceptance_media')
                excluded.add(name)
                continue
            names.append(row['file'])
        return names + [row['file'] for row in self.probe.report.get('videos', [])]

    def _observation(self, phase, cursor, stage, *, capture):
        p, evidence, bindings = self.probe, [], {'observation_mode': 'nonimage_stage_predicates'}
        if phase == 'C4':
            state = self._c4_state()
            if cursor == 'C1_REVIEW':
                checks = p.report.get('c1_monthly_rent_blank_checks')
                need(type(checks) is dict and set(checks) == {'before_save', 'after_reopen'}
                     and checks['before_save'] is True and checks['after_reopen'] is True,
                     'actual_c1_blank_rent_checks_required')
                bindings['c1_monthly_rent_blank_checks'] = dict(checks)
                names = self._c1_acceptance_media_names()
                evidence = self._media(names)
                frames = {name: self.c4.frame(p, name) for name in ('C1-restored-title.png', 'C1-restored-complete-photo.png')}
            elif cursor == 'REQUEST':
                frames = {}
                with self._read_session():
                    self.c4.prepared_brief_context(p, state)
            elif cursor == 'RESPONSE_READY':
                frames = state['response_ready_frames']
                evidence = self._media(list(frames))
            elif cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:
                group = {'AI_REVIEW': 'ai_frames', 'APPLY_REVIEW': 'apply_frames', 'RESTORE_REVIEW': 'restore_frames'}[cursor]
                frames = state[group]
                names = list(frames)
                if cursor == 'APPLY_REVIEW': names += list(state['ai_frames'])
                if cursor == 'RESTORE_REVIEW': names += [state['restore_video']['file']]
                evidence = self._media(names)
            else: frames = {}
            bindings['frames'] = frames_wire(frames) if frames else []
            if cursor == 'APPLY_REVIEW': bindings['approved_proposal_frames'] = frames_wire(state['ai_frames'])
            if cursor == 'RESTORE_REVIEW': bindings['video'] = video_wire(state['restore_video'])
            if cursor in {'SAVE', 'REOPEN'}:
                with self._read_session(): self._nonimage_check(phase, stage)
            else:
                with self._read_session(): bindings['safe_scene_sha256'] = self._safe_scene()
                bindings['observation_mode'] = 'safe_full_tree_scene_digest'
        elif stage == 'CONFIGURE_C2_FROM_C1':
            bindings['c1_monthly_rent_blank_checks'] = self._c1_entry_checks()
            bindings['entry_mode'] = 'standard_editor'
            evidence = self._media(['C1-photo-selected.png', 'C1-restored-title.png',
                                    'C1-restored-complete-photo.png'])
            bindings['configuration_frames'] = [{'file': row['file'], 'sha256': row['sha256']} for row in evidence]
            with self._read_session(): bindings['safe_scene_sha256'] = self._safe_scene()
            bindings['observation_mode'] = 'safe_full_tree_scene_digest'
        elif stage == 'CONFIGURE_C2':
            evidence = self._media(['C1-restored-title.png', 'C1-c4-restored-final-title.png'])
            bindings['configuration_frames'] = [{'file': row['file'], 'sha256': row['sha256']} for row in evidence]
            with self._read_session(): bindings['safe_scene_sha256'] = self._safe_scene()
            bindings['observation_mode'] = 'safe_full_tree_scene_digest'
        else:
            executor = p._root_c2_executor_v2
            if stage == 'regular_isolation':
                self.dispatcher._regular_bundle(p, executor)
                bindings.update(safe_surface_frames=copy.deepcopy(executor.regular_frames),
                    regular_cycle=executor.regular_cycle, nonimage_role_witness=copy.deepcopy(executor.regular_account_witness))
                evidence = self._media([row['file'] for row in executor.regular_frames.values()])
                with self._read_session(): self._nonimage_check(phase, stage)
            elif stage in self.c2.TARGETS or stage in self.c2.REVIEW_STAGES:
                with self._read_session():
                    cache = getattr(p, '_root_c2_v2_pending_frames', {})
                    held = cache.get(stage)
                    if held is None:
                        need(capture, 'actual_c2_gate_capture_required')
                        held = self.dispatcher._safe_capture(p, self.c2, executor, stage)
                        cache[stage] = held
                        p._root_c2_v2_pending_frames = cache
                    current = self.dispatcher._capture_rows(p, self.c2, executor, stage)
                    need(current == held['node_bindings'], 'actual_c2_gate_scene_changed')
                bindings.update(observation_mode='safe_exact_frame_node_bindings', actual_frame_file=held['file'],
                    frame_sha256=held['sha256'], node_bindings=copy.deepcopy(held['node_bindings']))
                if stage == 'review_photo_before_save':
                    # Transport the already observed synthetic policy preview
                    # required by the next review, without a contact-page image.
                    bindings['semantic_preview'] = {key: executor.rent_sai_readback[key] for key in (
                        'kind', 'fixture_key', 'fixture_tag', 'editor_chain', 'rent_text',
                        'sai_rate_text', 'fallback_notice', 'recording_stopped',
                        'custom_terms_visible', 'policy_was_visually_reviewed',
                        'persisted_policy_configuration_proved')}
                evidence = self._media([held['file']])
            elif stage in API_STAGES or stage in LOGIN_STAGES:
                self._nonimage_check(phase, stage)
            else:
                with self._read_session(): self._nonimage_check(phase, stage)
        return {'phase': phase, 'cursor': cursor, 'stage_name': stage, 'bindings': bindings, 'evidence': evidence}

    @exclusive
    def snapshot(self):
        need(self._initial_used and not self.uncertain() and not self.finished(), 'checkpoint_stage_required')
        phase, cursor, stage = self._position()
        observed = self._observation(phase, cursor, stage, capture=True)
        binding = digest(observed)
        bindings = dict(observed['bindings'], checkpoint_binding_sha256=binding)
        required = sorted(C4_EXTRA[cursor]) if phase == 'C4' and cursor in C4_EXTRA else []
        if stage == 'CONFIGURE_C2': required = ['c1_review', 'c4_review']
        elif stage == 'CONFIGURE_C2_FROM_C1': required = ['c1_review', 'c2_entry_review']
        result = {'phase': phase, 'cursor': cursor, 'stage': {'executor_cursor': cursor,
            'context': stage, 'bindings': bindings, 'requested_review_fields': required,
            'report_scope': 'Actual safe evidence; no Root review or acceptance created'}, 'evidence': observed['evidence']}
        self._snapshot = copy.deepcopy(result)
        return result

    @exclusive
    def fresh_scene_matches(self, review, snapshot):
        try:
            need(type(review) is dict and snapshot == self._snapshot and fresh_remote_review(review),
                 'exact_fresh_checkpoint_review_required')
            phase, cursor, stage = self._position()
            need((phase, cursor) == (snapshot['phase'], snapshot['cursor']), 'actual_cursor_changed')
            expected = snapshot['stage']['bindings']['checkpoint_binding_sha256']
            need(review.get('checkpoint_binding_sha256') == expected, 'signed_checkpoint_binding_mismatch')
            current = self._observation(phase, cursor, stage, capture=False)
            need(digest(current) == expected, 'actual_scene_or_evidence_changed')
            return True
        except BaseException:
            return False

    def _write_review(self, filename, value):
        allowed = set(C4_FILES.values()) | {self.dispatcher.C1_FILE, self.dispatcher.C4_FILE, self.dispatcher.STAGE_FILE}
        entry_file = getattr(self.dispatcher, 'C2_ENTRY_FILE', None)
        if type(entry_file) is str: allowed.add(entry_file)
        need(filename in allowed,
             'fixed_review_filename_required')
        data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
        need(0 < len(data) <= 16384 and not any(alias.encode() in data for alias in self.private_aliases()),
             'bounded_private_safe_review_required')
        root = Path(self.probe.out)
        need(root.is_dir() and not root.is_symlink(), 'owned_review_directory_required')
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        fd = os.open(root / filename, flags, 0o600)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException:
            raise ControllerRefused('review_write_unconfirmed_no_retry') from None

    @exclusive
    def advance(self, review):
        need(not self._advance_failed and not self.uncertain(), 'controller_stage_no_replay')
        phase, cursor, stage = self._position()
        self.probe.require_phase_scope(phase)
        need(self._snapshot is not None and self.fresh_scene_matches(review, self._snapshot), 'fresh_signed_scene_required')
        wanted = set(ROOT_KEYS)
        if phase == 'C4' and cursor in C4_EXTRA: wanted.add('phase_review')
        elif stage == 'CONFIGURE_C2': wanted.update({'c1_review', 'c4_review'})
        elif stage == 'CONFIGURE_C2_FROM_C1': wanted.update({'c1_review', 'c2_entry_review'})
        elif stage in self.c2.TARGETS or stage in self.c2.REVIEW_STAGES: wanted.add('phase_review')
        need(set(review) == wanted, 'exact_signed_stage_review_schema_required')
        if not self._root_preflight_done:
            # Actual helper identity, UTC and capability are observed again at
            # the first Root boundary, not inferred from pre-C1 installation.
            with self._read_session(): self.probe.preflight_deadline_helper()
            self._root_preflight_done = True
        # Consume before any file, phase, auth, UI or API attempt. Failure never
        # restores permission to replay even when the original executor held.
        self._advance_failed = True
        try:
            for key in wanted - ROOT_KEYS:
                record = review[key]
                need(type(record) is dict and record.get('review_completed_utc') == review['review_completed_utc'],
                     'actual_same_root_review_utc_required')
            if phase == 'C4' and 'phase_review' in review:
                self._write_review(C4_FILES[cursor], review['phase_review'])
            elif stage == 'CONFIGURE_C2':
                self._write_review(self.dispatcher.C1_FILE, review['c1_review'])
                self._write_review(self.dispatcher.C4_FILE, review['c4_review'])
            elif stage == 'CONFIGURE_C2_FROM_C1':
                self._write_review(self.dispatcher.C1_FILE, review['c1_review'])
                self._write_review(self.dispatcher.C2_ENTRY_FILE, review['c2_entry_review'])
            elif 'phase_review' in review:
                self._write_review(self.dispatcher.STAGE_FILE, review['phase_review'])
            before = getattr(getattr(self.probe, '_root_c2_executor_v2', None), 'cursor', None)
            with self._api_scope('advance'):
                self.dispatcher.run_phase(self.probe, phase)
            need(not self.uncertain(ignore_controller=True), 'actual_phase_uncertain')
            if phase == 'C4':
                after = self._c4_state()
                need(after['cursor'] != cursor and not after.get('held_error'), 'actual_c4_stage_not_advanced')
            elif stage in {'CONFIGURE_C2', 'CONFIGURE_C2_FROM_C1'}:
                need(getattr(self.probe, '_root_c2_executor_v2', None) is not None
                     and self.probe._root_c2_executor_v2.cursor == 0, 'actual_c2_configuration_required')
            else:
                executor = self.probe._root_c2_executor_v2
                need(executor.cursor == before + 1, 'exact_one_c2_stage_required')
                if stage == 'pin_promotion':
                    sessions = self.probe.report.get('c2_normal_api_sessions', [])
                    need(sessions and sessions[-1].get('logout_http_200') is True
                         and sessions[-1].get('revoked_token_me_http_401') is True,
                         'actual_pin_api_session_revocation_required')
                    self._promotion_pin, self._promotion_pin_at = executor.property_id, self._mono()
            self._advance_failed = False
            self._snapshot = None
            return True
        except BaseException:
            raise ControllerRefused('phase_attempt_not_confirmed_no_replay') from None

    def validate_promoted_identity(self, property_id):
        # The immediately preceding original pin_promotion did a strict fresh
        # pair read under its signed stage and normal API logout+me401. No auth
        # session is invented outside a grant merely to re-read this result.
        return (type(property_id) is int and property_id == self._promotion_pin
                and self._promotion_pin_at is not None and 0 <= self._mono() - self._promotion_pin_at <= 120)

    def fixture_removed_confirmed(self):
        receipt = self.probe.report.get('c2_promoted_cleanup') or self._cleanup_receipt or {}
        return (receipt.get('status') == 'PASS' and
                (receipt.get('known_application_rows_removed') is True and receipt.get('protected_baseline_restored') is True
                 or receipt.get('fixture_removed') is True and receipt.get('fresh_session_cleaned') is True))

    def finished(self):
        executor = getattr(self.probe, '_root_c2_executor_v2', None)
        return bool(executor is not None and executor.cursor == len(self.c2.STAGES)
                    and not executor.failed and not executor.inflight and self.fixture_removed_confirmed())

    def uncertain(self, *, ignore_controller=False):
        p = self.probe
        c4 = p.report.get(getattr(self.c4, 'KEY', 'local_c4_executor'), {})
        c2 = getattr(p, '_root_c2_executor_v2', None)
        return bool((self._advance_failed and not ignore_controller) or
            p.admission_metrics.get('state') == 'uncertain' or p.admission_metrics.get('inflight') or
            getattr(p, '_host_stop_unconfirmed', False) or c4.get('uncertain') or c4.get('inflight') is not None or
            getattr(p, 'auth_attempted', False) and not p.authenticated
                and getattr(p, 'native_auth_uncertain', False) or
            c2 is not None and (c2.failed or c2.inflight))

    @exclusive
    def quiesce_for_checkpoint(self):
        need(not self.uncertain() and self.probe.recorder is None, 'known_quiescent_checkpoint_required')
        if self.probe.adapter is not None: self.probe.stop_session('owner_checkpoint_admission_close')

    @exclusive
    def stop_writers(self, *, deadline):
        need(not self._stop_used, 'writer_stop_single_attempt_required')
        self._stop_used = True
        self._within(deadline)
        p = self.probe
        unknown = self.uncertain()
        if p.recorder is not None:
            try: p.record_stop(export=False)
            except BaseException: unknown = True
        if not unknown:
            try:
                if getattr(p, 'active_native_role', None) in self.c2.roles.KNOWN_ROLES and p.authenticated:
                    if p.adapter is None: p.start_session()
                    result = self.c2.roles.native_logout_role(p)
                    self._native_logout = result.get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE'
                elif p.auth_attempted:
                    p.native_logout()
                    self._native_logout = p.report.get('session_logged_out') is True
                else:
                    self._native_logout = not p.authenticated and (not p.auth_attempted
                        or not getattr(p, 'native_auth_uncertain', False))
                if p.adapter is not None: p.stop_session('owner_cleanup_admission_close')
                if p.serial: p.adb('shell', 'am', 'force-stop', self.app)
                self._writers_stopped = p.admission_metrics.get('inflight') == 0 and p.adapter is None
            except BaseException:
                unknown = True
        if unknown:
            # Unknown native completion is disposed, never reset/reopened. API
            # cleanup is safe only after all owned VM/relay processes ended.
            receipt = self.close_runtime(deadline=deadline)
            self._writers_stopped = receipt.get('all_created_processes_observed_ended') is True
        self._within(deadline)
        need(self._writers_stopped, 'native_writers_not_confirmed_stopped')

    def _confirm_cleanup_case(self):
        p = self.probe
        bootstrap = p.report.get('api_bootstrap') or {}
        sessions = p.report.get('c2_normal_api_sessions', [])
        api_revoked = bool(self._cleanup_receipt and self._cleanup_receipt.get('fresh_session_cleaned') is True
            or sessions and sessions[-1].get('logout_http_200') is True
                and sessions[-1].get('revoked_token_me_http_401') is True)
        confirmed = bool(self._native_logout and self.fixture_removed_confirmed()
                         and bootstrap.get('fresh_session_cleaned') is True and api_revoked)
        if confirmed:
            native_receipts = p.report.get('native_role_logout', [])
            logout_observed = bool(p.report.get('session_logged_out') is True or native_receipts
                and native_receipts[-1].get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE')
            p.mark('C1-cleanup', 'PASS', final_same_fixture_rows_removed=True,
                protected_preexisting_rows_unchanged=True, native_logout_confirmed=logout_observed,
                initial_native_journey_not_started=not self._initial_used,
                bootstrap_api_session_revoked=True, cleanup_api_session_revoked=True,
                cleanup_scope='strict_actual_unpromoted_or_property_first_final_cleanup')
        return confirmed

    @exclusive
    def cleanup_once(self, *, deadline):
        need(not self._cleanup_used, 'cleanup_single_attempt_required')
        self._cleanup_used = True
        self._within(deadline)
        need(self._writers_stopped, 'writers_must_stop_before_cleanup')
        p, executor = self.probe, getattr(self.probe, '_root_c2_executor_v2', None)
        if self.fixture_removed_confirmed():
            return self._confirm_cleanup_case()
        if getattr(p, 'fixture_api', None) is None or not p.fixture_api.state:
            return self._native_logout or not p.auth_attempted
        # A reserved source cleanup attempt is never reconstructed or retried.
        need(executor is None or getattr(executor, 'cleanup_helper', None) is None,
             'existing_promoted_cleanup_attempt_no_replay')
        memory = p._known_role_memory
        session = self.c2.NormalOwnerSession(lambda method, path, body, token:
            p.fixture_api._call(method, path, body=body, token=token), memory, p.private_values)
        route = {'kind': None}
        def inspect_and_clean(api):
            code, body = api('GET', '/listing-editor-drafts/' + self._state()['key'])
            if code == 404:
                route['kind'] = 'unpromoted'
                return
            row = body.get('data')
            state = self._state()
            need(code == 200 and type(row) is dict and row.get('key') == state['key']
                 and type(row.get('payload')) is dict and state['tag'] in
                 str(row['payload'].get('fields', {}).get('title', '')), 'cleanup_exact_original_draft_required')
            property_id = row.get('property_id')
            if property_id is None:
                route['kind'] = 'unpromoted'
                return
            need(type(property_id) is int and property_id > 0, 'cleanup_property_link_invalid')
            need(row['payload'].get('fields', {}).get('title') == p.title,
                 'cleanup_exact_native_promoted_title_required')
            route['kind'] = 'promoted'
            helper = self.c2.cleanup_module.PromotedFixtureCleanup(api, state)
            # Hold SAME helper through final pin and its sole deletion attempt.
            self._promoted_cleanup_helper = helper
            pin = helper.pin_candidate(native_writers_stopped=True)
            need(pin.get('status') == 'READY' and pin.get('property_id') == property_id,
                 'cleanup_strict_original_pair_pin_failed')
            self._cleanup_receipt = helper.cleanup(native_writers_stopped=True)
            need(self._cleanup_receipt.get('status') == 'PASS', 'property_first_cleanup_not_confirmed')
        with self._api_scope('cleanup', deadline):
            session.run(inspect_and_clean)
            if route['kind'] == 'unpromoted':
                # The original strict unpromoted cleaner refuses any promotion
                # and performs exact baseline/readback plus normal revocation.
                try:
                    p.fixture_api.cleanup()
                finally:
                    # Keep the actual bounded API result even when native
                    # logout is unproven; this never manufactures C1 cleanup.
                    receipt = p.fixture_api.last_receipt
                    if type(receipt) is dict and receipt.get('mode') == 'cleanup':
                        self._cleanup_receipt = copy.deepcopy(receipt)
                        p.report['api_cleanup'] = copy.deepcopy(receipt)
                        p.save()
            need(self.fixture_removed_confirmed(), 'actual_cleanup_readback_required')
            if route['kind'] == 'promoted':
                # session.run returned only after its actual logout200/me401.
                self._cleanup_receipt = dict(self._cleanup_receipt, fresh_session_cleaned=True)
        p.fixture_possible = False
        self._removed = True
        return self._confirm_cleanup_case()

    @exclusive
    def close_runtime(self, *, deadline):
        if self._runtime_receipt is None:
            need(not self._close_used, 'runtime_close_outcome_unknown_no_retry')
            self._close_used = True
            need(type(deadline) in (int, float) and math.isfinite(deadline), 'bounded_vm_deadline_required')
            # Even an exhausted budget reaches the fixed owned-process close
            # callback: it may issue a nonblocking kill and truthful poll. No
            # API/UI work or renewed waiting budget is granted here.
            observed = self._close(deadline=deadline)
            need(type(observed) is dict and set(observed) == {
                'vm_created', 'relay_created', 'vm_exit_code', 'relay_exit_code',
                'owned_process_group_absence_observed', 'all_created_processes_observed_ended'},
                'actual_runtime_stop_receipt_required')
            for name in ['vm_created', 'relay_created', 'owned_process_group_absence_observed',
                         'all_created_processes_observed_ended']:
                need(type(observed[name]) is bool, 'actual_runtime_stop_flags_required')
            for prefix in ['vm', 'relay']:
                code = observed[prefix + '_exit_code']
                need(type(code) is int if observed[prefix + '_created'] else code is None,
                     'actual_created_process_exit_required')
            need(not observed['all_created_processes_observed_ended'] or not observed['vm_created']
                 or observed['owned_process_group_absence_observed'], 'actual_owned_group_absence_required')
            self._runtime_receipt = copy.deepcopy(observed)
        return copy.deepcopy(self._runtime_receipt)

    @exclusive
    def clear_private_state(self):
        api = getattr(self.probe, 'fixture_api', None)
        try:
            if api is not None: api.clear_credentials()
        finally:
            self.probe.clear_role_memory()
            self._snapshot = None
            # Only controller-owned legacy review controls are removed. Actual
            # report/media/proofs and the separate signed consume ledger remain.
            review_files = set(C4_FILES.values()) | {
                self.dispatcher.C1_FILE, self.dispatcher.C4_FILE, self.dispatcher.STAGE_FILE}
            entry_file = getattr(self.dispatcher, 'C2_ENTRY_FILE', None)
            if type(entry_file) is str: review_files.add(entry_file)
            for name in sorted(review_files):
                path = Path(self.probe.out) / name
                try: info = path.lstat()
                except FileNotFoundError: continue
                need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                     and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o600
                     and info.st_size <= 16384, 'exact_owned_review_control_required')
                path.unlink()
