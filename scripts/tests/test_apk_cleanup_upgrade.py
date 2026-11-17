"""Synthetic guards/orchestration/measurement parsing; no real device or key."""
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

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location('cleanup_upgrade', SCRIPTS / 'probe_apk_cleanup_upgrade.py')
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)
SOURCE = 'a' * 40


def context():
    return {'GITHUB_ACTIONS': 'true', 'AQER_APK_CLEANUP_UPGRADE': 'true',
            'GITHUB_REPOSITORY': subject.REPOSITORY, 'GITHUB_REF': subject.BRANCH,
            'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_SHA': SOURCE}


def receipt(version):
    row = {'source_commit': subject.BASE_SOURCE if version == 1817 else SOURCE,
           'package': subject.PACKAGE, 'version_code': version, 'api': subject.API,
           'signer_certificate_sha256': subject.CERTIFICATE,
           'sha256': subject.BASE_SHA256 if version == 1817 else hashlib.sha256(b'fixture').hexdigest(),
           'bytes': subject.BASE_BYTES if version == 1817 else len(b'fixture')}
    if version != 1817:
        row.update({'native_library_compression': 'stored' if version == 1818 else 'deflated',
                    'extract_native_libs': version == 1819})
    return row


class CleanupGuards(unittest.TestCase):
    def test_only_exact_private_cleanup_ci_and_named_emulator_are_allowed(self):
        subject.guard(context(), SOURCE, 'emulator-5554')
        changes = [('GITHUB_ACTIONS', 'false'), ('AQER_APK_CLEANUP_UPGRADE', 'false'),
                   ('GITHUB_REPOSITORY', 'other/repo'), ('GITHUB_REF', 'refs/heads/main'),
                   ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'),
                   ('GITHUB_SHA', 'b' * 40)]
        for key, value in changes:
            with self.subTest(key=key), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), key: value}, SOURCE, 'emulator-5554')
        for serial in ['physical-phone', 'emulator-5556', 'emulator-5554;bad']:
            with self.subTest(serial=serial), self.assertRaises(subject.UpgradeError):
                subject.guard(context(), SOURCE, serial)

    def test_credentials_are_forbidden_even_in_an_otherwise_valid_job(self):
        for name in subject.FORBIDDEN_ENV:
            with self.subTest(name=name), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), name: 'SENSITIVE_SENTINEL'}, SOURCE, 'emulator-5554')

    def test_original_1817_is_pinned_and_both_candidates_share_new_source(self):
        rows = [receipt(v) for v in subject.VERSIONS]
        subject.validate_receipts(rows, SOURCE)
        for index, key, value in [
            (0, 'sha256', 'b' * 64), (0, 'bytes', 123), (0, 'source_commit', SOURCE),
            (1, 'source_commit', subject.BASE_SOURCE), (2, 'version_code', 1818),
            (1, 'version_code', True), (1, 'package', 'other.app'), (2, 'api', 'https://wrong.invalid'),
            (2, 'signer_certificate_sha256', 'b' * 64), (1, 'bytes', 0),
            (1, 'native_library_compression', 'deflated'), (2, 'extract_native_libs', 'true'),
        ]:
            changed = [dict(row) for row in rows]
            changed[index][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(subject.UpgradeError):
                subject.validate_receipts(changed, SOURCE)

    def test_public_identity_never_exports_unexpected_fields(self):
        value = subject.public_identity({**receipt(1819), 'unexpected': 'SENSITIVE_SENTINEL'})
        self.assertEqual(set(value), set(subject.IDENTITY_FIELDS))
        self.assertNotIn('SENSITIVE_SENTINEL', json.dumps(value))

    def test_replaces_preserve_uid_install_time_and_all_fixture_bytes(self):
        before = {'version_code': 1817, 'uid': 10123, 'first_install_time': 'unchanged'}
        hashes = {'file': 'a' * 64}
        for version in (1817, 1818, 1819):
            after = {**before, 'version_code': version}
            subject.assert_preserved(before, after, version, hashes, dict(hashes))
            for invalid in [{**after, 'uid': 10124}, {**after, 'first_install_time': 'new'},
                            {**after, 'version_code': 9999}]:
                with self.assertRaises(subject.UpgradeError):
                    subject.assert_preserved(before, invalid, version, hashes, hashes)
            with self.assertRaises(subject.UpgradeError):
                subject.assert_preserved(before, after, version, hashes, {})

    def test_launch_timings_require_success_and_single_bounded_metrics(self):
        text = 'Status: ok\nTotalTime: 123\nWaitTime: 135\nComplete\n'
        self.assertEqual(subject.parse_launch(text), {'totaltime_ms': 123, 'waittime_ms': 135})
        for invalid in [text.replace('ok', 'timeout'), text + 'TotalTime: 3\n',
                        text.replace('TotalTime: 123\n', ''), text.replace('123', '60001')]:
            with self.assertRaises(subject.UpgradeError):
                subject.parse_launch(invalid)

    def test_measurement_paths_cannot_leave_installed_package(self):
        value = '/data/app/~~abc==/' + subject.PACKAGE + '-def==/lib/x86_64'
        self.assertEqual(subject.owned_code_path(value), value)
        for invalid in ['/data/app/other.app/lib', '/data/user/0/' + subject.PACKAGE,
                        value + '/../bad', value + ';bad', value + '\nBAD']:
            with self.subTest(path=invalid), self.assertRaises(subject.UpgradeError):
                subject.owned_code_path(invalid)
        for invalid in ['-1', '1\n2', str(1024 ** 3 + 1), 'not a size']:
            with self.assertRaises(subject.UpgradeError):
                subject.size_value(invalid)

    def test_workspace_inputs_reject_symlinks_and_missing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            file = root / 'fixture.apk'
            file.write_bytes(b'fixture')
            link = root / 'link.apk'
            link.symlink_to(file)
            with mock.patch.object(subject, 'ROOT', root):
                self.assertEqual(subject.regular_input(file), file)
                for value in [link, root / 'missing.apk', root.parent]:
                    with self.assertRaises(subject.UpgradeError):
                        subject.regular_input(value)

    def test_duplicate_public_receipt_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp) / 'duplicate.json'
            p.write_text('{"sha256":"a","sha256":"b"}')
            with self.assertRaises(subject.UpgradeError):
                subject.read_receipt(p)

    def test_error_output_never_echoes_subprocess_private_diagnostics(self):
        error = subprocess.CalledProcessError(2, ['SENSITIVE_SENTINEL'],
                                             output='SENSITIVE_SENTINEL', stderr='SENSITIVE_SENTINEL')
        self.assertEqual(subject.failure_reason(error), 'device_or_verifier_command_failed_exit_2')


