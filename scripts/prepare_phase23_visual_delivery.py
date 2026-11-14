#!/usr/bin/env python3
"""Verify an ordinary-main visual revision and export recipient-encrypted APK.

Reuse the existing APK primitives explicitly, without changing any legacy gate.
No synthetic entry point, input helper, credentials or live preflight is used.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from phase23_preflight import GateError
from phase23_visual_revision import API, SHARE_BASE, guard
from phase23_firebase import disabled_receipt, verify_compiled_configuration
from prepare_phase1_close import android_tools, elf, encrypt

ROOT = Path(__file__).resolve().parents[1]
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
FORBIDDEN_MARKERS = (
    b'AQER_PHASE23_PRIVATE_PAGES_READ_ONLY_V1',
    b'AQER_PHASE23_CALLBACK_READ_ONLY_V1',
    b'AQER_OFFLINE_VISUAL_TARGET_V1', b'SYNTHETIC OFFLINE',
    b'AQER_VISUAL_CASE_', b'AQER_VISUAL_SCROLL', b'AQER_VISUAL_NEXT',
    b'AQER_OFFLINE_DEVICE_TARGET_V1', b'SYNTHETIC DEVICE SESSION',
    b'DEVICE_META ', b'AQER_DEVICE ',
    b'AQER_OFFLINE_JOURNEYS_TARGET_V1', b'AQER_OFFLINE_JOURNEYS_TAIL9_V1',
    b'AQER_JOURNEY_STAGE_', b'AQER_JOURNEY_NEXT', b'AQER_JOURNEY_SCROLL',
    b'AQER_LOCAL_MEDIA_FIXTURE_V1', b'AQER_LOCAL_MEDIA_BUILD_V1',
    b'http://10.0.2.2:8000/api',
)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def call(*args):
    return subprocess.check_output([str(x) for x in args], text=True, timeout=60)


def build_number(env):
    value = env.get('PHASE23_BUILD', '')
    if (not isinstance(value, str) or not re.fullmatch('[1-9][0-9]*', value)
            or not 1801 <= int(value) <= 2100000000):
        raise GateError('visual_delivery_build_number_invalid')
    if env.get('PHASE23_PREFETCH_ON') != 'true':
        raise GateError('visual_delivery_preserves_prefetch_on')
    if any(env.get(k) not in (None, '', 'false') for k in
           ('PHASE23_PRIVATE_PAGES', 'PHASE23_CALLBACK_HARNESS')):
        raise GateError('visual_delivery_ordinary_main_required')
    return int(value)


def verify_archive(archive, properties):
    names = archive.namelist()
    if len(names) != len(set(names)) or archive.testzip() is not None:
        raise GateError('visual_delivery_apk_archive_invalid')
    libs = [name for name in names if name.endswith('/libapp.so')]
    if set(libs) != {f'lib/{abi}/libapp.so' for abi in ABIS}:
        raise GateError('visual_delivery_three_abis_required')
    for name in libs:
        data = archive.read(name)
        if API.encode() not in data:
            raise GateError('visual_delivery_uat_api_missing')
        # The API string itself contains the share origin. Require a separate
        # compiled share-origin value, rather than counting that same prefix.
        if not re.search(re.escape(SHARE_BASE.encode()) + rb'(?!/api)', data):
            raise GateError('visual_delivery_uat_share_origin_missing')
        if any(marker in data for marker in FORBIDDEN_MARKERS):
            raise GateError('visual_delivery_test_target_forbidden')
    for name in names:
        if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
            elf(archive.read(name))
    if Path(properties).exists():
        raise GateError('visual_delivery_firebase_configuration_forbidden')
    firebase = verify_compiled_configuration(archive, properties)
    if firebase != disabled_receipt():
        raise GateError('visual_delivery_firebase_must_be_off')
    for name in names:
        if re.fullmatch(r'classes[0-9]*\.dex', name):
            data = archive.read(name)
            if re.search(rb'1:[0-9]+:android:[0-9a-f]+', data):
                raise GateError('visual_delivery_compiled_firebase_client_forbidden')
    return firebase


def prepare(env, root=ROOT):
    identity = guard(env, root)
    version = build_number(env)
    cert = root / 'scripts/phase23_recipient.pem'
    if (env.get('PHASE23_RECIPIENT_SHA256') != RECIPIENT_SHA256 or
            sha(cert) != RECIPIENT_SHA256 or
            '-----BEGIN CERTIFICATE-----' not in cert.read_text()):
        raise GateError('visual_delivery_recipient_mismatch')
    private = root / 'phase23-visual-delivery-private'
    private.mkdir(mode=0o700)
    private.chmod(0o700)
    apk = private / 'target.apk'
    shutil.copyfile(root / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', apk)
    apk.chmod(0o600)
    bt = android_tools(Path(env['ANDROID_HOME']))
    signature = call(bt / 'apksigner', 'verify', '--print-certs', apk)
    certificates = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
    if len(certificates) != 1:
        raise GateError('visual_delivery_single_verified_signer_required')
    badging = call(bt / 'aapt', 'dump', 'badging', apk)
    required = ["name='com.aqer.yemen.uat'", f"versionCode='{version}'",
                "sdkVersion:'23'", "targetSdkVersion:'36'"]
    if not all(value in badging for value in required) or 'application-debuggable' in badging:
        raise GateError('visual_delivery_release_identity_mismatch')
    call(bt / 'zipalign', '-c', '-P', '16', '4', apk)
    with zipfile.ZipFile(apk) as archive:
        firebase = verify_archive(archive, root / 'mobile_app/android/firebase-uat.properties')
    receipt = {**identity, 'product_source_commit': identity['source_commit'],
               'package': 'com.aqer.yemen.uat', 'version_code': version,
               'entrypoint': 'lib/main.dart', 'sha256': sha(apk), 'bytes': apk.stat().st_size,
               'certificate_sha256': certificates[0].lower(),
               'api': API, 'share_base_url': SHARE_BASE,
               'target_sdk': 36, 'min_sdk': 23, 'abis': sorted(ABIS),
               'elf_and_zip_16kb_verified': True,
               'signing': 'temporary UAT signing; owner update compatibility not accepted',
               'owner_update_compatibility_verified': False, 'firebase': firebase,
               'experiments': {'conditional_prefetch': True, 'callback_harness': False,
                               'private_pages': False, 'synthetic_offline': False},
               'native_acceptance_claimed': False, 'private_key_exported': False}
    (private / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    out = root / 'phase23-visual-installer-sealed'
    out.mkdir(mode=0o700)
    out.chmod(0o700)
    sealed = encrypt(apk, out / 'installer.cms', cert)
    receipt['encrypted_installer'] = sealed
    (out / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if {p.name for p in out.iterdir()} != {'installer.cms', 'APK_VERIFICATION.json'}:
        raise GateError('visual_delivery_ciphertext_only_output_required')
    print('AQER_PHASE23_VISUAL_ORDINARY_MAIN_ENCRYPTED')
    return receipt


if __name__ == '__main__':
    prepare(os.environ)
