"""Device collector boundary tests; no adb, credential, or live service is used."""
import copy
import hashlib
from html import escape
import json
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_phase23_offline_device as c
from phase23_preflight import GateError

P = {role: sorted(values)[0] for role, values in c.CANDIDATES.items()}


def meta(**changes):
    result = dict.fromkeys(c.FIELDS, 0)
    result.update(v=1, **changes)
    return result


def node(label='', package=c.PACKAGE, bounds='[10,200][200,300]', resource='', clickable=True, enabled=True, clazz='android.widget.Button'):
    return (f'<node package="{package}" text="{escape(label, quote=True)}" resource-id="{resource}" '
            f'clickable="{str(clickable).lower()}" enabled="{str(enabled).lower()}" bounds="{bounds}" class="{clazz}"/>')


def xml(extra='', value=None):
    return '<hierarchy>' + node(c.TARGET) + node(c.BANNER) + node('DEVICE_META ' + json.dumps(value or meta())) + extra + '</hierarchy>'


def receipt():
    return dict(schema=1, source_sha='a'*40, run_id='123', product_trees=c.TREES,
                target_marker=c.TARGET, package=c.PACKAGE, version_code=1901,
                apk_sha256='b'*64, api_level=36, network_scope=c.NETWORK_SCOPE,
                system_packages=P, stage='voice_grant', failure='voice_not_ready',
                case_failures={'voice': {'stage': 'voice_grant', 'failure': 'voice_not_ready'}},
                checks={'voice_denied': True}, cleanup=True, complete=False)


class MetadataTests(unittest.TestCase):
    def test_exact_closed_integer_schema_and_actual_location(self):
        value = meta(gpsPhase=2, gpsMethod=1, latE6=15372900, lonE6=44205100, gpsConfirmations=1)
        self.assertEqual(c.metadata(json.dumps(value)), value)
        for changes in ({'extra': 0}, {'voiceReadyCount': True}, {'latE6': 90_000_001},
                        {'voiceDictation': 2}, {'case': 4}, {'snapshotSeq': -1}):
            with self.subTest(changes=changes), self.assertRaises(c.Incomplete):
                c.metadata(json.dumps({**value, **changes}))
        del value['snapshotSeq']
        with self.assertRaises(c.Incomplete):
            c.metadata(json.dumps(value))

    def test_target_failures_never_become_accepted_frames(self):
        for key in ('failures', 'authBlocked', 'socketBlocked', 'searchStarted'):
            with self.subTest(key=key), self.assertRaisesRegex(c.Incomplete, 'target_failure'):
                c.metadata(json.dumps(meta(**{key: 1})))

    def test_only_closed_target_events_are_parsed(self):
        value = meta()
        self.assertEqual(c.events('irrelevant raw log\nI/flutter AQER_DEVICE ' + json.dumps(value)), [value])
        with self.assertRaises(c.Incomplete):
            c.events('I/flutter AQER_DEVICE {"token":"secret"}')


