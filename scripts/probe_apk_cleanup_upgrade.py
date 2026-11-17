#!/usr/bin/env python3
"""Measure 1817 -> 1818 -> 1819 on one empty, isolated API36 emulator.

Only ordinary signed APKs and synthetic private files are used. Timings and
APK-plus-extracted-native bytes are observations, not handset performance or
Android Settings total-storage acceptance. No account or signing key is read.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time
import zipfile

from prepare_phase1_followup import elf
from probe_durable_uat_upgrade import UpgradeError, package_metadata, synthetic_fixtures

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'JJalal1/real-estate-uat-backend'
BRANCH = 'refs/heads/work/apk-cleanup-1817-20261117'
PACKAGE = 'com.aqer.yemen.uat.offline'
ACTIVITY = 'com.example.real_estate_mobile.MainActivity'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
AVD_NAME = 'aqer-cleanup-upgrade'
CERTIFICATE = '8d878aa972d1b101025b2f1b6b8c60c0783f5f80d901e1e57de97b718f6726f3'
BASE_SOURCE = 'e91927e9d14994c9101d6f11b8886e666bb930d1'
BASE_SHA256 = '4c6141d08c045a23c63ee183b3bdb339de51ec1f58ae3f34aec014685764eda1'
BASE_BYTES = 120125414
VERSIONS = (1817, 1818, 1819)
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
NATIVE_FAMILIES = {'libapp.so', 'libflutter.so', 'libmaplibre.so', 'libdatastore_shared_counter.so'}
FORBIDDEN_ENV = (
    'AQER_UAT_KEYSTORE_BASE64', 'AQER_RELEASE_STORE_FILE', 'AQER_RELEASE_STORE_PASSWORD',
    'AQER_RELEASE_KEY_ALIAS', 'AQER_RELEASE_KEY_PASSWORD',
    'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', 'AQER_PHASE1_TEST_ACCESS_JSON',
    'SUPABASE_SERVICE_ROLE_KEY', 'DATABASE_URL',
)
IDENTITY_FIELDS = ('source_commit', 'package', 'version_code', 'api',
                   'signer_certificate_sha256', 'sha256', 'bytes')


def guard(env, source, serial):
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('AQER_APK_CLEANUP_UPGRADE') == 'true' and
            env.get('GITHUB_REPOSITORY') == REPOSITORY and env.get('GITHUB_REF') == BRANCH and
            env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[1-9][0-9]*', env.get('GITHUB_RUN_ID', '')) and
            re.fullmatch(r'[a-f0-9]{40}', source) and source == env.get('GITHUB_SHA') and
            serial == 'emulator-5554'):
        raise UpgradeError('explicit_private_cleanup_upgrade_context_required')
    if any(env.get(name) for name in FORBIDDEN_ENV):
        raise UpgradeError('signing_or_account_material_forbidden_in_cleanup_probe')


def regular_input(value):
    path = Path(value).absolute()
    if path != path.resolve() or not path.is_relative_to(ROOT) or not path.is_file():
        raise UpgradeError('regular_workspace_input_required')
    return path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_receipt(path):
    if path.stat().st_size > 128 * 1024:
        raise UpgradeError('oversized_public_apk_receipt')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise UpgradeError('duplicate_public_receipt_key')
            result[key] = value
        return result
    value = json.loads(path.read_text(), object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise UpgradeError('public_apk_receipt_required')
    return value


def validate_receipts(receipts, source):
    if len(receipts) != 3:
        raise UpgradeError('exact_three_version_chain_required')
    for receipt, version in zip(receipts, VERSIONS):
        expected_source = BASE_SOURCE if version == 1817 else source
        if (receipt.get('source_commit') != expected_source or receipt.get('package') != PACKAGE or
                type(receipt.get('version_code')) is not int or receipt['version_code'] != version or
                receipt.get('api') != API or receipt.get('signer_certificate_sha256') != CERTIFICATE or
                not isinstance(receipt.get('sha256'), str) or
                not re.fullmatch(r'[a-f0-9]{64}', receipt['sha256']) or
                type(receipt.get('bytes')) is not int or receipt['bytes'] <= 0):
            raise UpgradeError('pinned_baseline_and_same_source_candidate_identities_required')
        if version == 1817:
            if receipt['sha256'] != BASE_SHA256 or receipt['bytes'] != BASE_BYTES:
                raise UpgradeError('exact_original_1817_baseline_required')
        elif (receipt.get('native_library_compression') != ('stored' if version == 1818 else 'deflated') or
              receipt.get('extract_native_libs') is not (version == 1819)):
            raise UpgradeError('candidate_packaging_mode_mismatch')


def public_identity(receipt):
    return {key: receipt[key] for key in IDENTITY_FIELDS}


def command(*values, timeout=90):
    return subprocess.run([str(value) for value in values], cwd=ROOT, check=True,
                          capture_output=True, text=True, timeout=timeout).stdout.strip()


def verify_apk(path, receipt, tools):
    if path.stat().st_size != receipt['bytes'] or digest(path) != receipt['sha256']:
        raise UpgradeError('downloaded_apk_size_or_digest_mismatch')
    signature = command(tools / 'apksigner', 'verify', '--print-certs', path)
    certificates = re.findall(
        r'^Signer #([1-9][0-9]*) certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*$',
        signature, re.MULTILINE)
    if [(number, value.lower()) for number, value in certificates] != [('1', CERTIFICATE)]:
        raise UpgradeError('actual_apk_approved_signer_mismatch')
    badging = command(tools / 'aapt', 'dump', 'badging', path)
    if (re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE) != [(PACKAGE, str(receipt['version_code']))] or
            re.findall(r"^sdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['23'] or
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['36'] or
            'application-debuggable' in badging):
        raise UpgradeError('actual_release_apk_identity_or_sdk_mismatch')
    command(tools / 'zipalign', '-c', '-P', '16', '4', path)
    native_hashes, native_methods = {}, {}
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise UpgradeError('apk_archive_integrity_failed')
        libraries = {name for name in names if name.endswith('/libapp.so')}
        if libraries != {f'lib/{abi}/libapp.so' for abi in ABIS}:
            raise UpgradeError('exact_three_flutter_architectures_required')
        if any(API.encode() not in archive.read(name) for name in libraries):
            raise UpgradeError('compiled_uat_api_mismatch')
        if any(name.lower().endswith(('.keystore', '.jks', '.p12', '.pfx', '.key')) for name in names):
            raise UpgradeError('private_signing_material_forbidden_in_apk')
        for item in archive.infolist():
            if not item.filename.startswith('lib/') or not item.filename.endswith('.so'):
                continue
            data = archive.read(item)
            native_hashes[item.filename] = hashlib.sha256(data).hexdigest()
            native_methods[item.filename] = item.compress_type
            if item.filename.startswith(('lib/arm64-v8a/', 'lib/x86_64/')):
                elf(data)
        if receipt['version_code'] != 1817:
            expected = {f'lib/{abi}/{family}' for abi in ABIS for family in NATIVE_FAMILIES}
            method = zipfile.ZIP_STORED if receipt['version_code'] == 1818 else zipfile.ZIP_DEFLATED
            if set(native_hashes) != expected or any(value != method for value in native_methods.values()):
                raise UpgradeError('exact_clean_native_payload_and_packaging_required')
            if (receipt.get('native_library_sha256') != native_hashes or
                    receipt.get('native_library_methods') != native_methods):
                raise UpgradeError('actual_native_payload_does_not_match_build_receipt')
    return {'native_sha256': native_hashes, 'native_methods': native_methods}


def assert_preserved(before, after, version, expected_hashes, actual_hashes):
    if before['version_code'] != 1817 or after['version_code'] != version:
        raise UpgradeError('installed_version_chain_mismatch')
    if before['uid'] != after['uid'] or before['first_install_time'] != after['first_install_time']:
        raise UpgradeError('replace_install_identity_not_preserved')
    if not expected_hashes or expected_hashes != actual_hashes:
        raise UpgradeError('synthetic_private_file_changed_or_missing')


def parse_launch(output):
    if not re.search(r'^Status:\s*ok\s*$', output, re.MULTILINE):
        raise UpgradeError('ordinary_app_launch_failed')
    result = {}
    for field in ('TotalTime', 'WaitTime'):
        values = re.findall(r'^' + field + r':\s*([0-9]+)\s*$', output, re.MULTILINE)
        if len(values) != 1 or int(values[0]) > 60000:
            raise UpgradeError('unambiguous_bounded_android_launch_time_required')
        result[field.lower() + '_ms'] = int(values[0])
    return result


def size_value(value):
    if not re.fullmatch(r'[0-9]+', value) or int(value) > 1024 * 1024 * 1024:
        raise UpgradeError('bounded_device_file_size_required')
    return int(value)


def owned_code_path(value):
    if not (re.fullmatch(r'/data/app/[A-Za-z0-9_./=+~\-]+', value) and
            '/..' not in value and PACKAGE in value):
        raise UpgradeError('installed_application_code_path_required')
    return value


class Device:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *values, timeout=90):
        return command('adb', '-s', self.serial, *values, timeout=timeout)

    def verify_disposable_root(self):
        self.adb('wait-for-device')
        if (self.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
                self.adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
                self.adb('emu', 'avd', 'name').splitlines()[0] != AVD_NAME or
                self.adb('shell', 'getprop', 'ro.product.cpu.abi') != 'x86_64'):
            raise UpgradeError('exact_disposable_api36_x64_avd_required')
        self.adb('root')
        self.adb('wait-for-device')
        if self.adb('shell', 'id', '-u') != '0':
            raise UpgradeError('rooted_disposable_emulator_required')

    def snapshot(self):
        return package_metadata(self.adb('shell', 'dumpsys', 'package', PACKAGE),
                                self.adb('shell', 'stat', '-c', '%u', '/data/user/0/' + PACKAGE))

    def install(self, path, replace=False):
        start = time.perf_counter()
        output = self.adb('install', *(['-r'] if replace else []), str(path), timeout=180)
        elapsed = round((time.perf_counter() - start) * 1000, 3)
        if not re.search(r'^Success\s*$', output, re.MULTILINE):
            raise UpgradeError('package_install_failed')
        return elapsed

    def private_hashes(self, paths):
        result = {}
        for relative in paths:
            words = self.adb('shell', 'sha256sum', '/data/user/0/' + PACKAGE + '/' + relative).split()
            if not words or not re.fullmatch(r'[a-f0-9]{64}', words[0]):
                raise UpgradeError('private_fixture_digest_unavailable')
            result[relative] = words[0]
        return result

    def cold_launches(self):
        rows = []
        for _ in range(3):
            self.adb('shell', 'am', 'force-stop', PACKAGE)
            self.adb('logcat', '-c')
            start = time.perf_counter()
            output = self.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/' + ACTIVITY, timeout=60)
            row = parse_launch(output)
            row['host_wall_ms'] = round((time.perf_counter() - start) * 1000, 3)
            for _ in range(3):
                if not self.adb('shell', 'pidof', PACKAGE):
                    raise UpgradeError('ordinary_app_did_not_remain_running')
                time.sleep(1)
            if PACKAGE in self.adb('logcat', '-d', '-b', 'crash'):
                raise UpgradeError('ordinary_app_crashed_after_launch')
            rows.append(row)
        return {'runs': rows, 'median_total_time_ms': statistics.median(row['totaltime_ms'] for row in rows),
                'median_wait_time_ms': statistics.median(row['waittime_ms'] for row in rows),
                'median_host_wall_ms': statistics.median(row['host_wall_ms'] for row in rows),
                'scope': 'Three force-stopped activity/process starts in one sequential x86_64 emulator; not cache-cold, interactive-ready or physical-handset performance.'}

    def code_footprint(self, receipt, expected_native):
        paths = self.adb('shell', 'pm', 'path', PACKAGE).splitlines()
        if len(paths) != 1 or not paths[0].startswith('package:'):
            raise UpgradeError('single_installed_base_apk_required')
        apk_path = owned_code_path(paths[0].split(':', 1)[1])
        if not apk_path.endswith('/base.apk'):
            raise UpgradeError('installed_base_apk_required')
        apk_bytes = size_value(self.adb('shell', 'stat', '-c', '%s', apk_path))
        if apk_bytes != receipt['bytes']:
            raise UpgradeError('installed_apk_size_not_same_verified_installer')
        dump = self.adb('shell', 'dumpsys', 'package', PACKAGE)
        extraction = re.findall(r'^\s*extractNativeLibs=(true|false)\s*$', dump, re.MULTILINE)
        primary_abi = re.findall(r'^\s*primaryCpuAbi=([^\s]+)\s*$', dump, re.MULTILINE)
        expected_extract = receipt['version_code'] == 1819
        if extraction != [str(expected_extract).lower()] or primary_abi != ['x86_64']:
            raise UpgradeError('installed_target_abi_or_native_extraction_flag_mismatch')
        roots = re.findall(r'^\s*(?:legacyNativeLibraryDir|nativeLibraryDir)=([^\s]+)\s*$', dump, re.MULTILINE)
        if not roots or len(set(roots)) != 1:
            raise UpgradeError('unambiguous_native_library_directory_required')
        native_root = owned_code_path(roots[0])
        try:
            self.adb('shell', 'test', '-d', native_root)
        except subprocess.CalledProcessError as error:
            if error.returncode != 1:
                raise
            files = []
        else:
            files = self.adb('shell', 'find', native_root, '-type', 'f').splitlines()
        if len(files) > 12 or len(files) != len(set(files)):
            raise UpgradeError('bounded_extracted_native_file_set_required')
        extracted = {}
        for path in files:
            owned_code_path(path)
            if not path.startswith(native_root + '/') or not path.endswith('.so'):
                raise UpgradeError('only_owned_native_library_files_allowed')
            family = Path(path).name
            if family in extracted:
                raise UpgradeError('single_target_abi_extraction_required')
            words = self.adb('shell', 'sha256sum', path).split()
            expected = expected_native.get('lib/x86_64/' + family)
            if not words or words[0] != expected:
                raise UpgradeError('extracted_native_bytes_do_not_match_installer')
            extracted[family] = {'bytes': size_value(self.adb('shell', 'stat', '-c', '%s', path)),
                                 'sha256': expected}
        version = receipt['version_code']
        if version == 1818 and extracted:
            raise UpgradeError('default_packaging_unexpectedly_extracted_native_libraries')
        if version == 1819 and set(extracted) != NATIVE_FAMILIES:
            raise UpgradeError('compressed_packaging_must_extract_exact_target_libraries')
        native_bytes = sum(item['bytes'] for item in extracted.values())
        return {'base_apk_bytes': apk_bytes, 'extracted_native_library_bytes': native_bytes,
                'package_code_plus_extracted_native_bytes': apk_bytes + native_bytes,
                'extracted_target_abi': 'x86_64', 'extract_native_libs': expected_extract,
                'extracted_libraries': extracted,
                'scope': 'Base APK file plus regular files in its nativeLibraryDir only; excludes ART/OAT/VDEX, profiles, system metadata, app data, snapshots, photos and install-time peak space; not Android Settings total storage.'}


def write_fixtures(device, uid, fixtures):
    private = '/data/user/0/' + PACKAGE
    with tempfile.TemporaryDirectory(prefix='apk-cleanup-fixtures-') as temporary:
        for index, (relative, data) in enumerate(fixtures.items()):
            local = Path(temporary) / str(index)
            local.write_bytes(data)
            destination = private + '/' + relative
            directory = destination.rsplit('/', 1)[0]
            device.adb('shell', 'mkdir', '-p', directory)
            device.adb('push', str(local), destination)
            device.adb('shell', 'chown', f'{uid}:{uid}', destination)
            device.adb('shell', 'chmod', '600', destination)
            device.adb('shell', 'restorecon', '-R', directory)
        device.adb('shell', 'chown', '-R', f'{uid}:{uid}', private + '/no_backup/listing_recovery')
        device.adb('shell', 'chown', f'{uid}:{uid}', private + '/files')


def failure_reason(error):
    if isinstance(error, UpgradeError):
        return str(error)
    if isinstance(error, subprocess.CalledProcessError):
        return 'device_or_verifier_command_failed_exit_' + str(error.returncode)
    if isinstance(error, subprocess.TimeoutExpired):
        return 'device_or_verifier_command_timeout'
    return 'cleanup_probe_failed_' + type(error).__name__


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for role in ('baseline', 'clean', 'compressed'):
        parser.add_argument('--' + role + '-apk', required=True)
        parser.add_argument('--' + role + '-receipt', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', default='apk-cleanup-android-proof')
    args = parser.parse_args()
    guard(os.environ, args.source, args.serial)
    if command('git', 'rev-parse', 'HEAD') != args.source:
        raise UpgradeError('checked_out_source_mismatch')
    inputs = [regular_input(getattr(args, role + '_' + kind))
              for role in ('baseline', 'clean', 'compressed') for kind in ('apk', 'receipt')]
    if len(set(inputs)) != 6:
        raise UpgradeError('distinct_three_apks_and_receipts_required')
    output = Path(args.output).absolute()
    if output != output.resolve() or not output.is_relative_to(ROOT):
        raise UpgradeError('regular_workspace_output_required')
    output.mkdir(mode=0o700)
    device = Device(args.serial)
    rules, cleanup_failures = [], []
    installed = False
    proof = {'passed': False, 'status': 'failed', 'source_commit': args.source,
             'baseline_source_commit': BASE_SOURCE, 'package': PACKAGE,
             'signer_certificate_sha256': CERTIFICATE, 'android_api': 36,
             'environment': 'disposable_rooted_x86_64_emulator', 'version_chain': list(VERSIONS),
             'physical_phone_acceptance': False, 'real_account_data_used': False,
             'live_business_api_used': False, 'signing_material_used_in_probe': False,
             'keystore_or_signed_in_session_migration_tested': False,
             'map_tiles_or_gestures_tested': False, 'performance_regression_acceptance': False,
             'cleanup_failures': cleanup_failures, 'measurements': {},
             'limits': 'Ordinary three-version replace-install and synthetic private files only. Sequential emulator activity timings and partial code/native footprint are measurements, not a physical-phone or complete storage/performance acceptance.'}
    stage = 'validate_three_public_installers'
    try:
        receipts = [read_receipt(path) for path in inputs[1::2]]
        validate_receipts(receipts, args.source)
        tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
        inspected = [verify_apk(path, receipt, tools) for path, receipt in zip(inputs[::2], receipts)]
        for candidate in inspected[1:]:
            if any(value != inspected[0]['native_sha256'].get(name)
                   for name, value in candidate['native_sha256'].items() if not name.endswith('/libapp.so')):
                raise UpgradeError('protected_native_library_changed_from_1817')
        proof['installers'] = {str(version): public_identity(receipt) for version, receipt in zip(VERSIONS, receipts)}
        stage = 'verify_disposable_emulator'
        device.verify_disposable_root()
        stage = 'prove_package_absent'
        if device.adb('shell', 'pm', 'list', 'packages', '--user', '0', PACKAGE).strip():
            raise UpgradeError('clean_emulator_package_must_be_absent')
        proof['package_absent_before_first_install'] = True
        stage = 'install_1817_baseline'
        install_ms = device.install(inputs[0])
        installed = True
        before = device.snapshot()
        if before['version_code'] != 1817:
            raise UpgradeError('baseline_installed_version_mismatch')
        stage = 'isolate_owned_app_uid_network_before_first_launch'
        for family in ('iptables', 'ip6tables'):
            device.adb('shell', family, '-w', '5', '-I', 'OUTPUT', '-m', 'owner',
                       '--uid-owner', str(before['uid']), '-j', 'REJECT')
            rules.append((family, str(before['uid'])))
            device.adb('shell', family, '-w', '5', '-C', 'OUTPUT', '-m', 'owner',
                       '--uid-owner', str(before['uid']), '-j', 'REJECT')
        proof['network_isolation'] = 'Verified IPv4 and IPv6 OUTPUT reject rules scoped to the fresh application UID before first launch.'
        fixtures = synthetic_fixtures()
        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in fixtures.items()}
        stage = 'prepare_synthetic_private_files'
        write_fixtures(device, before['uid'], fixtures)
        if device.private_hashes(fixtures) != hashes:
            raise UpgradeError('baseline_private_fixture_setup_failed')
        for index, (version, receipt, info) in enumerate(zip(VERSIONS, receipts, inspected)):
            stage = 'replace_install_' + str(version) if index else 'measure_baseline_1817'
            if index:
                device.adb('shell', 'am', 'force-stop', PACKAGE)
                install_ms = device.install(inputs[index * 2], replace=True)
            current = device.snapshot()
            assert_preserved(before, current, version, hashes, device.private_hashes(fixtures))
            row = {'install_host_wall_ms': install_ms, 'installed_identity': current}
            proof['measurements'][str(version)] = row
            stage = 'measure_code_and_native_' + str(version)
            row['code_footprint'] = device.code_footprint(receipt, info['native_sha256'])
            stage = 'launch_and_recheck_' + str(version)
            row['activity_starts'] = device.cold_launches()
            assert_preserved(before, device.snapshot(), version, hashes, device.private_hashes(fixtures))
        clean = proof['measurements']['1818']['code_footprint']
        compressed = proof['measurements']['1819']['code_footprint']
        proof['comparison_1819_minus_1818'] = {
            'apk_bytes': receipts[2]['bytes'] - receipts[1]['bytes'],
            'partial_code_native_bytes': compressed['package_code_plus_extracted_native_bytes'] - clean['package_code_plus_extracted_native_bytes'],
            'median_activity_total_time_ms': proof['measurements']['1819']['activity_starts']['median_total_time_ms'] - proof['measurements']['1818']['activity_starts']['median_total_time_ms'],
            'scope': 'Observed sequential emulator differences only; no pass/fail threshold or phone-performance claim.'}
        proof.update({'passed': True, 'status': 'passed', 'uid_preserved': True,
                      'first_install_time_preserved': True, 'private_fixture_sha256': hashes,
                      'ordinary_launches_per_version': 3, 'uninstall_or_clear_data_used': False})
    except Exception as error:
        proof.update({'failed_stage': stage, 'reason': failure_reason(error)})
        raise
    finally:
        stopped = not installed
        if installed:
            try:
                device.adb('shell', 'am', 'force-stop', PACKAGE)
                stopped = True
            except Exception as error:
                cleanup_failures.append({'step': 'force_stop', 'reason': failure_reason(error)})
        if stopped:
            for family, uid in reversed(rules):
                try:
                    device.adb('shell', family, '-w', '5', '-D', 'OUTPUT', '-m', 'owner', '--uid-owner', uid, '-j', 'REJECT')
                except Exception as error:
                    cleanup_failures.append({'step': family, 'reason': failure_reason(error)})
        if cleanup_failures:
            proof.update({'passed': False, 'status': 'failed'})
            proof.setdefault('failed_stage', 'cleanup')
            proof.setdefault('reason', 'cleanup_failed_after_device_probe')
        (output / 'ANDROID_APK_CLEANUP_VERIFICATION.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof, sort_keys=True), flush=True)
    if cleanup_failures:
        raise UpgradeError('cleanup_failed_after_device_probe')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(failure_reason(error), flush=True)
        raise SystemExit(1) from None
