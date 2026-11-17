"""Guard and mocked device tests; no real emulator, accounts or signing keys."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / 'probe_durable_uat_upgrade.py'
SPEC = importlib.util.spec_from_file_location('durable_upgrade', SCRIPT)
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)
SOURCE = 'a' * 40


def context():
    return {'GITHUB_ACTIONS': 'true', 'AQER_DURABLE_UAT_UPGRADE': 'true',
            'GITHUB_REPOSITORY': subject.REPOSITORY, 'GITHUB_REF': subject.BRANCH,
            'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_SHA': SOURCE}


def receipt(version, payload=b'fixture'):
    return {'source_commit': SOURCE, 'package': subject.PACKAGE, 'version_code': version,
            'api': subject.API, 'signer_certificate_sha256': subject.APPROVED_PIN,
            'sha256': hashlib.sha256(payload).hexdigest(), 'bytes': len(payload)}


class UpgradeGuards(unittest.TestCase):
    def test_explicit_ci_emulator_and_public_approved_pin_required(self):
        subject.guard(context(), SOURCE, subject.APPROVED_PIN, 'emulator-5554')
        for field, value in [('GITHUB_ACTIONS', 'false'), ('AQER_DURABLE_UAT_UPGRADE', 'false'),
                             ('GITHUB_REPOSITORY', 'other/repo'), ('GITHUB_REF', 'refs/heads/main'),
                             ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'),
                             ('GITHUB_SHA', 'b' * 40)]:
            with self.subTest(field=field), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), field: value}, SOURCE, subject.APPROVED_PIN, 'emulator-5554')
        for source, pin, serial in [(SOURCE, 'b' * 64, 'emulator-5554'),
                                    (SOURCE, subject.APPROVED_PIN, 'physical-device'),
                                    (SOURCE, subject.APPROVED_PIN, 'emulator-5554;bad'),
                                    ('bad', subject.APPROVED_PIN, 'emulator-5554')]:
            with self.subTest(serial=serial, pin=pin), self.assertRaises(subject.UpgradeError):
                subject.guard(context(), source, pin, serial)

    def test_upgrade_job_refuses_signing_and_account_credentials(self):
        for name in subject.FORBIDDEN_ENV:
            with self.subTest(name=name), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), name: 'SENSITIVE_SENTINEL'}, SOURCE,
                              subject.APPROVED_PIN, 'emulator-5554')

    def test_pair_must_share_source_package_api_pin_and_exact_increasing_versions(self):
        before, after = receipt(1816), receipt(1817)
        subject.validate_pair(before, after, SOURCE, subject.APPROVED_PIN)
        for field, value in [('source_commit', 'b' * 40), ('package', 'com.other.app'),
                             ('api', 'https://other.invalid/api'), ('signer_certificate_sha256', 'b' * 64),
                             ('version_code', 1816), ('version_code', True), ('bytes', 0), ('sha256', 'bad')]:
            with self.subTest(field=field, value=value), self.assertRaises(subject.UpgradeError):
                subject.validate_pair(before, {**after, field: value}, SOURCE, subject.APPROVED_PIN)

    def test_clean_package_is_required_without_a_reset_fallback(self):
        subject.assert_clean_package('')
        for listing in ['package:' + subject.PACKAGE, 'unavailable command']:
            with self.assertRaises(subject.UpgradeError):
                subject.assert_clean_package(listing)

    def test_package_uid_install_time_and_fixture_bytes_must_survive_replace(self):
        before = {'version_code': 1816, 'uid': 10123, 'first_install_time': '2026-11-17 01:00:00'}
        after = {**before, 'version_code': 1817}
        hashes = {'files/theme.txt': 'a' * 64}
        subject.assert_preserved(before, after, hashes, dict(hashes))
        for changed in [{**after, 'uid': 10124}, {**after, 'first_install_time': 'new'},
                        {**after, 'version_code': 1815}]:
            with self.assertRaises(subject.UpgradeError):
                subject.assert_preserved(before, changed, hashes, hashes)
        for actual in [{}, {'files/theme.txt': 'b' * 64}]:
            with self.assertRaises(subject.UpgradeError):
                subject.assert_preserved(before, after, hashes, actual)

    def test_installed_metadata_must_be_unambiguous_and_app_owned(self):
        dump = '  userId=10123\n  versionCode=1816 minSdk=23\n  firstInstallTime=2026-11-17 01:00:00\n'
        self.assertEqual(subject.package_metadata(dump, '10123')['version_code'], 1816)
        for changed, uid in [(dump + ' userId=10123\n', '10123'), (dump, '0'),
                              (dump, '10124'), ('', '10123')]:
            with self.assertRaises(subject.UpgradeError):
                subject.package_metadata(changed, uid)

    def test_api36_aosp_app_id_and_single_user_zero_install_time(self):
        # AOSP android16-release Settings.dumpPackageLPr prints appId globally
        # and firstInstallTime under each user. The dedicated fresh AVD has user0.
        dump = (
            'Packages:\n'
            '  Package [com.aqer.yemen.uat.offline] (1234):\n'
            '    appId=10123\n'
            '    pkg=Package{1234 com.aqer.yemen.uat.offline}\n'
            '    versionCode=1816 minSdk=23 targetSdk=36\n'
            '    User 0: ceDataInode=123 installed=true hidden=false stopped=true\n'
            '      installReason=0\n'
            '      dataDir=/data/user/0/com.aqer.yemen.uat.offline\n'
            '      firstInstallTime=2026-11-17 01:00:00\n'
        )
        self.assertEqual(subject.package_metadata(dump, '10123'), {
            'version_code': 1816, 'uid': 10123,
            'first_install_time': '2026-11-17 01:00:00',
        })
        for extra in ['    appId=10123\n', '    userId=10123\n',
                      '    userId=10124\n', '      firstInstallTime=other\n']:
            with self.subTest(extra=extra), self.assertRaises(subject.UpgradeError):
                subject.package_metadata(dump + extra, '10123')

    def test_paths_cannot_escape_workspace_or_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            file = root / 'input.apk'
            file.write_bytes(b'fixture')
            link = root / 'link.apk'
            link.symlink_to(file)
            with mock.patch.object(subject, 'ROOT', root):
                self.assertEqual(subject.regular_input(str(file)), file)
                for candidate in [link, root / 'missing.apk', root.parent]:
                    with self.assertRaises(subject.UpgradeError):
                        subject.regular_input(str(candidate))

    def test_verifier_checks_actual_pin_and_compiled_origin(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'fixture.apk'
            with zipfile.ZipFile(path, 'w') as archive:
                for abi in subject.ABIS:
                    archive.writestr(f'lib/{abi}/libapp.so', subject.API.encode())
            meta = receipt(1816, path.read_bytes())
            badging = f"package: name='{subject.PACKAGE}' versionCode='1816'\nsdkVersion:'23'\ntargetSdkVersion:'36'"
            signature = 'Signer #1 certificate SHA-256 digest: ' + subject.APPROVED_PIN
            with mock.patch.object(subject, 'command', side_effect=[signature, badging, '']):
                subject.verify_apk(path, meta, Path('/tools'))
            with mock.patch.object(subject, 'command', return_value='Signer #1 certificate SHA-256 digest: ' + 'b' * 64):
                with self.assertRaises(subject.UpgradeError):
                    subject.verify_apk(path, meta, Path('/tools'))
            with zipfile.ZipFile(path, 'w') as archive:
                for abi in subject.ABIS:
                    archive.writestr(f'lib/{abi}/libapp.so', b'wrong origin')
            meta = receipt(1816, path.read_bytes())
            with mock.patch.object(subject, 'command', side_effect=[signature, badging, '']):
                with self.assertRaises(subject.UpgradeError):
                    subject.verify_apk(path, meta, Path('/tools'))

    def test_raw_device_diagnostics_are_not_exposed_as_failure_reason(self):
        error = subprocess.CalledProcessError(20, ['adb', 'SENSITIVE_SENTINEL'],
                                             output='SENSITIVE_SENTINEL', stderr='SENSITIVE_SENTINEL')
        self.assertEqual(subject.failure_reason(error), 'device_or_verifier_command_failed_exit_20')
        self.assertNotIn('SENSITIVE_SENTINEL', subject.failure_reason(error))

    def test_only_validated_public_apk_fields_enter_exported_identity(self):
        public = subject.public_apk_identity({**receipt(1816), 'unexpected': 'SENSITIVE_SENTINEL'})
        self.assertEqual(public, receipt(1816))
        self.assertNotIn('SENSITIVE_SENTINEL', json.dumps(public))


class MockedDeviceRun(unittest.TestCase):
    def run_probe(self, *, existing=False, corrupt=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        inputs = []
        for version in (1816, 1817):
            apk = root / f'{version}.apk'
            apk.write_bytes(b'fixture')
            metadata = root / f'{version}.json'
            metadata.write_text(json.dumps(receipt(version)))
            inputs.extend([str(apk), str(metadata)])
        output = root / 'proof'

        class FakeDevice:
            def __init__(self, serial):
                self.commands = []
                self.replaced = False
                self.launches = 0

            def verify_disposable_root(self):
                self.commands.append(('verify_disposable_root',))

            def adb(self, *values, **kwargs):
                self.commands.append(values)
                if values[:5] == ('shell', 'pm', 'list', 'packages', '--user'):
                    return 'package:' + subject.PACKAGE if existing else ''
                return ''

            def install(self, path, replace=False):
                self.commands.append(('install', '-r' if replace else 'first', str(path)))
                self.replaced = replace

            def snapshot(self):
                return {'version_code': 1817 if self.replaced else 1816, 'uid': 10123,
                        'first_install_time': '2026-11-17 01:00:00'}

            def private_hashes(self, paths):
                values = {key: hashlib.sha256(value).hexdigest()
                          for key, value in subject.synthetic_fixtures().items()}
                if corrupt and self.replaced:
                    values[next(iter(values))] = 'b' * 64
                return values

            def launch(self):
                self.launches += 1

        device = FakeDevice('emulator-5554')
        argv = ['probe', '--baseline-apk', inputs[0], '--baseline-receipt', inputs[1],
                '--upgrade-apk', inputs[2], '--upgrade-receipt', inputs[3],
                '--source', SOURCE, '--certificate', subject.APPROVED_PIN, '--output', str(output)]
        error = None
        with mock.patch.object(subject, 'ROOT', root), mock.patch.object(sys, 'argv', argv), \
                mock.patch.dict(os.environ, {**context(), 'ANDROID_HOME': str(root)}, clear=True), \
                mock.patch.object(subject, 'command', return_value=SOURCE), \
                mock.patch.object(subject, 'verify_apk'), mock.patch.object(subject, 'Device', return_value=device), \
                contextlib.redirect_stdout(io.StringIO()):
            try:
                subject.main()
            except subject.UpgradeError as caught:
                error = caught
        proof = json.loads((output / 'ANDROID_DURABLE_UPGRADE_VERIFICATION.json').read_text())
        return proof, device, error

    def test_replace_preserves_files_without_uninstall_or_clear_and_blocks_both_ip_families(self):
        proof, device, error = self.run_probe()
        self.assertIsNone(error)
        self.assertTrue(proof['passed'])
        self.assertEqual(device.launches, 2)
        self.assertEqual([row[:2] for row in device.commands if row[0] == 'install'],
                         [('install', 'first'), ('install', '-r')])
        self.assertEqual({row[1] for row in device.commands if len(row) > 4 and row[4] == '-I'},
                         {'iptables', 'ip6tables'})
        self.assertFalse(any('uninstall' in row or 'clear' in row for row in device.commands))
        self.assertFalse(proof['keystore_or_signed_in_session_migration_tested'])

    def test_existing_package_fails_before_any_install_and_has_no_reset_fallback(self):
        proof, device, error = self.run_probe(existing=True)
        self.assertIsInstance(error, subject.UpgradeError)
        self.assertFalse(proof['passed'])
        self.assertEqual(proof['failed_stage'], 'prove_package_absent_before_first_install')
        self.assertFalse(any(row[0] == 'install' for row in device.commands))

    def test_changed_private_file_fails_and_preserves_partial_evidence(self):
        proof, device, error = self.run_probe(corrupt=True)
        self.assertIsInstance(error, subject.UpgradeError)
        self.assertFalse(proof['passed'])
        self.assertEqual(proof['failed_stage'], 'replace_install_upgrade_without_data_reset')
        self.assertEqual(proof['reason'], 'app_private_fixture_changed_or_missing')
        self.assertFalse(any('uninstall' in row or 'clear' in row for row in device.commands))


if __name__ == '__main__':
    unittest.main()