class SurfaceTests(unittest.TestCase):
    def test_app_requires_both_markers_and_metadata(self):
        self.assertEqual(c.surface(xml(), 'app', P)[1], meta())
        for value in (xml().replace(c.TARGET, 'ordinary-app'), xml().replace(c.BANNER, 'LIVE'), '<hierarchy/>'):
            with self.subTest(value=value), self.assertRaises(c.Incomplete):
                c.surface(value, 'app', P)

    def test_system_permissions_are_separate_and_package_bound(self):
        value = '<hierarchy>' + node('Deny', P['permission']) + '</hierarchy>'
        c.surface(value, 'permission', P)
        for role in ('app', 'camera', 'picker'):
            with self.subTest(role=role), self.assertRaises(c.Incomplete):
                c.surface(value, role, P)
        with self.assertRaises(c.Incomplete):
            c.surface(value.replace(P['permission'], 'com.attacker'), 'permission', P)

    def test_foreign_overlays_and_xml_entities_rejected(self):
        for value in (xml(node('notice', 'com.android.systemui')), '<!DOCTYPE x>' + xml(), '<!ENTITY x "a">' + xml()):
            with self.subTest(value=value), self.assertRaises(c.Incomplete):
                c.surface(value, 'app', P)

    def test_bounds_and_unique_clickable_node_required(self):
        self.assertEqual(c.control(xml(node('DEVICE_HOME')), 'app', P, names=('DEVICE_HOME',)), (105, 250))
        for extra in (node('DEVICE_HOME', bounds='[0,0][1081,1920]'),
                      node('DEVICE_HOME', enabled=False), node('DEVICE_HOME', clickable=False),
                      node('DEVICE_HOME') + node('DEVICE_HOME', bounds='[300,400][600,500]')):
            with self.subTest(extra=extra), self.assertRaises(c.Incomplete):
                c.control(xml(extra), 'app', P, names=('DEVICE_HOME',))

    def test_control_resolution_waits_for_camera_processing(self):
        device = c.Device('emulator-5554', time.monotonic()+30)
        empty = '<hierarchy>' + node('Camera', P['camera']) + '</hierarchy>'
        ready = '<hierarchy>' + node('Done', P['camera']) + '</hierarchy>'
        with patch.object(device, 'wait', side_effect=[(empty, None), (ready, None)]), patch.object(device, 'adb') as adb, patch.object(c.time, 'sleep'):
            device.tap('camera', P, names=('Done',))
        adb.assert_called_once_with('shell', 'input', 'tap', '105', '250')

    def test_ambiguous_control_never_retried_or_tapped(self):
        device = c.Device('emulator-5554', time.monotonic()+30)
        value = xml(node('DEVICE_HOME') + node('DEVICE_HOME', bounds='[300,400][600,500]'))
        with patch.object(device, 'wait', return_value=(value, meta())) as wait, patch.object(device, 'adb') as adb:
            with self.assertRaisesRegex(c.Incomplete, 'control_ambiguous'):
                device.tap('app', P, names=('DEVICE_HOME',))
        self.assertEqual(wait.call_count, 1)
        adb.assert_not_called()

    def test_snapshot_requires_completed_new_sequence(self):
        device = c.Device('emulator-5554', time.monotonic()+30)
        def wait(role, packages, predicate, **kwargs):
            self.assertFalse(predicate(meta(snapshotSeq=4, cameraFiles=0)))
            self.assertTrue(predicate(meta(snapshotSeq=5, cameraFiles=1)))
            return xml(), meta(snapshotSeq=5, cameraFiles=1)
        with patch.object(device, 'app', return_value=(xml(), meta(snapshotSeq=4))), patch.object(device, 'tap') as tap, patch.object(device, 'wait', side_effect=wait):
            self.assertEqual(device.snapshot(P)['cameraFiles'], 1)
        tap.assert_called_once_with('app', P, names=('DEVICE_SNAPSHOT',))

    def test_picker_without_confirmation_can_return_directly_to_app(self):
        device = c.Device('emulator-5554', time.monotonic()+30)
        waiting = '<hierarchy>' + node('Downloads', P['picker']) + '</hierarchy>'
        returned = xml(value=meta(case=3))
        with patch.object(device, 'xml', side_effect=[waiting, returned]), patch.object(device, 'log', return_value=''), patch.object(device, 'adb') as adb, patch.object(c.time, 'sleep'):
            c.picker_return(device, P)
        adb.assert_not_called()

    def test_resolved_system_component_cannot_expand_allowlist(self):
        self.assertEqual(c.resolved_package(P['camera']+'/.Camera', 'camera', {P['camera']}), P['camera'])
        for output, installed in [('com.other/.Camera', {'com.other'}), (P['camera']+'/.Camera', set()), (P['camera']+'/.A\n'+P['camera']+'/.B', {P['camera']})]:
            with self.subTest(output=output), self.assertRaises(GateError):
                c.resolved_package(output, 'camera', installed)


