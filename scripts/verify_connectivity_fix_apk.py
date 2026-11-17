#!/usr/bin/env python3
"""Verify a durable UAT baseline/update against its approved public identity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from prepare_phase1_close import android_tools, elf
from uat_signing_identity import load_public_identity, verify_imported_environment

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/work/fix-connectivity-1815-20261117'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
PACKAGE = 'com.aqer.yemen.uat.offline'
APP_NAME = 'عقار أوفلاين اختبار'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}


class VerificationError(ValueError):
    """Fixed public reason codes only; never tool output or credential data."""


def call(*args):
    return subprocess.run([str(value) for value in args], cwd=ROOT, check=True,
                          capture_output=True, text=True, timeout=90).stdout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', type=int, choices=(1816, 1817), required=True)
    version = parser.parse_args(argv).version
    identity = load_public_identity(require_approval=True)
    certificate = identity['certificate_sha256']
    env = os.environ
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push'):
        raise VerificationError('explicit_durable_uat_ci_context_required')
    verify_imported_environment(identity, env)
    source = call('git', 'rev-parse', 'HEAD').strip()
    if source != env.get('GITHUB_SHA') or not re.fullmatch(r'[a-f0-9]{40}', source):
        raise VerificationError('source_checkout_mismatch')
    call('git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib',
         'mobile_app/android', 'mobile_app/assets', 'mobile_app/pubspec.yaml',
         'backend-api-runtime', 'docs/uat-signing-identity.json',
         'scripts/uat_signing_identity.py', 'scripts/verify_connectivity_fix_apk.py')
    # The established CI resolver completes the original lock with reviewed,
    # pinned entries. Verify that contract rather than requiring a byte-identical
    # committed lock, which would reject the existing reviewed build procedure.
    lock = ROOT / 'mobile_app/pubspec.lock'
    call(sys.executable, ROOT / 'scripts/verify_v3_dependency_lock.py', '--resolved', lock)
    apk = ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
    if apk.is_symlink() or not apk.is_file():
        raise VerificationError('uat_release_apk_required')
    tools = android_tools(Path(env['ANDROID_HOME']))
    signature = call(tools / 'apksigner', 'verify', '--print-certs', apk)
    certificates = re.findall(
        r'^Signer #([1-9][0-9]*) certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*$',
        signature, re.MULTILINE)
    if [(number, digest.lower()) for number, digest in certificates] != [('1', certificate)]:
        raise VerificationError('approved_durable_uat_signer_mismatch')
    badging = call(tools / 'aapt', 'dump', 'badging', apk)
    packages = re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE)
    if (packages != [(PACKAGE, str(version))] or
            re.findall(r"^sdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['23'] or
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['36'] or
            f"application-label:'{APP_NAME}'" not in badging or
            'application-debuggable' in badging):
        raise VerificationError('update_candidate_identity_or_sdk_mismatch')
    call(tools / 'zipalign', '-c', '-P', '16', '4', apk)
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise VerificationError('apk_archive_invalid')
        libraries = {name for name in names if name.endswith('/libapp.so')}
        if libraries != {f'lib/{abi}/libapp.so' for abi in ABIS}:
            raise VerificationError('apk_abis_mismatch')
        for name in names:
            if name in libraries and API.encode() not in archive.read(name):
                raise VerificationError('compiled_api_mismatch')
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                elf(archive.read(name))
            if name.lower().endswith(('.jks', '.keystore', '.p12', '.pfx', '.key')):
                raise VerificationError('unexpected_private_signing_file_in_apk')
    output = ROOT / 'mobile_app/connectivity-proof'
    output.mkdir(mode=0o700)
    try:
        filename = ('AQER-UAT-1816-Connectivity-Fix.apk' if version == 1816
                    else 'AQER-UAT-1817-Durable-Update.apk')
        exported = output / filename
        shutil.copy2(apk, exported)
        with exported.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        record = {
            'source_commit': source,
            'mobile_component': call('git', 'rev-parse', 'HEAD:mobile_app').strip(),
            'backend_component': call('git', 'rev-parse', 'HEAD:backend-api-runtime').strip(),
            'package': PACKAGE, 'version_code': version, 'sha256': digest,
            'application_name': APP_NAME,
            'bytes': exported.stat().st_size,
            'signer_certificate_sha256': certificate,
            'approved_public_identity': 'docs/uat-signing-identity.json',
            'approved_for_delivery': identity['approved_for_delivery'],
            'github_secret_storage_verified': identity['github_secret_storage_verified'],
            'same_package_as_1815': True, 'same_certificate_as_1815': False,
            'previous_1815_certificate_sha256': identity['previous_1815_certificate_sha256'],
            'transition_from_1815': identity['transition_from_1815'],
            'one_time_clean_install_required_from_1815': True,
            'upgrade_from_1815_compatible': False,
            'durable_identity_first_version': identity['first_durable_version'],
            'identity_role': 'durable_baseline' if version == 1816 else 'durable_update_candidate',
            'upgrade_from_1816_expected_identity_compatible': version == 1817,
            'signing': 'GitHub-configured durable UAT key; actual APK certificate matches approved public identity',
            'debug_signing_allowed': False,
            'api': API, 'compiled_api_verified_for_all_abis': True,
            'resolved_dependency_lock_sha256': hashlib.sha256(lock.read_bytes()).hexdigest(),
            'dependency_lock_guard_verified': True,
            'ranked_discovery_build_define': True,
            'min_sdk': 23, 'target_sdk': 36, 'abis': sorted(ABIS),
            'zip_elf_16kb': 'verified', 'backend_deployed': False,
            'parallel_install_required': False, 'installed_device_upgrade_tested': False,
            'durable_update_pair_verified_in_this_job': False,
            'physical_phone_acceptance': False, 'native_acceptance_tested_in_this_job': False,
            'scope': 'APK identity, signer, version and packaging only; 1815 requires one-time clean install; durable update and data retention need separate Android evidence',
        }
        (output / 'APK_VERIFICATION.json').write_text(json.dumps(record, indent=2) + '\n')
    except Exception:
        shutil.rmtree(output)
        raise
    print(json.dumps(record, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, VerificationError) else 'connectivity_update_apk_verification_failed',
              file=sys.stderr)
        raise SystemExit(1) from None
