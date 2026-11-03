"""Safety/control-flow tests only; no device, network or real account access."""
import base64
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

    def test_bootstrap_receipt_distinguishes_api_setup_from_native_creation(self):
        fixture = self.fixture()
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
        self.assertEqual(order, ['install', 'startup', 'public-app-network', 'api-bootstrap',
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