class ExportTests(unittest.TestCase):
    def test_receipt_rejects_every_unknown_metadata_channel(self):
        c.validate_receipt(receipt())
        variants = []
        for field in ('token', 'raw_log', 'xml'):
            value = receipt(); value[field] = 'not exportable'; variants.append(value)
        value = receipt(); value['checks'] = {'arbitrary': True}; variants.append(value)
        value = receipt(); value['checks'] = {'voice_denied': 1}; variants.append(value)
        value = receipt(); value['system_packages'] = {**P, 'other': 'com.other'}; variants.append(value)
        value = receipt(); value['system_packages'] = {**P, 'camera': 'com.other'}; variants.append(value)
        value = receipt(); value['case_failures'] = {'voice': {'stage': 'voice_grant', 'failure': 'arbitrary raw text'}}; variants.append(value)
        value = receipt(); value['complete'] = True; variants.append(value)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(GateError):
                c.validate_receipt(value)

    def test_partial_export_contains_only_cms_and_closed_public_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory)/'private'; private.mkdir()
            (private/'MANIFEST.json').write_text('{}')
            output = Path(directory)/'sealed'
            def encryptor(archive, dest, recipient):
                with zipfile.ZipFile(archive) as zipped:
                    self.assertEqual(zipped.namelist(), ['MANIFEST.json'])
                dest.write_bytes(b'encrypted')
                return {'bytes': 9, 'sha256': hashlib.sha256(b'encrypted').hexdigest()}
            c.seal(private, output, receipt(), [], encryptor)
            self.assertEqual({p.name for p in output.iterdir()}, {'device.cms', 'PUBLIC_RECEIPT.json'})
            result = json.loads((output/'PUBLIC_RECEIPT.json').read_text())
            self.assertEqual(result['result'], 'INCOMPLETE')
            self.assertFalse(result['apk_exported'])
            self.assertFalse(result['physical_device_acceptance'])
            self.assertFalse((Path(directory)/'device.zip').exists())

    def test_no_apk_or_unverified_diagnostic_can_enter_export(self):
        with tempfile.TemporaryDirectory() as directory:
            private = Path(directory)/'private'; private.mkdir()
            (private/'MANIFEST.json').write_text('{}')
            for name in ('app.apk', 'unverified.png', 'logcat.txt'):
                extra = private/name; extra.write_bytes(b'x')
                with self.subTest(name=name), self.assertRaises(GateError):
                    c.seal(private, Path(directory)/'sealed', receipt(), [])
                extra.unlink()

    def test_foreign_after_frame_is_never_saved(self):
        with tempfile.TemporaryDirectory() as directory:
            device = c.Device('emulator-5554', time.monotonic()+30)
            png = b'\x89PNG\r\n\x1a\n' + b'0'*8 + struct.pack('>II', *c.SIZE)
            with patch.object(device, 'wait', return_value=(xml(), meta())), patch.object(device, 'adb', return_value=png), patch.object(device, 'xml', return_value=xml(node('foreign', 'com.other'))):
                with self.assertRaises(c.Incomplete):
                    c.capture(device, Path(directory), [], P)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_failure_of_one_provider_preserves_other_case_execution(self):
        device = object(); calls = []
        def voice(*_):
            raise c.Incomplete('voice_not_ready')
        def location(*_): calls.append('location')
        def camera(*_): calls.append('camera')
        def picker(*_): calls.append('picker')
        class Fake:
            def app(self, *_args, **_kwargs): return xml(), meta()
            def wait(self, *_args, **_kwargs): return xml(), meta()
        failures = {}
        with patch.object(c, 'voice_case', side_effect=voice), patch.object(c, 'location_case', side_effect=location), patch.object(c, 'camera_case', side_effect=camera), patch.object(c, 'picker_case', side_effect=picker), patch.object(c, 'recover_home'), patch.object(c, 'capture'):
            c.execute(Fake(), None, [], P, {}, failures)
        self.assertEqual(calls, ['location', 'camera', 'picker'])
        self.assertEqual(failures['voice']['failure'], 'voice_not_ready')

    def test_camera_failure_recovers_verified_home_before_picker(self):
        order = []
        class Fake:
            def app(self, *_args, **_kwargs): return xml(), meta()
            def wait(self, *_args, **_kwargs): return xml(), meta()
        def camera(*_):
            order.append('camera')
            raise c.Incomplete('control_missing')
        def recover(*_): order.append('verified_home')
        def picker(*_): order.append('picker')
        failures = {}
        with patch.object(c, 'voice_case'), patch.object(c, 'location_case'), patch.object(c, 'camera_case', side_effect=camera), patch.object(c, 'picker_case', side_effect=picker), patch.object(c, 'recover_home', side_effect=recover), patch.object(c, 'capture'):
            c.execute(Fake(), None, [], P, {}, failures)
        self.assertEqual(order, ['camera', 'verified_home', 'picker'])
        self.assertEqual(failures['camera']['failure'], 'control_missing')

    def test_nonrecoverable_foreign_surface_stops_before_picker(self):
        class Fake:
            def app(self, *_args, **_kwargs): return xml(), meta()
            def wait(self, *_args, **_kwargs): return xml(), meta()
        with patch.object(c, 'voice_case'), patch.object(c, 'location_case'), patch.object(c, 'camera_case', side_effect=c.Incomplete('control_missing')), patch.object(c, 'picker_case') as picker, patch.object(c, 'recover_home', side_effect=c.Incomplete('unknown_surface')), patch.object(c, 'capture'):
            with self.assertRaisesRegex(c.Incomplete, 'unknown_surface'):
                c.execute(Fake(), None, [], P, {}, {})
        picker.assert_not_called()

    def test_recovery_requires_observed_back_then_synthetic_app_home(self):
        device = c.Device('emulator-5554', time.monotonic()+30)
        camera = '<hierarchy>' + node('Camera onboarding', P['camera']) + '</hierarchy>'
        app = xml(value=meta(case=3))
        with patch.object(device, 'xml', side_effect=[camera, app]), patch.object(device, 'back') as back, patch.object(device, 'tap') as tap, patch.object(device, 'app') as verify:
            c.recover_home(device, P)
        back.assert_called_once_with('camera', P)
        tap.assert_called_once_with('app', P, names=('DEVICE_HOME',))
        verify.assert_called_once_with(P, case=0)
        with patch.object(device, 'xml', return_value=xml(node('foreign', 'com.other'))), patch.object(device, 'back') as back:
            with self.assertRaisesRegex(c.Incomplete, 'unknown_surface'):
                c.recover_home(device, P)
        back.assert_not_called()

    def test_synthetic_png_is_fixed_valid_size(self):
        value = c.synthetic_png()
        self.assertEqual(value[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', value[16:24]), (256, 256))
        self.assertEqual(value, c.synthetic_png())


class WorkflowTests(unittest.TestCase):
    def test_workflow_is_isolated_and_never_uploads_apk(self):
        value = (c.ROOT/'.github/workflows/phase23-offline-device.yml').read_text()
        self.assertIn("[run-offline-device]", value)
        self.assertIn('timeout-minutes: 35', value)
        self.assertIn('--max-seconds 900', value)
        self.assertIn('--target-platform=android-x64', value)
        self.assertIn('-camera-back emulated -camera-front emulated', value)
        self.assertNotIn('webcam', value)
        self.assertNotIn('secrets.', value)
        self.assertNotIn('prepare_phase23_visual_delivery', value)
        upload = value.split('uses: actions/upload-artifact@v4', 1)[1]
        self.assertIn('phase23-offline-device-sealed/device.cms', upload)
        self.assertNotIn('.apk', upload)
        self.assertIn('if: always()', value)

    def test_app_permissions_use_only_real_declared_prompted_permissions(self):
        source = (c.ROOT/'scripts/run_phase23_offline_device.py').read_text()
        self.assertNotIn("'pm', 'grant'", source)
        self.assertNotIn("'pm', 'revoke'", source)
        self.assertNotIn('DEVICE_GPS', source)
        self.assertIn("device.geo()", source)
        self.assertIn("'gpsMethod'", source)
        self.assertIn("b'AQER_OFFLINE_JOURNEYS_TARGET_V1'", source)


if __name__ == '__main__':
    unittest.main()
