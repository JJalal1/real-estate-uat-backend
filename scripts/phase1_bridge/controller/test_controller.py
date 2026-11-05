"""Focused synthetic composition tests; no native/API/Root acceptance evidence."""
from datetime import datetime, timezone
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import threading
import unittest
import uuid

HERE = Path(__file__).resolve().parent
ADAPTER = HERE.parent / 'adapter'
if not (ADAPTER / 'ci_remote_evidence.py').is_file():
    ADAPTER = HERE.parent / 'integration-adapter'
sys.path.insert(0, str(ADAPTER))
import ci_remote_evidence as evidence
import controller as module


NOW = datetime(2026, 11, 4, 12, 0, tzinfo=timezone.utc)
KEY = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
TAG = 'AQER-C1-' + 'a' * 12
SHA = 'a' * 64


class Authority:
    def __init__(self, kind='SOURCE_PLAN_ONLY'):
        self.authority_kind = kind
        self.monotonic_deadline = 600
        self.active = True
    def require_input(self, context, category):
        if not self.active: raise RuntimeError('SYNTHETIC_EXPIRED')
        return True


class Memory:
    def resolve(self, role): return '+9000000001', '258147'
    def clear(self): pass


class Probe:
    def __init__(self, folder):
        self.out, self.events = folder, []
        self.report = {'cases': [], 'frames': [], 'videos': []}
        self.access = {'phones': {'broker': '+9000000001'}, 'otp': '258147'}
        self.private_values = {'+9000000001', '258147'}
        self.env = {'GITHUB_RUN_ID': '9001'}
        self.fixture_api = None
        self.adapter = None
        self.recorder = None
        self.title = 'SYNTHETIC ' + TAG
        self.authenticated = self.auth_attempted = self.native_auth_uncertain = False
        self.active_native_role = None
        self.serial = 'synthetic'
        self._known_role_memory = Memory()
        self.admission_metrics = {'state': 'closed', 'inflight': 0}
        self.rows = [{'text': 'PUBLISHED_SYNTHETIC', 'visible': True}]
        self.private_scene = False
    def case_phase(self, case): self.events.append(case)
    def validate_and_install(self): self.events.append('install')
    def configure_host_display(self): self.events.append('display_verified')
    def startup(self): self.events.append('startup'); self.start_session()
    def preflight_deadline_helper(self): self.events.append('actual_helper_utc_preflight')
    def start_session(self): self.adapter = object(); self.admission_metrics['state'] = 'open'
    def stop_session(self, reason): self.adapter = None; self.admission_metrics['state'] = 'closed'
    def require_preauth_runtime(self): self.events.append('native_runtime_readback')
    def matching(self, rows, title): return [row for row in rows if row.get('text') == title]
    def nodes(self): self.events.append('read_nodes'); return self.rows
    def scroll(self): self.events.append('scroll')
    def mark(self, case, status, **kwargs):
        self.report['cases'] = [row for row in self.report['cases'] if row['id'] != case]
        self.report['cases'].append({'id': case, 'status': status, **kwargs})
    def save(self): pass
    def login(self):
        self.events.append('login'); self.authenticated = self.auth_attempted = True
        self.mark('C1-auth', 'PASS')
    def create_and_save(self):
        self.events.append('create'); self.mark('C1-photo-save', 'PASS')
        self.report.setdefault('c1_monthly_rent_blank_checks', {})['before_save'] = True
    def restore(self):
        self.events.append('restore'); self.mark('C1-force-stop-restore', 'PASS')
        self.media('C1-restored-title.png'); self.media('C1-restored-complete-photo.png')
        self.media('C1-create-photo.webm'); self.media('C1-restored-facts.webm')
        self.report.setdefault('c1_monthly_rent_blank_checks', {})['after_reopen'] = True
    def hold_after_initial_c1(self):
        self.events.append('hold'); self.report['held_after_c1_restore_for_root_review'] = True
    def media(self, name):
        data = b'SYNTHETIC_ONLY_' + name.encode()
        path = self.out / name
        path.write_bytes(data); path.chmod(0o600)
        row = {'file': name, 'sha256': hashlib.sha256(data).hexdigest()}
        if name.endswith('.webm'):
            row.update(capture='official_emulator_console_host_webm', authentication_frames=False, duration_s=1.25)
            self.report['videos'].append(row)
        else:
            row.update(capture='official_emulator_console_host_png',authenticated_editor_only=True)
            self.report['frames'].append(row)
        return row
    def _capture_full_rows(self): self.events.append('read_full_rows'); return self.rows
    def _capture_rows_private(self, rows): return self.private_scene
    def require_phase_scope(self, phase): self.events.append('root_scope_' + phase); return True
    def adb(self, *args): self.events.append('force_stop'); return 'OK'
    def native_logout(self):
        self.events.append('native_logout'); self.authenticated = False
        self.report['session_logged_out'] = True
    def record_stop(self, export=False): self.events.append('recorder_stop'); self.recorder = None
    def clear_role_memory(self): self.access.clear(); self.private_values.clear()


class FixtureApi:
    def __init__(self, phone, otp, run_id, transport, expected_actor_id):
        self.transport, self.state, self.last_receipt = transport, None, None
        self.calls, self.property_id = [], None
    def bootstrap(self):
        self.calls.append('bootstrap')
        self.state = {'key': KEY, 'tag': TAG, 'title': 'BOOTSTRAP ' + TAG, 'actor_id': 28,
            'created_confirmed': True, 'creation_request_sent': True,
            'baseline': {'properties': {str(i): SHA for i in range(1,26)},
                         'drafts': {str(uuid.UUID(int=i+1)): SHA for i in range(7)}}}
        self.last_receipt = {'status': 'PASS', 'fresh_session_cleaned': True,
                            'identity': {'actor_id':28,'account_type':'broker'}}
    def cleanup(self):
        self.calls.append('unpromoted_cleanup')
        self.last_receipt = {'mode': 'cleanup', 'status': 'PASS', 'fixture_removed': True, 'fresh_session_cleaned': True}
    def _call(self, method, path, body=None, token=None):
        self.calls.append((method, path))
        if path == '/auth/whatsapp/verify':
            self.logged_out = False
            return 200, {'data': {'token': 'SYNTHETIC_SESSION'}}, 1
        if path == '/auth/me':
            if getattr(self, 'logged_out', False): return 401, {}, 1
            return 200, {'data': {'user': {'id': 28, 'account_type': 'broker'}}}, 1
        if path == '/auth/logout': self.logged_out = True; return 200, {}, 1
        if path == '/listing-editor-drafts/' + KEY:
            return 200, {'data': {'key': KEY, 'property_id': self.property_id,
                'payload': {'fields': {'title': self.native_title}}}}, 1
        return 200, {}, 1
    def clear_credentials(self): self.calls.append('clear_credentials')


class C4:
    KEY = 'local_c4_executor'
    @staticmethod
    def identity(p): return KEY, TAG, p.title
    @staticmethod
    def scene(rows): return module.digest(rows)
    @staticmethod
    def frame(p, name): return next(row['sha256'] for row in p.report['frames'] if row['file'] == name)
    @staticmethod
    def blank_rent(p): p.events.append('nonimage_blank_rent')
    @staticmethod
    def prepared_brief_context(p, state):
        p.events.append('prepared_brief_exact_readback')
        return SHA


class Executor:
    def __init__(self, cursor=0):
        self.cursor, self.failed, self.inflight = cursor, False, False
        self.property_id = self.cleanup_helper = None
    def _guest(self): pass


class C2:
    STAGES = ('load_roles', 'complete_rent', 'submit_open', 'cleanup')
    TARGETS = {'submit_open': ('broker', 'SYNTHETIC', 'fixture')}
    REVIEW_STAGES = set()
    roles = SimpleNamespace(KNOWN_ROLES={'broker','support','regular'}, AUTH_LABELS={'AUTH_SYNTHETIC'})
    cleanup_module = None
    NormalOwnerSession = None
    @staticmethod
    def _names(rows): return {row.get('text') for row in rows}


