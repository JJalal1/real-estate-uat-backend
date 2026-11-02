"""Safety boundaries only. FakeAndroid never proves actual UI/HTTP journeys."""
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from contextlib import redirect_stdout
from unittest.mock import MagicMock, patch
import xml.etree.ElementTree as ET

import test_phase1_android_ui as shared

ui, SOURCE = shared.ui, shared.SOURCE

SPEC = importlib.util.spec_from_file_location('phase1_guest', Path(__file__).parents[1] / 'probe_phase1_uat_guest.py')
guest = importlib.util.module_from_spec(SPEC)
with patch.dict('sys.modules', {'probe_phase1_android_ui': ui}):
    SPEC.loader.exec_module(guest)


class GuestProbeSafetyTest(unittest.TestCase):
    def setUp(self):
        # Reuse only the explicitly synthetic process-boundary fixture setup.
        fixture = shared.ReleaseStartupSafetyTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.root, self.env, self.android = fixture.root, fixture.env, fixture.android

    def probe(self):
        return guest.GuestProbe(self.root, self.env, self.android)

    def test_no_opt_in_means_no_commands_or_output_directory(self):
        self.env['AQER_ANDROID_UI_SMOKE'] = 'false'
        with self.assertRaisesRegex(ui.GateError, 'manual_opt_in_required'):
            self.probe()
        self.assertEqual([], self.android.calls)
        self.assertFalse((self.root / 'android-uat-guest-evidence').exists())

    def test_wrong_source_and_modified_apk_fail_before_android(self):
        self.env['GITHUB_SHA'] = 'c' * 40
        with self.assertRaisesRegex(ui.GateError, 'invalid_source_or_run'):
            self.probe().validate_environment()
        self.env['GITHUB_SHA'] = SOURCE
        (self.root / 'dist/real-estate-broker-uat-449.apk').write_bytes(b'changed')
        with self.assertRaisesRegex(ui.GateError, 'apk_bytes'):
            self.probe().validate_environment()
        self.assertEqual([], self.android.calls)

    def test_physical_device_and_preexisting_accounts_are_refused(self):
        self.android.device = 'owner-phone\tdevice'
        with self.assertRaisesRegex(ui.GateError, 'one_ready_emulator'):
            self.probe().validate_environment()
        self.android.device = 'emulator-5554\tdevice'
        self.android.preinstalled = True
        with self.assertRaisesRegex(ui.GateError, 'fresh_guest_install'):
            self.probe().validate_environment()
        self.assertFalse(any('install' in c or 'uninstall' in c for c in self.android.calls))

    def test_proof_is_retained_only_after_all_environment_guards(self):
        probe = self.probe()
        probe.validate_environment()
        self.assertEqual('emulator-5554', probe.report['serial'])
        self.assertEqual(1449, probe.report['version_code'])
        self.assertFalse(probe.out.exists())

    def test_blocked_network_cannot_be_misreported_as_live_uat(self):
        original = self.android
        def blocked(argv, **kwargs):
            result = original(argv, **kwargs)
            if '-C' in argv:
                result.returncode = 0
            return result
        with self.assertRaisesRegex(ui.GateError, 'guest_network_not_restored'):
            guest.GuestProbe(self.root, self.env, blocked).validate_environment()
        self.assertFalse(any('install' in c for c in self.android.calls))

    def test_host_overrides_and_reverse_proxies_cannot_pass(self):
        for fail_at, output in [('hosts', '127.0.0.1 real-estate-uat-api-frankfurt.onrender.com'),
                                ('reverse', 'emulator-5554 tcp:443 tcp:443')]:
            original = self.android
            def intercepted(argv, **kwargs):
                result = original(argv, **kwargs)
                if (fail_at == 'hosts' and argv[-1] == '/etc/hosts') or (fail_at == 'reverse' and '--list' in argv):
                    result.stdout = output
                return result
            with self.subTest(fail_at=fail_at), self.assertRaises(ui.GateError):
                guest.GuestProbe(self.root, self.env, intercepted).validate_environment()
        self.assertFalse(any('install' in c for c in self.android.calls))

    def test_foreign_nodes_hidden_bounds_and_partial_labels_are_not_tapped(self):
        probe = self.probe()
        nodes = [ET.Element('node', {'package': 'other.app', 'text': 'حسابي', 'bounds': '[0,0][30,30]'}),
                 ET.Element('node', {'package': ui.PACKAGE, 'text': 'حسابي', 'bounds': '[0,0][0,0]'}),
                 ET.Element('node', {'package': ui.PACKAGE, 'text': 'حسابي الخاص', 'bounds': '[0,0][30,30]'})]
        self.assertEqual([], probe.matches(nodes, 'حسابي'))

    def test_merged_semantic_line_keeps_exact_control_label_and_rejects_substrings(self):
        probe = self.probe()
        node = ET.Element('node', {'package': ui.PACKAGE, 'content-desc': 'تكبير الصور\n١ من ٣',
                                  'bounds': '[10,10][100,100]'})
        self.assertEqual([node], probe.matches([node], 'تكبير الصور'))
        self.assertEqual([], probe.matches([node], 'تكبير'))

    def test_home_coordinate_fallback_requires_a_fresh_known_size_and_all_home_witnesses(self):
        for size, labels in [((1, 1), ['ماذا تبحث عنه؟', 'العقارات', 'حسابي']),
                             ((1080, 1920), ['العقارات', 'حسابي']),
                             ((1080, 1920), ['ماذا تبحث عنه؟', 'حسابي'])]:
            probe = self.probe()
            nodes = [ET.Element('node', {'package': ui.PACKAGE, 'text': label,
                                         'bounds': '[10,10][30,30]'}) for label in labels]
            def frame(name):
                probe.report['frames'].append({'width': size[0], 'height': size[1]})
                return name + '.png'
            with patch.object(probe, 'has', return_value=False), patch.object(probe, 'frame', side_effect=frame), \
                    patch.object(probe, 'nodes', return_value=nodes), patch.object(probe, 'adb') as adb:
                with self.subTest(size=size, labels=labels), self.assertRaisesRegex(guest.Blocked, 'precondition_failed'):
                    probe.home_entry('map')
                adb.assert_not_called()
        probe = self.probe()
        with patch.object(probe, 'has', return_value=False), \
                patch.object(probe, 'frame', side_effect=ui.GateError('capture_failed')), patch.object(probe, 'adb') as adb:
            with self.assertRaises(ui.GateError):
                probe.home_entry('search')
            adb.assert_not_called()

    def test_search_input_requires_unique_enabled_app_field_and_search_route(self):
        probe = self.probe()
        header = ET.Element('node', {'package': ui.PACKAGE, 'text': 'البحث عن عقار', 'bounds': '[10,10][30,30]'})
        field = ET.Element('node', {'package': ui.PACKAGE, 'class': 'android.widget.EditText',
                                   'enabled': 'true', 'bounds': '[10,40][300,100]'})
        for nodes in [[field], [header], [header, field, field],
                      [header, ET.Element('node', {**field.attrib, 'package': 'other.app'})]]:
            with patch.object(probe, 'nodes', return_value=nodes), patch.object(probe, 'adb') as adb:
                with self.subTest(nodes=len(nodes)), self.assertRaises(guest.Blocked):
                    probe.search_input()
                adb.assert_not_called()

    def test_public_http_allowlist_has_no_login_or_write_operation(self):
        with patch.object(guest.urllib.request, 'build_opener') as opening:
            for path in ['/api/auth/whatsapp/start', '/api/auth/me', '//other.example/api/health', '/api/properties/61']:
                with self.subTest(path=path), self.assertRaisesRegex(ui.GateError, 'not_allowlisted'):
                    guest.get_public(path)
            opening.assert_not_called()

    def test_http_receipt_keeps_real_status_and_excludes_response_content(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 401
        response.geturl.return_value = guest.ORIGIN + '/api/listing-editor-drafts'
        response.read.return_value = b'{"message":"PRIVATE_SENTINEL"}'
        opening = MagicMock()
        opening.open.return_value = response
        with patch.object(guest.urllib.request, 'build_opener', return_value=opening):
            receipt, data = guest.get_public('/api/listing-editor-drafts')
        self.assertEqual(401, receipt['http_status'])
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(receipt))
        self.assertEqual('PRIVATE_SENTINEL', data['message'])
        self.assertNotIn('Authorization', opening.open.call_args.args[0].headers)

    def test_redirect_is_refused_before_any_second_request(self):
        opening = MagicMock()
        opening.open.side_effect = guest.urllib.error.HTTPError(
            guest.ORIGIN + '/api/health', 302, 'redirect', {'Location': 'https://other.example/private'}, None)
        with patch.object(guest.urllib.request, 'build_opener', return_value=opening) as builder:
            with self.assertRaisesRegex(ui.GateError, 'redirect_refused'):
                guest.get_public('/api/health')
        self.assertIsInstance(builder.call_args.args[0], guest.NoRedirect)
        self.assertEqual(1, opening.open.call_count)
        self.assertIsNone(guest.NoRedirect().redirect_request(None, None, 302, 'redirect', {}, 'https://other.example'))

    def test_stale_evidence_directory_is_not_overwritten(self):
        output = self.root / 'android-uat-guest-evidence'
        output.mkdir()
        (output / 'report.json').write_text('STALE_SENTINEL')
        with patch.object(guest, 'ROOT', self.root), patch.dict(os.environ, self.env), \
                patch.object(guest.GuestProbe, 'validate_environment'), redirect_stdout(io.StringIO()):
            self.assertEqual(1, guest.main())
        self.assertEqual('STALE_SENTINEL', (output / 'report.json').read_text())

    def test_installation_is_removed_after_an_unexpected_collection_failure(self):
        probe = self.probe()
        def public(path):
            status = 401 if path.startswith(('/api/listing-editor-drafts', '/api/admin/')) else 200
            return {'http_status': status}, {'database': True, 'data': {
                'id': guest.FIXTURE_ID, 'title': guest.FIXTURE_TITLE, 'status': 'published'}}
        with patch.object(guest, 'get_public', side_effect=public), \
                patch.object(probe, 'case', side_effect=ui.GateError('collection_failed')):
            with self.assertRaisesRegex(ui.GateError, 'collection_failed'):
                probe.execute()
        self.assertTrue(probe.report['cleanup_passed'])
        self.assertIn(['adb', '-s', 'emulator-5554', 'uninstall', ui.PACKAGE], self.android.calls)
        self.assertFalse(any('iptables' in c and '-I' in c for c in self.android.calls))

    def test_home_card_title_alone_cannot_pass_the_details_journey(self):
        probe = self.probe()
        probe.live_fixture = True
        with patch.object(probe, 'adb'), \
                patch.object(probe, 'has', side_effect=lambda label: label == guest.FIXTURE_TITLE), \
                patch.object(guest.time, 'monotonic', side_effect=[0, 0, 21]), \
                patch.object(guest.time, 'sleep'):
            with self.assertRaisesRegex(guest.Blocked, 'details_not_observed'):
                probe.details()


if __name__ == '__main__':
    unittest.main()
