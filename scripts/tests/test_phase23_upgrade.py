import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from phase23_preflight import API, TREES, GateError
from phase23_firebase import disabled_receipt
from prepare_phase23_upgrade import validate_pair
from run_phase23_native import NativeRun, validate_command


class UpgradeSafetyTest(unittest.TestCase):
    def pair(self):
        base = {'source_commit': 'a' * 40, 'product_source_commit': 'a' * 40,
                'product_trees': TREES.copy(), 'ci_run_id': '1234',
                'package': 'com.aqer.yemen.uat', 'api': API,
                'certificate_sha256': 'b' * 64, 'version_code': 1589,
                'target_sdk': 36, 'min_sdk': 23, 'experiments': {'conditional_prefetch': True},
                'firebase': disabled_receipt(),
                'sha256': 'c' * 64}
        return base, dict(base, version_code=1590)

    def test_same_job_pair_rejects_other_signers_sources_and_versions(self):
        base, upgrade = self.pair()
        validate_pair(base, upgrade)
        for key, value in [('certificate_sha256', 'd' * 64),
                           ('product_source_commit', 'd' * 40), ('ci_run_id', '1235'),
                           ('package', 'com.aqer.yemen'), ('api', 'https://example.invalid/api'),
                           ('version_code', 1589), ('version_code', True),
                           ('version_code', 1591), ('product_trees', {})]:
            with self.subTest(key=key, value=value):
                with self.assertRaises(GateError):
                    validate_pair(base, dict(upgrade, **{key: value}))
        for value in ['', 'not-a-certificate']:
            with self.assertRaises(GateError):
                validate_pair(dict(base, certificate_sha256=value),
                              dict(upgrade, certificate_sha256=value))

    def test_pair_requires_verified_matching_firebase_receipts(self):
        base, upgrade = self.pair()
        configured = dict(disabled_receipt(), configuration_present=True,
                          client_configured=True, client_push_enabled=True,
                          compiled_configuration_verified=True, config_fingerprint='e' * 64)
        with self.assertRaisesRegex(GateError, 'identity_mismatch'):
            validate_pair(base, dict(upgrade, firebase=configured))
        validate_pair(dict(base, firebase=configured), dict(upgrade, firebase=configured.copy()))
        with self.assertRaisesRegex(GateError, 'identity_mismatch'):
            validate_pair(dict(base, firebase=configured),
                          dict(upgrade, firebase=dict(configured, config_fingerprint='f' * 64)))
        for invalid in [None, {}, dict(configured, real_fcm_delivery_tested=True),
                        dict(configured, client_push_enabled=False),
                        dict(configured, api_key='SENSITIVE_SENTINEL')]:
            with self.subTest(invalid=invalid), self.assertRaises(GateError):
                validate_pair(dict(base, firebase=invalid), dict(upgrade, firebase=invalid))

    def test_replacement_checks_installed_version_and_preserves_app_data(self):
        base, upgrade = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            private = Path(folder)
            apk = private / 'upgrade.apk'
            apk.write_bytes(b'verified synthetic installer bytes')
            upgrade['sha256'] = hashlib.sha256(apk.read_bytes()).hexdigest()
            proof = private / 'UPGRADE_VERIFICATION.json'
            proof.write_text(json.dumps({'baseline': base, 'upgrade': upgrade}))
            run = object.__new__(NativeRun)
            run.report = {'source_sha': base['source_commit'], 'run_id': base['ci_run_id']}
            run.driver = Mock()
            run.driver.adb.side_effect = ['versionCode=1589 minSdk=23', 'Success',
                                          'versionCode=1590 minSdk=23']
            with patch('run_phase23_native.PRIVATE', private):
                result = run.upgrade_install()
            commands = [c.args for c in run.driver.adb.call_args_list]
            self.assertEqual(commands[1], ('install', '--no-streaming', '-r', apk))
            self.assertEqual(len(commands), 3)
            self.assertFalse(result['data_clear_or_uninstall'])
            self.assertTrue(result['draft_persistence_requires_ui_observation'])
            run.driver.startup.assert_called_once()
            # A changed artifact is rejected before any native mutation.
            apk.write_bytes(b'changed')
            run.driver.reset_mock()
            with patch('run_phase23_native.PRIVATE', private):
                with self.assertRaisesRegex(GateError, 'bytes_mismatch'):
                    run.upgrade_install()
            run.driver.adb.assert_not_called()

    def test_another_run_or_an_already_upgraded_install_is_not_replaced(self):
        base, upgrade = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            private = Path(folder)
            apk = private / 'upgrade.apk'
            apk.write_bytes(b'verified synthetic bytes')
            upgrade['sha256'] = hashlib.sha256(apk.read_bytes()).hexdigest()
            (private / 'UPGRADE_VERIFICATION.json').write_text(
                json.dumps({'baseline': base, 'upgrade': upgrade}))
            run = object.__new__(NativeRun)
            run.driver = Mock()
            run.report = {'source_sha': base['source_commit'], 'run_id': 'other'}
            with patch('run_phase23_native.PRIVATE', private):
                with self.assertRaisesRegex(GateError, 'current_run'):
                    run.upgrade_install()
            run.driver.adb.assert_not_called()
            run.report['run_id'] = base['ci_run_id']
            run.driver.adb.return_value = 'versionCode=1590 minSdk=23'
            with patch('run_phase23_native.PRIVATE', private):
                with self.assertRaisesRegex(GateError, 'baseline_must_be_installed'):
                    run.upgrade_install()
            self.assertEqual(run.driver.adb.call_count, 1)

    def test_fixed_upgrade_and_in_place_logout_cannot_take_paths_or_credentials(self):
        command = {'run_id': '1234', 'seq': 1, 'challenge': 'a' * 64, 'args': {}}
        for op in ['upgrade_install', 'logout_in_place']:
            self.assertEqual(validate_command(dict(command, op=op), '1234', 1, 'a' * 64)['op'], op)
            with self.assertRaises(GateError):
                validate_command(dict(command, op=op, args={'path': '/arbitrary.apk'}),
                                 '1234', 1, 'a' * 64)

    def test_checkpoint_identity_changes_only_after_observed_native_replacement(self):
        base, upgrade = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            private = Path(folder)
            (private / 'APK_VERIFICATION.json').write_text(json.dumps(base))
            (private / 'UPGRADE_VERIFICATION.json').write_text(
                json.dumps({'baseline': base, 'upgrade': upgrade}))
            run = object.__new__(NativeRun)
            run.report = {}
            with patch('run_phase23_native.PRIVATE', private):
                self.assertEqual(run.current_apk_receipt()['version_code'], 1589)
                run.report['upgrade'] = {'after': 1590, 'upgrade_sha256': upgrade['sha256']}
                self.assertEqual(run.current_apk_receipt()['version_code'], 1590)
                run.report['upgrade']['after'] = 1591
                with self.assertRaisesRegex(GateError, 'installed_upgrade_receipt_mismatch'):
                    run.current_apk_receipt()

    def test_in_place_logout_uses_normal_ui_without_restarting_process(self):
        run = object.__new__(NativeRun)
        run.driver = Mock(recorder=None)
        run.driver.has.return_value = False
        run.actor = 'broker'
        run.native_auth_attempted = True
        result = run.logout(restart=False)
        run.driver.adb.assert_not_called()
        run.driver.startup.assert_not_called()
        run.driver.wait_guest_boundary.assert_called_once()
        self.assertFalse(result['process_restart_requested'])
        self.assertIsNone(run.actor)


if __name__ == '__main__':
    unittest.main()
