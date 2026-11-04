"""Safety/control-flow tests only; no device, network or real account access."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import probe_phase1_native_account as native


class NativeAccountSafetyTest(unittest.TestCase):
    def test_fixed_mode_selected_before_account_input_dispatch(self):
        for op in ('account-click', 'account-set', 'account-scroll', 'account-snapshot'):
            receipt = ['INSTRUMENTATION_RESULT: passed=true',
                       'INSTRUMENTATION_RESULT: op=' + op, 'INSTRUMENTATION_CODE: -1']
            self.probe.adb = Mock(return_value='\n'.join(receipt))
            self.probe.instrument(op)
            argv = self.probe.adb.call_args.args
            if op in ('account-click', 'account-set'):
                index = argv.index('input_mode')
                self.assertEqual(argv[index + 1], 'physical_click_focus')
                self.assertEqual(argv.count('input_mode'), 1)
            elif op == 'account-scroll':
                index = argv.index('input_mode')
                self.assertEqual(argv[index + 1], 'physical_scroll')
                self.assertEqual(argv.count('input_mode'), 1)
            else:
                self.assertNotIn('input_mode', argv)
            self.probe.adb.assert_called_once()

    def test_caller_cannot_override_fixed_mode_before_any_dispatch(self):
        for value in ('semantic', 'physical_click_focus', 'physical_scroll', 'PRIVATE_SYNTHETIC_SENTINEL'):
            self.probe.adb = Mock()
            with self.assertRaisesRegex(native.Blocked, '^fixed_native_input_mode_required$'):
                self.probe.instrument('account-click', input_mode=value)
            self.probe.adb.assert_not_called()

    def test_failed_physical_call_is_not_replayed_or_recorded_as_delivered(self):
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: stage=account_pointer_tap',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.act('click', self.node('synthetic button', clickable=True))
        self.probe.adb.assert_called_once()
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['native_input_failures'][0]['java_stage'], 'account_pointer_tap')

    def test_selection_diagnostic_stage_retains_no_path_witness_or_value(self):
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: stage=pointer_bounds_containment',
            'INSTRUMENTATION_RESULT: foreground_category=APP',
            'INSTRUMENTATION_RESULT: node_witness=' + 'f' * 64,
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-click', node_path='0.999', node_witness='f' * 64)
        self.probe.adb.assert_called_once()
        row = self.probe.report['native_input_failures'][0]
        self.assertEqual(row['java_stage'], 'pointer_bounds_containment')
        self.assertNotIn('0.999', json.dumps(row))
        self.assertNotIn('f' * 64, json.dumps(row))
        self.assertEqual(self.probe.report['actions'], [])

    def test_failed_physical_scroll_is_never_replayed(self):
        self.probe.case_phase('C1-cleanup')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-scroll',
            'INSTRUMENTATION_RESULT: stage=account_pointer_swipe',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-scroll', node_path='0.1', node_witness='a' * 64)
        self.probe.adb.assert_called_once()
        self.assertEqual(self.probe.adb.call_args.args.count('physical_scroll'), 1)
        self.assertEqual(self.probe.report['actions'], [])

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.patch_root = patch.object(native, 'ROOT', self.root)
        self.patch_root.start()
        self.addCleanup(self.patch_root.stop)
        self.private = self.root / 'private'
        self.private.mkdir()
        # These are invented test strings; never import task-private credentials.
        self.access = {'otp': ''.join(str((index * 7 + 3) % 10) for index in range(6)), 'phones': {
            'broker': '+967700000001', 'support': '+967700000002',
            'regular': '+967700000003'}}
        self.probe = native.NativeAccount(self.private, {
            native.SECRET_NAME: json.dumps(self.access),
            'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40})
        self.probe.serial = 'emulator-5554'

    @staticmethod
    def node(text='', path='0.1', package=native.APP, bounds=None, **extra):
        return dict(text=text, path=path, package=package, visible=True,
                    enabled=True, bounds=bounds or [0, 0, 200, 50],
                    witness='a' * 64, **extra)

    def test_receipt_rejects_private_values_without_replacing_safe_previous_copy(self):
        path = self.probe.out / 'report.json'
        before = path.read_bytes()
        self.probe.report['unexpected'] = self.access['otp']
        with self.assertRaisesRegex(native.Blocked, 'private_value'):
            self.probe.save()
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn(self.access['otp'], path.read_text())

    def test_driver_retains_only_the_broker_and_never_activates_optional_accounts(self):
        self.assertEqual(set(self.probe.access['phones']), {'broker'})
        self.assertNotIn(self.access['phones']['support'], self.probe.private_values)
        self.assertNotIn(self.access['phones']['regular'], self.probe.private_values)
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_login_records_fixed_phase_before_each_unchanged_normal_operation(self):
        phases = []
        self.probe.tap = Mock(side_effect=lambda label: phases.append(self.probe.report['native_auth_phase']))
        self.probe.set = Mock(side_effect=lambda label, value: phases.append(self.probe.report['native_auth_phase']))
        self.probe.wait = Mock()
        self.probe.authenticated_account_evidence = Mock(
            side_effect=lambda: phases.append(self.probe.report['native_auth_phase']) or {})
        self.probe.login()
        self.assertEqual(phases, ['account_open', 'login_open', 'phone_entry', 'code_request',
                                  'otp_entry', 'confirm', 'postcondition'])
        self.assertEqual([call.args[0] for call in self.probe.tap.call_args_list],
                         ['حسابي', 'تسجيل الدخول أو إنشاء حساب', 'إرسال رمز واتساب', 'تأكيد والدخول'])
        self.probe.set.assert_any_call('رقم واتساب', self.access['phones']['broker'])
        self.probe.set.assert_any_call('رمز التحقق', self.access['otp'])
        self.assertIsNone(self.probe._auth_phase)
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.assertEqual(self.probe.report['frames'], [])

    def test_auth_input_failure_retains_only_fixed_phase_stage_op_and_booleans(self):
        witness = 'f' * 64
        private_blob = base64.b64encode(self.access['phones']['broker'].encode()).decode()
        self.probe.case_phase('C1-auth')
        self.probe.auth_phase('code_request')
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=account_pointer_tap',
            'INSTRUMENTATION_RESULT: foreground_category=APP',
            'INSTRUMENTATION_RESULT: tree_b64=' + private_blob,
            'INSTRUMENTATION_RESULT: reason=' + self.access['otp'],
            'INSTRUMENTATION_RESULT: witness=' + witness,
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.instrument('account-click', node_path='0.1', node_witness=witness)
        self.assertEqual(self.probe.report['native_input_failures'], [{
            'case': 'C1-auth', 'auth_phase': 'code_request', 'op': 'account-click',
            'java_stage': 'account_pointer_tap', 'foreground_category': 'APP',
            'passed_true': False, 'passed_false': True, 'code_minus_one': False,
            'code_zero': True, 'reason': 'native_input_not_delivered'}])
        serialized = (self.probe.out / 'report.json').read_text()
        for forbidden in [private_blob, witness, self.access['otp'], self.access['phones']['broker']]:
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['frames'], [])

    def test_private_exception_or_injected_stage_cannot_enter_auth_diagnostic(self):
        raw = self.access['phones']['broker'] + ' private framework exception ' + self.access['otp']
        for observation in [native.Blocked(raw), RuntimeError(raw),
                            native.Blocked('device_command_timeout'), '\n'.join([
                'INSTRUMENTATION_RESULT: op=account-set',
                'INSTRUMENTATION_RESULT: passed=false',
                'INSTRUMENTATION_RESULT: stage=' + raw,
                'INSTRUMENTATION_RESULT: foreground_category=' + raw,
                'INSTRUMENTATION_RESULT: arbitrary=' + raw,
                'INSTRUMENTATION_CODE: 0'])]:
            self.probe.report['native_input_failures'] = []
            self.probe.case_phase('C1-auth')
            self.probe.auth_phase('phone_entry')
            self.probe.adb = Mock(side_effect=observation) if isinstance(observation, Exception) \
                else Mock(return_value=observation)
            with self.subTest(observation_type=type(observation).__name__):
                with self.assertRaises(native.Blocked) as failure:
                    self.probe.instrument('account-set', value_b64=base64.b64encode(raw.encode()).decode())
                self.assertIn(str(failure.exception), native.INPUT_FAILURE_REASONS)
                diagnostic = self.probe.report['native_input_failures'][0]
                self.assertIsNone(diagnostic['java_stage'])
                self.assertEqual(diagnostic['foreground_category'], 'UNOBSERVED')
                self.assertIn(diagnostic['reason'], native.INPUT_FAILURE_REASONS)
                if isinstance(observation, native.Blocked) and str(observation) in native.INPUT_FAILURE_REASONS:
                    self.assertEqual(diagnostic['reason'], str(observation))
                self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())
                self.assertNotIn(self.access['otp'], json.dumps(diagnostic))

    def test_unknown_phase_and_requested_operation_never_enter_auth_diagnostic(self):
        raw = 'private-' + self.access['phones']['broker']
        with self.assertRaisesRegex(native.Blocked, '^fixed_native_auth_phase_required$'):
            self.probe.auth_phase(raw)
        self.assertNotIn('native_auth_phase', self.probe.report)
        self.probe.auth_phase('account_open')
        self.probe.case_phase('C1-auth')
        self.probe.adb = Mock(return_value='INSTRUMENTATION_RESULT: passed=false\nINSTRUMENTATION_CODE: 0')
        with self.assertRaises(native.Blocked):
            self.probe.instrument(raw)
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())

    def test_failure_diagnostic_is_disabled_outside_owned_case_and_covers_postauth(self):
        self.probe.adb = Mock(return_value='INSTRUMENTATION_RESULT: passed=false\nINSTRUMENTATION_CODE: 0')
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-snapshot')
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-snapshot')
        self.assertEqual(len(self.probe.report['native_input_failures']), 1)
        self.assertEqual(self.probe.report['native_input_failures'][0]['case'], 'C1-photo-save')
        self.assertIsNone(self.probe.report['native_input_failures'][0]['auth_phase'])

    def test_login_failure_clears_active_phase_without_auth_images_or_witness_hashes(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=root_ready', 'INSTRUMENTATION_CODE: 0']))
        self.probe.tap = Mock(side_effect=lambda label: self.probe.instrument('account-click'))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.login()
        self.assertIsNone(self.probe._auth_phase)
        self.assertEqual(self.probe.report['native_auth_phase'], 'account_open')
        self.assertEqual(self.probe.report['native_input_failures'][0]['java_stage'], 'root_ready')
        self.assertFalse(self.probe.auth_attempted)
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_input_diagnostics_keep_only_first_failure_for_each_fixed_case_and_six_total(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=initial_witness_match',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        for case in native.C1_CASES:
            self.probe.case_phase(case)
            self.probe.authenticated = True
            self.probe._auth_phase = self.access['phones']['broker']
            for repeated_failure in range(2):
                with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
                    self.probe.instrument('account-click', node_witness='f' * 64)
        failures = self.probe.report['native_input_failures']
        self.assertEqual(len(failures), 6)
        self.assertEqual([row['case'] for row in failures], list(native.C1_CASES))
        self.assertTrue(all(row['auth_phase'] is None and row['java_stage'] == 'initial_witness_match'
                            and row['foreground_category'] == 'APP' for row in failures))
        for row in failures:
            self.assertEqual(set(row), {'case', 'auth_phase', 'op', 'java_stage', 'foreground_category',
                                        'passed_true', 'passed_false', 'code_minus_one', 'code_zero', 'reason'})
        with self.assertRaisesRegex(native.Blocked, '^fixed_native_case_required$'):
            self.probe.case_phase(self.access['otp'])
        serialized = (self.probe.out / 'report.json').read_text()
        self.assertNotIn(self.access['phones']['broker'], serialized)
        self.assertNotIn('f' * 64, serialized)
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['videos'], [])

    def test_cleanup_instrument_failure_is_retained_separately_from_original_case(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=selected_path_resolve',
            'INSTRUMENTATION_RESULT: foreground_category=SYSTEM_UI', 'INSTRUMENTATION_CODE: 0']))
        self.probe.case_phase('C1-photo-save')
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-click')
        self.probe.native_logout = Mock(side_effect=lambda: self.probe.instrument('account-click'))
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        self.assertEqual([row['case'] for row in self.probe.report['native_input_failures']],
                         ['C1-photo-save', 'C1-cleanup'])
        fixture.cleanup.assert_called_once_with()

    def test_global_diagnostic_preserves_unexpected_exception_control_flow_without_its_text(self):
        raw = self.access['phones']['broker'] + ' private framework error'
        self.probe.case_phase('C1-native-network')
        self.probe.adb = Mock(side_effect=RuntimeError(raw))
        with self.assertRaises(RuntimeError):
            self.probe.instrument('account-snapshot')
        failure = self.probe.report['native_input_failures'][0]
        self.assertEqual(failure['case'], 'C1-native-network')
        self.assertEqual(failure['reason'], 'native_instrumentation_unobserved')
        self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())

    def test_diagnostic_stage_and_foreground_allowlists_match_fixed_java_literals(self):
        source = Path(__file__).resolve().parents[1] / 'phase1_device_input/Phase1Input.java'
        text = source.read_text()
        stages = set(native.re.findall(r'stage="([a-z_]+)"', text))
        self.assertTrue(native.INPUT_JAVA_STAGES <= stages)
        classifier = text.split('private static String foregroundCategory', 1)[1].split(
            'private static String numbers', 1)[0]
        self.assertEqual(set(native.re.findall(r'return "([A-Z_]+)"', classifier)),
                         set(native.FOREGROUND_CATEGORIES))
        success, failure = text.split('} catch (Throwable failure)', 1)
        self.assertNotIn('putString("foreground_category"', success)
        self.assertIn('putString("foreground_category", foreground)', failure)

    def test_capture_requires_authenticated_state_before_any_device_read(self):
        self.probe.nodes = Mock()
        self.probe.adb = Mock()
        with self.assertRaisesRegex(native.Blocked, 'authentication_capture'):
            self.probe.safe_capture('C1-untrusted')
        self.probe.nodes.assert_not_called()
        self.probe.adb.assert_not_called()
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_capture_refuses_auth_screens_and_visible_private_account_values(self):
        self.probe.authenticated = True
        for unsafe in ['رمز التحقق', self.access['phones']['broker'],
                       self.access['phones']['broker'].lstrip('+')]:
            with self.subTest(unsafe_type='auth' if unsafe == 'رمز التحقق' else 'private'):
                self.probe.nodes = Mock(return_value=[self.node(unsafe)])
                self.probe.adb = Mock()
                with self.assertRaisesRegex(native.Blocked, 'private_native_capture'):
                    self.probe.safe_capture('C1-refused')
                self.probe.adb.assert_not_called()
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_short_backend_phone_is_kept_whole_and_not_treated_as_a_country_prefix(self):
        digits = ''.join(str((index * 3 + 1) % 10) for index in range(7))
        env = {native.SECRET_NAME: json.dumps({'otp': self.access['otp'], 'phones': {'broker': digits}}),
               'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40}
        probe = native.NativeAccount(self.private, env)
        self.assertEqual(probe.access['phones']['broker'], digits)
        self.assertIn(digits, probe.private_values)
        self.assertNotIn(digits[3:], probe.private_values)

    def test_login_passes_the_provided_backend_phone_to_the_ui_without_country_rewriting(self):
        digits = ''.join(str((index * 7 + 2) % 10) for index in range(8))
        env = {native.SECRET_NAME: json.dumps({'otp': self.access['otp'], 'phones': {'broker': '+' + digits}}),
               'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40}
        probe = native.NativeAccount(self.private, env)
        probe.tap = Mock(); probe.wait = Mock(); probe.set = Mock()
        probe.nodes = Mock(return_value=[self.node('عملي'), self.node('العملاء')])
        probe.login()
        self.assertEqual(probe.set.call_args_list[0].args, ('رقم واتساب', '+' + digits))
        self.assertTrue(probe.report['native_auth_executed'])

    def test_recording_is_tainted_on_observed_auth_transition(self):
        self.probe.recorder = Mock()
        rows = [self.node('رمز التحقق')]
        encoded = base64.b64encode(json.dumps(rows).encode()).decode()
        self.probe.instrument = Mock(return_value={'tree_b64': encoded})
        with self.assertRaisesRegex(native.Blocked, 'authentication_transition'):
            self.probe.nodes()
        self.assertTrue(self.probe.record_tainted)
        self.assertEqual(self.probe.report['videos'], [])

    def test_profile_authentication_can_pin_broker_role_from_revoked_api_setup_without_footer_assumption(self):
        self.probe.report['api_bootstrap'] = {'status': 'PASS', 'fresh_session_cleaned': True,
            'identity': {'actor_id': 28, 'account_type': 'broker'}}
        self.probe.nodes = Mock(return_value=[self.node('تسجيل الخروج'), self.node('عقاراتي')])
        result = self.probe.authenticated_account_evidence()
        self.assertEqual(result['native_auth_witness'], 'authenticated_profile_logout_control')
        self.assertTrue(result['broker_role_api_pinned'])
        self.assertFalse(result['broker_role_ui_witness'])
        self.assertTrue(result['professional_controls_visible'])

    def test_profile_logout_or_professional_controls_alone_do_not_prove_broker_role(self):
        self.probe.nodes = Mock(return_value=[self.node('تسجيل الخروج'), self.node('عقاراتي')])
        with patch.object(native.time, 'sleep'), patch.object(native.time, 'monotonic', side_effect=[0, 1, 91]):
            with self.assertRaisesRegex(native.Blocked, '^native_broker_auth_not_observed$'):
                self.probe.authenticated_account_evidence()

    def test_current_public_reference_and_exact_native_match_are_recorded_as_hashes_not_full_list(self):
        references = [{'id': 71, 'title': 'fresh-host-title'}, {'id': 72, 'title': 'other-current-title'}]
        self.probe.nodes = Mock(return_value=[self.node('fresh-host-title')])
        with patch.object(native, 'read_public_reference', return_value=references) as read:
            self.probe.public_network_readiness()
        read.assert_called_once_with()
        case = next(row for row in self.probe.report['cases'] if row['id'] == 'C1-native-network')
        self.assertEqual(case['status'], 'PASS')
        self.assertEqual(case['public_reference_count'], 2)
        self.assertEqual(case['visible_match_count'], 1)
        self.assertEqual(case['public_reference_sha256'], native.digest(references))
        serialized = json.dumps(self.probe.report)
        self.assertNotIn('fresh-host-title', serialized); self.assertNotIn('other-current-title', serialized)

    def test_old_or_unrelated_native_title_does_not_satisfy_a_fresh_host_reference(self):
        self.probe.nodes = Mock(return_value=[self.node('old-hardcoded-title')])
        self.probe.scroll = Mock()
        with patch.object(native, 'read_public_reference', return_value=[{'id': 71, 'title': 'current-host-title'}]), \
                patch.object(native.time, 'sleep'), patch.object(native.time, 'monotonic', side_effect=[0, 1, 61]):
            with self.assertRaisesRegex(native.Blocked, '^native_public_uat_response_not_observed$'):
                self.probe.public_network_readiness()
        self.assertEqual(next(row for row in self.probe.report['cases'] if row['id'] == 'C1-native-network')['status'], 'NOT RUN')

    def test_missing_real_public_response_never_attempts_native_match_or_api_bootstrap(self):
        self.probe.nodes = Mock(); self.probe.fixture_api = None
        with patch.object(native, 'read_public_reference', side_effect=native.FixtureError('public_reference_http_or_shape')):
            with self.assertRaises(native.FixtureError): self.probe.public_network_readiness()
        self.probe.nodes.assert_not_called()
        self.assertIsNone(self.probe.fixture_api)

    def test_failed_or_unfinished_recording_is_discarded_by_default(self):
        recorder = Mock()
        recorder.poll.return_value = 0
        self.probe.recorder = recorder
        self.probe.video_name = 'C1-unfinished'
        self.probe.adb = Mock(return_value='')
        self.probe.safe_capture = Mock()
        self.probe.record_stop()
        self.probe.safe_capture.assert_not_called()
        self.assertFalse(any(call.args[:2] == ('exec-out', 'cat')
                             for call in self.probe.adb.call_args_list))
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(list(self.probe.out.glob('*.mp4')), [])
        self.probe.adb.assert_any_call('shell', 'rm', '-f',
                                      '/sdcard/phase1-account.mp4', codes=(0, 1))

    def test_explicit_video_export_still_refuses_a_tainted_segment(self):
        recorder = Mock()
        recorder.poll.return_value = 0
        self.probe.recorder = recorder
        self.probe.record_tainted = True
        self.probe.video_name = 'C1-tainted'
        self.probe.adb = Mock(return_value='')
        self.probe.safe_capture = Mock()
        with self.assertRaisesRegex(native.Blocked, 'tainted_native_video'):
            self.probe.record_stop(export=True)
        self.probe.safe_capture.assert_not_called()
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(list(self.probe.out.glob('*.mp4')), [])

    def test_instrumentation_duplicate_receipt_is_not_accepted(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=true',
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_CODE: -1']))
        with self.assertRaisesRegex(native.Blocked, 'ambiguous_native_input'):
            self.probe.instrument('account-click')

    def test_success_fields_without_successful_instrumentation_exit_are_refused(self):
        for ending in ['', 'INSTRUMENTATION_CODE: 0', 'INSTRUMENTATION_CODE: 1']:
            self.probe.adb = Mock(return_value='\n'.join([
                'INSTRUMENTATION_RESULT: passed=true',
                'INSTRUMENTATION_RESULT: op=account-click', ending]))
            with self.subTest(ending=ending):
                with self.assertRaisesRegex(native.Blocked, 'native_input_not_delivered'):
                    self.probe.instrument('account-click')

    def test_rejected_stale_witness_does_not_record_a_delivered_action(self):
        row = self.node('التالي', path='0.2.3', clickable=True)
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: reason=input_precondition_or_delivery_failed',
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, 'native_input_not_delivered'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'], [])
        invocation = self.probe.adb.call_args.args
        self.assertIn(row['path'], invocation)
        self.assertIn(row['witness'], invocation)

    def test_nonclickable_named_button_uses_only_that_observed_node(self):
        button = self.node('حسابي', path='0.2.4', clickable=False,
                           **{'class': 'android.widget.Button'})
        self.probe.nodes = Mock(return_value=[button])
        self.probe.act = Mock()
        self.probe.tap('حسابي', seek=False)
        self.probe.act.assert_called_once_with('click', button)

    def test_nonclickable_generic_view_has_no_coordinate_fallback(self):
        text = self.node('حسابي', clickable=False, **{'class': 'android.view.View'})
        self.probe.nodes = Mock(return_value=[text])
        self.probe.act = Mock()
        with self.assertRaisesRegex(native.Blocked, 'semantic_native_click_unavailable'):
            self.probe.tap('حسابي', seek=False)
        self.probe.act.assert_not_called()

    def test_duplicate_named_pointer_buttons_are_refused_instead_of_guessing_bounds(self):
        buttons = [self.node('التالي', path='0.2', clickable=False,
                             bounds=[0, 0, 150, 50], **{'class': 'android.widget.Button'}),
                   self.node('التالي', path='0.3', clickable=False,
                             bounds=[0, 80, 300, 160], **{'class': 'android.widget.Button'})]
        self.probe.nodes = Mock(return_value=buttons)
        self.probe.act = Mock()
        with self.assertRaisesRegex(native.Blocked, 'ambiguous_native_pointer_target'):
            self.probe.tap('التالي', seek=False)
        self.probe.act.assert_not_called()

    def test_existing_semantic_ancestor_remains_preferred_to_button_pointer_fallback(self):
        container = self.node('', path='0.1', clickable=True,
                              **{'class': 'android.view.View'})
        button = self.node('التالي', path='0.1.3', clickable=False,
                           **{'class': 'android.widget.Button'})
        self.probe.nodes = Mock(return_value=[container, button])
        self.probe.act = Mock()
        self.probe.tap('التالي', seek=False)
        self.probe.act.assert_called_once_with('click', container)

    def test_auth_pointer_action_keeps_only_count_and_never_the_node_witness(self):
        row = self.node('تأكيد والدخول')
        row['witness'] = 'f' * 64
        self.probe.instrument = Mock(return_value={
            'account_action_delivered': 'true', 'native_pointer_used': 'true',
            'native_pointer_events': '2'})
        with patch.object(native.time, 'sleep'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['auth_input_operations_delivered'], 1)
        self.assertNotIn(row['witness'], (self.probe.out / 'report.json').read_text())

    def test_postauth_pointer_action_keeps_the_verified_mode_and_exact_event_count(self):
        row = self.node('التالي')
        self.probe.authenticated = True
        self.probe.instrument = Mock(return_value={
            'account_action_delivered': 'true', 'native_pointer_used': 'true',
            'native_pointer_events': '2'})
        with patch.object(native.time, 'sleep'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'][0]['delivery'], 'pointer_tap')
        self.assertEqual(self.probe.report['actions'][0]['native_pointer_events'], 2)

    def test_failed_device_command_does_not_expose_captured_output(self):
        raw = self.access['otp'] + ' arbitrary private framework exception'
        result = subprocess.CompletedProcess(['adb'], 1, raw.encode(), raw.encode())
        with patch.object(native.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(native.Blocked, '^device_command_failed$') as failure:
                self.probe.command(['adb', 'shell', 'example'])
        self.assertNotIn(raw, str(failure.exception))

    def picker_xml(self, include_done=False, package='com.android.documentsui'):
        file = '<node package="' + package + '" text="' + self.probe.photo_name + \
               '" bounds="[10,10][30,30]" enabled="true" />'
        done = '<node package="' + package + '" text="OPEN" bounds="[90,190][110,210]" enabled="true" />'
        return '<hierarchy>' + file + (done if include_done else '') + '</hierarchy>'

    def test_os_picker_selects_file_once_then_the_observed_open_action(self):
        frames = [self.picker_xml(), self.picker_xml(include_done=True)]
        taps = []
        state = {'index': 0}

        def adb(*args, **kwargs):
            if args[:2] == ('exec-out', 'cat'):
                return frames[state['index']]
            if args[:3] == ('shell', 'input', 'tap'):
                taps.append(args[3:])
                state['index'] = min(1, state['index'] + 1)
            return ''

        self.probe.adb = Mock(side_effect=adb)
        self.probe.tap = Mock()
        self.probe.wait = Mock()
        with patch.object(native.time, 'sleep'):
            self.probe.photo_picker()
        self.assertEqual(taps, [(20, 20), (100, 200)])
        self.probe.wait.assert_called_once_with('صور الإعلان (1/12)', seconds=30)

    def test_os_picker_never_clicks_a_foreign_package_file(self):
        xml = self.picker_xml(include_done=True, package='com.example.untrusted')

        def adb(*args, **kwargs):
            return xml if args[:2] == ('exec-out', 'cat') else ''

        self.probe.adb = Mock(side_effect=adb)
        self.probe.tap = Mock()
        with patch.object(native.time, 'sleep'), \
                patch.object(native.time, 'monotonic', side_effect=[0, 1, 46]):
            with self.assertRaisesRegex(native.Blocked, 'genuine_os_photo_selection'):
                self.probe.photo_picker()
        self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap')
                             for call in self.probe.adb.call_args_list))

    def fixture(self):
        fixture = Mock()
        fixture.state = {'key': '83f56a55-1ee7-4b4f-a36b-7687f2e310e9',
                         'tag': 'AQER-C1-aabbccddeeff',
                         'title': 'مسودة اختبار الواجهة AQER-C1-aabbccddeeff',
                         'creation_request_sent': True}
        fixture.last_receipt = {'status': 'PASS', 'fresh_session_cleaned': True,
                                'revoked_token_http': 401}
        fixture.has_pending_fixture = False  # Its successful mocked cleanup removes only this UUID.
        return fixture

    def verified_install_environment(self):
        apk, helper = self.private / 'target.apk', self.private / 'input.apk'
        apk.write_bytes(b'synthetic product artifact for an offline boundary test')
        helper.write_bytes(b'synthetic helper artifact for an offline boundary test')
        proof = {'source_commit': self.probe.env['GITHUB_SHA'], 'package': native.APP,
                 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                 'input_driver': {'sha256': hashlib.sha256(helper.read_bytes()).hexdigest()},
                 'version_code': 1467}
        (self.private / 'APK_VERIFICATION.json').write_text(json.dumps(proof))
        self.probe.env['ANDROID_HOME'] = '/offline-test-sdk'
        self.probe.command = Mock(side_effect=lambda args, **kwargs:
                                  'List of devices attached\nemulator-5554\tdevice\n'
                                  if args == ['adb', 'devices'] else 'KVM is installed and usable')
        package_patch = patch.object(native.subprocess, 'run',
                                     return_value=subprocess.CompletedProcess(['fixed-pm-query'], 1, b'', b''))
        self.package_query = package_patch.start()
        self.addCleanup(package_patch.stop)

    @staticmethod
    def ready_adb(*args, **kwargs):
        if args[:2] == ('shell', 'getprop'):
            return {'ro.boot.qemu': '1', 'ro.build.version.sdk': '36',
                    'sys.boot_completed': '1', 'sys.user.0.ce_available': 'true'}[args[2]]
        if args == ('shell', 'service', 'check', 'package'):
            return 'Service package: found'
        if args == ('shell', 'pidof', 'system_server'):
            return '669'
        return ''

    def test_incomplete_boot_or_CE_blocks_package_queries_and_all_installs(self):
        self.verified_install_environment()
        for key, value in [('sys.boot_completed', ''), ('sys.boot_completed', '0'),
                           ('sys.user.0.ce_available', ''), ('sys.user.0.ce_available', 'false'),
                           ('sys.user.0.ce_available', 'True')]:
            def adb(*args, **kwargs):
                return value if args == ('shell', 'getprop', key) else self.ready_adb(*args, **kwargs)
            with self.subTest(property=key, observed=value):
                self.probe.adb = Mock(side_effect=adb)
                with self.assertRaisesRegex(native.Blocked, 'native_boot_CE_not_ready'):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' or call.args[:3] == ('shell', 'pm', 'path')
                                     for call in self.probe.adb.call_args_list))
                self.package_query.assert_not_called()

    def test_unready_or_unobserved_framework_blocks_package_queries_and_all_installs(self):
        self.verified_install_environment()
        checks = [
            (('shell', 'service', 'check', 'package'), ''),
            (('shell', 'service', 'check', 'package'), 'Service package: not found'),
            (('shell', 'service', 'check', 'package'), native.Blocked('device_command_timeout')),
            (('shell', 'pidof', 'system_server'), ''),
            (('shell', 'pidof', 'system_server'), '0'),
            (('shell', 'pidof', 'system_server'), '669 invalid'),
            (('shell', 'pidof', 'system_server'), '669 669'),
            (('shell', 'pidof', 'system_server'), native.Blocked('device_command_failed')),
        ]
        for command, value in checks:
            def adb(*args, **kwargs):
                if args == command:
                    if isinstance(value, Exception):
                        raise value
                    return value
                return self.ready_adb(*args, **kwargs)
            with self.subTest(command=command[1], observation_type=type(value).__name__):
                self.probe.adb = Mock(side_effect=adb)
                with self.assertRaises(native.Blocked):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' or call.args[:3] == ('shell', 'pm', 'path')
                                     for call in self.probe.adb.call_args_list))
                self.package_query.assert_not_called()

    def test_present_unobserved_and_error_package_queries_never_allow_install(self):
        self.verified_install_environment()
        self.probe.adb = Mock(side_effect=self.ready_adb)
        observations = [
            subprocess.CompletedProcess([], 1, b'', b'cmd: package service failed'),
            subprocess.CompletedProcess([], 1, b'', b'\n'),
            subprocess.CompletedProcess([], 1, b'unexpected response', b''),
            subprocess.CompletedProcess([], 0, b'', b''),
            subprocess.CompletedProcess([], 20, b'', b''),
            subprocess.CompletedProcess([], 0, b'package:/data/app/base.apk\n', b''),
            subprocess.TimeoutExpired(['fixed-pm-query'], 20),
            OSError('synthetic unobserved transport'),
        ]
        for observation in observations:
            self.probe.adb.reset_mock()
            self.package_query.reset_mock()
            self.package_query.side_effect = observation if isinstance(observation, Exception) else None
            self.package_query.return_value = observation
            with self.subTest(observation_type=type(observation).__name__):
                with self.assertRaises(native.Blocked):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' for call in self.probe.adb.call_args_list))
                self.package_query.assert_called_once_with(
                    ['adb', '-s', 'emulator-5554', 'shell', 'pm', 'path', native.APP],
                    capture_output=True, timeout=20)

    def test_absent_package_still_requires_fresh_healthy_framework_after_query(self):
        self.verified_install_environment()
        def adb(*args, **kwargs):
            if self.package_query.called and args == ('shell', 'service', 'check', 'package'):
                return 'Service package: not found'
            return self.ready_adb(*args, **kwargs)
        self.probe.adb = Mock(side_effect=adb)
        with self.assertRaisesRegex(native.Blocked, 'native_package_service_not_ready'):
            self.probe.validate_and_install()
        self.package_query.assert_called_once()
        self.assertFalse(any(call.args[0] == 'install' for call in self.probe.adb.call_args_list))

    def test_healthy_runtime_allows_only_verified_product_and_helper_installs(self):
        self.verified_install_environment()
        self.probe.adb = Mock(side_effect=self.ready_adb)
        self.probe.validate_and_install()
        installs = [call.args for call in self.probe.adb.call_args_list if call.args[0] == 'install']
        self.assertEqual(installs, [('install', '--no-streaming', self.private / 'target.apk'),
                                    ('install', '--no-streaming', '-t', self.private / 'input.apk')])
        self.assertEqual(self.probe.report['android_api'], 36)
        self.assertFalse(self.probe.report['native_auth_attempted'])

    def test_runtime_failure_after_product_install_blocks_helper_install(self):
        self.verified_install_environment()
        installed = []
        def adb(*args, **kwargs):
            if args[0] == 'install':
                installed.append(args)
            if installed and args == ('shell', 'service', 'check', 'package'):
                return 'Service package: not found'
            return self.ready_adb(*args, **kwargs)
        self.probe.adb = Mock(side_effect=adb)
        with self.assertRaisesRegex(native.Blocked, 'native_package_service_not_ready'):
            self.probe.validate_and_install()
        self.assertEqual(installed, [('install', '--no-streaming', self.private / 'target.apk')])

    def test_unhealthy_runtime_blocks_API_fixture_before_construction_or_authentication(self):
        for command in [('shell', 'service', 'check', 'package'), ('shell', 'pidof', 'system_server')]:
            def adb(*args, **kwargs):
                return '' if args == command else self.ready_adb(*args, **kwargs)
            self.probe.adb = Mock(side_effect=adb)
            with self.subTest(command=command[1]), patch.object(native, 'FixtureApi') as factory:
                with self.assertRaises(native.Blocked):
                    self.probe.bootstrap_fixture()
                factory.assert_not_called()
                self.assertIsNone(self.probe.fixture_api)
                self.assertFalse(self.probe.fixture_possible)
                self.assertFalse(self.probe.report['native_auth_attempted'])

    def test_bootstrap_receipt_distinguishes_api_setup_from_native_creation(self):
        fixture = self.fixture()
        self.probe.require_preauth_runtime = Mock()
        with patch.object(native, 'FixtureApi', return_value=fixture) as factory:
            self.probe.bootstrap_fixture()
        fixture.bootstrap.assert_called_once_with()
        factory.assert_called_once_with(self.access['phones']['broker'],
                                        self.access['otp'], '9')
        self.assertTrue(self.probe.fixture_possible)
        self.assertEqual(self.probe.bootstrap_title, fixture.state['title'])
        self.assertIn(fixture.state['tag'], self.probe.title)
        row = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-api-empty-fixture')
        self.assertEqual(row['status'], 'PASS')
        self.assertFalse(row['native_creation_claim'])
        self.assertFalse(row['facts_entered'])
        self.assertFalse(row['photos_uploaded'])
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_native_entry_refuses_unknown_or_foreign_fixture_before_any_ui_action(self):
        self.probe.tap = Mock()
        self.probe.fixture_api = self.fixture()
        for title in ['', 'protected old draft', None]:
            with self.subTest(title=title):
                with self.assertRaisesRegex(native.Blocked, 'known_new_fixture'):
                    self.probe.manual_entry(title)
        self.probe.tap.assert_not_called()

    def test_saved_fixture_entry_ignores_default_old_recovery_and_opens_exact_own_title(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        title = fixture.state['title']
        self.probe.tap = Mock()
        self.probe.has = Mock(return_value=False)
        self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل'),
                                             self.node('protected preexisting draft')])
        self.probe.wait = Mock()
        own = self.node(title)
        self.probe.seek = Mock(return_value=([own], [own]))
        self.probe.manual_entry(title)
        self.assertEqual([c.args[0] for c in self.probe.tap.call_args_list],
                         ['إضافة عقار', 'مسوداتي', title])
        self.probe.seek.assert_called_once_with(title)
        self.assertNotIn('متابعة الإعلان', [c.args[0] for c in self.probe.tap.call_args_list])
        self.assertNotIn('بدء إعلان جديد', [c.args[0] for c in self.probe.tap.call_args_list])

    def test_saved_fixture_entry_refuses_missing_or_duplicate_owned_title(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        title = fixture.state['title']
        for matches in [[], [self.node(title), self.node(title, path='0.2')]]:
            self.probe.tap = Mock()
            self.probe.has = Mock(return_value=False)
            self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل')])
            self.probe.wait = Mock()
            self.probe.seek = Mock(return_value=(matches, matches))
            with self.subTest(matches=len(matches)):
                with self.assertRaisesRegex(native.Blocked, 'unique_owned_saved_fixture'):
                    self.probe.manual_entry(title)
            self.assertEqual([c.args[0] for c in self.probe.tap.call_args_list],
                             ['إضافة عقار', 'مسوداتي'])

    def test_network_prerequisite_prevents_api_bootstrap_or_login_when_blocked(self):
        self.probe.validate_and_install = Mock()
        self.probe.startup = Mock()
        self.probe.public_network_readiness = Mock(side_effect=native.Blocked('mock_network_unready'))
        self.probe.bootstrap_fixture = Mock()
        self.probe.login = Mock()
        self.probe.cleanup = Mock()
        self.probe.record_stop = Mock()
        self.assertFalse(self.probe.execute())
        self.probe.bootstrap_fixture.assert_not_called()
        self.probe.login.assert_not_called()
        self.probe.cleanup.assert_not_called()
        network = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-native-network')
        self.assertEqual(network['status'], 'BLOCKED')
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_execute_orders_real_network_then_api_setup_logout_then_native_login(self):
        order = []
        fixture = self.fixture()
        fixture.bootstrap.side_effect = lambda: order.extend(['api-bootstrap', 'api-logout-401'])
        self.probe.require_preauth_runtime = Mock(side_effect=lambda: order.append('fresh-framework'))
        self.probe.validate_and_install = Mock(side_effect=lambda: order.append('install'))
        self.probe.startup = Mock(side_effect=lambda: order.append('startup'))
        self.probe.public_network_readiness = Mock(side_effect=lambda: order.append('public-app-network'))
        self.probe.login = Mock(side_effect=lambda: order.append('native-login'))
        self.probe.create_and_save = Mock(side_effect=lambda: order.append('native-edit-save'))
        self.probe.restore = Mock(side_effect=lambda: order.append('native-restore'))
        self.probe.cleanup = Mock(side_effect=lambda: order.append('cleanup'))
        self.probe.record_stop = Mock()
        with patch.object(native, 'FixtureApi', return_value=fixture):
            self.assertFalse(self.probe.execute())  # Mocked UI does not earn native PASS.
        self.assertEqual(order, ['install', 'startup', 'public-app-network', 'fresh-framework', 'api-bootstrap',
                                 'api-logout-401', 'native-login', 'native-edit-save',
                                 'native-restore', 'cleanup'])
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_api_cleanup_runs_after_partial_setup_even_without_native_authentication(self):
        fixture = self.fixture()
        fixture.bootstrap.side_effect = native.FixtureError('mock_setup_reply_lost')
        fixture.last_receipt = {'status': 'BLOCKED', 'fresh_session_cleaned': True}
        self.probe.validate_and_install = Mock()
        self.probe.startup = Mock()
        self.probe.public_network_readiness = Mock()
        self.probe.require_preauth_runtime = Mock()
        self.probe.login = Mock()
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock()
        self.probe.adb = Mock(return_value='')
        with patch.object(native, 'FixtureApi', return_value=fixture):
            self.assertFalse(self.probe.execute())
        self.probe.login.assert_not_called()
        self.probe.native_logout.assert_not_called()
        fixture.cleanup.assert_called_once_with()
        self.assertFalse(self.probe.fixture_possible)
        self.assertFalse(self.probe.report['native_auth_executed'])
        self.assertFalse(self.probe.report['session_may_remain'])

    def test_native_logout_failure_does_not_skip_known_uuid_api_cleanup(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock(side_effect=native.Blocked('mock_logout_unavailable'))
        self.probe.adb = Mock(return_value='')
        self.probe.tap = Mock()
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        fixture.cleanup.assert_called_once_with()
        self.probe.adb.assert_called_once_with('shell', 'am', 'force-stop', native.APP)
        self.probe.tap.assert_not_called()  # No native delete or unrelated recovery action.
        self.assertFalse(self.probe.fixture_possible)
        self.assertEqual(self.probe.report['api_cleanup'], fixture.last_receipt)

    def test_cleanup_orders_native_logout_writer_stop_and_only_known_api_fixture(self):
        order = []
        fixture = self.fixture()
        fixture.cleanup.side_effect = lambda: order.append('own-api-cleanup')
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock(side_effect=lambda: order.append('native-logout'))
        self.probe.adb = Mock(side_effect=lambda *a, **k: order.append('native-writer-stop'))
        self.probe.tap = Mock()
        self.probe.cleanup()
        self.assertEqual(order, ['native-logout', 'native-writer-stop', 'own-api-cleanup'])
        self.probe.tap.assert_not_called()
        fixture.cleanup.assert_called_once_with()
        self.assertFalse(self.probe.fixture_possible)

    def test_api_cleanup_failure_preserves_pending_fixture_and_receipt(self):
        fixture = self.fixture()
        fixture.cleanup.side_effect = native.FixtureError('mock_protected_baseline_inconclusive')
        fixture.last_receipt = {'status': 'BLOCKED', 'fresh_session_cleaned': True}
        fixture.has_pending_fixture = True
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock()
        self.probe.adb = Mock(return_value='')
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        self.probe.native_logout.assert_not_called()
        self.assertTrue(self.probe.fixture_possible)
        self.assertEqual(self.probe.report['api_cleanup'], fixture.last_receipt)
        case = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-cleanup')
        self.assertNotEqual(case['status'], 'PASS')


class AccountDeliverySafetyTest(unittest.TestCase):
    def test_only_complete_semantic_and_native_pointer_receipts_are_accepted(self):
        fixtures = [
            ('click', {'semantic_action_used': 'true'}, 'semantic_action', 0),
            ('scroll', {'semantic_action_used': 'true'}, 'semantic_action', 0),
            ('set', {'set_text_delivered': 'true'}, 'semantic_text', 0),
            ('click', {'native_pointer_used': 'true', 'native_pointer_events': '2'},
             'pointer_tap', 2),
            ('scroll', {'native_pointer_used': 'true', 'native_pointer_events': '14'},
             'pointer_swipe', 14),
            ('set', {'set_text_delivered': 'true', 'native_pointer_used': 'true',
                     'native_pointer_events': '2'}, 'pointer_focus', 2),
        ]
        for kind, fields, mode, events in fixtures:
            with self.subTest(kind=kind, mode=mode):
                result = native.account_delivery({'account_action_delivered': 'true', **fields}, kind)
                self.assertEqual(result, {'delivery': mode, 'native_pointer_events': events})

    def test_pointer_attempt_without_exact_complete_event_count_is_refused(self):
        for kind in ['click', 'scroll', 'set']:
            right = '14' if kind == 'scroll' else '2'
            for count in [None, '', '0', '1', '3', '02', right + '.0', int(right)]:
                fields = {'account_action_delivered': 'true', 'native_pointer_used': 'true',
                          'set_text_delivered': 'true'}
                if count is not None:
                    fields['native_pointer_events'] = count
                with self.subTest(kind=kind, count=count):
                    with self.assertRaisesRegex(native.Blocked, 'native_pointer_event_count_mismatch'):
                        native.account_delivery(fields, kind)

    def test_semantic_and_pointer_modes_cannot_both_claim_the_same_delivery(self):
        fields = {'account_action_delivered': 'true', 'semantic_action_used': 'true',
                  'native_pointer_used': 'true', 'native_pointer_events': '2',
                  'set_text_delivered': 'true'}
        for kind in ['click', 'scroll', 'set']:
            with self.subTest(kind=kind):
                with self.assertRaisesRegex(native.Blocked, 'native_delivery_receipt_ambiguous'):
                    native.account_delivery(fields, kind)

    def test_missing_delivery_or_invalid_boolean_flags_are_refused(self):
        for kind in ['click', 'scroll']:
            with self.subTest(kind=kind):
                with self.assertRaisesRegex(native.Blocked, 'native_delivery_mode_missing'):
                    native.account_delivery({'account_action_delivered': 'true'}, kind)
        for flag in ['native_pointer_used', 'semantic_action_used']:
            for value in [True, 1, 'yes', 'TRUE', '1', None]:
                with self.subTest(flag=flag, value=value):
                    with self.assertRaisesRegex(native.Blocked, 'native_delivery_receipt_invalid'):
                        native.account_delivery({'account_action_delivered': 'true', flag: value}, 'click')

    def test_semantic_receipt_cannot_include_unclaimed_pointer_events(self):
        for count in ['0', '2', 0]:
            with self.subTest(count=count):
                with self.assertRaisesRegex(native.Blocked, 'unexpected_native_pointer_events'):
                    native.account_delivery({'account_action_delivered': 'true',
                                             'semantic_action_used': 'true',
                                             'native_pointer_events': count}, 'click')

    def test_set_requires_confirmed_text_delivery_even_when_focus_pointer_succeeded(self):
        for fields in [{}, {'native_pointer_used': 'true', 'native_pointer_events': '2'}]:
            with self.subTest(fields=fields):
                with self.assertRaisesRegex(native.Blocked, 'native_set_text_not_delivered'):
                    native.account_delivery({'account_action_delivered': 'true', **fields}, 'set')

    def test_no_receipt_bypasses_failed_delivery_or_unsupported_action_kind(self):
        with self.assertRaisesRegex(native.Blocked, 'native_action_not_delivered'):
            native.account_delivery({'semantic_action_used': 'true'}, 'click')
        with self.assertRaisesRegex(native.Blocked, 'native_action_kind_invalid'):
            native.account_delivery({'account_action_delivered': 'true'}, 'shell')


if __name__ == '__main__':
    unittest.main()
