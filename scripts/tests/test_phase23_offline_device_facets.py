"""Selected device runs preserve old evidence without replaying or inheriting it."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_phase23_offline_device as c
from phase23_preflight import GateError


P = {role: sorted(values)[0] for role, values in c.CANDIDATES.items()}
REMAINING_CHECKS = {
    'voice_denied', 'voice_permission_granted', 'voice_retry_ready', 'voice_cancel',
    'location_denied', 'location_permission_granted', 'location_retry_gps', 'picker_select',
}
PRIOR_CHECKS = {'camera_cancel', 'camera_capture', 'picker_cancel'}


def receipt(*, complete=True):
    return dict(schema=1, source_sha='a'*40, run_id='456', product_trees=c.TREES,
                target_marker=c.TARGET, package=c.PACKAGE, version_code=1902,
                apk_sha256='b'*64, api_level=36, network_scope=c.NETWORK_SCOPE,
                system_packages=P, stage='finish', failure=None, case_failures={},
                checks={name: True for name in REMAINING_CHECKS} if complete else {},
                cleanup=True, complete=complete, startup_diagnostics=None,
                **c.facet_receipt_fields(c.REMAINING_FACETS))


class SelectionContractTests(unittest.TestCase):
    def test_only_reviewed_full_and_remaining_profiles_are_allowed(self):
        self.assertEqual(c.selected_facets({}), c.FULL_FACETS)
        self.assertEqual(c.selected_facets({'PHASE23_DEVICE_FACETS': 'voice,location,camera,picker'}), c.FULL_FACETS)
        self.assertEqual(c.selected_facets({'PHASE23_DEVICE_FACETS': 'voice,location,picker_select'}), c.REMAINING_FACETS)
        for value in ('', 'voice', 'voice,location,picker', 'location,voice,picker_select',
                      'voice,location,picker_select,picker_select', 'voice,location,picker_select,camera',
                      'voice, location,picker_select', 'voice,location,picker_select\n',
                      'voice,location,unknown', None, 1, ['voice', 'location', 'picker_select']):
            with self.subTest(value=value), self.assertRaisesRegex(GateError, 'device_facet_selection_invalid'):
                c.selected_facets({'PHASE23_DEVICE_FACETS': value})

    def test_direct_execution_cannot_bypass_the_selection_contract(self):
        for value in (None, 'voice,location,picker_select', (), ('picker_select',),
                      ('voice', 'location', 'picker_select', 'camera')):
            device = Mock()
            with self.subTest(value=value), patch.object(c, 'capture') as capture:
                with self.assertRaisesRegex(GateError, 'device_facet_selection_invalid'):
                    c.execute(device, None, [], P, {}, {}, value)
            device.app.assert_not_called()
            capture.assert_not_called()

    def test_completion_requires_only_new_selected_checks(self):
        observed = dict.fromkeys(REMAINING_CHECKS, True)
        self.assertTrue(c.checks_complete(observed, c.REMAINING_FACETS))
        self.assertFalse(c.checks_complete(observed))
        self.assertTrue(c.checks_complete({**observed, **dict.fromkeys(PRIOR_CHECKS, True)}))
        self.assertFalse(c.checks_complete({**observed, 'camera_capture': True}, c.REMAINING_FACETS))
        for name in REMAINING_CHECKS:
            for replacement in (None, False, 1):
                changed = dict(observed)
                if replacement is None:
                    del changed[name]
                else:
                    changed[name] = replacement
                with self.subTest(name=name, replacement=replacement):
                    self.assertFalse(c.checks_complete(changed, c.REMAINING_FACETS))


class ReceiptScopeTests(unittest.TestCase):
    def test_verified_reference_is_exact_and_never_current_success(self):
        value = receipt()
        c.validate_receipt(value)
        reference = value['prior_evidence_reference']
        self.assertEqual(reference, {
            'run_id': '43538357569',
            'source_sha': '91b24899f2961a3ecf39699fa7356444548962e1',
            'public_receipt_sha256': '40302f0e839859abd188105f6d9303172939e34cd8230dee61ba9a505e088a6c',
            'checks': ['camera_cancel', 'camera_capture', 'picker_cancel'],
            'replayed': False, 'accepted_by_this_run': False,
        })
        self.assertEqual(set(value['checks']), REMAINING_CHECKS)
        self.assertFalse(PRIOR_CHECKS & set(value['checks']))
        self.assertEqual(value['complete_scope'], 'current_selected_facets_only')
        reference['checks'].append('untrusted')
        self.assertNotIn('untrusted', c.facet_receipt_fields(c.REMAINING_FACETS)['prior_evidence_reference']['checks'])

    def test_prior_reference_cannot_be_altered_or_upgrade_acceptance(self):
        for key, replacement in (
                ('run_id', '43538357570'), ('source_sha', 'c'*40),
                ('public_receipt_sha256', 'd'*64), ('checks', ['camera_capture']),
                ('replayed', True), ('replayed', 0),
                ('accepted_by_this_run', True), ('accepted_by_this_run', 0),
                ('unexpected', 'raw content')):
            value = receipt()
            value['prior_evidence_reference'][key] = replacement
            with self.subTest(key=key, replacement=replacement), self.assertRaises(GateError):
                c.validate_receipt(value)

    def test_old_successes_cannot_fill_missing_new_checks(self):
        value = receipt(complete=False)
        c.validate_receipt(value)
        value['complete'] = True
        with self.assertRaises(GateError):
            c.validate_receipt(value)
        for name in PRIOR_CHECKS:
            value = receipt()
            value['checks'][name] = True
            with self.subTest(name=name), self.assertRaises(GateError):
                c.validate_receipt(value)

    def test_partial_selected_run_retains_observed_checks_and_exact_failure(self):
        value = receipt()
        value.update(complete=False, failure='gps_unproven',
                     case_failures={'location': {'stage': 'location_confirm', 'failure': 'gps_unproven'}})
        del value['checks']['location_retry_gps']
        c.validate_receipt(value)
        self.assertTrue(value['checks']['picker_select'])
        for extra_case in ('camera', 'picker', 'other'):
            changed = copy.deepcopy(value)
            changed['case_failures'][extra_case] = {'stage': 'picker_select', 'failure': 'control_missing'}
            with self.subTest(extra_case=extra_case), self.assertRaises(GateError):
                c.validate_receipt(changed)
        value['complete'] = True
        with self.assertRaises(GateError):
            c.validate_receipt(value)

    def test_scope_fields_are_an_exact_group_and_full_mode_has_no_reference(self):
        for field in ('selected_facets', 'complete_scope', 'prior_evidence_reference'):
            value = receipt()
            del value[field]
            with self.subTest(field=field), self.assertRaises(GateError):
                c.validate_receipt(value)
        for changes in ({'complete_scope': 'current_full_facets'},
                        {'prior_evidence_reference': None},
                        {'selected_facets': ['voice', 'location', 'picker']}):
            with self.subTest(changes=changes), self.assertRaises(GateError):
                c.validate_receipt({**receipt(), **changes})
        full = receipt()
        full.update(c.facet_receipt_fields(c.FULL_FACETS))
        full['checks'].update(dict.fromkeys(PRIOR_CHECKS, True))
        c.validate_receipt(full)
        self.assertIsNone(full['prior_evidence_reference'])
        full['prior_evidence_reference'] = c.facet_receipt_fields(c.REMAINING_FACETS)['prior_evidence_reference']
        with self.assertRaises(GateError):
            c.validate_receipt(full)

    def test_public_selected_result_does_not_claim_full_suite_or_phase_acceptance(self):
        for complete in (True, False):
            with self.subTest(complete=complete), tempfile.TemporaryDirectory() as directory:
                private = Path(directory) / 'private'
                private.mkdir()
                value = receipt(complete=complete)
                (private / 'MANIFEST.json').write_text(json.dumps(value))
                output = Path(directory) / 'sealed'
                def encryptor(_archive, destination, _recipient):
                    destination.write_bytes(b'encrypted')
                    return {'bytes': 9, 'sha256': hashlib.sha256(b'encrypted').hexdigest()}
                c.seal(private, output, value, [], encryptor)
                public = json.loads((output / 'PUBLIC_RECEIPT.json').read_text())
                self.assertEqual(public['result'], 'SELECTED_FACETS_COMPLETE' if complete else 'INCOMPLETE')
                self.assertEqual(public['checks'], value['checks'])
                self.assertEqual(public['prior_evidence_reference'], value['prior_evidence_reference'])
                self.assertFalse(public['phase23_accepted'])
                self.assertFalse(public['physical_device_acceptance'])
                self.assertIn('not replayed or accepted here', public['scope'])
                self.assertEqual({path.name for path in output.iterdir()}, {'device.cms', 'PUBLIC_RECEIPT.json'})


class NoReplayExecutionTests(unittest.TestCase):
    def test_remaining_run_calls_only_voice_location_and_selection(self):
        device, checks, failures, frames = Mock(), {}, {}, []
        order = []
        def record(name):
            def observed(*args, **kwargs):
                order.append(name)
                checks.update(dict.fromkeys(c.FACET_CHECKS[name], True))
            return observed
        with patch.object(c, 'voice_case', side_effect=record('voice')), \
                patch.object(c, 'location_case', side_effect=record('location')), \
                patch.object(c, 'camera_case') as camera, \
                patch.object(c, 'picker_case', side_effect=record('picker_select')) as picker, \
                patch.object(c, 'capture'):
            c.execute(device, None, frames, P, checks, failures, c.REMAINING_FACETS)
        self.assertEqual(order, ['voice', 'location', 'picker_select'])
        camera.assert_not_called()
        picker.assert_called_once_with(device, None, frames, P, checks, selection_only=True)
        self.assertTrue(c.checks_complete(checks, c.REMAINING_FACETS))
        self.assertEqual(failures, {})

    def test_failed_selected_facet_recovers_before_next_without_old_checks(self):
        checks, failures, order = {'voice_denied': True}, {}, []
        def location(*_):
            c.STAGE = 'location_confirm'
            raise c.Incomplete('gps_unproven')
        def picker(*_, **kwargs):
            self.assertEqual(kwargs, {'selection_only': True})
            order.append('picker_select')
            checks['picker_select'] = True
        with patch.object(c, 'voice_case'), patch.object(c, 'location_case', side_effect=location), \
                patch.object(c, 'camera_case') as camera, patch.object(c, 'picker_case', side_effect=picker), \
                patch.object(c, 'recover_home', side_effect=lambda *_: order.append('verified_home')), \
                patch.object(c, 'capture'):
            c.execute(Mock(), None, [], P, checks, failures, c.REMAINING_FACETS)
        camera.assert_not_called()
        self.assertEqual(order, ['verified_home', 'picker_select'])
        self.assertEqual(failures, {'location': {'stage': 'location_confirm', 'failure': 'gps_unproven'}})
        self.assertEqual(checks, {'voice_denied': True, 'picker_select': True})

    def test_unverified_recovery_cannot_continue_selected_run(self):
        with patch.object(c, 'voice_case'), \
                patch.object(c, 'location_case', side_effect=c.Incomplete('control_missing')), \
                patch.object(c, 'camera_case') as camera, patch.object(c, 'picker_case') as picker, \
                patch.object(c, 'recover_home', side_effect=c.Incomplete('unknown_surface')), \
                patch.object(c, 'capture'):
            with self.assertRaisesRegex(c.Incomplete, 'unknown_surface'):
                c.execute(Mock(), None, [], P, {}, {}, c.REMAINING_FACETS)
        camera.assert_not_called()
        picker.assert_not_called()

    def test_selection_only_opens_picker_once_without_cancel_or_cancel_success(self):
        class ReachedNativeSelection(Exception):
            pass
        device, checks = Mock(), {}
        device.snapshot.return_value = dict.fromkeys(
            ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes', 'mediaDecodable'), 0)
        device.wait.side_effect = ReachedNativeSelection()
        with patch.object(c, 'capture') as capture:
            with self.assertRaises(ReachedNativeSelection):
                c.picker_case(device, None, [], P, checks, selection_only=True)
        self.assertEqual(device.app.call_args_list[0].kwargs, {'case': 0})
        self.assertEqual(device.app.call_args_list[1].kwargs, {'case': 3})
        self.assertEqual(device.tap.call_count, 2)  # Fresh media screen, then its picker.
        device.wait.assert_called_once_with('picker', P)
        device.snapshot.assert_called_once_with(P)
        device.back.assert_not_called()
        capture.assert_not_called()
        self.assertEqual(checks, {})
        self.assertEqual(c.STAGE, 'picker_select')

    def test_selection_only_requires_empty_fresh_media_state(self):
        for name in ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes'):
            device = Mock()
            device.snapshot.return_value = dict.fromkeys(
                ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes', 'mediaDecodable'), 0)
            device.snapshot.return_value[name] = 1
            checks = {}
            with self.subTest(name=name), self.assertRaisesRegex(c.Incomplete, 'media_unproven'):
                c.picker_case(device, None, [], P, checks, selection_only=True)
            device.wait.assert_not_called()
            device.back.assert_not_called()
            self.assertEqual(checks, {})


if __name__ == '__main__':
    unittest.main()
