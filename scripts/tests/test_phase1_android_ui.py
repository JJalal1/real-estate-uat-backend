import copy
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

SPEC = importlib.util.spec_from_file_location('phase1_ui', Path(__file__).parents[1] / 'probe_phase1_android_ui.py')
ui = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ui)
SOURCE, CERT, VERSION = 'a' * 40, 'b' * 64, 1449


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def png(raw=b'\x00\x11\x22\x33'):
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def observation():
    return {'package': ui.PACKAGE, 'version_code': VERSION, 'flutter_view': True,
            'nonuniform_frame': True, 'semantic_keys': ['marketplace', 'account'], 'width': 1, 'height': 1}


def instrument_output(seen=None):
    return 'INSTRUMENTATION_STATUS: aqer_ui_smoke=' + json.dumps(seen or observation()) + '\nOK (1 test)\n'


class FakeAndroid:
    """Process boundary fixture; never launches adb or claims Android execution."""
    def __init__(self):
        self.calls = []
        self.output = instrument_output()
        self.image = png()
        self.device = 'emulator-5554\tdevice'
        self.fail_ipv6 = False
        self.preinstalled = False
        self.fail_cleanup = False
        self.bad_signer = False

    def __call__(self, argv, binary=False, timeout=120):
        self.calls.append(argv)
        code, out = 0, ''
        if argv[-1] == '-accel-check': out = 'KVM is installed and usable'
        elif 'verify' in argv: out = 'Signer #1 certificate SHA-256 digest: ' + ('c' * 64 if self.bad_signer else CERT)
        elif 'badging' in argv:
            package = ui.TEST_PACKAGE if str(argv[-1]).endswith('tests.apk') else ui.PACKAGE
            out = f"package: name='{package}' versionCode='{VERSION}'\n"
        elif argv == ['adb', 'devices']: out = 'List of devices attached\n' + self.device + '\n'
        else:
            args = argv[3:]
            if args[:2] == ['shell', 'getprop']:
                out = {'ro.build.version.sdk': '36', 'sys.boot_completed': '1', 'ro.boot.qemu': '1'}[args[2]]
            elif args == ['shell', 'id', '-u']: out = '0'
            elif args[:3] == ['shell', 'pm', 'path']:
                code, out = (0, 'package:/data/app/old.apk') if self.preinstalled else (1, '')
            elif '-C' in args: code = 1
            elif self.fail_ipv6 and args[:3] == ['shell', 'ip6tables', '-I']: code = 2
            elif args[:3] == ['shell', 'am', 'instrument']: out = self.output
            elif args[:2] == ['exec-out', 'cat']: out = self.image
            elif self.fail_cleanup and args[0] == 'uninstall': code = 1
        return subprocess.CompletedProcess(argv, code, out, '')


class ReleaseStartupSafetyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'dist').mkdir()
        (self.root / 'android-push-tests').mkdir()
        (self.root / 'sdk/build-tools/36.0.0').mkdir(parents=True)
        (self.root / 'sdk/build-tools/36.0.0/apksigner').touch()
        self.apk = b'synthetic APK process-boundary fixture'
        (self.root / 'dist/real-estate-broker-uat-449.apk').write_bytes(self.apk)
        (self.root / 'android-push-tests/tests.apk').write_bytes(b'synthetic test package')
        self.proof = {'source_commit': SOURCE, 'package': ui.PACKAGE, 'api': ui.API,
                      'version_code': VERSION, 'package_role': 'current-uat', 'zip_crc': 'passed',
                      'apksigner': 'passed', 'native_16kb_elf': 'passed', 'zipalign_16kb': 'passed',
                      'bytes': len(self.apk), 'sha256': ui.hashlib.sha256(self.apk).hexdigest(),
                      'certificate_sha256': CERT}
        self.save_proof()
        self.env = {'GITHUB_ACTIONS': 'true', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                    'AQER_ANDROID_UI_SMOKE': 'true', 'SOURCE_COMMIT': SOURCE,
                    'GITHUB_SHA': SOURCE, 'GITHUB_RUN_NUMBER': '449', 'ANDROID_HOME': str(self.root / 'sdk')}
        self.android = FakeAndroid()

    def save_proof(self):
        (self.root / 'dist/APK_VERIFICATION.json').write_text(json.dumps(self.proof))

    def run_probe(self):
        return ui.probe(self.root, self.env, self.android)

    def test_manual_opt_in_is_required_before_any_command(self):
        for key, value in [('AQER_ANDROID_UI_SMOKE', 'false'), ('GITHUB_EVENT_NAME', 'push'), ('GITHUB_ACTIONS', 'false')]:
            with self.subTest(key=key), patch.dict(self.env, {key: value}):
                with self.assertRaisesRegex(ui.GateError, 'manual_opt_in_required'): self.run_probe()
        self.assertEqual([], self.android.calls)

    def test_wrong_source_predecessor_and_endpoint_never_reach_android(self):
        for key, value in [('source_commit', 'c' * 40), ('package_role', 'upgrade-predecessor-same-source'),
                           ('api', 'http://10.0.2.2/api'), ('version_code', VERSION - 1)]:
            wrong = copy.deepcopy(self.proof); wrong[key] = value
            with self.subTest(key=key), self.assertRaises(ui.GateError):
                ui.validate_proof(wrong, self.apk, SOURCE, 449)
        self.assertEqual([], self.android.calls)

    def test_changed_apk_bytes_stop_before_adb(self):
        (self.root / 'dist/real-estate-broker-uat-449.apk').write_bytes(b'changed')
        with self.assertRaisesRegex(ui.GateError, 'apk_bytes'): self.run_probe()
        self.assertEqual([], self.android.calls)

    def test_debug_apk_is_not_release_acceptance(self):
        with self.assertRaisesRegex(ui.GateError, 'debug_apk'):
            ui.validate_badging(f"package: name='{ui.PACKAGE}' versionCode='{VERSION}'\napplication-debuggable\n",
                                ui.PACKAGE, VERSION, release=True)

    def test_mismatched_certificate_stops_before_adb(self):
        self.android.bad_signer = True
        with self.assertRaisesRegex(ui.GateError, 'signers'): self.run_probe()
        self.assertFalse(any(c[0] == 'adb' for c in self.android.calls))

    def test_physical_device_is_not_selected(self):
        self.android.device = 'owner-phone\tdevice'
        with self.assertRaisesRegex(ui.GateError, 'one_ready_emulator'): self.run_probe()
        self.assertFalse(any(c[:2] == ['adb', '-s'] for c in self.android.calls))

    def test_preexisting_installation_is_not_erased(self):
        self.android.preinstalled = True
        with self.assertRaisesRegex(ui.GateError, 'fresh_install'): self.run_probe()
        self.assertFalse(any('uninstall' in c or 'install' in c for c in self.android.calls))

    def test_ipv6_block_failure_restores_ipv4_before_install(self):
        self.android.fail_ipv6 = True
        with self.assertRaises(ui.GateError): self.run_probe()
        self.assertIn(['adb', '-s', 'emulator-5554', 'shell', 'iptables', '-D', 'OUTPUT', '-j', 'REJECT'], self.android.calls)
        self.assertFalse(any('install' in c for c in self.android.calls))

    def test_zero_exit_instrumentation_failure_is_not_success_and_cleans_up(self):
        self.android.output = 'FAILURES!!!\nINSTRUMENTATION_FAILED\n'
        with self.assertRaisesRegex(ui.GateError, 'ui_instrumentation_failed'): self.run_probe()
        self.assertEqual(2, sum('uninstall' in c for c in self.android.calls))
        self.assertEqual(2, sum('-D' in c for c in self.android.calls))

    def test_non_flutter_or_missing_semantics_cannot_pass(self):
        for key, value in [('flutter_view', False), ('nonuniform_frame', False), ('semantic_keys', ['account'])]:
            seen = observation(); seen[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ui.GateError, 'flutter_ui_not_observed'):
                ui.validate_instrumentation(instrument_output(seen), VERSION)

    def test_native_semantic_producer_consumer_and_host_receipt_agree(self):
        java = (Path(__file__).resolve().parents[2] / 'mobile_app/android/app/src/androidTest/java/'
                'com/example/real_estate_mobile/Phase1UiStartupTest.java').read_text()
        produced = set(re.findall(r'found\.add\("([a-z_]+)"\)', java))
        consumed = set(re.findall(r'keys\.contains\("([a-z_]+)"\)', java))
        receipt_line = next(line for line in java.splitlines() if '.put("semantic_keys",' in line)
        reported = re.findall(r'\.put\("([a-z_]+)"\)', receipt_line)
        self.assertTrue(produced)
        self.assertEqual(produced, consumed)
        self.assertEqual(produced, set(reported))
        seen = observation(); seen['semantic_keys'] = reported
        ui.validate_instrumentation(instrument_output(seen), VERSION)

    def test_truncated_png_and_bad_crc_and_wrong_scanlines_are_rejected(self):
        valid = png()
        for damaged in [valid[:-12], valid[:40] + bytes([valid[40] ^ 1]) + valid[41:], png(b'\x00')]:
            with self.subTest(size=len(damaged)), self.assertRaises(ui.GateError): ui.validate_png(damaged)
        self.assertEqual((1, 1), tuple(ui.validate_png(valid)[k] for k in ['width', 'height']))

    def test_bad_screenshot_still_uninstalls_packages_and_restores_network(self):
        self.android.image = png()[:-12]
        with self.assertRaises(ui.GateError): self.run_probe()
        self.assertEqual(2, sum('uninstall' in c for c in self.android.calls))
        self.assertEqual(2, sum('-D' in c for c in self.android.calls))

    def test_cleanup_failure_prevents_passing_result(self):
        self.android.fail_cleanup = True
        with self.assertRaisesRegex(ui.GateError, 'cleanup_failed'): self.run_probe()

    def test_success_is_explicitly_offline_and_reports_only_allowlisted_ui_keys(self):
        seen = observation(); seen['accessibility_tree'] = 'PRIVATE_SENTINEL'
        self.android.output = instrument_output(seen)
        report, image = self.run_probe()
        self.assertEqual('isolated-offline-release-startup', report['scope'])
        self.assertTrue(report['ipv4_ipv6_egress_rejected'])
        self.assertEqual(['marketplace', 'account'], report['semantic_keys'])
        self.assertEqual(png(), image)
        self.assertNotIn('accessibility_tree', report)
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(report))
        self.assertEqual(2, sum('uninstall' in c for c in self.android.calls))
        self.assertEqual(2, sum('-D' in c for c in self.android.calls))

    def test_export_contains_no_apk_or_raw_instrumentation_output(self):
        marker = self.root / 'github-output'
        with patch.object(ui, 'ROOT', self.root), patch.dict(os.environ, {**self.env, 'GITHUB_OUTPUT': str(marker)}), \
                patch.object(ui, 'probe', return_value=({'status': 'passed'}, png())), redirect_stdout(io.StringIO()):
            self.assertEqual(0, ui.main())
        self.assertEqual({'startup.png', 'report.json'}, {p.name for p in (self.root / 'android-ui-evidence').iterdir()})
        self.assertEqual('phase1_ui_evidence=true\n', marker.read_text())

    def test_off_does_not_create_artifacts(self):
        with patch.object(ui, 'ROOT', self.root), patch.dict(os.environ, {'AQER_ANDROID_UI_SMOKE': 'false'}), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(2, ui.main())
        self.assertFalse((self.root / 'android-ui-evidence').exists())

    def test_stale_directory_is_not_exported(self):
        marker = self.root / 'github-output'
        (self.root / 'android-ui-evidence').mkdir()
        with patch.object(ui, 'ROOT', self.root), patch.dict(os.environ, {**self.env, 'GITHUB_OUTPUT': str(marker)}), \
                self.assertRaises(FileExistsError):
            ui.main()
        self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