class Dispatcher:
    C1_FILE, C4_FILE, STAGE_FILE = 'C2_C1.json', 'C2_C4.json', 'C2_STAGE.json'
    def __init__(self): self.calls = []
    def run_phase(self, p, phase):
        self.calls.append((phase, p.report['local_c4_executor']['cursor']))
        if phase == 'C4':
            p.report['local_c4_executor']['cursor'] = 'AI_REVIEW'
        elif not hasattr(p, '_root_c2_executor_v2'):
            p._root_c2_executor_v2 = Executor()
        else: p._root_c2_executor_v2.cursor += 1
    def _capture_rows(self, p, c2, executor, stage):
        p.events.append('read_capture_bindings')
        return {'root': {'witness': module.digest(p.rows)}}
    def _safe_capture(self, p, c2, executor, stage):
        p.events.append('safe_capture_only')
        row = p.media('C2-' + stage + '-1.png')
        return dict(row, node_bindings=self._capture_rows(p, c2, executor, stage))


class C2OnlyDispatcher(Dispatcher):
    C2_ENTRY_FILE = 'C2_ENTRY.json'

    def run_phase(self, p, phase):
        if phase != 'C2' or 'local_c4_executor' in p.report:
            raise AssertionError('C2-only continuation must not execute or fabricate C4')
        if not hasattr(p, '_root_c2_executor_v2'):
            self.calls.append((phase, 'CONFIGURE_C2_FROM_C1'))
            self.entry_records = {name: json.loads((p.out / name).read_text())
                                  for name in (self.C1_FILE, self.C2_ENTRY_FILE)}
            p._root_c2_executor_v2 = Executor()
        else:
            self.calls.append((phase, p._root_c2_executor_v2.cursor))
            p._root_c2_executor_v2.cursor += 1


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='offline-controller-', dir=HERE)
        self.probe = Probe(Path(self.folder.name))
        self.authority = Authority()
        self.context = SimpleNamespace(phase='C1', cursor='INITIAL_C1')
        self.clock = 0
        self.dispatcher = Dispatcher()
        self.runtime_calls = []
        self.controller = module.Controller(probe=self.probe, c4=C4, c2=C2, dispatcher=self.dispatcher,
            fixture_api_class=FixtureApi, public_reference_reader=lambda **kwargs: [{'title': 'PUBLISHED_SYNTHETIC'}],
            boot_runtime=lambda **kwargs: self.runtime_calls.append(('boot', kwargs)),
            close_runtime=self.close, authority_getter=lambda: self.authority,
            context_getter=lambda: self.context, work_deadline_getter=lambda: 5400,
            monotonic_clock=lambda: self.clock, wait=lambda seconds: setattr(self, 'clock', self.clock+seconds))
        self.old_now = evidence.utc_now
        evidence.utc_now = lambda: NOW
    def tearDown(self): evidence.utc_now = self.old_now; self.folder.cleanup()
    def close(self, **kwargs):
        self.runtime_calls.append(('close', kwargs))
        return {'vm_created': True, 'relay_created': False, 'vm_exit_code': 0, 'relay_exit_code': None,
            'owned_process_group_absence_observed': True, 'all_created_processes_observed_ended': True}
    def initial(self):
        self.controller.prepare_runtime()
        self.assertTrue(self.controller.prepare_initial_native())
        self.controller.bootstrap_fixture()
        self.controller.quiesce_for_checkpoint()
        self.assertTrue(self.controller.initial_c1())
        self.probe.fixture_api.native_title = self.probe.title
    def root(self, phase='C4'):
        self.authority = Authority('ROOT_VERIFIED')
        self.authority.monotonic_deadline = 120
        self.context.phase = phase
    def signed(self, snapshot, **extra):
        return {'review_completed_utc': '2026-11-04T12:00:00Z',
            'checkpoint_binding_sha256': snapshot['stage']['bindings']['checkpoint_binding_sha256'], **extra}

    def c2_only_initial(self):
        self.dispatcher = C2OnlyDispatcher()
        self.controller = module.Controller(probe=self.probe, c4=C4, c2=C2, dispatcher=self.dispatcher,
            fixture_api_class=FixtureApi, public_reference_reader=lambda **kwargs: [{'title': 'PUBLISHED_SYNTHETIC'}],
            boot_runtime=lambda **kwargs: self.runtime_calls.append(('boot', kwargs)), close_runtime=self.close,
            authority_getter=lambda: self.authority, context_getter=lambda: self.context,
            work_deadline_getter=lambda: 5400, monotonic_clock=lambda: self.clock,
            wait=lambda seconds: setattr(self, 'clock', self.clock+seconds), entry_mode='c2_only')
        original_create = self.probe.create_and_save
        def create():
            original_create()
            self.probe.media('C1-photo-selected.png')
        self.probe.create_and_save = create
        def no_c4_state():
            raise AssertionError('C2-only path must not initialize C4')
        self.controller._c4_state = no_c4_state
        self.initial()
        self.root('C2')

    def c2_entry_reviews(self):
        stamp = '2026-11-04T12:00:00Z'
        return ({'review_completed_utc': stamp, 'fixture_key': KEY, 'fixture_tag': TAG,
                 'native_title': self.probe.title, 'c1_accepted': True},
                {'review_completed_utc': stamp, 'fixture_key': KEY, 'fixture_tag': TAG,
                 'entry_mode': 'standard_editor'})

    def test_c2_only_entry_binds_three_actual_c1_frames_and_never_creates_c4(self):
        self.c2_only_initial()
        snapshot = self.controller.snapshot()
        self.assertEqual((snapshot['phase'], snapshot['cursor']), ('C2', 'CONFIGURE_C2_FROM_C1'))
        self.assertEqual(snapshot['stage']['context'], 'CONFIGURE_C2_FROM_C1')
        self.assertEqual(snapshot['stage']['requested_review_fields'], ['c1_review', 'c2_entry_review'])
        wanted = ['C1-photo-selected.png', 'C1-restored-complete-photo.png', 'C1-restored-title.png']
        self.assertEqual([row['file'] for row in snapshot['evidence']], wanted)
        bindings = snapshot['stage']['bindings']
        self.assertEqual(bindings['entry_mode'], 'standard_editor')
        self.assertEqual(bindings['c1_monthly_rent_blank_checks'], {'before_save': True, 'after_reopen': True})
        self.assertEqual(bindings['configuration_frames'], [
            {'file': row['file'], 'sha256': row['sha256']} for row in snapshot['evidence']])
        self.assertTrue(self.controller.fresh_scene_matches(self.signed(snapshot), snapshot))
        self.assertNotIn('local_c4_executor', self.probe.report)
        self.assertEqual(self.dispatcher.calls, [])

    def test_c2_only_entry_refuses_missing_c1_hold_cases_blank_checks_and_existing_c4(self):
        self.c2_only_initial()
        original = copy.deepcopy(self.probe.report)
        mutations = [
            lambda r: r.pop('held_after_c1_restore_for_root_review'),
            lambda r: r['cases'].clear(),
            lambda r: r.__setitem__('cases', [x for x in r['cases'] if x['id'] != 'C1-force-stop-restore']),
            lambda r: r.pop('c1_monthly_rent_blank_checks'),
            lambda r: r['c1_monthly_rent_blank_checks'].__setitem__('after_reopen', False),
            lambda r: r['c1_monthly_rent_blank_checks'].__setitem__('before_save', 1),
            lambda r: r['c1_monthly_rent_blank_checks'].__setitem__('unverified_extra', True),
            lambda r: r.__setitem__('local_c4_executor', {'accepted': True}),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                self.probe.report = copy.deepcopy(original)
                mutate(self.probe.report)
                with self.assertRaises(module.ControllerRefused): self.controller.snapshot()
                self.assertEqual(self.dispatcher.calls, [])
        self.probe.report = original

    def test_c2_only_entry_refuses_missing_or_changed_original_photo_before_dispatch(self):
        self.c2_only_initial()
        original = copy.deepcopy(self.probe.report['frames'])
        for name in ('C1-photo-selected.png', 'C1-restored-complete-photo.png', 'C1-restored-title.png'):
            with self.subTest(name=name):
                self.probe.report['frames'] = [row for row in original if row['file'] != name]
                with self.assertRaises(module.ControllerRefused): self.controller.snapshot()
        self.probe.report['frames'] = original
        snapshot = self.controller.snapshot()
        (self.probe.out / 'C1-photo-selected.png').write_bytes(b'CHANGED_SYNTHETIC_IMAGE')
        self.assertFalse(self.controller.fresh_scene_matches(self.signed(snapshot), snapshot))
        c1, entry = self.c2_entry_reviews()
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot, c1_review=c1, c2_entry_review=entry))
        self.assertEqual(self.dispatcher.calls, [])
        self.assertFalse((self.probe.out / self.dispatcher.C2_ENTRY_FILE).exists())

    def test_c2_only_entry_requires_exact_review_schema_and_copies_current_proofs(self):
        self.c2_only_initial()
        snapshot = self.controller.snapshot()
        c1, entry = self.c2_entry_reviews()
        for extras in ({}, {'c1_review': c1}, {'c1_review': c1, 'c4_review': entry},
                       {'c1_review': c1, 'c2_entry_review': entry, 'phase_review': {}},
                       {'c1_review': c1, 'c2_entry_review': entry, 'c4_review': entry}):
            with self.subTest(keys=sorted(extras)):
                with self.assertRaises(module.ControllerRefused): self.controller.advance(self.signed(snapshot, **extras))
                self.assertEqual(self.dispatcher.calls, [])
        self.assertTrue(self.controller.advance(self.signed(snapshot, c1_review=c1, c2_entry_review=entry)))
        self.assertEqual(self.dispatcher.calls, [('C2', 'CONFIGURE_C2_FROM_C1')])
        self.assertEqual(self.dispatcher.entry_records,
                         {self.dispatcher.C1_FILE: c1, self.dispatcher.C2_ENTRY_FILE: entry})
        self.assertFalse((self.probe.out / self.dispatcher.C4_FILE).exists())
        self.assertNotIn('local_c4_executor', self.probe.report)
        self.assertEqual(self.probe._root_c2_executor_v2.cursor, 0)
        self.assertEqual(self.probe.events.count('actual_helper_utc_preflight'), 3)
        next_snapshot = self.controller.snapshot()
        self.assertEqual((next_snapshot['phase'], next_snapshot['cursor']), ('C2', 'C2_0_LOAD_ROLES'))
        self.assertEqual(next_snapshot['stage']['requested_review_fields'], [])
        self.assertTrue(self.controller.advance(self.signed(next_snapshot)))
        self.assertEqual(self.probe._root_c2_executor_v2.cursor, 1)
        self.assertNotIn('local_c4_executor', self.probe.report)

    def test_c2_only_entry_refuses_stale_c1_review_without_refresh_or_dispatch(self):
        self.c2_only_initial()
        snapshot = self.controller.snapshot()
        c1, entry = self.c2_entry_reviews()
        c1['review_completed_utc'] = '2026-11-04T11:00:00Z'
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot, c1_review=c1, c2_entry_review=entry))
        self.assertEqual(c1['review_completed_utc'], '2026-11-04T11:00:00Z')
        self.assertEqual(self.dispatcher.calls, [])
        self.assertTrue(self.controller.uncertain())
        self.assertNotIn('local_c4_executor', self.probe.report)

    def test_c2_only_entry_configuration_must_stop_at_cursor_zero_and_cannot_replay(self):
        self.c2_only_initial()
        snapshot = self.controller.snapshot()
        c1, entry = self.c2_entry_reviews()
        def skip_configuration(p, phase):
            self.dispatcher.calls.append((phase, 'INVALID_SKIPPED_STAGE'))
            p._root_c2_executor_v2 = Executor(cursor=1)
        self.dispatcher.run_phase = skip_configuration
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot, c1_review=c1, c2_entry_review=entry))
        self.assertTrue(self.controller.uncertain())
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot, c1_review=c1, c2_entry_review=entry))
        self.assertEqual(self.dispatcher.calls, [('C2', 'INVALID_SKIPPED_STAGE')])
        self.assertNotIn('local_c4_executor', self.probe.report)

    def test_boot_is_vm_only_and_public_network_precedes_single_fixture_seed(self):
        self.controller.prepare_runtime()
        self.assertEqual(self.probe.events, [])
        with self.assertRaises(module.ControllerRefused): self.controller.bootstrap_fixture()
        self.assertTrue(self.controller.prepare_initial_native())
        self.assertIsNone(self.probe.fixture_api)
        self.controller.bootstrap_fixture()
        self.assertEqual(self.probe.fixture_api.calls, ['bootstrap'])
        self.assertEqual(self.probe.events[:5], ['C1-native-network','install','display_verified','startup','actual_helper_utc_preflight'])
        with self.assertRaises(module.ControllerRefused): self.controller.prepare_initial_native()
        with self.assertRaises(module.ControllerRefused): self.controller.bootstrap_fixture()

    def test_missing_native_card_blocks_api_seed_and_cannot_restart_prepare(self):
        self.controller.prepare_runtime()
        self.probe.rows = []
        self.assertFalse(self.controller.prepare_initial_native())
        with self.assertRaises(module.ControllerRefused): self.controller.bootstrap_fixture()
        with self.assertRaises(module.ControllerRefused): self.controller.prepare_initial_native()
        self.assertIsNone(self.probe.fixture_api)

    def test_preflight_failure_records_fixed_stage_without_raw_error_or_api_seed(self):
        self.controller.prepare_runtime()
        def fail():
            raise RuntimeError('SYNTHETIC_PRIVATE_FAILURE')
        self.probe.preflight_deadline_helper = fail
        with self.assertRaises(RuntimeError):
            self.controller.prepare_initial_native()
        self.assertEqual(self.probe.report['initial_native_readiness_stage'], 'helper_clock_preflight')
        self.assertNotIn('SYNTHETIC_PRIVATE_FAILURE', json.dumps(self.probe.report))
        self.assertIsNone(self.probe.fixture_api)
        with self.assertRaises(module.ControllerRefused):
            self.controller.bootstrap_fixture()
        with self.assertRaises(module.ControllerRefused):
            self.controller.prepare_initial_native()

    def test_c1_capture_failure_preserves_fixed_diagnostic_before_logout_cleanup_stage(self):
        self.controller.prepare_runtime()
        self.controller.prepare_initial_native()
        self.controller.bootstrap_fixture()
        def fail():
            self.probe.report['native_journey_stages']={'C1-photo-save':'home_wait'}
            raise RuntimeError('host_png_dimensions_or_structure_invalid')
        self.probe.create_and_save=fail
        with self.assertRaises(RuntimeError):self.controller.initial_c1()
        self.probe.report['native_journey_stages']['C1-photo-save']='logout_confirm'
        self.assertEqual(self.probe.report['initial_c1_failure_before_cleanup'], {
            'case':'C1-photo-save','code':'host_png_dimensions_or_structure_invalid','stage':'home_wait'})
        with self.assertRaises(module.ControllerRefused):self.controller.initial_c1()

    def test_unknown_c1_error_never_exports_error_arguments_or_arbitrary_stage(self):
        self.controller.prepare_runtime()
        self.controller.prepare_initial_native()
        self.controller.bootstrap_fixture()
        def fail():
            self.probe.report['native_journey_stages']={'C1-photo-save':'SYNTHETIC_PRIVATE_STAGE'}
            raise RuntimeError('SYNTHETIC_PRIVATE_EXCEPTION')
        self.probe.create_and_save=fail
        with self.assertRaises(RuntimeError):self.controller.initial_c1()
        result=self.probe.report['initial_c1_failure_before_cleanup']
        self.assertEqual(result,{'case':'C1-photo-save','code':'controller_phase_failed','stage':None})
        self.assertNotIn('SYNTHETIC_PRIVATE',json.dumps(result))

    def test_fixed_video_refusal_is_preserved_without_arbitrary_probe_output(self):
        self.controller.prepare_runtime();self.controller.prepare_initial_native();self.controller.bootstrap_fixture()
        def fail():
            self.probe.report['native_journey_stages']={'C1-photo-save':'photo_capture'}
            raise RuntimeError('host_webm_stream_or_duration_invalid')
        self.probe.create_and_save=fail
        with self.assertRaises(RuntimeError):self.controller.initial_c1()
        self.assertEqual(self.probe.report['initial_c1_failure_before_cleanup'],{
            'case':'C1-photo-save','code':'host_webm_stream_or_duration_invalid','stage':'photo_capture'})

    def test_initial_cases_real_callback_order_and_minimal_summary(self):
        self.initial()
        actions = [event for event in self.probe.events if event in {'login','create','restore','hold'}]
        self.assertEqual(actions, ['login','create','restore','hold'])
        summary = self.controller.fixture_summary()
        self.assertEqual(set(summary), {'fixture','baseline'})
        self.assertEqual(set(summary['fixture']), {'draft_uuid','tag','actor_id','property_id'})
        self.assertEqual(summary['baseline']['properties']['count'],25)
        self.assertNotIn('synthetic-0', json.dumps(summary))
        with self.assertRaises(module.ControllerRefused): self.controller.initial_c1()

    def test_snapshot_is_read_only_no_general_phase_calls_and_wire_frame_list(self):
        self.initial()
        before = list(self.dispatcher.calls)
        snapshot = self.controller.snapshot()
        self.assertEqual(self.dispatcher.calls, before)
        self.assertEqual(snapshot['phase'], 'C4')
        self.assertIsInstance(snapshot['stage']['bindings']['frames'], list)
        self.assertNotIn('phase_review', snapshot)
        self.assertEqual(set(snapshot), {'phase','cursor','stage','evidence'})
        self.assertFalse(any('manual_review_completed' in row for row in snapshot['evidence']))
        self.assertTrue(self.controller.fresh_scene_matches(self.signed(snapshot), snapshot))
        self.probe.rows = [{'text':'CHANGED', 'visible':True}]
        self.assertFalse(self.controller.fresh_scene_matches(self.signed(snapshot), snapshot))

    def test_contact_stage_has_no_tree_or_hash_observation(self):
        self.initial()
        state = self.controller._c4_state(); state['cursor'] = 'SAVE'
        self.probe.private_scene = True
        self.probe.events.clear()
        snapshot = self.controller.snapshot()
        self.assertEqual(snapshot['evidence'], [])
        self.assertNotIn('safe_scene_sha256', snapshot['stage']['bindings'])
        self.assertEqual(self.probe.events, ['nonimage_blank_rent'])
        self.assertTrue(self.controller.fresh_scene_matches(self.signed(snapshot), snapshot))
        self.assertNotIn('read_full_rows', self.probe.events)

    def _completion_save_checkpoint(self):
        preview = {'kind':'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'fixture_key':KEY,
                   'fixture_tag':TAG, 'editor_chain':'C2-V2:'+KEY,
                   'rent_text':'50000', 'sai_rate_text':'0'}
        def forbidden(*args, **kwargs):
            raise AssertionError('completion checkpoint must not read hidden rent/SAI inputs')
        self.probe.field = forbidden
        self.probe.scroll = forbidden
        self.probe._root_c2_executor_v2 = SimpleNamespace(
            failed=False, inflight=False, rent_sai_readback=preview,
            rent_sai_recheck=dict(preview), _rent_sai_preview=forbidden,
            _actor=lambda role: self.probe.events.append('actor_'+role))
        self.probe.rows = [{'text':label,'visible':True} for label in
                           ('أكمل الناقص فقط','خيارات المسودة')]
        return self.probe._root_c2_executor_v2

    def test_completion_save_checkpoint_uses_serialized_preview_and_actual_surface_without_hidden_inputs(self):
        self._completion_save_checkpoint()
        observed = self.controller._observation('C2','C2_7_FULL_SAVE','full_save',capture=True)
        self.assertEqual(observed['evidence'],[])
        self.assertEqual(observed['bindings'],{'observation_mode':'nonimage_stage_predicates'})
        self.assertEqual(self.probe.events,['actor_broker','read_nodes'])

    def test_completion_save_checkpoint_refuses_missing_or_changed_preview(self):
        for readback,recheck in [(None,None),({},{}),({'rent_text':'50000'},None),
                                  ({'rent_text':'50000'},{'rent_text':'50001'})]:
            with self.subTest(readback=readback,recheck=recheck):
                executor=self._completion_save_checkpoint()
                executor.rent_sai_readback,executor.rent_sai_recheck=readback,recheck
                with self.assertRaisesRegex(module.ControllerRefused,'same_actual_preview_required'):
                    self.controller._nonimage_check('C2','full_save')

    def test_completion_save_checkpoint_refuses_missing_surface_or_auth_context(self):
        for labels in [(),('أكمل الناقص فقط',),('خيارات المسودة',),
                       ('أكمل الناقص فقط','خيارات المسودة','AUTH_SYNTHETIC')]:
            with self.subTest(labels=labels):
                self._completion_save_checkpoint()
                self.probe.rows=[{'text':label,'visible':True} for label in labels]
                with self.assertRaisesRegex(module.ControllerRefused,'actual_completion_save_surface_required'):
                    self.controller._nonimage_check('C2','full_save')

    def _rent_navigation_checkpoint(self, stage):
        executor = self._completion_save_checkpoint()
        executor.rent_sai_readback.update(fallback_notice='SYNTHETIC_FALLBACK',recording_stopped=True)
        executor.rent_sai_recheck=dict(executor.rent_sai_readback)
        executor.cursor = 3 if stage == 'navigate_previous_to_specs' else 6
        previous = 'complete_rent' if executor.cursor == 3 else 'return_next_step3'
        self.probe.report['c2_segmented_execution']=[{'status':'STAGE_COMPLETED',
            'completed':previous,'cursor':executor.cursor,'next_stage':stage}]
        self.probe.rows=[{'text':label,'visible':True,'enabled':True} for label in
                        ('نسبة السعي %','SYNTHETIC_FALLBACK','السابق','العودة إلى النواقص')]
        return executor

    def test_rent_navigation_checkpoint_binds_previous_actual_readback_without_seeking_hidden_rent(self):
        for stage in ('navigate_previous_to_specs','back_gaps_to_completion'):
            with self.subTest(stage=stage):
                self._rent_navigation_checkpoint(stage)
                self.probe.events.clear()
                observed=self.controller._observation('C2','SYNTHETIC_CURSOR',stage,capture=True)
                self.assertEqual(self.probe.events,['actor_broker','read_nodes'])
                self.assertEqual(observed['evidence'],[])
                self.assertEqual(observed['bindings'],{'observation_mode':'nonimage_stage_predicates'})

    def test_rent_navigation_checkpoint_refuses_wrong_predecessor_cursor_or_changed_recheck(self):
        for fault in ('missing_receipt','wrong_predecessor','wrong_cursor','wrong_next_stage','changed_recheck','missing_preview'):
            with self.subTest(fault=fault):
                executor=self._rent_navigation_checkpoint('back_gaps_to_completion')
                receipt=self.probe.report['c2_segmented_execution'][-1]
                if fault=='missing_receipt':self.probe.report['c2_segmented_execution']=[]
                elif fault=='wrong_predecessor':receipt['completed']='complete_rent'
                elif fault=='wrong_cursor':receipt['cursor']=3
                elif fault=='wrong_next_stage':receipt['next_stage']='full_save'
                elif fault=='changed_recheck':executor.rent_sai_recheck['rent_text']='50001'
                else:executor.rent_sai_readback=None
                with self.assertRaisesRegex(module.ControllerRefused,'immediately_preceding_rent_sai_readback_required'):
                    self.controller._nonimage_check('C2','back_gaps_to_completion')

    def test_rent_navigation_checkpoint_refuses_wrong_surface_disabled_control_or_auth(self):
        for fault in ('missing_rate','missing_fallback','missing_back','disabled_previous','auth'):
            with self.subTest(fault=fault):
                self._rent_navigation_checkpoint('navigate_previous_to_specs')
                removed={'missing_rate':'نسبة السعي %','missing_fallback':'SYNTHETIC_FALLBACK',
                         'missing_back':'العودة إلى النواقص'}.get(fault)
                if removed:self.probe.rows=[r for r in self.probe.rows if r['text']!=removed]
                elif fault=='disabled_previous':
                    next(r for r in self.probe.rows if r['text']=='السابق')['enabled']=False
                else:self.probe.rows.append({'text':'AUTH_SYNTHETIC','visible':True})
                with self.assertRaisesRegex(module.ControllerRefused,'actual_reviewed_rent_navigation_surface_required'):
                    self.controller._nonimage_check('C2','navigate_previous_to_specs')

    def test_complete_rent_checkpoint_reads_visible_blank_field_with_seek_disabled(self):
        self._completion_save_checkpoint()
        calls=[]
        def field(label, *, seek):
            calls.append((label,seek))
            self.assertIs(seek,False)
            return {'text':''}
        self.probe.field=field
        self.controller._nonimage_check('C2','complete_rent')
        self.assertEqual(calls,[('الإيجار الشهري بالريال اليمني *',False)])

    def test_safe_photo_checkpoint_transports_observed_policy_without_extra_data_or_acceptance(self):
        self.controller.c2 = SimpleNamespace(TARGETS={}, REVIEW_STAGES={'review_photo_before_save'})
        preview = {'kind':'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'fixture_key':KEY,
            'fixture_tag':TAG, 'editor_chain':'C2-V2:'+KEY, 'rent_text':'50000',
            'sai_rate_text':'0', 'fallback_notice':'اختيار 0% يفعّل السعي الثابت 50% تلقائيًا.',
            'recording_stopped':True, 'custom_terms_visible':False,
            'policy_was_visually_reviewed':False, 'persisted_policy_configuration_proved':False,
            'native_contact_readback_matches_fixture':True, 'contact_policy_valid':True,
            'optional_contact_empty':True, 'contact_policy_observed_in_ui':True}
        self.probe._root_c2_executor_v2 = SimpleNamespace(
            failed=False, inflight=False, cursor=4, entry_mode='standard_editor',
            rent_sai_readback=dict(preview, unrelated_private_value='PRIVATE_SENTINEL'))
        observed = self.controller._observation('C2', 'C2_4_REVIEW_PHOTO_BEFORE_SAVE',
            'review_photo_before_save', capture=True)
        self.assertEqual(observed['bindings']['semantic_preview'], preview)
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(observed))
        self.assertEqual(len(observed['evidence']), 1)
        self.assertEqual(self.dispatcher.calls, [])
        self.assertNotIn('manual_review_completed', observed['bindings'])

    def test_signed_review_is_copied_exactly_one_stage_no_approval_created(self):
        self.initial(); self.root()
        snapshot = self.controller.snapshot()
        # A synthetic signed payload tests faithful file transport only. The
        # original executor (not this fake dispatcher) owns affirmative checks.
        record = {'review_completed_utc':'2026-11-04T12:00:00Z', 'manual_review_completed':False}
        review = self.signed(snapshot, phase_review=record)
        self.assertTrue(self.controller.advance(review))
        path = self.probe.out / 'C4_ROOT_C1_REVIEW.json'
        self.assertEqual(json.loads(path.read_text()), record)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(len(self.dispatcher.calls), 1)
        self.assertFalse(self.controller.uncertain())
        self.assertEqual(self.probe.events.count('actual_helper_utc_preflight'), 3)

    def test_failed_phase_is_latched_and_never_replayed(self):
        self.initial(); self.root()
        snapshot = self.controller.snapshot()
        self.dispatcher.run_phase = lambda *args: None
        record={'review_completed_utc':'2026-11-04T12:00:00Z'}
        with self.assertRaises(module.ControllerRefused): self.controller.advance(self.signed(snapshot, phase_review=record))
        self.assertTrue(self.controller.uncertain())
        with self.assertRaises(module.ControllerRefused): self.controller.advance(self.signed(snapshot, phase_review=record))

    def test_prepared_request_checkpoint_needs_fresh_common_authority_and_no_visual_flags(self):
        self.initial(); self.root()
        state=self.controller._c4_state()
        state.update(cursor='REQUEST',prepared_brief_scene=SHA)
        snapshot=self.controller.snapshot()
        self.assertEqual(snapshot['stage']['context'],'REQUEST')
        self.assertEqual(snapshot['stage']['requested_review_fields'],[])
        self.assertEqual(snapshot['evidence'],[])
        self.assertIn('prepared_brief_exact_readback',self.probe.events)
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot,phase_review={}))
        self.assertEqual(self.dispatcher.calls,[])
        self.assertTrue(self.controller.advance(self.signed(snapshot)))
        self.assertEqual(self.dispatcher.calls,[('C4','REQUEST')])
        self.assertEqual(state['cursor'],'AI_REVIEW')

    def test_response_ready_exports_only_original_snapshot_and_requires_fresh_no_flag_authority(self):
        self.initial();self.root()
        state=self.controller._c4_state()
        row=self.probe.media('C1-c4-response-ready.png')
        state.update(cursor='RESPONSE_READY',response_ready_scene=SHA,
            response_ready_frames={'C1-c4-response-ready.png':row['sha256']})
        snapshot=self.controller.snapshot()
        self.assertEqual(snapshot['stage']['context'],'RESPONSE_READY')
        self.assertEqual(snapshot['stage']['requested_review_fields'],[])
        self.assertEqual([x['file'] for x in snapshot['evidence']],['C1-c4-response-ready.png'])
        self.assertEqual(snapshot['stage']['bindings']['frames'],[{'file':'C1-c4-response-ready.png','sha256':row['sha256']}])
        with self.assertRaises(module.ControllerRefused):
            self.controller.advance(self.signed(snapshot,phase_review={}))
        self.assertEqual(self.dispatcher.calls,[])
        self.assertTrue(self.controller.advance(self.signed(snapshot)))
        self.assertEqual(self.dispatcher.calls,[('C4','RESPONSE_READY')])

    def test_c2_configuration_requires_fresh_actual_two_proofs_without_refresh(self):
        self.initial(); self.root('C2')
        state = self.controller._c4_state(); state.update(accepted=True, cursor='C4_SAVED_RESTORED_HOLD_FOR_C2')
        self.probe.media('C1-c4-restored-final-title.png')
        snapshot = self.controller.snapshot()
        self.assertEqual(snapshot['cursor'],'CONFIGURE_C2')
        self.assertEqual(self.dispatcher.calls,[])
        c1={'review_completed_utc':'2026-11-04T12:00:00Z','c1_accepted':False}
        c4={'review_completed_utc':'2026-11-04T11:00:00Z','c4_accepted':False}
        with self.assertRaises(module.ControllerRefused): self.controller.advance(self.signed(snapshot,c1_review=c1,c4_review=c4))
        self.assertEqual(c4['review_completed_utc'],'2026-11-04T11:00:00Z')
        self.assertEqual(self.dispatcher.calls,[])

    def test_c2_safe_gate_snapshot_captures_only_and_freshness_checks_exact_bindings(self):
        self.initial(); self.root('C2')
        self.controller._c4_state().update(accepted=True, cursor='C4_SAVED_RESTORED_HOLD_FOR_C2')
        self.probe._root_c2_executor_v2 = Executor(cursor=2)
        snapshot = self.controller.snapshot()
        self.assertIn('safe_capture_only', self.probe.events)
        self.assertEqual(self.dispatcher.calls,[])
        self.assertTrue(self.controller.fresh_scene_matches(self.signed(snapshot),snapshot))
        self.probe.rows = [{'text':'changed','visible':True}]
        self.assertFalse(self.controller.fresh_scene_matches(self.signed(snapshot),snapshot))

    def pending_review_setup(self, change=None):
        for name in (Dispatcher.C1_FILE, Dispatcher.C4_FILE, Dispatcher.STAGE_FILE):
            (Path(self.folder.name) / name).unlink(missing_ok=True)
        self.probe = Probe(Path(self.folder.name))
        self.authority, self.context = Authority(), SimpleNamespace(phase='C1', cursor='INITIAL_C1')
        self.dispatcher = Dispatcher()
        reason = 'safe_photo_plus_serialized_identity_and_nonimage_policy_review_required'
        def capture(probe, c2, executor, stage):
            index = probe.events.count('safe_capture_only') + 1
            probe.events.append('safe_capture_only')
            row = probe.media('C2-' + stage + '-' + str(index) + '.png')
            return dict(row, node_bindings=self.dispatcher._capture_rows(probe,c2,executor,stage))
        self.dispatcher._safe_capture = capture
        c2 = SimpleNamespace(STAGES=('load_roles','complete_rent','review_photo_before_save','cleanup'),
            TARGETS={}, REVIEW_STAGES={'review_photo_before_save'}, roles=C2.roles,
            _names=C2._names, PREPARE_REFUSAL_REASONS=frozenset({reason}))
        self.controller = module.Controller(probe=self.probe, c4=C4, c2=c2, dispatcher=self.dispatcher,
            fixture_api_class=FixtureApi, public_reference_reader=lambda **kwargs: [{'title':'PUBLISHED_SYNTHETIC'}],
            boot_runtime=lambda **kwargs: None, close_runtime=self.close,
            authority_getter=lambda:self.authority, context_getter=lambda:self.context,
            work_deadline_getter=lambda:5400, monotonic_clock=lambda:self.clock,
            wait=lambda seconds:None)
        self.initial(); self.root('C2')
        self.controller._c4_state().update(accepted=True, cursor='C4_SAVED_RESTORED_HOLD_FOR_C2')
        executor = Executor(cursor=2)
        executor.entry_mode = 'standard_editor'
        executor.preparation_attempt, executor.pending_preparation, executor.reviews = 0, None, {}
        executor.rent_sai_readback = {'kind':'NATIVE_NONIMAGE_RENT_SAI_PREVIEW',
            'fixture_key':KEY,'fixture_tag':TAG,'editor_chain':'C2-V2:'+KEY,
            'rent_text':'50000','sai_rate_text':'0','fallback_notice':'SYNTHETIC_FALLBACK',
            'recording_stopped':True,'custom_terms_visible':False,
            'policy_was_visually_reviewed':False,'persisted_policy_configuration_proved':False,
            'native_contact_readback_matches_fixture':True,'contact_policy_valid':True,
            'optional_contact_empty':True,'contact_policy_observed_in_ui':True}
        self.probe._root_c2_executor_v2 = executor
        def pending(probe, phase):
            self.dispatcher.calls.append((phase, executor.cursor))
            path = probe.out / self.dispatcher.STAGE_FILE
            executor.reviews['review_photo_before_save'] = json.loads(path.read_text())
            path.unlink()  # The dispatcher consumes the exact review before _prepare.
            executor.preparation_attempt += 1
            proof = {'attempt':executor.preparation_attempt,'stage':'review_photo_before_save',
                'cursor':2,'preparation_only':True,'execution_called':False,
                'reservation_created':False,'failed':False,'inflight':False,'reason':reason}
            executor.pending_preparation = copy.deepcopy(proof)
            result = {'requested_phase':'C2','status':'PENDING_ROOT_REVIEW','cursor':2,
                'pending':'review_photo_before_save','next_stage':'review_photo_before_save',
                'uncertain':False,'automatic_replay_allowed':False,'phase1_accepted':False,
                'report_persisted':True,'dispatcher_version':2,'pending_preparation':proof}
            if change: change(probe, executor, result)
            return result
        self.dispatcher.run_phase = pending
        snapshot = self.controller.snapshot()
        review = self.signed(snapshot, phase_review={'review_completed_utc':'2026-11-04T12:00:00Z'})
        return executor, snapshot, review

    def test_proven_readonly_c2_pending_creates_fresh_checkpoint_without_replaying_review(self):
        executor, old, review = self.pending_review_setup()
        self.probe._root_c2_v2_last_capture = {'stage':'review_photo_before_save','file':'OLD'}
        self.assertTrue(self.controller.advance(review))
        self.assertEqual(executor.cursor, 2)
        self.assertFalse(self.controller.uncertain())
        self.assertIsNone(self.controller._snapshot)
        self.assertNotIn('review_photo_before_save', executor.reviews)
        self.assertNotIn('review_photo_before_save', self.probe._root_c2_v2_pending_frames)
        self.assertFalse(hasattr(self.probe, '_root_c2_v2_last_capture'))
        self.assertFalse(self.controller.fresh_scene_matches(review, old))
        self.assertEqual(self.dispatcher.calls, [('C2',2)])
        captures = self.probe.events.count('safe_capture_only')
        fresh = self.controller.snapshot()
        self.assertEqual(fresh['cursor'], old['cursor'])
        self.assertEqual(self.probe.events.count('safe_capture_only'), captures+1)
        pending = fresh['stage']['bindings']['pending_preparation']
        self.assertEqual(pending['attempt'], 1)
        self.assertEqual(pending['reason'], 'safe_photo_plus_serialized_identity_and_nonimage_policy_review_required')
        self.assertNotEqual(fresh['stage']['bindings']['checkpoint_binding_sha256'],
                            old['stage']['bindings']['checkpoint_binding_sha256'])
        self.assertFalse(self.controller.fresh_scene_matches(review, fresh))
        # Only a new bound review can attempt the same observation stage again.
        new_review = self.signed(fresh, phase_review={'review_completed_utc':'2026-11-04T12:00:00Z'})
        self.assertTrue(self.controller.advance(new_review))
        self.assertEqual(executor.preparation_attempt, 2)
        self.assertEqual(self.dispatcher.calls, [('C2',2),('C2',2)])
        self.assertFalse(self.controller.finished())

    def test_readonly_pending_then_new_review_advances_once_and_clears_pending_binding(self):
        executor, _, review = self.pending_review_setup()
        self.assertTrue(self.controller.advance(review))
        fresh = self.controller.snapshot()
        def completed(probe, phase):
            self.dispatcher.calls.append((phase, executor.cursor))
            (probe.out / self.dispatcher.STAGE_FILE).unlink()
            executor.preparation_attempt += 1
            executor.pending_preparation = None
            executor.cursor += 1
            return {'status':'STAGE_COMPLETED','cursor':executor.cursor}
        self.dispatcher.run_phase = completed
        self.assertTrue(self.controller.advance(self.signed(fresh,
            phase_review={'review_completed_utc':'2026-11-04T12:00:00Z'})))
        self.assertEqual(executor.cursor, 3)
        self.assertIsNone(self.controller._c2_pending_preparation)
        self.assertIsNone(self.controller._snapshot)
        self.assertFalse(self.controller.uncertain())

    def test_pending_preparation_never_recovers_mutation_uncertainty_or_unproven_receipts(self):
        faults = [
            lambda p,e,r:r.pop('pending_preparation'),
            lambda p,e,r:r.update(status='HELD_LOCAL_REVIEW_REQUIRED'),
            lambda p,e,r:r.update(uncertain=True),
            lambda p,e,r:r.update(report_persisted=False),
            lambda p,e,r:r.update(pending='different_stage'),
            lambda p,e,r:r.update(completed='review_photo_before_save'),
            lambda p,e,r:r.update(oneshot_admission_closed_at_boundary=False),
            lambda p,e,r:setattr(e,'preparation_attempt',0),
            lambda p,e,r:setattr(e,'preparation_attempt',2),
            lambda p,e,r:setattr(e,'failed',True),
            lambda p,e,r:setattr(e,'inflight',True),
            lambda p,e,r:setattr(e,'cursor',3),
            lambda p,e,r:setattr(p,'_root_c2_executor_v2',copy.copy(e)),
            lambda p,e,r:p.admission_metrics.update(state='uncertain'),
            lambda p,e,r:p.admission_metrics.update(inflight=1),
            lambda p,e,r:setattr(p,'adapter',object()),
            lambda p,e,r:setattr(p,'_root_extension_dispatch_v2_save_failed',True),
            lambda p,e,r:setattr(p,'_root_extension_dispatch_v2_admission_failed',True),
            lambda p,e,r:setattr(p,'_root_extension_dispatch_v2_latched',{'C2'}),
            lambda p,e,r:(p.out/self.dispatcher.STAGE_FILE).write_text('{}'),
        ]
        for index, fault in enumerate(faults):
            with self.subTest(fault=index):
                executor, _, review = self.pending_review_setup(fault)
                with self.assertRaises(module.ControllerRefused): self.controller.advance(review)
                self.assertTrue(self.controller._advance_failed)
                self.assertIsNone(self.controller._c2_pending_preparation)
                calls = list(self.dispatcher.calls)
                with self.assertRaises(module.ControllerRefused): self.controller.advance(review)
                self.assertEqual(self.dispatcher.calls, calls)

    def test_pending_proof_requires_fixed_reason_exact_source_record_and_no_execution(self):
        for key, value in [('attempt',0),('attempt',True),('cursor',True),('stage','other'),
                           ('preparation_only',False),('execution_called',True),
                           ('reservation_created',True),('failed',True),('inflight',True),
                           ('reason','PRIVATE_UNCLASSIFIED_REASON')]:
            with self.subTest(key=key,value=value):
                def changed(probe, executor, result):
                    result['pending_preparation'][key] = value
                    executor.pending_preparation = copy.deepcopy(result['pending_preparation'])
                _, _, review = self.pending_review_setup(changed)
                with self.assertRaises(module.ControllerRefused): self.controller.advance(review)
                self.assertIsNone(self.controller._c2_pending_preparation)
        def mismatch(probe, executor, result):
            executor.pending_preparation = None
        _, _, review = self.pending_review_setup(mismatch)
        with self.assertRaises(module.ControllerRefused): self.controller.advance(review)

    def test_target_preparation_remains_fail_closed_even_with_a_pending_proof(self):
        _, _, review = self.pending_review_setup()
        self.controller.c2.TARGETS['review_photo_before_save'] = ('broker','SYNTHETIC','fixture')
        with self.assertRaises(module.ControllerRefused): self.controller.advance(review)
        self.assertTrue(self.controller._advance_failed)

    def test_api_deadline_is_original_authority_bound_and_revocation_refuses(self):
        self.authority.monotonic_deadline = 77
        with self.controller._api_scope('source'):
            self.assertEqual(self.controller._transport.deadline_getter(),77)
            self.authority.active = False
            with self.assertRaises(RuntimeError): self.controller._transport.deadline_getter()
        with self.assertRaises(module.ControllerRefused): self.controller._transport.deadline_getter()

    def test_uncertain_native_completion_disposes_before_api_cleanup_and_cannot_reopen(self):
        self.initial()
        self.controller._advance_failed = True
        self.authority = Authority('OWNER_CLEANUP'); self.context.phase,self.context.cursor='C5','OWNER_CLEANUP'
        self.controller.stop_writers(deadline=500)
        self.assertEqual(self.runtime_calls[-1][0],'close')
        self.assertTrue(self.controller._writers_stopped)
        self.assertTrue(self.controller.uncertain())
        self.assertNotIn('native_logout',self.probe.events)
        self.assertEqual(self.controller.close_runtime(deadline=500), self.close_receipt())
        self.assertEqual(len([row for row in self.runtime_calls if row[0]=='close']),1)

    def close_receipt(self):
        return {'vm_created': True, 'relay_created': False, 'vm_exit_code':0, 'relay_exit_code':None,
            'owned_process_group_absence_observed':True,'all_created_processes_observed_ended':True}

    def cleanup_scope(self):
        self.authority = Authority('OWNER_CLEANUP')
        self.context.phase,self.context.cursor='C5','OWNER_CLEANUP'

    def cleanup_dependencies(self, *, fail_after_delete=False, pin_failure=None):
        path = ADAPTER / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py'
        spec = importlib.util.spec_from_file_location('_controller_actual_normal_session', path)
        actual = importlib.util.module_from_spec(spec); spec.loader.exec_module(actual)
        created = []
        class Helper:
            def __init__(self, api, state):
                self.api, self.events = api, []
                created.append(self)
            def pin_candidate(self, *, native_writers_stopped):
                self.events.append('pin')
                if pin_failure is not None: return pin_failure
                return {'status':'READY','property_id':77}
            def cleanup(self, *, native_writers_stopped):
                self.events.append('cleanup')
                self.api('DELETE','/properties/77')
                if fail_after_delete: raise RuntimeError('SYNTHETIC_UNKNOWN_RESULT')
                self.api('DELETE','/listing-editor-drafts/' + KEY)
                return {'status':'PASS','known_application_rows_removed':True,'protected_baseline_restored':True}
        self.controller.c2 = SimpleNamespace(**{name:getattr(C2,name) for name in
            ['STAGES','TARGETS','REVIEW_STAGES','roles','_names']}, NormalOwnerSession=actual.NormalOwnerSession,
            pin_candidate_diagnostic=actual.pin_candidate_diagnostic,
            cleanup_module=SimpleNamespace(PromotedFixtureCleanup=Helper))
        return created

    def test_unpromoted_cleanup_uses_original_cleaner_once_after_native_stop(self):
        self.initial(); self.cleanup_dependencies(); self.cleanup_scope()
        self.controller.stop_writers(deadline=500)
        self.assertTrue(self.controller.cleanup_once(deadline=500))
        self.assertEqual(self.probe.fixture_api.calls.count('unpromoted_cleanup'),1)
        self.assertTrue(self.controller.fixture_removed_confirmed())
        before=list(self.probe.fixture_api.calls)
        with self.assertRaises(module.ControllerRefused): self.controller.cleanup_once(deadline=500)
        self.assertEqual(self.probe.fixture_api.calls,before)

    def test_actual_api_cleanup_receipt_survives_unconfirmed_native_logout_without_pass(self):
        self.initial(); self.cleanup_dependencies(); self.cleanup_scope()
        self.controller._writers_stopped = True
        self.controller._native_logout = False
        self.assertFalse(self.controller.cleanup_once(deadline=500))
        self.assertEqual(self.probe.report['api_cleanup'], self.probe.fixture_api.last_receipt)
        self.assertTrue(self.probe.report['api_cleanup']['fresh_session_cleaned'])
        self.assertTrue(self.controller.fixture_removed_confirmed())
        self.assertFalse(any(row['id']=='C1-cleanup' and row['status']=='PASS'
                             for row in self.probe.report['cases']))

    def test_promoted_cleanup_pins_and_deletes_property_first_same_helper(self):
        self.initial(); created=self.cleanup_dependencies(); self.cleanup_scope()
        self.probe.fixture_api.property_id = 77
        self.controller.stop_writers(deadline=500)
        self.assertTrue(self.controller.cleanup_once(deadline=500))
        self.assertEqual(len(created),1)
        self.assertIs(self.controller._promoted_cleanup_helper,created[0])
        self.assertEqual(created[0].events,['pin','cleanup'])
        deletes=[row for row in self.probe.fixture_api.calls if type(row) is tuple and row[0]=='DELETE']
        self.assertEqual(deletes,[('DELETE','/properties/77'),('DELETE','/listing-editor-drafts/'+KEY)])
        self.assertNotIn('unpromoted_cleanup',self.probe.fixture_api.calls)
        self.assertTrue(self.probe.fixture_api.logged_out)

    def test_promoted_cleanup_receipt_survives_failed_native_relogin_without_acceptance(self):
        self.initial(); created = self.cleanup_dependencies(); self.cleanup_scope()
        self.probe.fixture_api.property_id = 77
        self.controller._writers_stopped = True
        self.controller._native_logout = False
        self.probe.native_auth_uncertain = True
        self.assertFalse(self.controller.cleanup_once(deadline=500))
        receipt = self.probe.report['c2_promoted_cleanup']
        self.assertEqual(receipt['status'], 'PASS')
        self.assertTrue(receipt['known_application_rows_removed'])
        self.assertTrue(receipt['protected_baseline_restored'])
        self.assertTrue(receipt['fresh_session_cleaned'])
        self.assertEqual(created[0].events, ['pin', 'cleanup'])
        self.assertTrue(self.probe.report['c2_normal_api_sessions'][-1]['logout_http_200'])
        self.assertFalse(any(row['id'] == 'C1-cleanup' and row['status'] == 'PASS'
                             for row in self.probe.report['cases']))
        self.assertTrue(self.probe.native_auth_uncertain)

    def test_promoted_cleanup_receipt_survives_api_revocation_failure_without_false_proof(self):
        self.initial(); created = self.cleanup_dependencies(); self.cleanup_scope()
        self.probe.fixture_api.property_id = 77
        self.controller._writers_stopped = True
        self.controller._native_logout = False
        original = self.probe.fixture_api._call
        def fail_logout(method, path, body=None, token=None):
            if path == '/auth/logout': return 500, {}, 1
            return original(method, path, body, token)
        self.probe.fixture_api._call = fail_logout
        with self.assertRaisesRegex(Exception, '^normal_api_logout_revocation_not_confirmed$'):
            self.controller.cleanup_once(deadline=500)
        receipt = self.probe.report['c2_promoted_cleanup']
        self.assertEqual(receipt['status'], 'PASS')
        self.assertTrue(receipt['known_application_rows_removed'])
        self.assertFalse(receipt['fresh_session_cleaned'])
        self.assertEqual(created[0].events, ['pin', 'cleanup'])
        session = self.probe.report['c2_normal_api_sessions'][-1]
        self.assertFalse(session['logout_http_200'])
        self.assertFalse(session['revoked_token_me_http_401'])
        self.assertFalse(any(row['id'] == 'C1-cleanup' and row['status'] == 'PASS'
                             for row in self.probe.report['cases']))
        self.assertNotIn('SYNTHETIC_SESSION', json.dumps(self.probe.report))

    def test_cleanup_pin_failure_preserves_only_fixed_reason_before_session_wrap(self):
        self.initial()
        created = self.cleanup_dependencies(pin_failure={
            'status': 'BLOCKED', 'reason': 'new_property_ownership_required',
            'payload': 'PRIVATE_BODY', 'token': 'PRIVATE_TOKEN'})
        self.cleanup_scope(); self.probe.fixture_api.property_id = 77
        self.controller.stop_writers(deadline=500)
        with self.assertRaisesRegex(Exception, '^normal_api_work_or_auth_uncertain$'):
            self.controller.cleanup_once(deadline=500)
        self.assertEqual(self.probe.report['c2_cleanup_pin_diagnostic'],
                         {'status': 'BLOCKED', 'reason': 'new_property_ownership_required'})
        self.assertEqual(created[0].events, ['pin'])
        self.assertFalse(any(type(row) is tuple and row[0] == 'DELETE'
                             for row in self.probe.fixture_api.calls))
        self.assertTrue(self.probe.fixture_api.logged_out)
        self.assertNotIn('PRIVATE', json.dumps(self.probe.report))

    def test_unknown_promoted_delete_never_retries_or_falls_back(self):
        self.initial(); created=self.cleanup_dependencies(fail_after_delete=True); self.cleanup_scope()
        self.probe.fixture_api.property_id=77
        self.controller.stop_writers(deadline=500)
        with self.assertRaises(Exception): self.controller.cleanup_once(deadline=500)
        calls=list(self.probe.fixture_api.calls)
        with self.assertRaises(module.ControllerRefused): self.controller.cleanup_once(deadline=500)
        self.assertEqual(self.probe.fixture_api.calls,calls)
        self.assertEqual(len(created),1)
        self.assertNotIn('unpromoted_cleanup',calls)

    def test_existing_source_cleanup_helper_cannot_be_reconstructed(self):
        self.initial(); created=self.cleanup_dependencies(); self.cleanup_scope()
        self.probe._root_c2_executor_v2=Executor()
        self.probe._root_c2_executor_v2.cleanup_helper=object()
        self.controller.stop_writers(deadline=500)
        calls=list(self.probe.fixture_api.calls)
        with self.assertRaises(module.ControllerRefused): self.controller.cleanup_once(deadline=500)
        self.assertEqual(self.probe.fixture_api.calls,calls)
        self.assertEqual(created,[])

    def test_action_ledger_never_retains_selected_node_or_private_fields(self):
        row={'kind':'set','authenticated':True,'witness':'SYNTHETIC_PRIVATE_WITNESS',
             'value':'SYNTHETIC_PRIVATE_TEXT','delivery':'semantic_text','native_pointer_events':0}
        self.probe.report['actions'].append(row)
        self.assertEqual(self.probe.report['actions'],[{'kind':'set','delivery':'semantic_text','native_pointer_events':0}])
        self.assertNotIn('SYNTHETIC_PRIVATE',json.dumps(self.probe.report))

    def test_clear_unlinks_only_exact_owned_control_files_preserving_actual_media(self):
        self.initial()
        controls=set(module.C4_FILES.values())|{self.dispatcher.C1_FILE,self.dispatcher.C4_FILE,self.dispatcher.STAGE_FILE}
        for name in controls:
            path=self.probe.out/name; path.write_text('{}'); path.chmod(0o600)
        other=self.probe.out/'proof.json'; other.write_text('SYNTHETIC_PROOF')
        self.controller.clear_private_state()
        self.assertTrue(all(not (self.probe.out/name).exists() for name in controls))
        self.assertTrue(other.exists())
        self.assertTrue((self.probe.out/'C1-restored-title.png').exists())

    def test_runtime_receipt_without_real_exit_poll_never_allows_api_cleanup(self):
        self.initial(); self.cleanup_scope(); self.controller._advance_failed=True
        called=[]
        self.controller._close=lambda **kwargs: (called.append(kwargs) or {
            'vm_created':True,'relay_created':False,'vm_exit_code':None,'relay_exit_code':None,
            'owned_process_group_absence_observed':True,'all_created_processes_observed_ended':True})
        with self.assertRaises(module.ControllerRefused): self.controller.stop_writers(deadline=500)
        self.assertFalse(self.controller._writers_stopped)
        with self.assertRaises(module.ControllerRefused): self.controller.close_runtime(deadline=500)
        self.assertEqual(len(called),1)

    def test_login_checkpoint_does_not_touch_force_stopped_app(self):
        self.initial(); self.root('C2')
        self.controller._c4_state().update(accepted=True,cursor='C4_SAVED_RESTORED_HOLD_FOR_C2')
        self.controller.c2=SimpleNamespace(STAGES=('broker_login_for_submit',), TARGETS={},REVIEW_STAGES=set())
        self.probe._root_c2_executor_v2=Executor()
        self.probe.nodes=lambda: (_ for _ in ()).throw(AssertionError('APP is force-stopped'))
        snapshot=self.controller.snapshot()
        self.assertEqual(snapshot['evidence'],[])
        self.assertNotIn('safe_scene_sha256',snapshot['stage']['bindings'])
        self.assertEqual(self.dispatcher.calls,[])

    def test_real_thread_second_advance_refused_without_second_dispatch(self):
        self.initial(); self.root()
        snapshot=self.controller.snapshot()
        record={'review_completed_utc':'2026-11-04T12:00:00Z'}
        review=self.signed(snapshot,phase_review=record)
        entered,release=threading.Event(),threading.Event()
        calls=[]; failures=[]
        def phase(p,kind):
            calls.append(kind); entered.set(); release.wait(timeout=3)
            p.report['local_c4_executor']['cursor']='AI_REVIEW'
        self.dispatcher.run_phase=phase
        def first():
            try:self.controller.advance(review)
            except BaseException as error:failures.append(type(error).__name__)
        thread=threading.Thread(target=first); thread.start()
        self.assertTrue(entered.wait(timeout=3))
        with self.assertRaisesRegex(module.ControllerRefused,'^controller_transaction_inflight$'):
            self.controller.advance(review)
        self.assertEqual(calls,['C4'])
        release.set(); thread.join(timeout=3)
        self.assertFalse(thread.is_alive()); self.assertEqual(failures,[])

    def test_exhausted_budget_still_reaches_fixed_owned_vm_close_without_new_time(self):
        self.clock=500
        self.assertTrue(self.controller.close_runtime(deadline=500)['all_created_processes_observed_ended'])
        self.assertEqual(self.runtime_calls,[('close',{'deadline':500})])

    def test_expired_deadline_prevents_stop_and_cleanup_before_dispatch(self):
        self.initial()
        calls = list(self.runtime_calls)
        self.clock = 500
        with self.assertRaises(module.ControllerRefused): self.controller.stop_writers(deadline=500)
        with self.assertRaises(module.ControllerRefused): self.controller.cleanup_once(deadline=500)
        self.assertEqual(self.runtime_calls,calls)


if __name__ == '__main__': unittest.main()
