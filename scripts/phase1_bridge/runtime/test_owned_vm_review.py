"""Independent offline review probes. No actual VM or ADB subprocess can run.

Failing admission probes identify source-review blockers, not native failures.
"""
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import owned_vm as vm


class OwnedVmSourceReview(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sdk = self.root / 'sdk'; self.sdk.mkdir()
        (self.sdk / 'emulator').mkdir()
        self.binary = self.sdk / 'emulator/emulator'
        self.binary.write_text('synthetic placeholder; must never execute')
        self.binary.chmod(0o700)
        self.avd = self.root / 'avd'; self.avd.mkdir()
        (self.avd / 'aqer-native-account.avd').mkdir()
        (self.avd / 'aqer-native-account.avd/config.ini').write_text('test-placeholder-only')
        self.env = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
            'GITHUB_REF': 'refs/heads/work/phase1-native-account-20261103',
            'GITHUB_EVENT_NAME': 'push',
            'ANDROID_HOME': str(self.sdk), 'ANDROID_AVD_HOME': str(self.avd),
            'RUNNER_TEMP': str(self.root), 'GITHUB_SHA': 'a' * 40, 'SOURCE_COMMIT': 'a' * 40,
            'GITHUB_RUN_ID': '9001', 'GITHUB_RUN_ATTEMPT': '2'}

    def test_child_environment_removes_action_endpoints_and_all_known_task_credentials(self):
        names = ['AQER_PHASE1_TEST_ACCESS_JSON', 'GITHUB_TOKEN', 'ACTIONS_RUNTIME_TOKEN',
                 'ACTIONS_RESULTS_URL', 'ACTIONS_RUNTIME_URL', 'UAT_TEST_OTP_CODE',
                 'NEW_SUPABASE_SERVICE_KEY', 'SSH_AUTH_SOCK']
        synthetic = dict(self.env, **{name: 'synthetic-value-not-a-real-credential' for name in names})
        cleaned = vm.child_environment(synthetic)
        self.assertEqual([name for name in names if name in cleaned], [])
        self.assertEqual(cleaned['ANDROID_HOME'], str(self.sdk))

    def test_constructor_requires_complete_matching_source_and_run_context(self):
        variants = [dict(self.env, SOURCE_COMMIT='b' * 40),
                    {name: value for name, value in self.env.items() if name != 'GITHUB_SHA'},
                    {name: value for name, value in self.env.items() if name != 'GITHUB_RUN_ID'},
                    dict(self.env, GITHUB_RUN_ATTEMPT='0')]
        for index, env in enumerate(variants):
            # Each probe uses a separate root so freshness does not hide missing
            # source checks behind a directory-exists error.
            probe_root = self.root / ('context-' + str(index)); probe_root.mkdir()
            env = dict(env, RUNNER_TEMP=str(probe_root))
            with self.subTest(index=index), self.assertRaises(vm.VmBlocked):
                vm.OwnedApi36Vm(env)

    def test_existing_emulator_serial_cannot_satisfy_new_owned_vm_readiness(self):
        instance = vm.OwnedApi36Vm(self.env)
        fake_process = Mock(pid=987654, returncode=None)
        fake_process.poll.return_value = None
        original_stat, original_access = os.stat, os.access
        def observed_stat(path, *args, **kwargs):
            if str(path) == '/dev/kvm':
                return os.stat_result((stat.S_IFCHR | 0o600, 1, 1, 1, 1, 1, 0, 0, 0, 0))
            return original_stat(path, *args, **kwargs)
        def observed_access(path, mode, *args, **kwargs):
            return True if str(path) == '/dev/kvm' else original_access(path, mode, *args, **kwargs)
        def fake_adb(args, **kwargs):
            if 'devices' in args:
                return subprocess.CompletedProcess(args, 0, b'List of devices attached\nemulator-5554\tdevice\n', b'')
            value = {'sys.boot_completed': b'1\n', 'sys.user.0.ce_available': b'true\n',
                     'ro.build.version.sdk': b'36\n'}.get(args[-1], b'')
            return subprocess.CompletedProcess(args, 0, value, b'')
        with patch.object(vm.os, 'stat', side_effect=observed_stat), \
             patch.object(vm.os, 'access', side_effect=observed_access), \
             patch.object(vm.subprocess, 'Popen', return_value=fake_process) as launch, \
             patch.object(vm.subprocess, 'run', side_effect=fake_adb):
            with self.assertRaises(vm.VmBlocked):
                instance.start(boot_seconds=1)
            launch.assert_not_called()

    def test_observe_timeout_or_error_never_returns_command_output(self):
        instance = vm.OwnedApi36Vm(self.env)
        for error in [subprocess.TimeoutExpired(['fixed-synthetic-observation'], 3),
                      OSError('synthetic-private-message')]:
            with self.subTest(kind=type(error).__name__), \
                 patch.object(vm.subprocess, 'run', side_effect=error):
                self.assertIsNone(instance._observe('shell', 'getprop', 'sys.boot_completed'))

    def test_actual_parent_exit_and_group_absence_are_reported_without_fabricated_zero(self):
        instance = vm.OwnedApi36Vm(self.env)
        process = Mock(pid=987654, returncode=-11)
        process.poll.return_value = -11
        instance.process = process
        with patch.object(vm.os, 'killpg', side_effect=ProcessLookupError) as groups:
            receipt = instance.close()
        self.assertEqual(receipt['vm_parent_exit_code'], -11)
        self.assertTrue(receipt['owned_process_group_absence_observed'])
        groups.assert_called_once_with(process.pid, 0)
        process.wait.assert_not_called()

    def test_group_presence_after_parent_exit_is_not_reported_as_absence(self):
        instance = vm.OwnedApi36Vm(self.env)
        process = Mock(pid=987654, returncode=-11)
        process.poll.return_value = -11
        instance.process = process
        with patch.object(vm.os, 'killpg', return_value=None) as groups, \
             patch.object(vm.time, 'monotonic', return_value=100.0):
            receipt = instance.close(deadline=100.0)
        self.assertEqual(receipt['vm_parent_exit_code'], -11)
        self.assertFalse(receipt['owned_process_group_absence_observed'])
        groups.assert_called_once_with(process.pid, 0)

    def test_unconfirmed_group_identity_is_never_signalled(self):
        instance = vm.OwnedApi36Vm(self.env)
        process = Mock(pid=987654, returncode=None)
        process.poll.return_value = None
        instance.process = process
        with patch.object(vm.os, 'getpgid', return_value=123), \
             patch.object(vm.os, 'killpg') as groups:
            receipt = instance.close()
        groups.assert_not_called()
        self.assertIsNone(receipt['vm_parent_exit_code'])
        self.assertTrue(receipt['vm_shutdown_unconfirmed'])
        self.assertFalse(receipt['owned_process_group_absence_observed'])

    def test_avd_name_and_live_owned_parent_are_required_after_boot_properties(self):
        original_stat, original_access = os.stat, os.access
        def observed_stat(path, *args, **kwargs):
            if str(path) == '/dev/kvm':
                return os.stat_result((stat.S_IFCHR | 0o600, 1, 1, 1, 1, 1, 0, 0, 0, 0))
            return original_stat(path, *args, **kwargs)
        def observed_access(path, mode, *args, **kwargs):
            return True if str(path) == '/dev/kvm' else original_access(path, mode, *args, **kwargs)
        variants = [('foreign-avd\nOK\n', [None]), ('aqer-native-account\n', [None]),
                    ('aqer-native-account\nOK\n', [None, -11]),
                    ('aqer-native-account\nOK\n', [None, None])]
        for index, (name, polls) in enumerate(variants):
            probe_root = self.root / ('avd-proof-' + str(index)); probe_root.mkdir()
            instance = vm.OwnedApi36Vm(dict(self.env, RUNNER_TEMP=str(probe_root)))
            process = Mock(pid=987654, returncode=None); process.poll.side_effect = polls
            def fake_adb(args, **kwargs):
                if 'devices' in args:
                    return subprocess.CompletedProcess(args, 0, b'List of devices attached\n\n', b'')
                if args[-3:] == ['emu', 'avd', 'name']:
                    return subprocess.CompletedProcess(args, 0, name.encode(), b'')
                output = {'sys.boot_completed': b'1\n', 'sys.user.0.ce_available': b'true\n',
                          'ro.build.version.sdk': b'36\n'}[args[-1]]
                return subprocess.CompletedProcess(args, 0, output, b'')
            with self.subTest(index=index), patch.object(vm.os, 'stat', side_effect=observed_stat), \
                 patch.object(vm.os, 'access', side_effect=observed_access), \
                 patch.object(vm.subprocess, 'Popen', return_value=process) as launch, \
                 patch.object(vm.subprocess, 'run', side_effect=fake_adb):
                if index < 3:
                    with self.assertRaisesRegex(vm.VmBlocked, 'owned_avd_identity_unobserved'):
                        instance.start(boot_seconds=1)
                    self.assertFalse(instance.receipt['boot_and_CE_ready'])
                else:
                    instance.start(boot_seconds=1)
                    self.assertTrue(instance.receipt['boot_and_CE_ready'])
                    command = launch.call_args.args[0]
                    self.assertEqual(command[command.index('-accel') + 1], 'on')
                    self.assertEqual(stat.S_IMODE((instance.private / 'emulator.log').stat().st_mode), 0o600)

    def test_cleanup_waits_are_capped_by_actual_remaining_deadline(self):
        instance = vm.OwnedApi36Vm(self.env)
        process = Mock(pid=987654, returncode=None)
        process.poll.return_value = None
        process.wait.side_effect = subprocess.TimeoutExpired(['synthetic-owned-process'], 0)
        instance.process = process
        with patch.object(vm.os, 'getpgid', return_value=process.pid), \
             patch.object(vm.os, 'killpg'), patch.object(vm.time, 'monotonic', return_value=100.0):
            receipt = instance.close(deadline=100.0)
        self.assertTrue(all(call.kwargs['timeout'] == 0 for call in process.wait.call_args_list))
        self.assertTrue(receipt['vm_shutdown_unconfirmed'])
        self.assertIsNone(receipt['vm_parent_exit_code'])
        self.assertFalse(receipt['owned_process_group_absence_observed'])

    def clock_instance(self):
        instance = vm.OwnedApi36Vm(self.env)
        instance.started = True
        instance.receipt['boot_and_CE_ready'] = True
        instance.process = Mock(pid=987654, returncode=None)
        instance.process.poll.return_value = None
        return instance

    def test_clock_setter_is_once_before_apps_and_restores_default_shell_without_sync_claim(self):
        instance = self.clock_instance()
        calls, rooted = [], [False]
        def fake(args, **kwargs):
            self.assertEqual(args[:3], [str(self.sdk/'platform-tools/adb'), '-s', 'emulator-5554'])
            operation = args[3:]; calls.append(operation)
            self.assertLessEqual(kwargs['timeout'], 10)
            if operation == ['root']: rooted[0] = True
            elif operation == ['unroot']: rooted[0] = False
            elif operation == ['shell','id','-u']:
                return subprocess.CompletedProcess(args, 0, b'0\n' if rooted[0] else b'2000\n', b'')
            elif operation[:4] == ['shell','date','-u','-s']:
                self.assertTrue(rooted[0])
                self.assertEqual(operation[4], '@1793754123.123456789')
            else: self.assertEqual(operation, ['wait-for-device'])
            return subprocess.CompletedProcess(args, 0, b'', b'')
        with patch.object(vm.subprocess,'run',side_effect=fake), \
             patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
             patch.object(vm.time,'monotonic',return_value=100):
            self.assertTrue(instance.prepare_utc_clock(deadline=150))
            before = len(calls)
            with self.assertRaises(vm.VmBlocked): instance.prepare_utc_clock(deadline=150)
            self.assertEqual(len(calls),before)
        self.assertEqual(sum(call[:2] == ['shell','date'] for call in calls),1)
        self.assertEqual(calls[-3:],[['unroot'],['wait-for-device'],['shell','id','-u']])
        self.assertEqual(instance.receipt['clock_preparation'],{
            'attempted_once':True,'root_uid_verified':True,'date_setter_exit_zero':True,
            'default_shell_uid_restored':True,'clock_acceptance_claimed':False})
        self.assertNotIn('1793754123',str(instance.receipt))

    def test_failed_clock_setter_still_restores_shell_and_never_replays_or_exports_output(self):
        instance = self.clock_instance()
        calls, rooted = [], [False]
        def fake(args, **kwargs):
            operation=args[3:];calls.append(operation)
            if operation==['root']:rooted[0]=True
            elif operation==['unroot']:rooted[0]=False
            elif operation==['shell','id','-u']:
                return subprocess.CompletedProcess(args,0,b'0\n' if rooted[0] else b'2000\n',b'')
            elif operation[:2]==['shell','date']:
                return subprocess.CompletedProcess(args,1,b'SYNTHETIC_PRIVATE_OUTPUT',b'SYNTHETIC_PRIVATE_ERROR')
            return subprocess.CompletedProcess(args,0,b'',b'')
        with patch.object(vm.subprocess,'run',side_effect=fake), \
             patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
             patch.object(vm.time,'monotonic',return_value=100):
            with self.assertRaises(vm.VmBlocked) as caught:instance.prepare_utc_clock(deadline=150)
            self.assertNotIn('SYNTHETIC_PRIVATE',str(caught.exception))
            with self.assertRaises(vm.VmBlocked):instance.prepare_utc_clock(deadline=150)
        self.assertEqual(sum(call[:2]==['shell','date'] for call in calls),1)
        self.assertFalse(instance.receipt['clock_preparation']['date_setter_exit_zero'])
        self.assertTrue(instance.receipt['clock_preparation']['default_shell_uid_restored'])

    def test_clock_preparation_requires_live_owned_boot_and_cannot_extend_expired_budget(self):
        instance=self.clock_instance()
        with patch.object(vm.subprocess,'run') as run, patch.object(vm.time,'monotonic',return_value=100):
            with self.assertRaises(vm.VmBlocked):instance.prepare_utc_clock(deadline=100)
            instance.process.poll.return_value=0
            with self.assertRaises(vm.VmBlocked):instance.prepare_utc_clock(deadline=150)
            run.assert_not_called()


if __name__ == '__main__': unittest.main()
