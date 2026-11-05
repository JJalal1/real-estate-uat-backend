"""Final-entry contracts with synthetic files/fake SDK calls only."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
ENTRY = HERE / 'run_phase1_native_bridge.py'
if not ENTRY.exists():
    ENTRY = HERE.parents[1] / 'run_phase1_native_bridge.py'
spec = importlib.util.spec_from_file_location('_entry_under_test', ENTRY)
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


def ci_env(root):
    return {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': entry.REPO,
        'GITHUB_REF': entry.REF, 'GITHUB_EVENT_NAME': 'push',
        'GITHUB_SHA': 'a'*40, 'SOURCE_COMMIT': 'a'*40,
        'GITHUB_RUN_ID': '9001', 'GITHUB_RUN_NUMBER': '7', 'GITHUB_RUN_ATTEMPT': '2',
        'AQER_PHASE1_NATIVE_ACCOUNT': 'true', 'UAT_API_BASE_URL': entry.API,
        'GITHUB_WORKSPACE': str(root), 'RUNNER_TEMP': str(root / 'runner-temp'),
        'ANDROID_HOME': str(root / 'fake-sdk'), 'PATH': '/synthetic/bin'}


class EntryContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = ci_env(self.root)

    def test_import_is_inert_and_manifest_scope_is_fixed_unique(self):
        fresh = importlib.util.module_from_spec(spec)
        with patch.object(entry.subprocess, 'run', side_effect=AssertionError('no runtime')):
            spec.loader.exec_module(fresh)
        self.assertEqual(len(entry.EXPECTED_FILES), len(set(entry.EXPECTED_FILES)))
        self.assertEqual(entry.EXPECTED_FILES, tuple(sorted(entry.EXPECTED_FILES)))
        self.assertNotIn(entry.MANIFEST, entry.EXPECTED_FILES)
        for path in entry.EXPECTED_FILES:
            self.assertNotIn('private', path.lower()); self.assertNotIn('node_modules', path)
        self.assertEqual(entry.PAIRED_PROBE_SHA,
            'c1c46a574b922643647d8e052fe62391042335217d71f6b4795dbc18bcbd1367')
        self.assertIn('scripts/phase1_bridge/adapter/test_logout_home.py', entry.EXPECTED_FILES)
        for path in ('adapter/c1_home_capture.py', 'adapter/test_home_capture.py', 'controller/test_home_diagnostic.py',
                     'adapter/c1_basics_capture.py', 'adapter/test_basics_capture.py'):
            self.assertIn('scripts/phase1_bridge/' + path, entry.EXPECTED_FILES)

    def test_checked_in_sources_match_the_frozen_pair_before_any_android_build(self):
        # Regression: a changed probe and matching manifest could pass offline
        # tests but previously fail only after a full Android build.
        root = ENTRY.parents[1]
        actual = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in (
            'scripts/probe_phase1_native_account.py', 'scripts/phase1_device_input/Phase1Input.java')}
        entry.verify_paired_sources(actual)
        for name in actual:
            changed = dict(actual, **{name: 'f' * 64})
            with self.subTest(name=name), self.assertRaisesRegex(entry.EntryBlocked, 'paired_helper'):
                entry.verify_paired_sources(changed)

    def test_runtime_channels_are_popped_before_any_child_and_unknown_env_dropped(self):
        original = dict(self.env, GITHUB_TOKEN='SYNTHETIC_TOKEN',
            AQER_PHASE1_TEST_ACCESS_JSON='SYNTHETIC_SECRET_JSON', ACTIONS_RUNTIME_TOKEN='SYNTHETIC_ACTION',
            NEW_OTHER_SECRET='SYNTHETIC_OTHER', PYTHONPATH='/foreign')
        public, token, secret = entry.isolate_environment(original)
        self.assertEqual((token, secret), ('SYNTHETIC_TOKEN', 'SYNTHETIC_SECRET_JSON'))
        for value in [original, public]:
            self.assertNotIn('GITHUB_TOKEN', value); self.assertNotIn(entry.SECRET, value)
            self.assertNotIn('NEW_OTHER_SECRET', value); self.assertNotIn('ACTIONS_RUNTIME_TOKEN', value)
        self.assertEqual(set(original), {'PATH', 'ANDROID_HOME'})
        self.assertNotIn('GITHUB_SHA', original)
        self.assertEqual(public['GITHUB_SHA'], 'a'*40)

    def test_exact_source_run_attempt_api_context_is_mandatory(self):
        entry.check_ci(self.env)
        for changes in [{'GITHUB_RUN_ATTEMPT': '0'}, {'GITHUB_RUN_ATTEMPT': 'true'},
                        {'SOURCE_COMMIT': 'b'*40}, {'GITHUB_REF': 'refs/heads/foreign'},
                        {'UAT_API_BASE_URL': 'http://foreign.invalid'}, {'GITHUB_EVENT_NAME': 'pull_request'}]:
            with self.subTest(changes=list(changes)), self.assertRaises(entry.EntryBlocked):
                entry.check_ci(dict(self.env, **changes))

    def test_channel_handoff_is_empty_before_long_session_can_retain_raw_json(self):
        channels = ['SYNTHETIC_TOKEN', 'SYNTHETIC_RAW_JSON']
        def load(_):
            self.assertEqual(channels, [])
            raise entry.EntryBlocked('synthetic_stop_before_dependencies')
        run_root = self.root/'runner-temp/aqer-phase1-bridge-9001-2'
        run_root.mkdir(parents=True, mode=0o700)
        env = dict(self.env, AQER_BRIDGE_TOOLBUNDLE_SHA='b'*64)
        with patch.object(entry, 'load_runtime', side_effect=load) as loader:
            with self.assertRaisesRegex(entry.EntryBlocked, 'synthetic_stop'):
                entry.run_native(self.root, env, channels, run_root, 'b'*64, object())
            loader.assert_called_once()
            with self.assertRaisesRegex(entry.EntryBlocked, 'one_runtime_channel'):
                entry.run_native(self.root, env, channels, run_root, 'b'*64, object())
            loader.assert_called_once()

    def manifest(self, *, names=('scripts/a.py',), update=None, raw=None):
        values = {}
        for name in names:
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'SYNTHETIC_SOURCE\n')
            values[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        if update: values.update(update)
        path = self.root / entry.MANIFEST; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw or (json.dumps({'version': 1, 'files': values}, sort_keys=True)+'\n').encode())
        return path

    def test_manifest_hashes_actual_raw_bytes_and_all_exact_files(self):
        path = self.manifest()
        digest, files = entry.verify_manifest(self.root, expected_files=('scripts/a.py',))
        self.assertEqual(digest, hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(set(files), {'scripts/a.py'})
        (self.root/'scripts/a.py').write_bytes(b'CHANGED')
        with self.assertRaisesRegex(entry.EntryBlocked, 'bytes_mismatch'):
            entry.verify_manifest(self.root, expected_files=('scripts/a.py',))

    def test_duplicate_unknown_symlink_or_hardlink_source_is_refused(self):
        for raw in [b'{"version":1,"version":1,"files":{}}',
                    b'{"version":true,"files":{}}', b'{"version":1,"files":{},"extra":1}']:
            self.manifest(raw=raw)
            with self.subTest(raw=raw), self.assertRaises(entry.EntryBlocked):
                entry.verify_manifest(self.root, expected_files=())
        self.manifest(); source = self.root/'scripts/a.py'
        source.unlink(); source.symlink_to('/dev/null')
        with self.assertRaises(entry.EntryBlocked): entry.verify_manifest(self.root, expected_files=('scripts/a.py',))
        source.unlink(); source.write_bytes(b'SYNTHETIC_SOURCE\n')
        os.link(source, self.root/'hardlink')
        with self.assertRaises(entry.EntryBlocked): entry.verify_manifest(self.root, expected_files=('scripts/a.py',))

    def test_source_guard_pins_pair_and_public_root_before_actual_prepare_guard(self):
        hashes = {'scripts/phase1_device_input/Phase1Input.java': entry.HELPER_SOURCE_SHA,
                  'scripts/probe_phase1_native_account.py': entry.PAIRED_PROBE_SHA}
        pin = {'algorithm': 'Ed25519', 'root_public_b64': entry.ROOT_PUBLIC_B64,
               'root_key_id': entry.ROOT_KEY_ID, 'scope': 'Synthetic test uses public pin only'}
        guard = SimpleNamespace(API=entry.API, guard=Mock(return_value={'source_commit': 'a'*40}))
        with patch.object(entry, 'verify_manifest', return_value=('b'*64, hashes)), \
             patch.object(entry, 'read_owned', return_value=json.dumps(pin).encode()), \
             patch.object(entry, 'load', return_value=guard):
            self.assertEqual(entry.source_guard(self.root, self.env), ('b'*64, guard))
            guard.guard.assert_called_once_with(self.env)
            guard.guard.reset_mock()
            hashes['scripts/probe_phase1_native_account.py'] = 'c'*64
            with self.assertRaisesRegex(entry.EntryBlocked, 'paired_helper'):
                entry.source_guard(self.root, self.env)
            guard.guard.assert_not_called()

    def test_github_env_exports_only_verified_public_digest(self):
        folder = self.root/'runner-temp'; folder.mkdir()
        path = folder/'env-file'; path.touch(mode=0o600)
        env = dict(self.env, GITHUB_ENV=str(path))
        entry.export_github_env(env, 'b'*64)
        self.assertEqual(path.read_text(), 'AQER_BRIDGE_TOOLBUNDLE_SHA='+'b'*64+'\n')
        with self.assertRaises(entry.EntryBlocked):
            entry.export_github_env(dict(env, GITHUB_ENV=str(self.root/'foreign')), 'b'*64)
        target = self.root/'target'; target.mkdir(); (target/'empty').touch()
        (folder/'link').symlink_to(target)
        with self.assertRaises(entry.EntryBlocked):
            entry.export_github_env(dict(env, GITHUB_ENV=str(folder/'link/empty')), 'b'*64)


class RuntimeObservationContracts(unittest.TestCase):
    def setUp(self):
        self.paths = '/data/app/~~SyntheticOne/com.aqer.phase1.input-Abc_123/base.apk'
        self.calls = []
        self.outputs = [f'package:{self.paths}\n'.encode(), ('a'*64+'  '+self.paths+'\n').encode()]
        def run(args, **kwargs):
            self.calls.append((args, kwargs))
            return subprocess.CompletedProcess(args, 0, self.outputs.pop(0), b'')
        self.check = entry.RuntimeChecks(sdk='/synthetic/sdk', child_env={'PATH': '/synthetic/bin'},
            helper_sha='a'*64, deadline_getter=lambda: 10, runner=run,
            monotonic_clock=lambda: 0, utc_ms=lambda: 1793754123000)

    def test_only_fixed_helper_package_and_installed_apk_sha_are_observed(self):
        self.assertTrue(self.check.verify_helper_identity())
        self.assertEqual(self.calls[0][0], ['/synthetic/sdk/platform-tools/adb', '-s', 'emulator-5554',
            'shell', 'pm', 'path', 'com.aqer.phase1.input'])
        self.assertEqual(self.calls[1][0][-3:], ['shell', 'sha256sum', self.paths])
        for _, kwargs in self.calls:
            self.assertEqual(kwargs['env'], {'PATH': '/synthetic/bin'})
            self.assertEqual(kwargs['timeout'], 5)
            self.assertEqual(kwargs['stdin'], subprocess.DEVNULL)

    def test_installed_split_path_hash_error_and_timeout_fail_without_raw_output(self):
        for outputs in [[b'package:/data/app/x/base.apk\npackage:/data/app/x/split.apk\n'],
                        [b'package:/data/data/private/base.apk\n'],
                        [b'package:/data/app/../x/base.apk\n'],
                        [f'package:{self.paths}\n'.encode(), b'PRIVATE_SENTINEL']]:
            self.outputs = outputs
            with self.subTest(shape=len(outputs)), self.assertRaises(entry.EntryBlocked) as error:
                self.check.verify_helper_identity()
            self.assertNotIn('PRIVATE_SENTINEL', str(error.exception))
        self.check.runner = Mock(side_effect=subprocess.TimeoutExpired(['synthetic'], 5))
        with self.assertRaisesRegex(entry.EntryBlocked, 'unobserved'): self.check.verify_helper_identity()

    def test_actual_guest_utc_requires_precise_bounded_consistent_host_bracket(self):
        self.outputs = [b'1793754123000\n']
        self.assertTrue(self.check.verify_guest_utc())
        self.assertEqual(self.calls[0][0][-4:], ['shell', 'date', '-u', '+%s%3N'])
        for output in [b'1793754123\n', b'1793754123%3N\n', b'1793754129000\n']:
            self.outputs = [output]
            with self.subTest(output=output), self.assertRaises(entry.EntryBlocked): self.check.verify_guest_utc()
        self.outputs = [b'1793754123000\n']
        times = iter([1793754123000, 1793754123500])
        self.check.utc_ms = lambda: next(times)
        with self.assertRaisesRegex(entry.EntryBlocked, 'observation_invalid'):
            self.check.verify_guest_utc()

    def test_delayed_utc_observation_does_not_understate_offset_interval(self):
        # A guest value at the start of a400ms command is not proof that the
        # clock lies within250ms at the unknown actual sample time.
        self.outputs = [b'1793754123000\n']
        times = iter([1793754123000, 1793754123400])
        monotimes = iter([0, 0, 0.4, 0.4])
        self.check.utc_ms = lambda: next(times)
        self.check.mono = lambda: next(monotimes)
        with self.assertRaisesRegex(entry.EntryBlocked, 'unsynchronized'):
            self.check.verify_guest_utc()

    def test_readiness_diagnostics_export_only_fixed_status_and_bounded_clock_deltas(self):
        rows = []
        self.check.diagnostic_sink = rows.append
        self.assertTrue(self.check.verify_helper_identity())
        self.outputs = [b'1793754123300\n']
        with self.assertRaisesRegex(entry.EntryBlocked, 'unsynchronized'):
            self.check.verify_guest_utc()
        self.assertEqual(rows[:3], [
            {'check':'helper_identity','status':'path_query'},
            {'check':'helper_identity','status':'hash_query'},
            {'check':'helper_identity','status':'verified'}])
        self.assertEqual(rows[-1]['offset_low_ms'], 300)
        self.assertEqual(rows[-1]['offset_high_ms'], 300)
        self.assertNotIn(self.paths, json.dumps(rows))
        self.assertNotIn('a'*64, json.dumps(rows))
        self.assertNotIn('1793754123', json.dumps(rows))
        self.outputs = [b'PRIVATE_CLOCK_SENTINEL\n']
        with self.assertRaisesRegex(entry.EntryBlocked, 'observation_invalid'):
            self.check.verify_guest_utc()
        self.assertFalse(rows[-1]['format_valid'])
        self.assertIsNone(rows[-1]['offset_low_ms'])
        self.assertNotIn('PRIVATE_CLOCK_SENTINEL', json.dumps(rows))

    def test_cleanup_deadline_uses_original_reserve_after_work_deadline(self):
        owner = SimpleNamespace(work_deadline=1,
            active_authority=SimpleNamespace(monotonic_deadline=600))
        self.assertEqual(entry.authority_deadline(owner), 600)
        owner.active_authority = None
        self.assertEqual(entry.authority_deadline(owner), 1)

    def test_new_runtime_api_aliases_are_refused_before_any_checkpoint_seal(self):
        probe = SimpleNamespace(private_values={'SYNTHETIC_ROLE'}, fixture_api=None)
        underlying = SimpleNamespace(seal=Mock(return_value='sealed'), identity={}, max_allocated=-1)
        packager = entry.LivePrivacyPackager(underlying, lambda: entry.current_private_aliases(probe))
        self.assertEqual(packager.seal(stage={'report_scope': 'safe'}), 'sealed')
        probe.fixture_api = SimpleNamespace(_private_values={'SYNTHETIC_LATE_TOKEN'})
        with self.assertRaisesRegex(entry.EntryBlocked, 'private_boundary'):
            packager.seal(stage={'report_scope': 'SYNTHETIC_LATE_TOKEN'})
        underlying.seal.assert_called_once()

    def test_truthful_vm_mapping_does_not_create_exit_codes_or_relays(self):
        vm = SimpleNamespace(process=object(), close=Mock(return_value={
            'vm_parent_exit_code': None, 'owned_process_group_absence_observed': True}))
        result = entry.runtime_close(vm, deadline=20)
        self.assertFalse(result['all_created_processes_observed_ended'])
        self.assertIsNone(result['vm_exit_code']); self.assertFalse(result['relay_created'])
        vm.close.return_value['vm_parent_exit_code'] = -15
        self.assertTrue(entry.runtime_close(vm, deadline=20)['all_created_processes_observed_ended'])
        vm.process = None; vm.close.return_value['vm_parent_exit_code'] = None
        result = entry.runtime_close(vm, deadline=20)
        self.assertFalse(result['vm_created']); self.assertTrue(result['all_created_processes_observed_ended'])


class ConcreteCompositionContract(unittest.TestCase):
    def test_actual_entry_composes_one_c2_instance_and_caps_fake_probe_child(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); env = ci_env(root)
            temp = root/'runner-temp'; temp.mkdir()
            run_root = temp/'aqer-phase1-bridge-9001-2'; run_root.mkdir(mode=0o700)
            private = root/'phase1-native-account-private'; private.mkdir(mode=0o700)
            helper = private/'input.apk'; helper.write_bytes(b'SYNTHETIC_HELPER'); helper.chmod(0o600)
            (private/'APK_VERIFICATION.json').write_text(json.dumps({'source_commit': 'a'*40,
                'package': 'synthetic.app', 'input_driver': {'sha256': hashlib.sha256(helper.read_bytes()).hexdigest()}}))
            env['AQER_BRIDGE_TOOLBUNDLE_SHA'] = 'b'*64
            record = {}
            c2 = SimpleNamespace(roles=SimpleNamespace(install_known_roles=object()))
            class Probe:
                def __init__(self, private, supplied_env, **callbacks):
                    record['probe_env'] = dict(supplied_env); record['callbacks'] = callbacks
                    self.env = {k:v for k,v in supplied_env.items() if k != entry.SECRET}
                    self.private_values = {'SYNTHETIC_ROLE'}
                    self.report = {}
                    self._transport = SimpleNamespace(instrument_op=None)
                    self.out = root/'phase1-native-account-evidence'; self.out.mkdir(mode=0o700)
                    record['probe'] = self
                def command(self, args, **kwargs):
                    assert 'clock_preparation_deadline' in record
                    assert 'recording_environment_deadline' in record
                    record['command'] = kwargs
                    return 'SYNTHETIC'
                def save(self): pass
                def c4_prepare_command_budget(self, op, requested, remaining):
                    record['bounded_command_budget'] = (op, requested, remaining)
            def factory(**kwargs): record['factory'] = kwargs; return Probe
            class VM:
                def __init__(self, supplied_env): self.process = None; self.receipt = {}; record['vm_env']=supplied_env
                def start(self, *, boot_seconds):
                    record['boot_seconds'] = boot_seconds
                    self.process = SimpleNamespace(poll=lambda: None)
                    self.receipt['boot_and_CE_ready'] = True
                def prepare_utc_clock(self, *, deadline):
                    record['clock_preparation_deadline'] = deadline
                    self.receipt['clock_preparation'] = {'attempted_once': True,
                        'default_shell_uid_restored': True, 'clock_acceptance_claimed': False}
                    return True
                def prepare_recording_environment(self, *, deadline):
                    assert 'clock_preparation_deadline' in record
                    record['recording_environment_deadline'] = deadline
                    self.receipt['recording_environment'] = {'attempted_once':True,
                        'current_android_user0_verified':True,'system_sound_effects_disabled_readback':True,
                        'actual_recorded_silence_claimed':False,'stage':'complete'}
                    return True
                def close(self, *, deadline): return {'vm_parent_exit_code': -15, 'owned_process_group_absence_observed': True}
            class Controller:
                def __init__(self, **kwargs): record['controller'] = kwargs
            class Owner:
                def __init__(self, **kwargs):
                    record['owner'] = kwargs
                    self.work_deadline = time.monotonic()+20
                    self.active_authority = None; self.current_context = object()
                def request_stop(self, *_): pass
                def run(self):
                    record['controller']['boot_runtime'](deadline=self.work_deadline)
                    self.assert_context = record['callbacks']['context_getter']() is self.current_context
                    record['probe'].command(['synthetic'], timeout=90)
                    record['closed'] = record['controller']['close_runtime'](deadline=self.work_deadline)
                    return SimpleNamespace(reason_code='COLLECTED_PENDING_ROOT_ACCEPTANCE',
                        collected=True, cleanup_confirmed=True, runtime_ended=True)
            class Public:
                @staticmethod
                def from_public_bytes(raw): return object()
            class Job:
                def public(self): return bytes(32)
            def packager(**kwargs): record['packager']=kwargs; return object()
            def channel(*args): record['channel']=args; return object()
            modules = {'owner_session': SimpleNamespace(OwnerSession=Owner),
                'grants': SimpleNamespace(VerifiedGrant=type('Root',(),{}),SourcePlanLease=type('Initial',(),{}),CleanupLease=type('Cleanup',(),{})),
                'review_protocol': SimpleNamespace(Ed25519PublicKey=Public, JobEphemeralKey=Job),
                'base': SimpleNamespace(NativeAccount=object, validate_access=object(), APP='synthetic.app', ACTIVITY='synthetic.activity', HELPER='synthetic.helper', FixtureApi=object(), read_public_reference=object()),
                'capture': SimpleNamespace(HostConsoleCaptureMixin=object), 'ci_probe_adapter': SimpleNamespace(make_probe_class=factory),
                'c2': c2, 'c4': object(), 'dispatch': object(), 'owned_vm': SimpleNamespace(OwnedApi36Vm=VM),
                'controller': SimpleNamespace(Controller=Controller),
                'checkpoint_packager': SimpleNamespace(CheckpointPackager=packager),
                'command_transport': SimpleNamespace(CommandChannel=channel),
                'checkpoint_io': SimpleNamespace(StdIOBridge=lambda **_: object())}
            guard = SimpleNamespace(close=SimpleNamespace(RECIPIENT='.github/public.pem',RECIPIENT_SHA256='c'*64))
            with patch.object(entry, 'load_runtime', return_value=modules), patch.object(entry.signal, 'signal'):
                self.assertEqual(entry.run_native(root, env, ['SYNTHETIC_TOKEN', 'SYNTHETIC_JSON'], run_root, 'b'*64, guard), 0)
            self.assertIs(record['factory']['install_known_roles'], c2.roles.install_known_roles)
            self.assertIs(record['controller']['c2'], c2)
            self.assertNotIn('GITHUB_TOKEN', record['probe_env'])
            self.assertEqual(record['channel'], ('9001', 2, 'SYNTHETIC_TOKEN'))
            self.assertIn('SYNTHETIC_TOKEN', record['packager']['private_aliases'])
            self.assertLessEqual(record['boot_seconds'], 20)
            self.assertGreater(record['clock_preparation_deadline'], time.monotonic())
            self.assertFalse(record['probe'].report['owned_vm_clock_preparation']['clock_acceptance_claimed'])
            self.assertEqual(record['recording_environment_deadline'],record['clock_preparation_deadline'])
            recording=record['probe'].report['owned_vm_recording_environment']
            self.assertTrue(recording['current_android_user0_verified'])
            self.assertTrue(recording['system_sound_effects_disabled_readback'])
            self.assertFalse(recording['actual_recorded_silence_claimed'])
            self.assertLess(record['command']['timeout'], 20)
            self.assertTrue(record['closed']['all_created_processes_observed_ended'])


if __name__ == '__main__': unittest.main()