class MeasurementParsing(unittest.TestCase):
    def test_candidate_native_methods_and_payload_are_verified_independently(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'candidate.apk'
            native = {f'lib/{abi}/{name}': subject.API.encode() if name == 'libapp.so' else b'native-fixture'
                      for abi in subject.ABIS for name in subject.NATIVE_FAMILIES}
            def write(method, extra=False):
                with zipfile.ZipFile(path, 'w', compression=method) as archive:
                    for name, payload in native.items():
                        archive.writestr(name, payload)
                    if extra:
                        archive.writestr('lib/x86_64/libsqlite3.so', b'forbidden')
                row = receipt(1819)
                row.update({'bytes': path.stat().st_size, 'sha256': subject.digest(path),
                            'native_library_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in native.items()},
                            'native_library_methods': {name: method for name in native}})
                return row
            signature = 'Signer #1 certificate SHA-256 digest: ' + subject.CERTIFICATE
            badging = f"package: name='{subject.PACKAGE}' versionCode='1819'\nsdkVersion:'23'\ntargetSdkVersion:'36'"
            row = write(zipfile.ZIP_DEFLATED)
            with mock.patch.object(subject, 'command', side_effect=[signature, badging, '']), mock.patch.object(subject, 'elf'):
                result = subject.verify_apk(path, row, Path('/tools'))
            self.assertEqual(set(result['native_methods'].values()), {zipfile.ZIP_DEFLATED})
            for method, extra in [(zipfile.ZIP_STORED, False), (zipfile.ZIP_DEFLATED, True)]:
                row = write(method, extra)
                with self.subTest(method=method, extra=extra), \
                        mock.patch.object(subject, 'command', side_effect=[signature, badging, '']), \
                        mock.patch.object(subject, 'elf'), self.assertRaises(subject.UpgradeError):
                    subject.verify_apk(path, row, Path('/tools'))

    def test_compressed_libraries_are_measured_and_hash_bound_to_installer(self):
        device = subject.Device('emulator-5554')
        base = '/data/app/~~abc==/' + subject.PACKAGE + '-def=='
        native = base + '/lib'
        expected = {'lib/x86_64/' + name: hashlib.sha256(name.encode()).hexdigest()
                    for name in subject.NATIVE_FAMILIES}
        def adb(*values, **kwargs):
            if values[:3] == ('shell', 'pm', 'path'):
                return 'package:' + base + '/base.apk'
            if values[:3] == ('shell', 'dumpsys', 'package'):
                return 'legacyNativeLibraryDir=' + native + '\nextractNativeLibs=true\nprimaryCpuAbi=x86_64\n'
            if values[:2] == ('shell', 'test'):
                return ''
            if values[:2] == ('shell', 'find'):
                return '\n'.join(native + '/x86_64/' + name for name in sorted(subject.NATIVE_FAMILIES))
            if values[:2] == ('shell', 'sha256sum'):
                name = Path(values[-1]).name
                return expected['lib/x86_64/' + name] + '  path'
            if values[:2] == ('shell', 'stat'):
                return '100' if values[-1].endswith('/base.apk') else '20'
            raise AssertionError(values)
        with mock.patch.object(device, 'adb', side_effect=adb):
            result = device.code_footprint({**receipt(1819), 'bytes': 100}, expected)
        self.assertEqual(result['base_apk_bytes'], 100)
        self.assertEqual(result['extracted_native_library_bytes'], 80)
        self.assertEqual(result['package_code_plus_extracted_native_bytes'], 180)
        self.assertFalse('total_storage_bytes' in result)
        with mock.patch.object(device, 'adb', side_effect=adb), self.assertRaises(subject.UpgradeError):
            device.code_footprint({**receipt(1819), 'bytes': 100}, {key: 'b' * 64 for key in expected})

    def test_false_extraction_flag_cannot_be_claimed_for_compressed_version(self):
        device = subject.Device('emulator-5554')
        base = '/data/app/~~abc==/' + subject.PACKAGE + '-def=='
        answers = ['package:' + base + '/base.apk', '100',
                   'legacyNativeLibraryDir=' + base + '/lib\nextractNativeLibs=false\nprimaryCpuAbi=x86_64\n']
        with mock.patch.object(device, 'adb', side_effect=answers), self.assertRaises(subject.UpgradeError):
            device.code_footprint({**receipt(1819), 'bytes': 100}, {})


class MockedThreeVersionRun(unittest.TestCase):
    def run_probe(self, *, existing=False, corrupt=False):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        args = ['probe']
        for role, version in zip(('baseline', 'clean', 'compressed'), subject.VERSIONS):
            apk = root / (str(version) + '.apk')
            apk.write_bytes(b'fixture')
            info = root / (str(version) + '.json')
            info.write_text(json.dumps(receipt(version)))
            args += ['--' + role + '-apk', str(apk), '--' + role + '-receipt', str(info)]
        args += ['--source', SOURCE, '--output', str(root / 'proof')]
        class FakeDevice:
            def __init__(self):
                self.commands, self.version, self.launches = [], 1817, []
            def adb(self, *values, **kwargs):
                self.commands.append(values)
                if values[:5] == ('shell', 'pm', 'list', 'packages', '--user'):
                    return 'package:' + subject.PACKAGE if existing else ''
                return ''
            def verify_disposable_root(self):
                self.commands.append(('verify_disposable',))
            def install(self, path, replace=False):
                self.version = int(Path(path).stem)
                self.commands.append(('install', '-r' if replace else 'first', str(path)))
                return 100.5
            def snapshot(self):
                return {'version_code': self.version, 'uid': 10123, 'first_install_time': 'same'}
            def private_hashes(self, paths):
                values = {name: hashlib.sha256(data).hexdigest()
                          for name, data in subject.synthetic_fixtures().items()}
                if corrupt and self.version == 1819:
                    values[next(iter(values))] = 'b' * 64
                return values
            def cold_launches(self):
                self.launches.append(self.version)
                return {'runs': [{}, {}, {}], 'median_total_time_ms': 100}
            def code_footprint(self, meta, native):
                return {'package_code_plus_extracted_native_bytes': 100,
                        'base_apk_bytes': meta['bytes'], 'extracted_native_library_bytes': 0}
        device = FakeDevice()
        inspect = {'native_sha256': {'lib/x86_64/libflutter.so': 'a' * 64}, 'native_methods': {}}
        error = None
        with mock.patch.object(subject, 'ROOT', root), mock.patch.object(sys, 'argv', args), \
                mock.patch.dict(os.environ, {**context(), 'ANDROID_HOME': str(root)}, clear=True), \
                mock.patch.object(subject, 'command', return_value=SOURCE), \
                mock.patch.object(subject, 'verify_apk', return_value=inspect), \
                mock.patch.object(subject, 'write_fixtures'), \
                mock.patch.object(subject, 'Device', return_value=device), \
                contextlib.redirect_stdout(io.StringIO()):
            try:
                subject.main()
            except subject.UpgradeError as caught:
                error = caught
        proof = json.loads((root / 'proof/ANDROID_APK_CLEANUP_VERIFICATION.json').read_text())
        return proof, device, error

    def test_three_version_chain_retains_files_and_never_resets_or_uninstalls(self):
        proof, device, error = self.run_probe()
        self.assertIsNone(error)
        self.assertTrue(proof['passed'])
        self.assertEqual(device.launches, [1817, 1818, 1819])
        self.assertEqual([row[1] for row in device.commands if row[0] == 'install'], ['first', '-r', '-r'])
        self.assertFalse(any('uninstall' in row or 'clear' in row for row in device.commands))
        self.assertEqual(set(proof['measurements']), {'1817', '1818', '1819'})
        self.assertFalse(proof['physical_phone_acceptance'])
        self.assertFalse(proof['performance_regression_acceptance'])
        self.assertEqual({row[1] for row in device.commands if len(row) > 4 and row[4] == '-I'}, {'iptables', 'ip6tables'})

    def test_existing_package_blocks_first_install_without_reset_fallback(self):
        proof, device, error = self.run_probe(existing=True)
        self.assertIsInstance(error, subject.UpgradeError)
        self.assertFalse(proof['passed'])
        self.assertFalse(any(row[0] == 'install' for row in device.commands))

    def test_corruption_in_second_update_keeps_failed_receipt(self):
        proof, device, error = self.run_probe(corrupt=True)
        self.assertIsInstance(error, subject.UpgradeError)
        self.assertFalse(proof['passed'])
        self.assertEqual(proof['failed_stage'], 'replace_install_1819')
        self.assertEqual(proof['reason'], 'synthetic_private_file_changed_or_missing')
        self.assertFalse(any('uninstall' in row or 'clear' in row for row in device.commands))


if __name__ == '__main__':
    unittest.main()
