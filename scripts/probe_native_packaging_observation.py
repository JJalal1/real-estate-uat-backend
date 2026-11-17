#!/usr/bin/env python3
"""Observe pinned 1818/1819 packaging in four fresh, counterbalanced groups.

This is a new keyless measurement harness, not another APK build or an update
preservation proof. The unchanged historical APK source is distinct from the
current harness source. Fresh synthetic installs are explicitly removed between
ABBA groups; each gets one warmup and five measured force-stopped starts. No
timing threshold or physical-phone performance acceptance is inferred.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import time

from probe_apk_cleanup_upgrade import (
    API, ACTIVITY, BRANCH, CERTIFICATE, Device, FORBIDDEN_ENV, PACKAGE, REPOSITORY,
    ROOT, UpgradeError, command, failure_reason, parse_launch, public_identity,
    read_receipt, regular_input, synthetic_fixtures, verify_apk, write_fixtures,
)

ARTIFACT_SOURCE = 'c0629a48c2431748b5d5ac1b5d6edb9318946fa8'
SOURCE_RUN_ID = 44156549567
ARTIFACTS = {
    1818: {'id': 14363025905, 'sha256': '9a3923693cf8c278c80bae8a414833f92107fb887df07097f599f1b92fed4ca4',
           'bytes': 104022511},
    1819: {'id': 14362467229, 'sha256': '13af0b61df2266735030718d8f2354e332ae4d7a2e1f67acfef1b222c3644fdb',
           'bytes': 45190809},
}
ORDER = (1818, 1819, 1819, 1818)
AVD_NAME = 'aqer-native-packaging-observation'
STARTS_PER_GROUP = 5


def guard(env, harness_source, artifact_source, serial):
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('AQER_NATIVE_PACKAGING_OBSERVATION') == 'true' and
            env.get('GITHUB_REPOSITORY') == REPOSITORY and env.get('GITHUB_REF') == BRANCH and
            env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[1-9][0-9]*', env.get('GITHUB_RUN_ID', '')) and
            re.fullmatch(r'[a-f0-9]{40}', harness_source) and harness_source == env.get('GITHUB_SHA') and
            harness_source != ARTIFACT_SOURCE and artifact_source == ARTIFACT_SOURCE and
            serial == 'emulator-5554'):
        raise UpgradeError('explicit_separate_harness_and_pinned_artifact_context_required')
    if any(env.get(name) for name in FORBIDDEN_ENV):
        raise UpgradeError('signing_or_account_material_forbidden_in_observation')


def validate_receipts(receipts, artifact_source):
    if artifact_source != ARTIFACT_SOURCE or len(receipts) != 2:
        raise UpgradeError('exact_two_historical_packaging_receipts_required')
    for receipt, version in zip(receipts, (1818, 1819)):
        if (receipt.get('source_commit') != ARTIFACT_SOURCE or receipt.get('package') != PACKAGE or
                type(receipt.get('version_code')) is not int or receipt['version_code'] != version or
                receipt.get('api') != API or receipt.get('signer_certificate_sha256') != CERTIFICATE or
                receipt.get('sha256') != ARTIFACTS[version]['sha256'] or
                type(receipt.get('bytes')) is not int or receipt['bytes'] != ARTIFACTS[version]['bytes'] or
                receipt.get('native_library_compression') != ('stored' if version == 1818 else 'deflated') or
                receipt.get('extract_native_libs') is not (version == 1819)):
            raise UpgradeError('exact_historical_apk_identity_and_packaging_required')


class ObservationDevice(Device):
    def adb(self, *values, timeout=60):
        # Every individual device command, including wait-for-device/install,
        # has a hard deadline. No sleep or readiness wait exceeds three seconds.
        return super().adb(*values, timeout=min(timeout, 60))

    def verify_disposable_root(self):
        self.adb('wait-for-device')
        if (self.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
                self.adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
                self.adb('emu', 'avd', 'name').splitlines()[0] != AVD_NAME or
                self.adb('shell', 'getprop', 'ro.product.cpu.abi') != 'x86_64'):
            raise UpgradeError('exact_observation_api36_x64_avd_required')
        self.adb('root')
        self.adb('wait-for-device')
        if self.adb('shell', 'id', '-u') != '0':
            raise UpgradeError('rooted_disposable_observation_emulator_required')

    def require_absent(self):
        if self.adb('shell', 'pm', 'list', 'packages', '--user', '0', PACKAGE).strip():
            raise UpgradeError('fresh_synthetic_group_requires_package_absent')

    def uninstall_synthetic(self, expected):
        # Only a package just installed by this guarded harness may be removed.
        # A mismatch stops the run; there is no uninstall/reset retry fallback.
        if self.snapshot() != expected:
            raise UpgradeError('only_current_synthetic_group_may_be_uninstalled')
        start = time.perf_counter()
        if self.adb('uninstall', PACKAGE).strip() != 'Success':
            raise UpgradeError('synthetic_group_uninstall_failed')
        self.require_absent()
        return round((time.perf_counter() - start) * 1000, 3)

    def start_once(self):
        self.adb('shell', 'am', 'force-stop', PACKAGE)
        self.adb('logcat', '-c')
        start = time.perf_counter()
        output = self.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/' + ACTIVITY)
        row = parse_launch(output)
        row['host_wall_ms'] = round((time.perf_counter() - start) * 1000, 3)
        for _ in range(3):
            if not self.adb('shell', 'pidof', PACKAGE):
                raise UpgradeError('ordinary_observation_app_did_not_remain_running')
            time.sleep(1)
        if PACKAGE in self.adb('logcat', '-d', '-b', 'crash'):
            raise UpgradeError('ordinary_observation_app_crashed_after_launch')
        return row


def check_group_identity(device, identity, fixtures, hashes):
    if device.snapshot() != identity or device.private_hashes(fixtures) != hashes:
        raise UpgradeError('synthetic_group_identity_or_fixture_bytes_changed')


def run_group(device, version, receipt, apk, inspected, group_index, proof):
    device.require_absent()
    install_ms = device.install(apk, replace=False)
    identity = device.snapshot()
    if identity['version_code'] != version or not 10000 <= identity['uid'] <= 99999:
        raise UpgradeError('fresh_group_installed_version_or_uid_mismatch')
    row = {'group_index': group_index, 'version_code': version, 'fresh_install': True,
           'install_host_wall_ms': install_ms, 'installed_identity': identity, 'runs': []}
    proof['groups'].append(row)
    rules, cleanup_failures = [], []
    failed = False
    try:
        for family in ('iptables', 'ip6tables'):
            rules.append(family)
            device.adb('shell', family, '-w', '5', '-I', 'OUTPUT', '1', '-m', 'owner',
                       '--uid-owner', str(identity['uid']), '-j', 'REJECT')
            device.adb('shell', family, '-w', '5', '-C', 'OUTPUT', '-m', 'owner',
                       '--uid-owner', str(identity['uid']), '-j', 'REJECT')
        row['network_isolation'] = 'IPv4 and IPv6 app-UID OUTPUT REJECT rules verified before first launch.'
        fixtures = synthetic_fixtures()
        hashes = {key: hashlib.sha256(value).hexdigest() for key, value in fixtures.items()}
        write_fixtures(device, identity['uid'], fixtures)
        check_group_identity(device, identity, fixtures, hashes)
        row['synthetic_private_fixture_sha256'] = hashes
        row['code_footprint'] = device.code_footprint(receipt, inspected['native_sha256'])
        row['warmup'] = device.start_once()
        check_group_identity(device, identity, fixtures, hashes)
        for _ in range(STARTS_PER_GROUP):
            row['runs'].append(device.start_once())
            check_group_identity(device, identity, fixtures, hashes)
        for raw, key in (('totaltime_ms', 'median_total_time_ms'), ('waittime_ms', 'median_wait_time_ms'),
                         ('host_wall_ms', 'median_host_wall_ms')):
            row[key] = statistics.median(run[raw] for run in row['runs'])
        row['synthetic_fixture_and_identity_preserved_within_group'] = True
    except Exception:
        failed = True
        raise
    finally:
        stopped = False
        try:
            device.adb('shell', 'am', 'force-stop', PACKAGE)
            stopped = True
        except Exception as error:
            cleanup_failures.append({'group_index': group_index, 'step': 'force_stop', 'reason': failure_reason(error)})
        # Retain network rejection until emulator destruction if force-stop fails.
        if stopped:
            for family in reversed(rules):
                try:
                    device.adb('shell', family, '-w', '5', '-D', 'OUTPUT', '-m', 'owner',
                               '--uid-owner', str(identity['uid']), '-j', 'REJECT')
                except Exception as error:
                    cleanup_failures.append({'group_index': group_index, 'step': family, 'reason': failure_reason(error)})
        proof['cleanup_failures'].extend(cleanup_failures)
        if cleanup_failures and not failed:
            raise UpgradeError('observation_group_cleanup_failed')
    return row


def summarize(groups):
    if len(groups) != len(ORDER) or [row['version_code'] for row in groups] != list(ORDER):
        raise UpgradeError('complete_four_group_abba_observation_required')
    result = {}
    for version in (1818, 1819):
        rows = [row for row in groups if row['version_code'] == version]
        if any(len(row['runs']) != STARTS_PER_GROUP for row in rows):
            raise UpgradeError('exact_five_measured_starts_per_group_required')
        starts = [run for row in rows for run in row['runs']]
        result[str(version)] = {
            'group_indices': [row['group_index'] for row in rows], 'measured_starts': len(starts),
            'fresh_install_host_wall_ms': [row['install_host_wall_ms'] for row in rows],
            'group_median_total_time_ms': [row['median_total_time_ms'] for row in rows],
            'partial_code_native_bytes': [row['code_footprint']['package_code_plus_extracted_native_bytes'] for row in rows],
            **{key: statistics.median(run[raw] for run in starts) for raw, key in (
                ('totaltime_ms', 'median_total_time_ms'), ('waittime_ms', 'median_wait_time_ms'),
                ('host_wall_ms', 'median_host_wall_ms'))},
        }
    old, new = result['1818']['median_total_time_ms'], result['1819']['median_total_time_ms']
    result['compressed_minus_stored'] = {
        'median_total_time_ms': new - old,
        'median_total_time_percent': (new - old) / old * 100 if old else None,
        'scope': 'Descriptive pooled medians from 10 starts per version, grouped ABBA after one warmup per fresh install. Not a statistical significance test, phone result or performance pass/fail.'}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for role in ('clean', 'compressed'):
        parser.add_argument('--' + role + '-apk', required=True)
        parser.add_argument('--' + role + '-receipt', required=True)
    parser.add_argument('--artifact-source', required=True)
    parser.add_argument('--harness-source', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', default='native-packaging-observation-proof')
    args = parser.parse_args()
    guard(os.environ, args.harness_source, args.artifact_source, args.serial)
    if command('git', 'rev-parse', 'HEAD', timeout=30) != args.harness_source:
        raise UpgradeError('checked_out_observation_harness_source_mismatch')
    inputs = [regular_input(getattr(args, role + '_' + kind))
              for role in ('clean', 'compressed') for kind in ('apk', 'receipt')]
    if len(set(inputs)) != 4:
        raise UpgradeError('distinct_two_apks_and_receipts_required')
    output = Path(args.output).absolute()
    if output != output.resolve() or not output.is_relative_to(ROOT):
        raise UpgradeError('regular_workspace_observation_output_required')
    output.mkdir(mode=0o700)
    proof = {
        'passed': False, 'status': 'failed', 'source_commit': args.harness_source,
        'harness_source_commit': args.harness_source, 'artifact_source_commit': ARTIFACT_SOURCE,
        'harness_run_id': int(os.environ['GITHUB_RUN_ID']), 'source_apk_run_id': SOURCE_RUN_ID,
        'source_apk_artifact_ids': {str(version): ARTIFACTS[version]['id'] for version in (1818, 1819)},
        'package': PACKAGE, 'signer_certificate_sha256': CERTIFICATE, 'android_api': 36,
        'environment': 'disposable_rooted_x86_64_emulator', 'avd_name': AVD_NAME,
        'order': list(ORDER), 'warmups_per_group': 1, 'measured_starts_per_group': STARTS_PER_GROUP,
        'groups': [], 'cleanup_failures': [], 'explicit_fresh_synthetic_uninstalls_between_groups': 0,
        'ordinary_upgrade_preservation_proof_replaced': False,
        'real_account_data_used': False, 'live_business_api_used': False, 'signing_material_used': False,
        'physical_phone_acceptance': False, 'map_tiles_or_gestures_tested': False,
        'performance_regression_acceptance': False, 'performance_pass_claim': False,
        'scope': 'Only new counterbalanced fresh-install observations of the exact previously built APKs. Synthetic fixtures and per-UID IPv4/IPv6 denial; no real accounts. Twenty measured force-stopped starts plus four warmups. System caches persist; no cache-cold or interactive-ready timing claim. Partial APK plus extracted target-ABI native bytes exclude ART/OAT/VDEX, profiles, app data/cache and install-time peak; not Android Settings storage.'}
    device = ObservationDevice(args.serial)
    stage = 'validate_historical_public_apks'
    try:
        receipts = [read_receipt(path) for path in inputs[1::2]]
        validate_receipts(receipts, args.artifact_source)
        tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
        inspected = [verify_apk(path, receipt, tools) for path, receipt in zip(inputs[::2], receipts)]
        proof['installers'] = {str(version): public_identity(receipt) for version, receipt in zip((1818, 1819), receipts)}
        candidates = {version: (receipt, inputs[index * 2], inspected[index])
                      for index, (version, receipt) in enumerate(zip((1818, 1819), receipts))}
        stage = 'verify_fresh_disposable_emulator'
        device.verify_disposable_root()
        device.require_absent()
        proof['package_absent_before_first_install'] = True
        previous = None
        for index, version in enumerate(ORDER, 1):
            if previous is not None:
                stage = 'remove_completed_synthetic_group_' + str(index - 1)
                uninstall_ms = device.uninstall_synthetic(previous['installed_identity'])
                previous['synthetic_uninstall_host_wall_ms'] = uninstall_ms
                proof['explicit_fresh_synthetic_uninstalls_between_groups'] += 1
            stage = 'observe_group_' + str(index) + '_version_' + str(version)
            receipt, apk, info = candidates[version]
            previous = run_group(device, version, receipt, apk, info, index, proof)
        if proof['cleanup_failures']:
            raise UpgradeError('observation_cleanup_failed')
        proof.update({'passed': True, 'status': 'observations_recorded', 'summary': summarize(proof['groups'])})
    except Exception as error:
        proof.update({'failed_stage': stage, 'reason': failure_reason(error)})
        raise
    finally:
        (output / 'NATIVE_PACKAGING_OBSERVATION.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof, sort_keys=True), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(failure_reason(error), flush=True)
        raise SystemExit(1) from None
