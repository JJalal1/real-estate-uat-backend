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
                    ('aqer-native-account\nOK\n', [None, None]),
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
                if args[-3:] == ['shell', 'wm', 'size']:
                    display = b'Physical size: 1080x1920\n' if index == 4 else b'Physical size: 540x960\n'
                    return subprocess.CompletedProcess(args, 0, display, b'')
                output = {'sys.boot_completed': b'1\n', 'sys.user.0.ce_available': b'true\n',
                          'ro.build.version.sdk': b'36\n'}[args[-1]]
                return subprocess.CompletedProcess(args, 0, output, b'')
            with self.subTest(index=index), patch.object(vm.os, 'stat', side_effect=observed_stat), \
                 patch.object(vm.os, 'access', side_effect=observed_access), \
                 patch.object(vm.subprocess, 'Popen', return_value=process) as launch, \
                 patch.object(vm.subprocess, 'run', side_effect=fake_adb):
                if index < 3 or index == 4:
                    code = 'owned_physical_capture_display_mismatch' if index == 4 else 'owned_avd_identity_unobserved'
                    with self.assertRaisesRegex(vm.VmBlocked, code):
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

    def clock_instance(self, suffix=None):
        env=self.env
        if suffix is not None:
            root=self.root/suffix;root.mkdir()
            env=dict(self.env,RUNNER_TEMP=str(root))
        instance = vm.OwnedApi36Vm(env)
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
        self.assertEqual(calls[-2:],[['unroot'],['shell','id','-u']])
        self.assertEqual(instance.receipt['clock_preparation'],{
            'attempted_once':True,'root_uid_verified':True,'date_setter_exit_zero':True,
            'default_shell_uid_restored':True,
            'root_request':{'attempted_once':True,'transport':'EXIT_ZERO','stderr':'EMPTY'},
            'unroot_request':{'attempted_once':True,'transport':'EXIT_ZERO','stderr':'EMPTY'},
            'clock_acceptance_claimed':False,'stage':'complete'})
        self.assertNotIn('1793754123',str(instance.receipt))

    def test_restart_request_errors_still_require_and_accept_actual_uid_proof_once(self):
        for operation in ('root','unroot'):
            for mode,status,stderr in [('nonzero','EXIT_NONZERO','EMPTY'),
                                       ('stderr','EXIT_ZERO','REPORTED'),
                                       ('timeout','UNOBSERVED','UNOBSERVED'),
                                       ('oserror','UNOBSERVED','UNOBSERVED')]:
                instance=self.clock_instance(operation+'-'+mode)
                calls,rooted=[],[False]
                def fake(args,**kwargs):
                    op=args[3:];calls.append(op)
                    if op in (['root'],['unroot']):
                        rooted[0]=op==['root']
                        if op==[operation]:
                            if mode=='timeout':raise subprocess.TimeoutExpired(['SYNTHETIC_PRIVATE_COMMAND'],5,output=b'SYNTHETIC_PRIVATE_OUTPUT',stderr=b'SYNTHETIC_PRIVATE_ERROR')
                            if mode=='oserror':raise OSError('SYNTHETIC_PRIVATE_ERROR')
                            return subprocess.CompletedProcess(args,1 if mode=='nonzero' else 0,
                                b'SYNTHETIC_PRIVATE_OUTPUT',b'SYNTHETIC_PRIVATE_ERROR' if mode=='stderr' else b'')
                    elif op==['shell','id','-u']:
                        return subprocess.CompletedProcess(args,0,b'0\n' if rooted[0] else b'2000\n',b'')
                    return subprocess.CompletedProcess(args,0,b'',b'')
                with self.subTest(operation=operation,mode=mode),patch.object(vm.subprocess,'run',side_effect=fake), \
                     patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
                     patch.object(vm.time,'monotonic',return_value=100):
                    self.assertTrue(instance.prepare_utc_clock(deadline=150))
                observation=instance.receipt['clock_preparation']
                self.assertEqual(observation[operation+'_request'],{'attempted_once':True,'transport':status,'stderr':stderr})
                self.assertTrue(observation['root_uid_verified'])
                self.assertTrue(observation['date_setter_exit_zero'])
                self.assertTrue(observation['default_shell_uid_restored'])
                self.assertFalse(observation['clock_acceptance_claimed'])
                self.assertEqual(observation['stage'],'complete')
                self.assertEqual(sum(c==['root'] for c in calls),1)
                self.assertEqual(sum(c==['unroot'] for c in calls),1)
                self.assertEqual(sum(c[:2]==['shell','date'] for c in calls),1)
                self.assertEqual(calls[calls.index([operation])+1],['shell','id','-u'])
                self.assertNotIn('SYNTHETIC_PRIVATE',str(instance.receipt))

    def test_restart_ack_or_transport_error_never_substitutes_for_missing_uid_state(self):
        for missing in ('root','unroot'):
            for mode in ('zero','nonzero','stderr','timeout'):
                instance=self.clock_instance('missing-'+missing+'-'+mode)
                calls,phase=[],['root']
                def fake(args,**kwargs):
                    op=args[3:];calls.append(op)
                    if op in (['root'],['unroot']):
                        phase[0]=op[0]
                        if op==[missing]:
                            if mode=='timeout':raise subprocess.TimeoutExpired(['SYNTHETIC_PRIVATE_COMMAND'],5)
                            return subprocess.CompletedProcess(args,1 if mode=='nonzero' else 0,b'',b'SYNTHETIC_PRIVATE_ERROR' if mode=='stderr' else b'')
                    if op==['shell','id','-u']:
                        actual='2000' if phase[0]=='unroot' else '0'
                        if phase[0]==missing:actual='0' if missing=='unroot' else '2000'
                        return subprocess.CompletedProcess(args,0,(actual+'\n').encode(),b'')
                    return subprocess.CompletedProcess(args,0,b'',b'')
                ticks=iter(100+i*.05 for i in range(5000))
                expected='owned_clock_root_uid_unverified' if missing=='root' else 'owned_default_shell_uid_unverified'
                with self.subTest(missing=missing,mode=mode),patch.object(vm.subprocess,'run',side_effect=fake), \
                     patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
                     patch.object(vm.time,'monotonic',side_effect=lambda:next(ticks)),patch.object(vm.time,'sleep'):
                    with self.assertRaisesRegex(vm.VmBlocked,'^'+expected+'$'):
                        instance.prepare_utc_clock(deadline=150)
                observation=instance.receipt['clock_preparation']
                self.assertEqual(sum(c==['root'] for c in calls),1)
                self.assertEqual(sum(c==['unroot'] for c in calls),1)
                self.assertEqual(sum(c[:2]==['shell','date'] for c in calls),0 if missing=='root' else 1)
                self.assertEqual(observation['root_uid_verified'],missing!='root')
                self.assertEqual(observation['default_shell_uid_restored'],missing!='unroot')
                self.assertFalse(observation['clock_acceptance_claimed'])
                key='failure_stage' if missing=='root' else 'restore_failure_stage'
                self.assertEqual(observation[key],'root_uid_wait' if missing=='root' else 'shell_uid_wait')
                self.assertNotIn('SYNTHETIC_PRIVATE',str(instance.receipt))

    def test_restart_timeout_uses_remaining_original_budget_and_never_renews_uid_wait(self):
        instance=self.clock_instance()
        calls,clock,rooted=[],[100.0],[False]
        def fake(args,**kwargs):
            op=args[3:];calls.append((op,kwargs['timeout']))
            self.assertLessEqual(kwargs['timeout'],110-clock[0])
            if op in (['root'],['unroot']):
                rooted[0]=op==['root'];clock[0]+=kwargs['timeout']
                raise subprocess.TimeoutExpired(['SYNTHETIC_PRIVATE_COMMAND'],kwargs['timeout'])
            if op==['shell','id','-u']:
                return subprocess.CompletedProcess(args,0,b'0\n' if rooted[0] else b'2000\n',b'')
            return subprocess.CompletedProcess(args,0,b'',b'')
        with patch.object(vm.subprocess,'run',side_effect=fake), \
             patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
             patch.object(vm.time,'monotonic',side_effect=lambda:clock[0]),patch.object(vm.time,'sleep'):
            with self.assertRaisesRegex(vm.VmBlocked,'^owned_default_shell_uid_unverified$'):
                instance.prepare_utc_clock(deadline=110)
        self.assertEqual(clock[0],110)
        self.assertEqual([op for op,timeout in calls],[['root'],['shell','id','-u'],['shell','date','-u','-s','@1793754123.123456789'],['unroot']])
        observation=instance.receipt['clock_preparation']
        self.assertEqual(observation['root_request']['transport'],'UNOBSERVED')
        self.assertEqual(observation['unroot_request']['transport'],'UNOBSERVED')
        self.assertTrue(observation['root_uid_verified'])
        self.assertTrue(observation['date_setter_exit_zero'])
        self.assertFalse(observation['default_shell_uid_restored'])
        self.assertEqual(observation['restore_failure_stage'],'shell_uid_wait')

    def test_clock_preparation_waits_for_actual_uid_without_replaying_mutations(self):
        instance = self.clock_instance()
        calls, phase, reads = [], ['root'], {'root':0,'shell':0}
        def fake(args, **kwargs):
            operation=args[3:];calls.append(operation)
            if operation==['unroot']: phase[0]='shell'
            elif operation==['shell','id','-u']:
                key=phase[0];reads[key]+=1
                if reads[key]==1:
                    return subprocess.CompletedProcess(args,1,b'',b'SYNTHETIC_TRANSIENT_DISCONNECT')
                uid=(b'2000\n' if key=='root' else b'0\n') if reads[key]==2 else (b'0\n' if key=='root' else b'2000\n')
                return subprocess.CompletedProcess(args,0,uid,b'')
            return subprocess.CompletedProcess(args,0,b'',b'')
        with patch.object(vm.subprocess,'run',side_effect=fake), \
             patch.object(vm.time,'time_ns',return_value=1793754123123456789), \
             patch.object(vm.time,'monotonic',return_value=100), patch.object(vm.time,'sleep'):
            self.assertTrue(instance.prepare_utc_clock(deadline=150))
        self.assertEqual(sum(c==['root'] for c in calls),1)
        self.assertEqual(sum(c==['unroot'] for c in calls),1)
        self.assertEqual(sum(c[:2]==['shell','date'] for c in calls),1)
        self.assertEqual(reads,{'root':3,'shell':3})
        self.assertNotIn('SYNTHETIC_TRANSIENT',str(instance.receipt))
        self.assertFalse(instance.receipt['clock_preparation']['clock_acceptance_claimed'])

    def test_clock_uid_wait_remains_bounded_and_records_only_fixed_failure_stage(self):
        instance = self.clock_instance()
        calls = []
        def fake(args, **kwargs):
            operation=args[3:];calls.append(operation)
            return subprocess.CompletedProcess(args,0,b'2000\n' if operation==['shell','id','-u'] else b'',b'')
        ticks=iter(100+i*.25 for i in range(1000))
        with patch.object(vm.subprocess,'run',side_effect=fake), \
             patch.object(vm.time,'monotonic',side_effect=lambda:next(ticks)), patch.object(vm.time,'sleep'):
            with self.assertRaisesRegex(vm.VmBlocked,'^owned_clock_root_uid_unverified$'):
                instance.prepare_utc_clock(deadline=150)
        self.assertEqual(sum(c==['root'] for c in calls),1)
        self.assertEqual(sum(c==['unroot'] for c in calls),1)
        self.assertFalse(any(c[:2]==['shell','date'] for c in calls))
        observation=instance.receipt['clock_preparation']
        self.assertEqual(observation['failure_stage'],'root_uid_wait')
        self.assertFalse(observation['root_uid_verified'])
        self.assertTrue(observation['default_shell_uid_restored'])
        self.assertFalse(observation['clock_acceptance_claimed'])

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

    def recording_instance(self, suffix=None):
        instance=self.clock_instance(suffix)
        instance._clock_preparation_used=True
        instance.receipt['clock_preparation']={'stage':'complete','root_uid_verified':True,
            'date_setter_exit_zero':True,'default_shell_uid_restored':True,'clock_acceptance_claimed':False}
        return instance

    def test_recording_environment_once_observes_user0_and_only_disables_its_system_sound_effects(self):
        instance=self.recording_instance()
        operations=[]
        expected=[['shell','id','-u'],['shell','am','get-current-user'],
                  ['shell','settings','--user','0','put','system','sound_effects_enabled','0'],
                  ['shell','settings','--user','0','get','system','sound_effects_enabled']]
        def fake(args,**kwargs):
            self.assertEqual(args[:3],[str(self.sdk/'platform-tools/adb'),'-s','emulator-5554'])
            op=args[3:];operations.append(op);self.assertLessEqual(kwargs['timeout'],3)
            return subprocess.CompletedProcess(args,0,b'2000\n' if op==expected[0] else b'0\n' if op in (expected[1],expected[3]) else b'',b'')
        with patch.object(vm.subprocess,'run',side_effect=fake),patch.object(vm.time,'monotonic',return_value=100):
            self.assertTrue(instance.prepare_recording_environment(deadline=150))
            with self.assertRaises(vm.VmBlocked):instance.prepare_recording_environment(deadline=150)
        self.assertEqual(operations,expected)
        self.assertEqual(instance.receipt['recording_environment'],{'attempted_once':True,
            'current_android_user0_verified':True,'system_sound_effects_disabled_readback':True,
            'actual_recorded_silence_claimed':False,'stage':'complete'})
        self.assertFalse(instance.receipt['clock_preparation']['clock_acceptance_claimed'])

    def test_recording_environment_requires_actual_owned_clock_proofs_and_an_existing_deadline(self):
        variants=['not_started','closed','not_ready','parent_ended','clock_unused','clock_missing',
                  'clock_incomplete','root_unverified','setter_unverified','shell_unverified','expired','nonfinite']
        for variant in variants:
            instance=self.recording_instance(variant)
            if variant=='not_started':instance.started=False
            elif variant=='closed':instance.closed=True
            elif variant=='not_ready':instance.receipt['boot_and_CE_ready']=False
            elif variant=='parent_ended':instance.process.poll.return_value=0
            elif variant=='clock_unused':instance._clock_preparation_used=False
            elif variant=='clock_missing':instance.receipt.pop('clock_preparation')
            elif variant=='clock_incomplete':instance.receipt['clock_preparation']['stage']='unroot_request'
            elif variant=='root_unverified':instance.receipt['clock_preparation']['root_uid_verified']=False
            elif variant=='setter_unverified':instance.receipt['clock_preparation']['date_setter_exit_zero']=False
            elif variant=='shell_unverified':instance.receipt['clock_preparation']['default_shell_uid_restored']=False
            deadline=100 if variant=='expired' else float('nan') if variant=='nonfinite' else 150
            with self.subTest(variant=variant),patch.object(vm.subprocess,'run') as run,patch.object(vm.time,'monotonic',return_value=100):
                with self.assertRaises(vm.VmBlocked):instance.prepare_recording_environment(deadline=deadline)
                run.assert_not_called()
            self.assertNotIn('recording_environment',instance.receipt)

    def test_recording_environment_refuses_wrong_actual_uid_or_current_user_before_any_settings_write(self):
        for index,(uid,user,expected_stage) in enumerate([('0','0','shell_uid'),('2000','1','current_user'),
                                                        ('2000','null','current_user'),('2000','','current_user')]):
            instance=self.recording_instance('scope-'+str(index));operations=[]
            def fake(args,**kwargs):
                op=args[3:];operations.append(op)
                self.assertIn(op,[['shell','id','-u'],['shell','am','get-current-user']])
                return subprocess.CompletedProcess(args,0,((uid if op==['shell','id','-u'] else user)+'\n').encode(),b'')
            with self.subTest(uid=uid,user=user),patch.object(vm.subprocess,'run',side_effect=fake),patch.object(vm.time,'monotonic',return_value=100):
                with self.assertRaises(vm.VmBlocked):instance.prepare_recording_environment(deadline=150)
            observation=instance.receipt['recording_environment']
            self.assertEqual(observation['failure_stage'],expected_stage)
            self.assertFalse(observation['current_android_user0_verified'])
            self.assertFalse(observation['system_sound_effects_disabled_readback'])
            self.assertFalse(observation['actual_recorded_silence_claimed'])
            self.assertEqual(len(operations),1 if expected_stage=='shell_uid' else 2)

    def test_recording_environment_strict_command_failures_never_replay_or_export_private_output(self):
        stages=['shell_uid','current_user','system_sound_effects_put','system_sound_effects_get']
        for failed_index,stage in enumerate(stages):
            for mode in ['nonzero','stderr','timeout','oserror','nonascii','oversized','runtime_lost','wrong_readback']:
                if mode=='wrong_readback' and failed_index!=3:continue
                instance=self.recording_instance('failure-'+str(failed_index)+'-'+mode);operations=[]
                def fake(args,**kwargs):
                    op=args[3:];operations.append(op)
                    normal=b'2000\n' if len(operations)==1 else b'0\n' if len(operations) in (2,4) else b''
                    if len(operations)==failed_index+1:
                        if mode=='timeout':raise subprocess.TimeoutExpired(['SYNTHETIC_PRIVATE_COMMAND'],3,output=b'SYNTHETIC_PRIVATE_OUTPUT')
                        if mode=='oserror':raise OSError('SYNTHETIC_PRIVATE_ERROR')
                        if mode=='runtime_lost':instance.process.poll.return_value=0
                        output=b'\xff' if mode=='nonascii' else b'X'*4097 if mode=='oversized' else b'SYNTHETIC_PRIVATE_OUTPUT' if mode=='wrong_readback' else normal
                        return subprocess.CompletedProcess(args,1 if mode=='nonzero' else 0,output,b'SYNTHETIC_PRIVATE_ERROR' if mode=='stderr' else b'')
                    return subprocess.CompletedProcess(args,0,normal,b'')
                with self.subTest(stage=stage,mode=mode),patch.object(vm.subprocess,'run',side_effect=fake),patch.object(vm.time,'monotonic',return_value=100):
                    with self.assertRaises(vm.VmBlocked) as caught:instance.prepare_recording_environment(deadline=150)
                    before=len(operations)
                    with self.assertRaises(vm.VmBlocked):instance.prepare_recording_environment(deadline=150)
                    self.assertEqual(len(operations),before)
                observation=instance.receipt['recording_environment']
                self.assertEqual(len(operations),failed_index+1)
                self.assertEqual(observation['failure_stage'],stage)
                self.assertFalse(observation['system_sound_effects_disabled_readback'])
                self.assertFalse(observation['actual_recorded_silence_claimed'])
                self.assertNotIn('SYNTHETIC_PRIVATE',str(instance.receipt))
                self.assertNotIn('SYNTHETIC_PRIVATE',str(caught.exception))
                self.assertLessEqual(sum('put' in op for op in operations),1)
                self.assertLessEqual(sum('get' in op for op in operations),1)

    def test_recording_environment_deadline_is_shared_across_reads_write_and_readback(self):
        for seconds in (1,10):
            instance=self.recording_instance('deadline-'+str(seconds));clock=[100.0];operations=[];timeouts=[]
            def fake(args,**kwargs):
                operations.append(args[3:]);timeouts.append(kwargs['timeout'])
                self.assertLessEqual(kwargs['timeout'],min(3,100+seconds-clock[0]))
                clock[0]+=kwargs['timeout']
                output=b'2000\n' if len(operations)==1 else b'0\n' if len(operations) in (2,4) else b''
                return subprocess.CompletedProcess(args,0,output,b'')
            with self.subTest(seconds=seconds),patch.object(vm.subprocess,'run',side_effect=fake),patch.object(vm.time,'monotonic',side_effect=lambda:clock[0]):
                with self.assertRaisesRegex(vm.VmBlocked,'^owned_recording_environment_deadline_or_runtime_lost$'):
                    instance.prepare_recording_environment(deadline=101 if seconds==1 else 150)
            self.assertEqual(clock[0],100+seconds)
            self.assertEqual(timeouts,[1] if seconds==1 else [3,3,3,1])
            observation=instance.receipt['recording_environment']
            self.assertFalse(observation['system_sound_effects_disabled_readback'])
            self.assertFalse(observation['actual_recorded_silence_claimed'])
            self.assertEqual(observation['failure_stage'],'shell_uid' if seconds==1 else 'system_sound_effects_get')

    def test_clock_preparation_requires_live_owned_boot_and_cannot_extend_expired_budget(self):
        instance=self.clock_instance()
        with patch.object(vm.subprocess,'run') as run, patch.object(vm.time,'monotonic',return_value=100):
            with self.assertRaises(vm.VmBlocked):instance.prepare_utc_clock(deadline=100)
            instance.process.poll.return_value=0
            with self.assertRaises(vm.VmBlocked):instance.prepare_utc_clock(deadline=150)
            run.assert_not_called()


if __name__ == '__main__': unittest.main()
