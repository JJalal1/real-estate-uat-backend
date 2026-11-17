"""Synthetic guards and orchestration only; no ADB, network, key or Flutter."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    'native_packaging_observation', SCRIPTS / 'probe_native_packaging_observation.py')
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)
HARNESS = 'a' * 40


def context():
    return {'GITHUB_ACTIONS': 'true', 'AQER_NATIVE_PACKAGING_OBSERVATION': 'true',
            'GITHUB_REPOSITORY': subject.REPOSITORY, 'GITHUB_REF': subject.BRANCH,
            'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_SHA': HARNESS}


def receipt(version):
    return {'source_commit': subject.ARTIFACT_SOURCE, 'package': subject.PACKAGE,
            'version_code': version, 'api': subject.API,
            'signer_certificate_sha256': subject.CERTIFICATE,
            'sha256': subject.ARTIFACTS[version]['sha256'],
            'bytes': subject.ARTIFACTS[version]['bytes'],
            'native_library_compression': 'stored' if version == 1818 else 'deflated',
            'extract_native_libs': version == 1819}


def hashes():
    return {name: hashlib.sha256(data).hexdigest()
            for name, data in subject.synthetic_fixtures().items()}


class FakeDevice:
    def __init__(self, *, corrupt_after=None, fail_force_stop=False, fail_ipv6=False):
        self.events, self.version, self.starts = [], None, 0
        self.corrupt_after = corrupt_after
        self.fail_force_stop, self.fail_ipv6 = fail_force_stop, fail_ipv6

    def verify_disposable_root(self):
        self.events.append(('verify_disposable',))

    def require_absent(self):
        self.events.append(('require_absent',))
        if self.version is not None:
            raise subject.UpgradeError('fresh_synthetic_group_requires_package_absent')

    def install(self, path, replace=False):
        self.version = int(Path(path).stem)
        self.starts = 0
        self.events.append(('install', self.version, replace))
        return 123.456

    def snapshot(self):
        return {'version_code': self.version, 'uid': 10123,
                'first_install_time': 'SYNTHETIC-' + str(self.version)}

    def private_hashes(self, fixtures):
        result = hashes()
        if self.corrupt_after is not None and self.starts >= self.corrupt_after:
            result[next(iter(result))] = 'b' * 64
        return result

    def code_footprint(self, row, native):
        self.events.append(('footprint', self.version))
        extra = 35000000 if self.version == 1819 else 0
        return {'base_apk_bytes': row['bytes'], 'extracted_native_library_bytes': extra,
                'package_code_plus_extracted_native_bytes': row['bytes'] + extra}

    def start_once(self):
        self.starts += 1
        self.events.append(('start', self.version, self.starts))
        return {'totaltime_ms': self.starts * 10, 'waittime_ms': self.starts * 10 + 2,
                'host_wall_ms': self.starts * 10 + 4.5}

    def adb(self, *args, **kwargs):
        self.events.append(args)
        if self.fail_force_stop and args[:3] == ('shell', 'am', 'force-stop'):
            raise subject.UpgradeError('synthetic_stop_failure')
        if self.fail_ipv6 and args[:5] == ('shell', 'ip6tables', '-w', '5', '-I'):
            raise subject.UpgradeError('synthetic_rule_failure')
        return ''

    def uninstall_synthetic(self, expected):
        if self.snapshot() != expected:
            raise subject.UpgradeError('only_current_synthetic_group_may_be_uninstalled')
        self.events.append(('uninstall_synthetic', self.version))
        self.version = None
        return 20.25


class ObservationGuards(unittest.TestCase):
    def test_exact_ci_context_requires_separate_harness_and_pinned_artifacts(self):
        subject.guard(context(), HARNESS, subject.ARTIFACT_SOURCE, 'emulator-5554')
        for key, value in [('GITHUB_ACTIONS', 'false'),
                           ('AQER_NATIVE_PACKAGING_OBSERVATION', 'false'),
                           ('GITHUB_REPOSITORY', 'other/repo'), ('GITHUB_REF', 'refs/heads/main'),
                           ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'),
                           ('GITHUB_SHA', subject.ARTIFACT_SOURCE)]:
            with self.subTest(key=key), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), key: value}, HARNESS, subject.ARTIFACT_SOURCE,
                              'emulator-5554')
        for harness, artifact, serial in [
                (subject.ARTIFACT_SOURCE, subject.ARTIFACT_SOURCE, 'emulator-5554'),
                (HARNESS, HARNESS, 'emulator-5554'), (HARNESS, subject.ARTIFACT_SOURCE, 'phone'),
                (HARNESS, subject.ARTIFACT_SOURCE, 'emulator-5556'),
                ('A' * 40, subject.ARTIFACT_SOURCE, 'emulator-5554')]:
            with self.subTest(harness=harness, artifact=artifact, serial=serial), \
                    self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), 'GITHUB_SHA': harness}, harness, artifact, serial)

    def test_account_and_signing_material_is_forbidden(self):
        for name in subject.FORBIDDEN_ENV:
            with self.subTest(name=name), self.assertRaises(subject.UpgradeError):
                subject.guard({**context(), name: 'PRIVATE_SENTINEL'}, HARNESS,
                              subject.ARTIFACT_SOURCE, 'emulator-5554')

    def test_receipts_pin_original_bytes_source_identity_and_packaging(self):
        rows = [receipt(1818), receipt(1819)]
        subject.validate_receipts(rows, subject.ARTIFACT_SOURCE)
        for index, key, value in [
                (0, 'source_commit', HARNESS), (1, 'sha256', 'b' * 64), (0, 'bytes', 1),
                (0, 'bytes', True), (1, 'version_code', True), (1, 'version_code', 1818),
                (0, 'package', 'other.app'), (1, 'api', 'https://wrong.invalid'),
                (0, 'signer_certificate_sha256', 'b' * 64),
                (0, 'native_library_compression', 'deflated'), (1, 'extract_native_libs', 'true')]:
            changed = [dict(row) for row in rows]
            changed[index][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(subject.UpgradeError):
                subject.validate_receipts(changed, subject.ARTIFACT_SOURCE)
        for invalid in [[], rows[:1], rows[::-1], rows + rows[:1]]:
            with self.assertRaises(subject.UpgradeError):
                subject.validate_receipts(invalid, subject.ARTIFACT_SOURCE)
        with self.assertRaises(subject.UpgradeError):
            subject.validate_receipts(rows, HARNESS)

    def test_all_adb_commands_are_capped_at_sixty_seconds(self):
        device = subject.ObservationDevice('emulator-5554')
        with mock.patch.object(subject.Device, 'adb', return_value='') as adb:
            device.adb('install', 'fixture.apk', timeout=180)
            self.assertEqual(adb.call_args.kwargs['timeout'], 60)
            device.adb('shell', 'id', timeout=7)
            self.assertEqual(adb.call_args.kwargs['timeout'], 7)

    def test_named_api36_x64_disposable_root_is_required(self):
        device = subject.ObservationDevice('emulator-5554')
        def adb(*args, **kwargs):
            return {('shell', 'getprop', 'ro.kernel.qemu'): '1',
                    ('shell', 'getprop', 'ro.build.version.sdk'): '36',
                    ('emu', 'avd', 'name'): subject.AVD_NAME + '\nOK',
                    ('shell', 'getprop', 'ro.product.cpu.abi'): 'x86_64',
                    ('shell', 'id', '-u'): '0'}.get(args, '')
        with mock.patch.object(device, 'adb', side_effect=adb) as calls:
            device.verify_disposable_root()
        self.assertIn(mock.call('root'), calls.call_args_list)
        for bad in [('shell', 'getprop', 'ro.kernel.qemu'),
                    ('shell', 'getprop', 'ro.build.version.sdk'), ('emu', 'avd', 'name'),
                    ('shell', 'getprop', 'ro.product.cpu.abi'), ('shell', 'id', '-u')]:
            with self.subTest(command=bad), \
                    mock.patch.object(device, 'adb', side_effect=lambda *a, **kw: 'wrong' if a == bad else adb(*a)), \
                    self.assertRaises(subject.UpgradeError):
                device.verify_disposable_root()

    def test_uninstall_checks_exact_current_synthetic_identity(self):
        device = subject.ObservationDevice('emulator-5554')
        expected = {'uid': 10123, 'version_code': 1818, 'first_install_time': 'synthetic'}
        with mock.patch.object(device, 'snapshot', return_value={**expected, 'uid': 10124}), \
                mock.patch.object(device, 'adb') as adb, self.assertRaises(subject.UpgradeError):
            device.uninstall_synthetic(expected)
        adb.assert_not_called()
        with mock.patch.object(device, 'snapshot', return_value=expected), \
                mock.patch.object(device, 'adb', side_effect=['Success', '']) as adb:
            self.assertGreaterEqual(device.uninstall_synthetic(expected), 0)
        self.assertEqual(adb.call_args_list[0], mock.call('uninstall', subject.PACKAGE))


class ObservationOrchestration(unittest.TestCase):
    def run_group(self, **kwargs):
        device, proof = FakeDevice(**kwargs), {'groups': [], 'cleanup_failures': []}
        with mock.patch.object(subject, 'write_fixtures',
                               side_effect=lambda *a: device.events.append(('fixtures',))):
            row = subject.run_group(device, 1818, receipt(1818), Path('1818.apk'),
                                    {'native_sha256': {}}, 1, proof)
        return device, proof, row

    def test_fresh_group_isolates_both_families_before_warmup_and_five_starts(self):
        device, proof, row = self.run_group()
        self.assertEqual(device.events[0], ('require_absent',))
        self.assertEqual(device.events[1], ('install', 1818, False))
        first_start = next(i for i, event in enumerate(device.events) if event[0] == 'start')
        for family in ('iptables', 'ip6tables'):
            verified = next(i for i, event in enumerate(device.events)
                            if event[:5] == ('shell', family, '-w', '5', '-C'))
            self.assertLess(verified, first_start)
        self.assertEqual([event[2] for event in device.events if event[0] == 'start'], list(range(1, 7)))
        self.assertEqual(row['warmup']['totaltime_ms'], 10)
        self.assertEqual([run['totaltime_ms'] for run in row['runs']], [20, 30, 40, 50, 60])
        self.assertEqual(row['median_total_time_ms'], 40)
        self.assertEqual(row['synthetic_private_fixture_sha256'], hashes())
        self.assertTrue(row['synthetic_fixture_and_identity_preserved_within_group'])
        self.assertEqual(proof['groups'], [row])
        self.assertEqual(proof['cleanup_failures'], [])
        self.assertFalse(any('clear' in event or event[0] == 'uninstall' for event in device.events))

    def test_fixture_corruption_fails_and_stops_before_removing_network_rules(self):
        device, proof = FakeDevice(corrupt_after=1), {'groups': [], 'cleanup_failures': []}
        with mock.patch.object(subject, 'write_fixtures'), self.assertRaises(subject.UpgradeError):
            subject.run_group(device, 1818, receipt(1818), Path('1818.apk'),
                              {'native_sha256': {}}, 1, proof)
        stop = device.events.index(('shell', 'am', 'force-stop', subject.PACKAGE))
        deletions = [i for i, event in enumerate(device.events)
                     if len(event) > 4 and event[4] == '-D']
        self.assertEqual(len(deletions), 2)
        self.assertTrue(all(i > stop for i in deletions))
        self.assertEqual(proof['groups'][0]['runs'], [])

    def test_failed_force_stop_retains_rejection_and_fails_the_group(self):
        device, proof = FakeDevice(fail_force_stop=True), {'groups': [], 'cleanup_failures': []}
        with mock.patch.object(subject, 'write_fixtures'), self.assertRaises(subject.UpgradeError):
            subject.run_group(device, 1818, receipt(1818), Path('1818.apk'),
                              {'native_sha256': {}}, 1, proof)
        self.assertEqual(proof['cleanup_failures'][0]['step'], 'force_stop')
        self.assertFalse(any(len(event) > 4 and event[4] == '-D' for event in device.events))

    def test_failed_ipv6_isolation_prevents_every_launch(self):
        device, proof = FakeDevice(fail_ipv6=True), {'groups': [], 'cleanup_failures': []}
        with mock.patch.object(subject, 'write_fixtures') as fixtures, \
                self.assertRaises(subject.UpgradeError):
            subject.run_group(device, 1818, receipt(1818), Path('1818.apk'),
                              {'native_sha256': {}}, 1, proof)
        fixtures.assert_not_called()
        self.assertFalse(any(event[0] == 'start' for event in device.events))

    def test_complete_main_runs_abba_with_three_explicit_synthetic_uninstalls(self):
        with tempfile.TemporaryDirectory() as temp:
            root, args = Path(temp), ['probe']
            for role, version in [('clean', 1818), ('compressed', 1819)]:
                apk, info = root / f'{version}.apk', root / f'{version}.json'
                apk.write_bytes(b'SYNTHETIC: no installer')
                info.write_text(json.dumps(receipt(version)))
                args += ['--' + role + '-apk', str(apk), '--' + role + '-receipt', str(info)]
            output = root / 'proof'
            args += ['--artifact-source', subject.ARTIFACT_SOURCE, '--harness-source', HARNESS,
                     '--output', str(output)]
            device = FakeDevice()
            with mock.patch.object(subject, 'ROOT', root), \
                    mock.patch.object(subject, 'regular_input', side_effect=lambda p: Path(p)), \
                    mock.patch.object(subject, 'command', return_value=HARNESS), \
                    mock.patch.object(subject, 'verify_apk', return_value={'native_sha256': {}}), \
                    mock.patch.object(subject, 'write_fixtures'), \
                    mock.patch.object(subject, 'ObservationDevice', return_value=device), \
                    mock.patch.object(sys, 'argv', args), \
                    mock.patch.dict(os.environ, {**context(), 'ANDROID_HOME': str(root)}, clear=True), \
                    contextlib.redirect_stdout(io.StringIO()):
                subject.main()
            proof = json.loads((output / 'NATIVE_PACKAGING_OBSERVATION.json').read_text())
        self.assertTrue(proof['passed'])
        self.assertEqual(proof['harness_source_commit'], HARNESS)
        self.assertEqual(proof['artifact_source_commit'], subject.ARTIFACT_SOURCE)
        self.assertEqual([event[1] for event in device.events if event[0] == 'install'], list(subject.ORDER))
        self.assertTrue(all(event[2] is False for event in device.events if event[0] == 'install'))
        self.assertEqual([event[1] for event in device.events if event[0] == 'uninstall_synthetic'], [1818, 1819, 1819])
        self.assertEqual(proof['explicit_fresh_synthetic_uninstalls_between_groups'], 3)
        self.assertEqual(sum(event[0] == 'start' for event in device.events), 24)
        self.assertEqual(proof['summary']['1818']['measured_starts'], 10)
        for name in ('ordinary_upgrade_preservation_proof_replaced', 'physical_phone_acceptance',
                     'map_tiles_or_gestures_tested', 'performance_regression_acceptance',
                     'performance_pass_claim', 'real_account_data_used', 'live_business_api_used',
                     'signing_material_used'):
            self.assertIs(proof[name], False)

    def test_summary_uses_pooled_ten_runs_and_requires_exact_abba_and_run_count(self):
        groups = []
        for index, version in enumerate(subject.ORDER, 1):
            values = [index * 10 + offset for offset in range(5)]
            groups.append({'group_index': index, 'version_code': version,
                           'install_host_wall_ms': index * 100.25,
                           'median_total_time_ms': statistics.median(values),
                           'code_footprint': {'package_code_plus_extracted_native_bytes': version},
                           'runs': [{'totaltime_ms': n, 'waittime_ms': n + 1,
                                     'host_wall_ms': n + 2.5} for n in values]})
        result = subject.summarize(groups)
        self.assertEqual(result['1818']['group_indices'], [1, 4])
        self.assertEqual(result['1819']['group_indices'], [2, 3])
        self.assertEqual(result['1818']['median_total_time_ms'], 27)
        self.assertEqual(result['1819']['median_total_time_ms'], 27)
        self.assertEqual(result['compressed_minus_stored']['median_total_time_ms'], 0)
        for invalid in [groups[:-1], [groups[1], groups[0], *groups[2:]],
                        [{**groups[0], 'runs': groups[0]['runs'][:4]}, *groups[1:]]]:
            with self.assertRaises(subject.UpgradeError):
                subject.summarize(invalid)


if __name__ == '__main__':
    unittest.main()
