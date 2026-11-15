#!/usr/bin/env python3
"""Verify the approved UAT signer and export only recipient-encrypted APK bytes."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from phase23_preflight import API, GateError, TREES, guard
from phase23_firebase import verify_compiled_configuration
import prepare_phase1_close as android

ROOT = Path(__file__).resolve().parents[1]
RECIPIENT = ROOT / 'scripts/phase23_recipient.pem'
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
PACKAGE = 'com.aqer.yemen.uat'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def signing_context(env):
    """Only a successful explicit UAT import may enter this release path."""
    if (env.get('AQER_SIGNING_ENVIRONMENT') != 'uat' or
            env.get('AQER_UAT_SIGNING_CONFIGURED') != 'true' or
            env.get('AQER_ALLOW_DEBUG_RELEASE_SIGNING') != 'false' or
            not re.fullmatch(r'[a-f0-9]{64}', env.get('AQER_UAT_SIGNING_CERT_SHA256', '')) or
            not re.fullmatch(r'[1-9][0-9]{0,9}', env.get('PHASE23_BUILD', '')) or
            not re.fullmatch(r'[1-9][0-9]*', env.get('GITHUB_RUN_ID', ''))):
        raise GateError('verified_uat_signing_context_required')
    version = int(env['PHASE23_BUILD'])
    if not 1612 <= version <= 2100000000:
        raise GateError('new_uat_version_required')
    return version, env['AQER_UAT_SIGNING_CERT_SHA256']


def verify_metadata(signature, badging, version, pin):
    # Reject extra signers as well as a different signer; a substring match is
    # insufficient proof of the certificate that signed this APK.
    certificates = re.findall(
        r'^Signer #([1-9][0-9]*) certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\s*$',
        signature, re.MULTILINE)
    if [(number, digest.lower()) for number, digest in certificates] != [('1', pin)]:
        raise GateError('uat_apk_signing_certificate_mismatch')
    packages = re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE)
    if (packages != [(PACKAGE, str(version))] or
            re.findall(r"^sdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['23'] or
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", badging, re.MULTILINE) != ['36'] or
            'application-debuggable' in badging):
        raise GateError('uat_apk_identity_or_sdk_mismatch')


def verify_archive(apk, properties):
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise GateError('uat_apk_archive_invalid')
        libraries = [name for name in names if name.endswith('/libapp.so')]
        if set(libraries) != {f'lib/{abi}/libapp.so' for abi in ABIS}:
            raise GateError('uat_apk_architectures_mismatch')
        if not all(API.encode() in archive.read(name) for name in libraries):
            raise GateError('uat_apk_api_mismatch')
        for name in names:
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                android.elf(archive.read(name))
        return verify_compiled_configuration(archive, properties)


def verify_recipient(recipient):
    if (recipient.is_symlink() or not recipient.is_file() or
            sha256(recipient) != RECIPIENT_SHA256):
        raise GateError('reviewed_uat_recipient_required')


def export_sealed(apk, receipt, output, recipient):
    """Fresh output directory contains ciphertext and a public receipt only."""
    verify_recipient(recipient)
    # Exclusive creation prevents stale artifacts or redirected output. We
    # remove only the directory created by this invocation on failure.
    output.mkdir(mode=0o700)
    try:
        encrypted = android.encrypt(apk, output / 'installer.cms', recipient)
        exported = {**receipt, 'encrypted_installer': encrypted,
                    'recipient_sha256': RECIPIENT_SHA256}
        with (output / 'APK_VERIFICATION.json').open('x', encoding='utf-8') as stream:
            stream.write(json.dumps(exported, indent=2) + '\n')
        return exported
    except Exception:
        shutil.rmtree(output)
        raise


def prepare():
    version, pin = signing_context(os.environ)
    guard(os.environ)  # Exact repository/ref/push/SHA and reviewed component trees.
    subprocess.run([
        'git', '-C', str(ROOT), 'diff', '--exit-code', 'HEAD', '--',
        'mobile_app/lib', 'mobile_app/android', 'mobile_app/assets',
        'mobile_app/pubspec.yaml', 'backend-api-runtime',
    ], check=True, capture_output=True, timeout=30)
    apk = ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
    if apk.is_symlink() or not apk.is_file():
        raise GateError('uat_release_apk_required')
    bt = android.android_tools(Path(os.environ['ANDROID_HOME']))

    def call(*args):
        return subprocess.run([str(arg) for arg in args], check=True,
                              capture_output=True, text=True, timeout=90).stdout

    signature = call(bt / 'apksigner', 'verify', '--print-certs', apk)
    badging = call(bt / 'aapt', 'dump', 'badging', apk)
    verify_metadata(signature, badging, version, pin)
    call(bt / 'zipalign', '-c', '-P', '16', '4', apk)
    firebase = verify_archive(apk, ROOT / 'mobile_app/android/firebase-uat.properties')
    receipt = {
        'source_commit': os.environ['GITHUB_SHA'], 'product_trees': TREES,
        'ci_run_id': os.environ['GITHUB_RUN_ID'], 'package': PACKAGE,
        'version_code': version, 'sha256': sha256(apk), 'bytes': apk.stat().st_size,
        'certificate_sha256': pin, 'api': API, 'target_sdk': 36, 'min_sdk': 23,
        'abis': sorted(ABIS), 'zip_and_elf_16kb_verified': True,
        'signing': 'configured UAT private key; actual APK certificate matches approved pin',
        'stable_signing_used_for_build': True, 'debug_signing_allowed': False,
        'firebase': firebase, 'native_acceptance_tested_in_this_job': False,
        'upgrade_from_previous_apk_tested': False, 'production_or_store_release': False,
        'acceptance_scope': 'Installer identity, signature and packaging only; no device, upgrade or FCM delivery acceptance',
    }
    export_sealed(apk, receipt, ROOT / 'phase23-signed-uat-sealed', RECIPIENT)
    print('AQER_PHASE23_SIGNED_UAT_INSTALLER_VERIFIED')


if __name__ == '__main__':
    try:
        prepare()
    except Exception as error:
        # Third-party tool output and paths never become public failure logs.
        print(str(error) if isinstance(error, GateError) else 'uat_signed_installer_verification_failed',
              file=sys.stderr)
        raise SystemExit(1) from None
