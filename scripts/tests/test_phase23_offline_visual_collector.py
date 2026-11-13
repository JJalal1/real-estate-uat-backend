"""Collector boundary tests: synthetic target binding, input and sealed export."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import struct
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_phase23_offline_visual as collector
from phase23_preflight import GateError


def event(case=0, **changes):
    surface, role, state, dark, scale = collector.CASES[case]
    value = dict(event='ready', case=case, surface=surface, role=role,
                 state=state, dark=dark, textScale=scale, requests=1, failures=0)
    value.update(changes)
    return value


def log(case=0):
    return '\n'.join('I/flutter: AQER_VISUAL ' + json.dumps(event(number))
                     for number in range(case + 1))


def xml(case=0, banner=collector.BANNER, target=collector.TARGET,
        package=collector.PACKAGE, next_bounds='[100,80][300,160]',
        enabled=None, clickable='true', extra=''):
    if enabled is None:
        enabled = 'false' if case == 13 else 'true'
    return (f'<hierarchy><node package="{package}" text="{banner}" />'
            f'<node package="{package}" text="{target}" />'
            f'<node package="{package}" text="{collector.marker(case)}" />'
            f'<node package="{package}" content-desc="AQER_VISUAL_NEXT&#10;Next" '
            f'enabled="{enabled}" clickable="{clickable}" bounds="{next_bounds}" />'
            f'{extra}</hierarchy>')


def receipt():
    return dict(schema=1, source_sha='a'*40, product_trees=collector.TREES,
                run_id='123', package=collector.PACKAGE, version_code=1612,
                target_marker=collector.TARGET, apk_sha256='b'*64,
                api_level=36, display_size_px=[1080, 1920], network_disabled=True, live_authentication=False,
                scroll_cases=sorted(collector.SCROLL_TARGETS), scroll_coverage_complete=True)


class SurfaceTests(unittest.TestCase):
    def test_all_fixed_cases_and_final_disabled_button(self):
        for case in range(14):
            with self.subTest(case=case):
                tap, ready = collector.verified_frame(xml(case), log(case), case, (1080, 1920))
                self.assertEqual(tap, None if case == 13 else (200, 120))
                self.assertEqual(ready, event(case))

    def test_missing_wrong_or_spoofed_banner_and_target(self):
        for changes in ({'banner': ''}, {'banner': 'LIVE'},
                        {'banner': 'prefix SYNTHETIC OFFLINE suffix'}, {'target': 'ordinary-app'}):
            with self.subTest(changes=changes), self.assertRaises(GateError):
                collector.ui_state(xml(**changes), 0, (1080, 1920))

    def test_wrong_or_duplicate_case(self):
        with self.assertRaises(GateError):
            collector.ui_state(xml(1), 0, (1080, 1920))
        with self.assertRaises(GateError):
            collector.ui_state(xml(extra='<node text="AQER_VISUAL_CASE_01" />'), 0, (1080, 1920))

    def test_failure_marker_never_becomes_screenshot(self):
        with self.assertRaisesRegex(GateError, 'target_failure'):
            collector.ui_state(xml(extra='<node text="AQER_VISUAL_FAILURE" />'), 0, (1080, 1920))

    def test_foreign_package_refused(self):
        with self.assertRaisesRegex(GateError, 'foreign_surface'):
            collector.ui_state(xml(package='com.other.app'), 0, (1080, 1920))

    def test_xml_entity_and_malformed_input_refused(self):
        for value in ('<hierarchy>', '<!DOCTYPE x><hierarchy/>', '<!ENTITY x "sensitive"><hierarchy/>'):
            with self.subTest(value=value), self.assertRaises(GateError):
                collector.ui_state(value, 0, (1080, 1920))

    def test_tap_uses_observed_bounds_and_rejects_invalid_bounds(self):
        self.assertEqual(collector.ui_state(xml(next_bounds='[720,40][1000,100]'), 0, (1080, 1920)), (860, 70))
        for value in ('[-1,0][100,10]', '[100,80][50,160]', '[0,0][1081,1920]', '[0,0][0,0]', '1,2,3,4'):
            with self.subTest(value=value), self.assertRaises(GateError):
                collector.ui_state(xml(next_bounds=value), 0, (1080, 1920))

    def test_tap_requires_unique_enabled_clickable_next(self):
        for changes in ({'enabled': 'false'}, {'clickable': 'false'},
                        {'extra': '<node content-desc="AQER_VISUAL_NEXT" />'}):
            with self.subTest(changes=changes), self.assertRaises(GateError):
                collector.ui_state(xml(**changes), 0, (1080, 1920))
        with self.assertRaises(GateError):
            collector.ui_state(xml(13, enabled='true'), 13, (1080, 1920))


class ScrollTests(unittest.TestCase):
    def surface(self, case=4, target_bounds='[20,400][1060,700]', wrapper_bounds='[0,220][1080,1850]',
                scrollable='true', enabled='true', label=collector.SCROLL, duplicate=False):
        wrapper = (f'<node package="{collector.PACKAGE}" content-desc="{label}" '
                   f'bounds="{wrapper_bounds}" enabled="{enabled}" scrollable="{scrollable}" />')
        target = collector.SCROLL_TARGETS.get(case, ('not allowed',))[0]
        node = (f'<node package="{collector.PACKAGE}" content-desc="{target}&#10;متوفر" '
                f'bounds="{target_bounds}" />')
        return xml(case, extra=wrapper + (wrapper if duplicate else '') + node)

    def test_scroll_coordinates_derive_from_one_observed_body(self):
        value = self.surface()
        self.assertEqual(collector.scroll_gesture(value, 4, (1080, 1920)), (540, 1524, 540, 546))
        viewport, targets = collector.scroll_state(value, 4, (1080, 1920))
        self.assertEqual(viewport, (0, 220, 1080, 1850))
        self.assertEqual(targets, {'إعلان اصطناعي للاختبار 1': (20, 400, 1060, 700)})

    def test_scroll_requires_exact_synthetic_case_unique_actionable_viewport(self):
        variants = [self.surface(label='other-scroll'), self.surface(scrollable='false'),
                    self.surface(enabled='false'), self.surface(duplicate=True),
                    self.surface(wrapper_bounds='[0,80][1080,1850]'),
                    self.surface(wrapper_bounds='[0,220][1081,1850]'),
                    self.surface().replace('SYNTHETIC OFFLINE', 'ordinary live app')]
        for value in variants:
            with self.subTest(value=value), self.assertRaises(GateError):
                collector.scroll_gesture(value, 4, (1080, 1920))
        with self.assertRaises(GateError):
            collector.scroll_gesture(self.surface(), 5, (1080, 1920))
        with self.assertRaises(GateError):
            collector.scroll_gesture(self.surface(3), 3, (1080, 1920))

    def test_clipped_hidden_or_too_small_target_does_not_count_as_visible(self):
        for box in ('[20,1800][1060,1850]', '[20,220][1060,700]', '[20,400][1060,410]'):
            with self.subTest(box=box):
                self.assertEqual(collector.scroll_state(self.surface(target_bounds=box), 4, (1080, 1920))[1], {})
        value = self.surface().replace('bounds="[20,400][1060,700]"', 'bounds="[20,400][1060,700]" visible-to-user="false"')
        self.assertEqual(collector.scroll_state(value, 4, (1080, 1920))[1], {})

    def test_capture_rechecks_case_and_failure_before_saving_pixels(self):
        value = self.surface()
        class FakeDevice:
            def wait_frame(self, case, size): return value, (200, 120), event(4)
            def adb(self, *_args, **_kwargs): return b'\x89PNG\r\n\x1a\n' + b'\x00'*8 + struct.pack('>II', 1080, 1920)
            def xml(self): return value.replace('AQER_VISUAL_CASE_04', 'AQER_VISUAL_CASE_05')
            def log(self): return log(4)
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory)
            with self.assertRaises(GateError):
                collector.capture_frame(FakeDevice(), private, 4, (1080, 1920), 1)
            self.assertEqual(list(private.iterdir()), [])
            with self.assertRaises(GateError):
                collector.capture_frame(FakeDevice(), private, 4, (1080, 1920), 5)

    def test_only_declared_supplemental_triplets_and_contiguous_steps_are_sealed(self):
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory)
            (private/'MANIFEST.json').write_text('{}')
            for case in range(14):
                for suffix in ('png', 'xml', 'json'):
                    (private/f'case-{case:02d}.{suffix}').write_text('synthetic')
            for suffix in ('png', 'xml', 'json'):
                (private/f'case-04-scroll-01.{suffix}').write_text('synthetic')
            self.assertEqual(collector.frame_inventory(private)[1], 15)
            (private/'case-04-scroll-01.xml').unlink()
            with self.assertRaises(GateError): collector.frame_inventory(private)
            (private/'case-04-scroll-01.xml').write_text('synthetic')
            for suffix in ('png', 'xml', 'json'):
                (private/f'case-04-scroll-03.{suffix}').write_text('synthetic')
            with self.assertRaises(GateError): collector.frame_inventory(private)


class LogTests(unittest.TestCase):
    def test_missing_ready_and_stale_ready_rejected(self):
        for logs in ('', log(0)):
            with self.assertRaises(GateError):
                collector.verified_frame(xml(1), logs, 1, (1080, 1920))

    def test_failure_and_unknown_event_rejected(self):
        for value in ({'event': 'failure', 'code': 'socket_forbidden', 'failures': 1},
                      {'event': 'request', 'url': 'https://example.invalid'},
                      event(failures=1), event(unknown='secret'), event(requests=0),
                      event(requests=True), event(case=True), event(role='admin'),
                      event(surface='unknown'), event(dark=1), event(textScale=1.5)):
            with self.subTest(value=value), self.assertRaises(GateError):
                collector.ready_events('AQER_VISUAL ' + json.dumps(value))

    def test_malformed_log_and_failure_marker_rejected(self):
        for value in ('AQER_VISUAL not-json', 'AQER_VISUAL []', 'AQER_VISUAL_FAILURE'):
            with self.subTest(value=value), self.assertRaises(GateError):
                collector.ready_events(value)

    def test_case_jump_and_wrap_rejected(self):
        with self.assertRaises(GateError):
            collector.verified_frame(xml(1), 'AQER_VISUAL '+json.dumps(event(1)), 1, (1080, 1920))
        with self.assertRaises(GateError):
            collector.ready_events(log(1)+'\nAQER_VISUAL '+json.dumps(event(0)))

    def test_unrelated_logs_not_exported(self):
        self.assertEqual(collector.ready_events('unrelated secret\n'+log()), [event()])


class ArchiveTests(unittest.TestCase):
    def test_ordinary_apk_cannot_enter_collector(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory)/'target.apk'
            with zipfile.ZipFile(apk, 'w') as target:
                target.writestr('lib/x86_64/libapp.so', b'ordinary live app')
            with self.assertRaisesRegex(GateError, 'compiled_target'):
                collector.verify_archive(apk)
            with zipfile.ZipFile(apk, 'w') as target:
                target.writestr('lib/x86_64/libapp.so', (collector.TARGET+' '+collector.BANNER).encode())
            collector.verify_archive(apk)

    def test_wrong_package_sdk_and_debug_build_rejected(self):
        good = "package: name='com.aqer.yemen.uat' versionCode='1612'\nsdkVersion:'23'\ntargetSdkVersion:'36'\n"
        self.assertEqual(collector.verify_badging(good), 1612)
        for value in (good.replace('.uat', ''), good.replace("'36'", "'35'"),
                      good+'application-debuggable\n', good+good):
            with self.assertRaises(GateError):
                collector.verify_badging(value)

    def make_frames(self, private):
        private.mkdir()
        (private/'MANIFEST.json').write_text('SYNTHETIC_PRIVATE_MANIFEST')
        for case in range(14):
            for suffix in ('png', 'xml', 'json'):
                (private/f'case-{case:02d}.{suffix}').write_text('SYNTHETIC_PRIVATE_FRAME')

    def fake_encrypt(self, plain, destination, recipient):
        with zipfile.ZipFile(plain) as archive:
            self.assertGreaterEqual(len(archive.namelist()), 43)
            self.assertFalse(any(name.endswith('.apk') for name in archive.namelist()))
        destination.write_bytes(b'\x30ciphertext-placeholder')
        return {'file': destination.name, 'bytes': destination.stat().st_size,
                'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
                'cipher': 'CMS-AES256GCM-RSAOAEP-SHA256'}

    def test_public_output_contains_only_ciphertext_and_safe_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); private = base/'private'; output = base/'sealed'
            self.make_frames(private)
            collector.seal(private, output, receipt(), self.fake_encrypt)
            self.assertEqual({path.name for path in output.iterdir()}, {'visual.cms', 'PUBLIC_RECEIPT.json'})
            exported = b''.join(path.read_bytes() for path in output.iterdir())
            self.assertNotIn(b'SYNTHETIC_PRIVATE', exported)
            self.assertNotIn(b'.png', exported)
            self.assertEqual(json.loads((output/'PUBLIC_RECEIPT.json').read_text())['display_size_px'], [1080, 1920])
            self.assertFalse((base/'private.zip').exists())
            with self.assertRaises(FileExistsError):
                collector.seal(private, output, receipt(), self.fake_encrypt)

    def test_supplemental_frames_are_counted_without_public_plaintext(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); private = base/'private'; output = base/'sealed'
            self.make_frames(private)
            for suffix in ('png', 'xml', 'json'):
                (private/f'case-04-scroll-01.{suffix}').write_text('SYNTHETIC_PRIVATE_SCROLL')
            public = collector.seal(private, output, receipt(), self.fake_encrypt)
            self.assertEqual((public['case_count'], public['frame_count'], public['supplemental_frame_count']), (14, 15, 1))
            self.assertTrue(public['scroll_coverage_complete'])
            self.assertNotIn('SYNTHETIC_PRIVATE', (output/'PUBLIC_RECEIPT.json').read_text())

    def test_display_metadata_accepts_only_actual_reviewed_pixel_sizes(self):
        for size in ([1080, 1920], [840, 1493]):
            collector.safe_receipt(dict(receipt(), display_size_px=size))
        for size in ([1080, 1921], [320, 568], [1080.0, 1920], [True, 1920], '1080x1920', (1080, 1920)):
            with self.subTest(size=size), self.assertRaises(GateError):
                collector.safe_receipt(dict(receipt(), display_size_px=size))

    def test_unknown_public_fields_and_private_apk_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); private = base/'private'; output = base/'sealed'
            self.make_frames(private)
            with self.assertRaisesRegex(GateError, 'public_receipt'):
                collector.seal(private, output, dict(receipt(), raw_log='secret'), self.fake_encrypt)
            (private/'target.apk').write_text('APK must never be exported')
            with self.assertRaisesRegex(GateError, 'private_export_scope'):
                collector.seal(private, output, receipt(), self.fake_encrypt)
            self.assertFalse(output.exists())

    def test_seal_failure_removes_partial_output_and_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); private = base/'private'; output = base/'sealed'
            self.make_frames(private)
            def fail(*_args):
                raise RuntimeError('private error')
            with self.assertRaises(RuntimeError):
                collector.seal(private, output, receipt(), fail)
            self.assertFalse(output.exists())
            self.assertFalse((base/'private.zip').exists())


class NetworkTests(unittest.TestCase):
    def test_null_legacy_mobile_flag_with_actual_offline_network_passes(self):
        state = collector.network_state('1', '3', 'null',
                                        'Wifi is disabled\nWifi scanning is always available',
                                        '  Active default network: none\n')
        self.assertTrue(collector.network_is_offline(state))
        self.assertEqual(state['mobile_global'], 'null')

    def test_active_network_unknown_status_or_enabled_wifi_fails_closed(self):
        for airplane, wifi, active in [('1', 'Wifi is disabled', 'Active default network: 123'),
                                       ('1', 'Wifi is disabled', 'missing connectivity output'),
                                       ('1', 'unknown wifi status', 'Active default network: none'),
                                       ('1', 'Wifi is enabled', 'Active default network: none'),
                                       ('0', 'Wifi is disabled', 'Active default network: none'),
                                       ('null', 'Wifi is disabled', 'Active default network: none'),
                                       ('1', 'Wifi is disabled\nWifi is enabled', 'Active default network: none')]:
            with self.subTest(airplane=airplane, wifi=wifi, active=active):
                self.assertFalse(collector.network_is_offline(
                    collector.network_state(airplane, '0', '0', wifi, active)))

    def test_failure_diagnostic_contains_only_safe_enums(self):
        state = collector.network_state('private-airplane', 'SSID-private', 'SIM-private',
                                        'secret device state', 'Active default network: secret-network-id')
        self.assertEqual(state, {'airplane': 'unknown', 'wifi_global': 'unknown',
                                 'mobile_global': 'unknown', 'active_default': 'unknown',
                                 'wifi_disabled': False})
        device = collector.Device('emulator-5554', 1)
        with patch.object(device, 'adb', return_value='private-value'), patch.object(collector.time, 'sleep'):
            with self.assertRaises(GateError) as raised:
                device.offline()
        self.assertNotIn('private-value', str(raised.exception))
        self.assertIn('"active_default": "unknown"', str(raised.exception))


class ContextTests(unittest.TestCase):
    def test_guard_reused_and_source_or_auth_mismatch_rejected(self):
        good = dict(PHASE23_OFFLINE_VISUAL='true', SOURCE_COMMIT='a'*40,
                    GITHUB_SHA='a'*40, GITHUB_RUN_ID='123')
        with patch.object(collector, 'guard') as guard, patch.object(collector.subprocess, 'run'), patch.object(collector, 'digest', return_value=collector.RECIPIENT_SHA256):
            collector.context(good)
            guard.assert_called_once_with(good)
            for changes in ({'SOURCE_COMMIT': 'b'*40}, {'PHASE23_OFFLINE_VISUAL': 'false'},
                            {'AQER_PHASE1_TEST_ACCESS_JSON': 'secret'}, {'AQER_RELEASE_KEY_PASSWORD': 'secret'}):
                with self.subTest(changes=changes), self.assertRaises(GateError):
                    collector.context(dict(good, **changes))

    def test_static_failure_diagnostics_exclude_command_output_and_private_values(self):
        error = collector.subprocess.CalledProcessError(1, ['private-command', '/private/path'],
                                                       output='private output', stderr='private stderr')
        with patch.object(collector, 'STAGE', 'context'):
            self.assertEqual(collector.failure_message(error),
                             'offline_visual_collection_failed stage=context exception=CalledProcessError')
            self.assertEqual(collector.failure_message(GateError('offline_visual_timeout')),
                             'offline_visual_timeout')

    def test_physical_device_serial_refused(self):
        with self.assertRaises(GateError):
            collector.Device('physical-device', 1)


if __name__ == '__main__':
    unittest.main()
