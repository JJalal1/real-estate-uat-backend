#!/usr/bin/env python3
"""Replace 1816 with 1817 on a clean disposable emulator, without signing keys.

Only synthetic app-private files are tested. No real account, live business
request, handset acceptance or Android Keystore migration is inferred.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'JJalal1/real-estate-uat-backend'
BRANCH = 'refs/heads/work/fix-connectivity-1815-20261117'
PACKAGE = 'com.aqer.yemen.uat.offline'
ACTIVITY = 'com.example.real_estate_mobile.MainActivity'
AVD_NAME = 'aqer-durable-upgrade'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
APPROVED_PIN = '8d878aa972d1b101025b2f1b6b8c60c0783f5f80d901e1e57de97b718f6726f3'
BASELINE_VERSION, UPGRADE_VERSION = 1816, 1817
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
FORBIDDEN_ENV = (
    'AQER_UAT_KEYSTORE_BASE64', 'AQER_RELEASE_STORE_FILE',
    'AQER_RELEASE_STORE_PASSWORD', 'AQER_RELEASE_KEY_ALIAS',
    'AQER_RELEASE_KEY_PASSWORD', 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64',
    'AQER_PHASE1_TEST_ACCESS_JSON', 'SUPABASE_SERVICE_ROLE_KEY', 'DATABASE_URL',
)


class UpgradeError(ValueError):
    """Public fixed reason codes only; never include subprocess output."""


def guard(env, source, certificate, serial):
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('AQER_DURABLE_UAT_UPGRADE') == 'true' and
            env.get('GITHUB_REPOSITORY') == REPOSITORY and
            env.get('GITHUB_REF') == BRANCH and
            env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[1-9][0-9]*', env.get('GITHUB_RUN_ID', '')) and
            re.fullmatch(r'[a-f0-9]{40}', source) and source == env.get('GITHUB_SHA') and
            certificate == APPROVED_PIN and re.fullmatch(r'emulator-[0-9]{4}', serial)):
        raise UpgradeError('explicit_approved_disposable_upgrade_context_required')
    if any(env.get(name) for name in FORBIDDEN_ENV):
        raise UpgradeError('signing_or_account_credentials_forbidden_in_upgrade_probe')


def regular_input(value):
    path = Path(value).absolute()
    if path != path.resolve() or not path.is_relative_to(ROOT) or not path.is_file():
        raise UpgradeError('regular_workspace_input_required')
    return path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_receipt(path):
    if path.stat().st_size > 64 * 1024:
        raise UpgradeError('oversized_public_apk_receipt')
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise UpgradeError('public_apk_receipt_required')
    return value


def validate_pair(baseline, upgrade, source, certificate):
    for receipt, version in ((baseline, BASELINE_VERSION), (upgrade, UPGRADE_VERSION)):
        if (receipt.get('source_commit') != source or receipt.get('package') != PACKAGE or
                type(receipt.get('version_code')) is not int or receipt['version_code'] != version or
                receipt.get('api') != API or receipt.get('signer_certificate_sha256') != certificate or
                not re.fullmatch(r'[a-f0-9]{64}', receipt.get('sha256', '')) or
                type(receipt.get('bytes')) is not int or receipt['bytes'] <= 0):
            raise UpgradeError('same_source_approved_package_signer_and_versions_required')


def public_apk_identity(receipt):
    # Do not echo arbitrary input JSON into logs or the exported public proof.
    # All these values have fixed identities or bounded digest/number guards.
    return {key: receipt[key] for key in ('source_commit', 'package', 'version_code',
                                          'api', 'signer_certificate_sha256', 'sha256', 'bytes')}


def command(*values, timeout=90):
    return subprocess.run([str(value) for value in values], cwd=ROOT,
                          capture_output=True, text=True, check=True, timeout=timeout).stdout.strip()


def verify_apk(path, receipt, tools):
    if path.stat().st_size != receipt['bytes'] or digest(path) != receipt['sha256']:
        raise UpgradeError('downloaded_apk_digest_or_size_mismatch')
    signature = command(tools / 'apksigner', 'verify', '--print-certs', path)
    certificates = re.findall(
        r'^Signer #([1-9][0-9]*) certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*$',
        signature, re.MULTILINE)
    if [(number, value.lower()) for number, value in certificates] != [('1', APPROVED_PIN)]:
        raise UpgradeError('actual_apk_approved_signer_mismatch')
    badging = command(tools / 'aapt', 'dump', 'badging', path)
    packages = re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE)
    if (packages != [(PACKAGE, str(receipt['version_code']))] or
            re.findall(r"^sdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['23'] or
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['36'] or
            'application-debuggable' in badging):
        raise UpgradeError('actual_release_apk_identity_or_sdk_mismatch')
    command(tools / 'zipalign', '-c', '-P', '16', '4', path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise UpgradeError('apk_archive_integrity_failed')
        libraries = {name for name in names if name.endswith('/libapp.so')}
        if libraries != {f'lib/{abi}/libapp.so' for abi in ABIS}:
            raise UpgradeError('ordinary_three_abi_apk_required')
        if any(API.encode() not in archive.read(name) for name in libraries):
            raise UpgradeError('compiled_uat_api_mismatch')
        if any(name.lower().endswith(('.keystore', '.jks', '.p12', '.pfx', '.key')) for name in names):
            raise UpgradeError('private_signing_material_forbidden_in_apk')


def assert_clean_package(listing):
    if listing.strip():
        raise UpgradeError('clean_emulator_package_must_be_absent')


def package_metadata(dump, uid):
    versions = re.findall(r'^\s*versionCode=([0-9]+)\b', dump, re.MULTILINE)
    # Android 16/API36 Settings.dumpPackageLPr names this appId; older releases
    # printed userId. This fresh emulator uses user 0, whose UID equals appId.
    # Accept one spelling only rather than guessing among multiple identities.
    users = re.findall(r'^\s*(?:appId|userId)=([0-9]+)\s*$', dump, re.MULTILINE)
    installed = re.findall(r'^\s*firstInstallTime=(.+)$', dump, re.MULTILINE)
    if (len(versions) != 1 or len(users) != 1 or len(installed) != 1 or
            not re.fullmatch(r'[1-9][0-9]*', uid) or int(uid) < 10000 or uid != users[0]):
        raise UpgradeError('unambiguous_installed_package_metadata_required')
    return {'version_code': int(versions[0]), 'uid': int(uid), 'first_install_time': installed[0].strip()}


def assert_preserved(before, after, expected_hashes, actual_hashes):
    if before['version_code'] != BASELINE_VERSION or after['version_code'] != UPGRADE_VERSION:
        raise UpgradeError('installed_version_pair_mismatch')
    if before['uid'] != after['uid'] or before['first_install_time'] != after['first_install_time']:
        raise UpgradeError('package_identity_was_not_preserved_by_replace_install')
    if not expected_hashes or expected_hashes != actual_hashes:
        raise UpgradeError('app_private_fixture_changed_or_missing')


def synthetic_fixtures():
    return {
        'files/aqer_theme_mode.txt': b'dark',
        'no_backup/listing_recovery/u999999/p0/state.json': json.dumps({
            'version': 1, 'user_id': 999999, 'listing_id': 0,
            'data': {'fields': {'title': 'Synthetic durable UAT upgrade fixture'},
                     'draft_key': 'd00daaaa-0000-4000-8000-000000000001',
                     'entry_method': 'manual', 'offline_prepared': True},
            'image_files': [], 'image_keys': [],
        }, sort_keys=True).encode(),
    }


class Device:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *values, timeout=90):
        return command('adb', '-s', self.serial, *values, timeout=timeout)

    def verify_disposable_root(self):
        self.adb('wait-for-device')
        if (self.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
                self.adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
                self.adb('emu', 'avd', 'name').splitlines()[0] != AVD_NAME):
            raise UpgradeError('exact_disposable_api36_avd_required')
        self.adb('root')
        self.adb('wait-for-device')
        if self.adb('shell', 'id', '-u') != '0':
            raise UpgradeError('rooted_disposable_emulator_required')

    def snapshot(self):
        return package_metadata(self.adb('shell', 'dumpsys', 'package', PACKAGE),
                                self.adb('shell', 'stat', '-c', '%u', '/data/user/0/' + PACKAGE))

    def install(self, path, replace=False):
        output = self.adb('install', *(['-r'] if replace else []), str(path), timeout=180)
        if not re.search(r'^Success\s*$', output, re.MULTILINE):
            raise UpgradeError('package_install_did_not_succeed')

    def private_hashes(self, paths):
        result = {}
        for relative in paths:
            value = self.adb('shell', 'sha256sum', '/data/user/0/' + PACKAGE + '/' + relative).split()
            if not value or not re.fullmatch(r'[a-f0-9]{64}', value[0]):
                raise UpgradeError('private_fixture_digest_unavailable')
            result[relative] = value[0]
        return result

    def launch(self):
        self.adb('logcat', '-c')
        output = self.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/' + ACTIVITY, timeout=60)
        if not re.search(r'^Status:\s*ok\s*$', output, re.MULTILINE):
            raise UpgradeError('ordinary_app_launch_failed')
        for _ in range(3):
            if not self.adb('shell', 'pidof', PACKAGE):
                raise UpgradeError('ordinary_app_did_not_remain_running')
            time.sleep(1)
        crash = self.adb('logcat', '-d', '-b', 'crash')
        if PACKAGE in crash:
            raise UpgradeError('ordinary_app_crashed_after_launch')


def failure_reason(error):
    if isinstance(error, UpgradeError):
        return str(error)
    if isinstance(error, subprocess.CalledProcessError):
        return 'device_or_verifier_command_failed_exit_' + str(error.returncode)
    if isinstance(error, subprocess.TimeoutExpired):
        return 'device_or_verifier_command_timeout'
    return 'upgrade_probe_failed_' + type(error).__name__


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-apk', required=True)
    parser.add_argument('--baseline-receipt', required=True)
    parser.add_argument('--upgrade-apk', required=True)
    parser.add_argument('--upgrade-receipt', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--certificate', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', default='durable-upgrade-proof')
    args = parser.parse_args()
    guard(os.environ, args.source, args.certificate, args.serial)
    if command('git', 'rev-parse', 'HEAD') != args.source:
        raise UpgradeError('checked_out_source_mismatch')
    inputs = [regular_input(value) for value in
              (args.baseline_apk, args.baseline_receipt, args.upgrade_apk, args.upgrade_receipt)]
    if len(set(inputs)) != 4:
        raise UpgradeError('distinct_baseline_and_upgrade_inputs_required')
    baseline_path, baseline_receipt, upgrade_path, upgrade_receipt = inputs
    output = Path(args.output).absolute()
    if output != output.resolve() or not output.is_relative_to(ROOT):
        raise UpgradeError('regular_workspace_output_required')
    output.mkdir(mode=0o700)
    device = Device(args.serial)
    rules, cleanup_failures = [], []
    installed = False
    receipt = {'passed': False, 'status': 'failed', 'source_commit': args.source,
               'package': PACKAGE, 'signer_certificate_sha256': args.certificate,
               'android_api': 36, 'environment': 'disposable_rooted_emulator',
               'physical_phone_acceptance': False, 'real_account_data_used': False,
               'live_business_api_used': False, 'signing_material_used_in_probe': False,
               'keystore_or_signed_in_session_migration_tested': False,
               'cleanup_failures': cleanup_failures,
               'limits': 'Ordinary APK install-replace and synthetic private file preservation only; not the one-time removal of 1815, real user data migration, cryptographic key migration, or handset acceptance.'}
    stage = 'validate_public_apk_pair'
    try:
        baseline, upgrade = read_receipt(baseline_receipt), read_receipt(upgrade_receipt)
        validate_pair(baseline, upgrade, args.source, args.certificate)
        tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
        verify_apk(baseline_path, baseline, tools)
        verify_apk(upgrade_path, upgrade, tools)
        receipt['baseline'] = public_apk_identity(baseline)
        receipt['upgrade'] = public_apk_identity(upgrade)
        stage = 'verify_disposable_emulator'
        device.verify_disposable_root()
        stage = 'prove_package_absent_before_first_install'
        assert_clean_package(device.adb('shell', 'pm', 'list', 'packages', '--user', '0', PACKAGE))
        receipt['package_absent_before_first_install'] = True
        stage = 'install_baseline_once'
        device.install(baseline_path)
        installed = True
        before = device.snapshot()
        if before['version_code'] != BASELINE_VERSION:
            raise UpgradeError('baseline_installed_version_mismatch')
        stage = 'block_app_uid_network_before_first_launch'
        for family in ('iptables', 'ip6tables'):
            rule = ('shell', family, '-w', '5', '-I', 'OUTPUT', '-m', 'owner',
                    '--uid-owner', str(before['uid']), '-j', 'REJECT')
            device.adb(*rule)
            rules.append((family, str(before['uid'])))
            device.adb('shell', family, '-w', '5', '-C', 'OUTPUT', '-m', 'owner',
                       '--uid-owner', str(before['uid']), '-j', 'REJECT')
        receipt['network_isolation'] = 'verified IPv4 and IPv6 OUTPUT reject rules scoped to the fresh application UID; no network interface validation claim'
        stage = 'write_synthetic_private_fixtures'
        private = '/data/user/0/' + PACKAGE
        fixtures = synthetic_fixtures()
        expected_hashes = {relative: hashlib.sha256(data).hexdigest() for relative, data in fixtures.items()}
        with tempfile.TemporaryDirectory(prefix='durable-upgrade-') as temporary:
            for index, (relative, data) in enumerate(fixtures.items()):
                local = Path(temporary) / str(index)
                local.write_bytes(data)
                destination = private + '/' + relative
                directory = destination.rsplit('/', 1)[0]
                device.adb('shell', 'mkdir', '-p', directory)
                device.adb('push', str(local), destination)
                device.adb('shell', 'chown', f"{before['uid']}:{before['uid']}", destination)
                device.adb('shell', 'chmod', '600', destination)
                device.adb('shell', 'restorecon', '-R', directory)
            device.adb('shell', 'chown', '-R', f"{before['uid']}:{before['uid']}", private + '/no_backup/listing_recovery')
            device.adb('shell', 'chown', f"{before['uid']}:{before['uid']}", private + '/files')
        if device.private_hashes(fixtures) != expected_hashes:
            raise UpgradeError('baseline_private_fixture_setup_failed')
        stage = 'launch_baseline_without_business_network'
        device.launch()
        if device.private_hashes(fixtures) != expected_hashes:
            raise UpgradeError('baseline_launch_changed_synthetic_private_files')
        device.adb('shell', 'am', 'force-stop', PACKAGE)
        stage = 'replace_install_upgrade_without_data_reset'
        device.install(upgrade_path, replace=True)
        after = device.snapshot()
        assert_preserved(before, after, expected_hashes, device.private_hashes(fixtures))
        stage = 'launch_upgrade_and_recheck_private_files'
        device.launch()
        after_launch = device.snapshot()
        actual_hashes = device.private_hashes(fixtures)
        assert_preserved(before, after_launch, expected_hashes, actual_hashes)
        receipt.update({'passed': True, 'status': 'passed', 'same_certificate': True,
                        'baseline_install': before, 'upgrade_install': after_launch,
                        'uid_preserved': True, 'first_install_time_preserved': True,
                        'private_fixture_sha256': actual_hashes,
                        'ordinary_baseline_and_upgrade_launch_passed': True,
                        'uninstall_or_clear_data_used': False})
    except Exception as error:
        receipt.update({'passed': False, 'status': 'failed', 'failed_stage': stage,
                        'reason': failure_reason(error)})
        raise
    finally:
        stopped = not installed
        if installed:
            try:
                device.adb('shell', 'am', 'force-stop', PACKAGE)
                stopped = True
            except Exception as error:
                cleanup_failures.append({'step': 'force_stop', 'reason': failure_reason(error)})
        # If force-stop failed, keep the owned deny rules until the workflow
        # destroys this emulator rather than allowing an app to use the network.
        if stopped:
            for family, uid in reversed(rules):
                try:
                    device.adb('shell', family, '-w', '5', '-D', 'OUTPUT', '-m', 'owner',
                               '--uid-owner', uid, '-j', 'REJECT')
                except Exception as error:
                    cleanup_failures.append({'step': family, 'reason': failure_reason(error)})
        (output / 'ANDROID_DURABLE_UPGRADE_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, sort_keys=True), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(failure_reason(error), flush=True)
        raise SystemExit(1) from None
