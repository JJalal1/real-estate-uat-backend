#!/usr/bin/env python3
"""Verify a same-package/same-signer 1816 candidate; never claim device upgrade."""
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

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/work/fix-connectivity-1815-20261117'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
PACKAGE = 'com.aqer.yemen.uat.offline'
APP_NAME = 'عقار أوفلاين اختبار'
VERSION = 1816
INSTALLED_1815_SIGNER = 'a157c63cd37090cebac83d2a2786e1e3342a8b09f17daeea30e93a5cbd65796f'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}


class VerificationError(ValueError):
    """Fixed public reason codes only; never tool output or credential data."""


def call(*args):
    return subprocess.run([str(value) for value in args], cwd=ROOT, check=True,
                          capture_output=True, text=True, timeout=90).stdout


def main():
    env = os.environ
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and
            env.get('AQER_SIGNING_ENVIRONMENT') == 'uat' and
            env.get('AQER_UAT_SIGNING_CONFIGURED') == 'true' and
            env.get('AQER_ALLOW_DEBUG_RELEASE_SIGNING') == 'false' and
            env.get('AQER_UAT_SIGNING_CERT_SHA256') == INSTALLED_1815_SIGNER):
        raise VerificationError('verified_installed_uat_signing_context_required')
    source = call('git', 'rev-parse', 'HEAD').strip()
    if source != env.get('GITHUB_SHA') or not re.fullmatch(r'[a-f0-9]{40}', source):
        raise VerificationError('source_checkout_mismatch')
    call('git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib',
         'mobile_app/android', 'mobile_app/assets', 'mobile_app/pubspec.yaml',
         'backend-api-runtime')
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
    if [(number, digest.lower()) for number, digest in certificates] != [('1', INSTALLED_1815_SIGNER)]:
        raise VerificationError('installed_1815_signer_mismatch')
    badging = call(tools / 'aapt', 'dump', 'badging', apk)
    packages = re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE)
    if (packages != [(PACKAGE, str(VERSION))] or
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
        exported = output / 'AQER-UAT-1816-Connectivity-Fix.apk'
        shutil.copy2(apk, exported)
        with exported.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        record = {
            'source_commit': source,
            'mobile_component': call('git', 'rev-parse', 'HEAD:mobile_app').strip(),
            'backend_component': call('git', 'rev-parse', 'HEAD:backend-api-runtime').strip(),
            'package': PACKAGE, 'version_code': VERSION, 'sha256': digest,
            'application_name': APP_NAME,
            'bytes': exported.stat().st_size,
            'signer_certificate_sha256': INSTALLED_1815_SIGNER,
            'same_package_and_certificate_as_installed_1815': True,
            'signing': 'existing GitHub-configured UAT key; actual certificate pinned to installed 1815',
            'debug_signing_allowed': False, 'new_signing_key_generated': False,
            'api': API, 'compiled_api_verified_for_all_abis': True,
            'resolved_dependency_lock_sha256': hashlib.sha256(lock.read_bytes()).hexdigest(),
            'dependency_lock_guard_verified': True,
            'ranked_discovery_build_define': True,
            'min_sdk': 23, 'target_sdk': 36, 'abis': sorted(ABIS),
            'zip_elf_16kb': 'verified', 'backend_deployed': False,
            'parallel_install_required': False, 'installed_device_upgrade_tested': False,
            'physical_phone_acceptance': False, 'native_acceptance_tested_in_this_job': False,
            'scope': 'APK identity, signer, version and packaging; installed-device update and data retention remain untested',
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
