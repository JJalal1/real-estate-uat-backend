"""Offline owner/transport/grant tests; no real credentials, device or API."""
import base64
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import shutil
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import Mock
import urllib.error

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'protocol'))
import review_protocol as p
import command_transport as t
import grants
import owner_session as owner
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class Response:
    def __init__(self, value, url=None, status=200):
        self.data = value; self.url = url; self.status = status
    def __enter__(self): return self
    def __exit__(self, *_): pass
    def geturl(self): return self.url
    def read(self, maximum): return self.data[:maximum]


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.opener = Mock()
        self.channel = t.CommandChannel('9001', 2, 'SYNTHETIC_READ_TOKEN', opener=self.opener)
        self.data = b'{"signed":"synthetic-only"}'
        self.path = self.channel.path(1)
        self.value = {'name': '000001.json', 'path': self.path, 'size': len(self.data),
            'sha': hashlib.sha1(b'blob ' + str(len(self.data)).encode() + b'\0' + self.data).hexdigest(),
            'type': 'file', 'encoding': 'base64', 'content': base64.b64encode(self.data).decode(),
            'url': 'https://ignored.invalid', 'html_url': 'https://ignored.invalid',
            'git_url': 'https://ignored.invalid', 'download_url': 'https://must-not-follow.invalid',
            '_links': {'self': 'https://ignored.invalid', 'git': 'https://ignored.invalid', 'html': 'https://ignored.invalid'}}
        def open_request(request, timeout):
            return Response(json.dumps(self.value).encode(), request.full_url)
        self.opener.open.side_effect = open_request

    def test_only_exact_get_contents_branch_path_and_inline_data_are_used(self):
        self.assertEqual(self.channel.poll(1), self.data)
        self.opener.open.assert_called_once()
        request = self.opener.open.call_args.args[0]
        self.assertEqual(request.get_method(), 'GET'); self.assertIsNone(request.data)
        self.assertEqual(request.full_url, 'https://api.github.com/repos/JJalal1/real-estate-uat-backend/contents/phase1-commands/9001/2/000001.json?ref=work%2Fphase1-root-review-20261104')
        self.assertNotIn('SYNTHETIC_READ_TOKEN', request.full_url)
        self.assertEqual(self.opener.open.call_args.kwargs, {'timeout': 20})

    def test_404_is_only_absent_result_other_http_errors_are_fixed(self):
        for code in [404, 302, 403, 429, 500]:
            self.opener.open.side_effect = urllib.error.HTTPError('fixed', code, 'PRIVATE_SENTINEL', {}, None)
            if code == 404: self.assertIsNone(self.channel.poll(1))
            else:
                with self.assertRaisesRegex(t.ChannelRefused, '^command_channel_http_failed$') as error:
                    self.channel.poll(1)
                self.assertNotIn('PRIVATE_SENTINEL', str(error.exception))
        self.assertIsNone(t.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://foreign.invalid'))

    def test_redirect_wrong_metadata_unknown_keys_and_corrupt_blob_are_refused(self):
        for update in [{'path': 'foreign.json'}, {'type': 'symlink'}, {'encoding': 'utf-8'},
                       {'size': True}, {'sha': 'f' * 40}, {'unexpected': 'PRIVATE_SENTINEL'},
                       {'content': base64.b64encode(self.data).decode() + '='}]:
            original = dict(self.value); self.value.update(update)
            with self.subTest(fields=list(update)), self.assertRaises(t.ChannelRefused):
                self.channel.poll(1)
            self.value = original
        self.opener.open.side_effect = lambda request, timeout: Response(b'{}', 'https://foreign.invalid')
        with self.assertRaisesRegex(t.ChannelRefused, 'unexpected_command_response'):
            self.channel.poll(1)

    def test_size_duplicate_json_transport_error_and_closed_channel_fail_closed(self):
        for raw in [b'x' * (t.MAX_RESPONSE + 1), b'{"size":1,"size":2}', b'[]', b'\xff']:
            self.opener.open.side_effect = lambda request, timeout, raw=raw: Response(raw, request.full_url)
            with self.subTest(size=len(raw)), self.assertRaises(t.ChannelRefused): self.channel.poll(1)
        self.opener.open.side_effect = RuntimeError('SYNTHETIC_PRIVATE_ERROR')
        with self.assertRaisesRegex(t.ChannelRefused, '^command_channel_transport_failed$'):
            self.channel.poll(1)
        self.channel.close()
        with self.assertRaisesRegex(t.ChannelRefused, 'channel_closed'): self.channel.poll(1)

    def test_path_identity_cannot_be_traversed_or_boolean(self):
        for value in [0, True, -1, 10001, '../escape', 1.0]:
            with self.subTest(kind=type(value).__name__), self.assertRaises(t.ChannelRefused): self.channel.path(value)
        for run, attempt in [('../x', 1), ('0', 1), ('9001', True)]:
            with self.assertRaises(t.ChannelRefused): t.CommandChannel(run, attempt, 'synthetic')


class FakeClock:
    def __init__(self): self.value = 0.0
    def monotonic(self): return self.value
    def utc(self): return datetime(2026, 11, 4, 1, 2, 3, tzinfo=timezone.utc) + timedelta(seconds=self.value)
    def wait(self, event, seconds): self.value += seconds


class GrantTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock(); self.root = Ed25519PrivateKey.generate(); self.job = p.JobEphemeralKey()
        self.ctx = p.Context(p.REPOSITORY, '9001', 2, 'a' * 40, 'b' * 64, 1,
                             'C4', 'AI_REVIEW', 'c' * 64, 'd' * 64, '0' * 64)

    def grant(self, reviewed=None):
        raw = p.build_command(self.ctx, {'review_completed_utc': reviewed or '2026-11-04T01:02:03Z'},
                              self.root, self.job.public(), self.clock.utc())
        valid = p.validate_command(raw, self.ctx, self.root.public_key(), self.job, self.clock.utc())
        return grants.issue_verified(validated=valid, context=self.ctx,
            issued_utc='2026-11-04T01:02:03Z', received_utc=self.clock.utc(),
            received_monotonic=self.clock.monotonic(), work_deadline=600,
            utc_clock=self.clock.utc, monotonic_clock=self.clock.monotonic)

    def test_verified_grant_exact_context_category_expiry_and_revocation(self):
        grant = self.grant(); self.assertEqual(grant.authority_kind, 'ROOT_VERIFIED')
        self.assertEqual(grant.monotonic_deadline, 90)
        self.assertTrue(grant.require_input(self.ctx, 'tap', 45))
        for context, category in [(replace(self.ctx, cursor='OTHER'), 'tap'), (self.ctx, 'arbitrary_shell')]:
            with self.assertRaises(grants.GrantRefused): grant.require_input(context, category)
        self.clock.value = 91
        with self.assertRaisesRegex(grants.GrantRefused, 'deadline_expired'): grant.require_input(self.ctx, 'tap')
        self.clock.value = 0; grant.revoke()
        with self.assertRaisesRegex(grants.GrantRefused, 'active_context'): grant.require_input(self.ctx, 'tap')

    def test_raw_dict_or_stale_future_actual_review_is_not_a_factory(self):
        with self.assertRaises(grants.GrantRefused):
            grants.VerifiedGrant(None, validated={}, context=self.ctx, issued_utc='', received_utc=self.clock.utc(),
                received_monotonic=0, work_deadline=600, utc_clock=self.clock.utc, monotonic_clock=self.clock.monotonic)
        for stamp in ['2026-11-04T00:59:00Z', '2026-11-04T01:02:09Z', '2026-11-04T01:02:03.5Z']:
            with self.subTest(stamp=stamp), self.assertRaises(grants.GrantRefused): self.grant(stamp)

    def test_validated_command_cannot_be_rebound_to_other_same_sequence_context(self):
        raw = p.build_command(self.ctx, {'review_completed_utc': '2026-11-04T01:02:03Z'},
                              self.root, self.job.public(), self.clock.utc())
        valid = p.validate_command(raw, self.ctx, self.root.public_key(), self.job, self.clock.utc())
        with self.assertRaisesRegex(grants.GrantRefused, 'context_mismatch'):
            grants.issue_verified(validated=valid, context=replace(self.ctx, cipher_sha='e'*64),
                issued_utc='2026-11-04T01:02:03Z', received_utc=self.clock.utc(),
                received_monotonic=0, work_deadline=600, utc_clock=self.clock.utc,
                monotonic_clock=self.clock.monotonic)

    def test_forward_utc_jump_does_not_overstate_per_input_remaining_budget(self):
        grant = self.grant()
        self.clock.utc = lambda: datetime(2026, 11, 4, 1, 3, 28, tzinfo=timezone.utc)
        grant._utc = self.clock.utc
        with self.assertRaisesRegex(grants.GrantRefused, 'deadline_expired'):
            grant.require_input(self.ctx, 'tap', 45)
        self.assertTrue(grant.require_input(self.ctx, 'app_stop', 1))

    def test_initial_source_plan_is_distinct_phase_c1_bounded_no_root_review_fields(self):
        context = replace(self.ctx, phase='C1', cursor='INITIAL_C1')
        lease = grants.issue_initial(context=context, start_monotonic=0, work_deadline=1000,
                                     monotonic_clock=self.clock.monotonic)
        self.assertEqual(lease.authority_kind, 'SOURCE_PLAN_ONLY')
        self.assertEqual(lease.monotonic_deadline, 600)
        self.assertFalse(hasattr(lease, 'review_completed_utc'))
        self.assertTrue(lease.require_input(context, 'text'))
        with self.assertRaises(grants.GrantRefused): lease.require_input(self.ctx, 'text')
        self.clock.value = 601
        with self.assertRaises(grants.GrantRefused): lease.require_input(context, 'text')

    def test_cleanup_never_clears_uncertainty_and_ui_expiry_is_whole_seconds(self):
        context = replace(self.ctx, phase='C5', cursor='OWNER_CLEANUP')
        self.clock.value = 0.9
        lease = grants.issue_cleanup(context=context, cleanup_deadline=600, uncertain=True,
                    utc_clock=self.clock.utc, monotonic_clock=self.clock.monotonic)
        self.assertEqual(lease.expires_utc.microsecond, 0)
        self.assertEqual(lease.monotonic_deadline, 600)
        self.assertTrue(lease.require_input(context, 'app_stop'))
        for category in ['tap', 'text', 'os_picker', 'recorder_start', 'media_write']:
            with self.subTest(category=category), self.assertRaises(grants.GrantRefused):
                lease.require_input(context, category)
        self.clock.value = 130
        self.assertTrue(lease.require_input(context, 'app_stop'))
        self.clock.value = 601
        with self.assertRaises(grants.GrantRefused): lease.require_input(context, 'app_stop')


IDENTITY = {'repo': p.REPOSITORY, 'run_id': '9001', 'run_attempt': 2,
            'source_sha': 'a' * 40, 'toolbundle_sha': 'b' * 64}
SEED = {'fixture': {'draft_uuid': 'f8dc3db4-e1e7-4600-8f2b-b4047a6b9a31',
                   'tag': 'AQER-C1-aaaaaaaaaaaa', 'actor_id': 28, 'property_id': None},
        'baseline': {'properties': {'count': 25, 'sha256': 'c' * 64},
                     'drafts': {'count': 7, 'sha256': 'd' * 64}}}


class FakePackager:
    def __init__(self): self.max_allocated = -1; self.identity = dict(IDENTITY); self.records = []; self.latest = None
    def seal(self, **kwargs):
        self.max_allocated = kwargs['seq']; self.records.append(kwargs)
        public = {**IDENTITY, 'checkpoint_challenge': 'e' * 64, 'cipher_sha': 'f' * 64}
        held = {**IDENTITY, 'seq': kwargs['seq'], 'phase': kwargs['phase'], 'cursor': kwargs['cursor'],
                'checkpoint_challenge': 'e' * 64, 'cipher_sha': 'f' * 64,
                'prev_result_sha': kwargs['prev_result_sha']} if kwargs['kind'] == 'review_checkpoint' else None
        self.latest = SimpleNamespace(public_receipt=public, held_context=held)
        return self.latest
    def close(self): pass


class FakeController:
    def __init__(self):
        self.events = []; self.step = 0; self.is_uncertain = False; self.seed = json.loads(json.dumps(SEED))
        self.session = None
    def prepare_runtime(self): self.events.append('prepare')
    def prepare_initial_native(self):
        self.events.append('fresh-native-network')
        self.source_authority = self.session.active_authority
        self.source_authority.require_input(self.source_authority.context, 'app_start')
        return True
    def bootstrap_fixture(self): self.events.append('api-title-bootstrap')
    def fixture_summary(self): return self.seed
    def validate_promoted_identity(self, property_id): return property_id == 999
    def fixture_removed_confirmed(self): return False
    def quiesce_for_checkpoint(self): self.events.append('quiesce')
    def initial_c1(self):
        self.events.append('initial-c1')
        self.session.active_authority.require_input(self.session.active_authority.context, 'tap')
        if self.session.active_authority is not self.source_authority:
            raise RuntimeError('source lease was refreshed')
        return True
    def finished(self): return self.step == 1
    def snapshot(self): return {'phase': 'C4', 'cursor': 'AI_REVIEW', 'stage': {'report_scope': 'synthetic'}, 'evidence': []}
    def fresh_scene_matches(self, review, snapshot): return True
    def advance(self, review):
        self.events.append('advance')
        self.session.active_authority.require_input(self.session.active_authority.context, 'text')
        self.step += 1
        return True
    def private_aliases(self): return ('SYNTHETIC_PRIVATE_ALIAS',)
    def uncertain(self): return self.is_uncertain
    def stop_writers(self, *, deadline): self.events.append('stop-writers')
    def cleanup_once(self, *, deadline): self.events.append('cleanup'); return True
    def close_runtime(self, *, deadline):
        self.events.append('runtime-close')
        return {'vm_created': True, 'relay_created': False, 'vm_exit_code': -15,
                'relay_exit_code': None, 'owned_process_group_absence_observed': True,
                'all_created_processes_observed_ended': True}
    def clear_private_state(self): self.events.append('clear-private')


class FakeIO:
    def __init__(self): self.uploads = []; self.statuses = []; self.on_upload = None
    def announce_and_wait(self, sealed, deadline, event, *, cleanup):
        self.uploads.append((sealed, cleanup))
        if self.on_upload: return self.on_upload(sealed, cleanup)
        return True
    def status(self, code, seq): self.statuses.append((code, seq))


class OwnerKernelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.clock, self.packager, self.controller, self.io = FakeClock(), FakePackager(), FakeController(), FakeIO()
        self.root = Ed25519PrivateKey.generate(); self.job = p.JobEphemeralKey(); self.op = 'advance'
        self.channel = Mock()
        def poll(seq):
            context = p.Context(**self.packager.latest.held_context)
            return p.build_command(context, {'review_completed_utc': self.clock.utc().strftime('%Y-%m-%dT%H:%M:%SZ')},
                                   self.root, self.job.public(), self.clock.utc(), op=self.op)
        self.channel.poll.side_effect = poll
        self.session = self.make_session()
        self.controller.session = self.session

    def make_session(self, packager=None, budget=None):
        return owner.OwnerSession(root=Path(self.temp.name), controller=self.controller,
            channel=self.channel, packager=packager or self.packager, job_key=self.job,
            root_public=self.root.public_key(), checkpoint_io=self.io,
            budget=budget or owner.Budget(work_seconds=600, cleanup_seconds=60, hold_seconds=30, poll_seconds=5), clock=self.clock)

    def extended_review_session(self):
        self.session = self.make_session(budget=owner.Budget(
            work_seconds=600, cleanup_seconds=60, hold_seconds=900, poll_seconds=5))
        self.controller.session = self.session

    def test_extended_review_wait_accepts_a_new_fresh_signature_after_visual_review(self):
        self.extended_review_session()
        original = self.channel.poll.side_effect
        def reviewed_later(seq):
            self.assertIsNone(self.session.active_authority)
            self.assertNotIn('advance', self.controller.events)
            self.clock.value += 400
            return original(seq)
        self.channel.poll.side_effect = reviewed_later
        result = self.session.run()
        self.assertTrue(result.collected)
        self.assertTrue(result.cleanup_confirmed)
        self.assertEqual(self.controller.events.count('advance'), 1)

    def test_extended_review_wait_does_not_renew_an_expired_signature(self):
        self.extended_review_session()
        original = self.channel.poll.side_effect
        cached = []
        def expired(seq):
            if not cached:
                cached.append(original(seq))
                self.clock.value += 400
            return cached[0]
        self.channel.poll.side_effect = expired
        result = self.session.run()
        self.assertFalse(result.collected)
        self.assertNotIn('advance', self.controller.events)
        self.assertTrue(result.cleanup_confirmed)
        self.assertIn(('COMMAND_REFUSED', 1), self.io.statuses)

    def test_extended_review_wait_cannot_extend_the_overall_work_deadline(self):
        self.extended_review_session()
        original = self.channel.poll.side_effect
        def past_work_budget(seq):
            self.clock.value += 601
            return original(seq)
        self.channel.poll.side_effect = past_work_budget
        result = self.session.run()
        self.assertFalse(result.collected)
        self.assertNotIn('advance', self.controller.events)
        self.assertTrue(result.cleanup_confirmed)

    def test_same_owner_keeps_fixture_sequence_and_reserves_before_active_grant(self):
        def advance(review):
            grant = self.session.active_authority
            self.assertEqual(grant.authority_kind, 'ROOT_VERIFIED')
            self.assertEqual(self.session.current_context, self.session.current_input_context)
            self.assertEqual(self.session.current_context, grant.context)
            self.assertTrue((Path(self.temp.name) / 'command-ledger/000001.command.json').is_file())
            return FakeController.advance(self.controller, review)
        self.controller.advance = advance
        result = self.session.run()
        self.assertTrue(result.collected); self.assertTrue(result.cleanup_confirmed); self.assertTrue(result.runtime_ended)
        self.assertFalse(result.phase1_accepted)
        self.assertEqual([r['seq'] for r in self.packager.records], [0, 1, 2])
        self.assertEqual(self.packager.records[0]['cursor'], 'PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP')
        self.assertEqual(self.controller.events.count('api-title-bootstrap'), 1)
        self.assertLess(self.controller.events.index('fresh-native-network'), self.controller.events.index('api-title-bootstrap'))
        self.assertEqual(self.controller.events.count('cleanup'), 1)
        self.assertLess(self.controller.events.index('stop-writers'), self.controller.events.index('cleanup'))
        self.assertIsNone(self.session.active_authority)

    def test_negative_upload_ack_blocks_initial_native_edits_but_runs_cleanup(self):
        self.io.on_upload = lambda sealed, cleanup: cleanup
        result = self.session.run()
        self.assertNotIn('initial-c1', self.controller.events)
        self.assertTrue(result.cleanup_confirmed)
        self.assertEqual([r['seq'] for r in self.packager.records], [0, 1])
        self.assertEqual(self.controller.events.count('cleanup'), 1)

    def test_early_failure_has_terminal_one_and_conservative_cleanup_deadline(self):
        self.controller.prepare_runtime = Mock(side_effect=RuntimeError('SYNTHETIC_PRIVATE_ERROR'))
        self.controller.stop_writers = Mock()
        result = self.session.run()
        self.assertEqual([r['seq'] for r in self.packager.records], [1])
        self.assertEqual(self.controller.stop_writers.call_args.kwargs['deadline'], 60)
        self.assertFalse(result.collected)
        self.assertNotIn('SYNTHETIC_PRIVATE_ERROR', repr(result))

    def test_initial_failure_retains_stage_without_private_exception_values(self):
        private_value = 'SYNTHETIC_PRIVATE_ERROR_DO_NOT_EXPORT'
        def failing_initial():
            raise RuntimeError(private_value)
        self.controller.initial_c1 = failing_initial
        result = self.session.run()
        terminal = self.packager.records[-1]['stage']['postconditions']
        diagnostic = terminal['failure_location']
        self.assertEqual(diagnostic['operation'], 'initial_c1')
        self.assertEqual(diagnostic['exception_type'], 'RuntimeError')
        self.assertTrue(diagnostic['source_frames'])
        self.assertTrue(all(set(frame) == {'file', 'line', 'function'} for frame in diagnostic['source_frames']))
        self.assertNotIn(private_value, json.dumps(terminal))
        self.assertFalse(result.collected)
        self.assertEqual(self.controller.events.count('cleanup'), 1)

    def test_success_keeps_failure_location_empty(self):
        self.assertTrue(self.session.run().collected)
        self.assertIsNone(self.packager.records[-1]['stage']['postconditions']['failure_location'])

    def test_repeated_stop_during_cleanup_never_revokes_cleanup_lease(self):
        def cleanup(*, deadline):
            authority = self.session.active_authority
            self.assertEqual(authority.authority_kind, 'OWNER_CLEANUP')
            self.assertEqual(self.session.current_context, authority.context)
            self.assertEqual(self.session.current_context.phase, 'C5')
            self.session.request_stop(); self.session.request_stop()
            self.assertTrue(authority.require_input(authority.context, 'app_stop'))
            self.controller.events.append('cleanup')
            return True
        self.controller.cleanup_once = cleanup
        self.assertTrue(self.session.run().cleanup_confirmed)

    def test_owner_rechecks_hold_deadline_after_slow_command_poll(self):
        original = self.channel.poll.side_effect
        def late(seq):
            self.clock.value += 31
            return original(seq)
        self.channel.poll.side_effect = late
        result = self.session.run()
        self.assertNotIn('advance', self.controller.events)
        self.assertFalse(result.collected); self.assertTrue(result.cleanup_confirmed)
        self.assertFalse((Path(self.temp.name) / 'command-ledger/000001.command.json').exists())

    def test_incorrect_signature_is_unconsumed_and_times_out_without_any_advance(self):
        self.channel.poll.side_effect = lambda seq: b'{"untrusted":"no commands"}'
        result = self.session.run()
        self.assertFalse(result.collected)
        self.assertNotIn('advance', self.controller.events)
        self.assertTrue(self.io.statuses)
        self.assertEqual(list((Path(self.temp.name) / 'command-ledger').iterdir()), [])

    def test_root_finish_stops_early_without_making_a_review_or_acceptance(self):
        self.op = 'finish'
        result = self.session.run()
        self.assertEqual(result.reason_code, 'ROOT_FINISHED_EARLY')
        self.assertFalse(result.collected); self.assertFalse(result.phase1_accepted)
        self.assertNotIn('advance', self.controller.events)

    def test_unknown_runtime_exit_does_not_become_an_observed_end(self):
        self.controller.close_runtime = lambda *, deadline: {'vm_exit_code': None}
        result = self.session.run()
        self.assertFalse(result.runtime_ended)
        terminal = self.packager.records[-1]['stage']['postconditions']['runtime']
        self.assertIsNone(terminal['vm_exit_code'])
        self.assertFalse(terminal['all_created_processes_observed_ended'])

    def test_claimed_end_with_created_vm_and_missing_poll_cannot_pass(self):
        self.controller.close_runtime = lambda *, deadline: {'vm_created': True, 'relay_created': False,
            'vm_exit_code': None, 'relay_exit_code': None, 'all_created_processes_observed_ended': True,
            'owned_process_group_absence_observed': True}
        self.assertFalse(self.session.run().runtime_ended)

    def test_changed_fixture_or_baseline_is_never_adopted(self):
        original = self.controller.fixture_summary
        def changed():
            value = json.loads(json.dumps(original()))
            if 'initial-c1' in self.controller.events: value['fixture']['tag'] = 'AQER-C1-bbbbbbbbbbbb'
            return value
        self.controller.fixture_summary = changed
        result = self.session.run()
        self.assertFalse(result.collected); self.assertNotIn('advance', self.controller.events)
        self.assertEqual(self.controller.events.count('cleanup'), 1)

    def test_failed_native_network_proof_never_bootstraps_or_authenticates(self):
        self.controller.prepare_initial_native = lambda: False
        result = self.session.run()
        self.assertFalse(result.collected)
        self.assertNotIn('api-title-bootstrap', self.controller.events)
        self.assertNotIn('initial-c1', self.controller.events)
        self.assertEqual(self.controller.events.count('cleanup'), 1)

    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL required for actual packager interface test')
    def test_real_packager_identity_and_dict_context_interoperate_with_owner(self):
        import checkpoint_packager as cp
        root = Path(self.temp.name)
        certificate, test_key = root / 'test-public.pem', root / 'test-private.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
            '-keyout', str(test_key), '-out', str(certificate), '-days', '1',
            '-subj', '/CN=OwnerInterfaceSyntheticTest'], capture_output=True, check=True)
        test_key.chmod(0o600)
        evidence = root / 'evidence'; evidence.mkdir(mode=0o700)
        real = cp.CheckpointPackager(root=root, evidence_root=evidence, identity=dict(IDENTITY),
            recipient_cert=certificate, recipient_sha256=hashlib.sha256(certificate.read_bytes()).hexdigest(),
            job_public=self.job.public(), root_key_id=p.key_id(self.root.public_key()),
            private_aliases=self.controller.private_aliases())
        self.session.ledger.close()
        self.session = self.make_session(packager=real); self.controller.session = self.session
        def real_poll(seq):
            context = p.Context(**self.io.uploads[-1][0].held_context)
            return p.build_command(context, {'review_completed_utc': self.clock.utc().strftime('%Y-%m-%dT%H:%M:%SZ')},
                self.root, self.job.public(), self.clock.utc())
        self.channel.poll.side_effect = real_poll
        result = self.session.run()
        self.assertTrue(result.collected); self.assertTrue(result.cleanup_confirmed)
        self.assertEqual([p.name for p in sorted((root / 'checkpoints').iterdir())], ['000000', '000001', '000002'])
        self.assertTrue(all((p / 'checkpoint.cms').stat().st_size > 0 for p in (root / 'checkpoints').iterdir()))


if __name__ == '__main__':
    unittest.main()
