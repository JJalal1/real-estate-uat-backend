#!/usr/bin/env python3
"""Verify an isolated private Phase04 candidate, without claiming phone acceptance."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from prepare_phase1_close import android_tools, elf

ROOT = Path(__file__).resolve().parents[1]
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
PACKAGE = 'com.aqer.yemen.uat.phase04'


def main():
    apk = ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
    tools = android_tools(Path(os.environ['ANDROID_HOME']))
    def call(*args):
        return subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True).stdout
    source = call('git', 'rev-parse', 'HEAD').strip()
    if source != os.environ['GITHUB_SHA']:
        raise RuntimeError('source_checkout_mismatch')
    call('git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib', 'mobile_app/android', 'backend-api-runtime')
    signature = call(tools / 'apksigner', 'verify', '--print-certs', apk)
    certificates = re.findall(r'^Signer #[0-9]+ certificate SHA-256 digest:\s*([a-fA-F0-9]{64})$', signature, re.MULTILINE)
    if len(certificates) != 1:
        raise RuntimeError('one_verified_test_signer_required')
    badging = call(tools / 'aapt', 'dump', 'badging', apk)
    if (f"name='{PACKAGE}' versionCode='1814'" not in badging or "sdkVersion:'23'" not in badging
            or "targetSdkVersion:'36'" not in badging or 'application-debuggable' in badging):
        raise RuntimeError('isolated_candidate_identity_mismatch')
    call(tools / 'zipalign', '-c', '-P', '16', '4', apk)
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('apk_archive_invalid')
        abis = sorted({p.split('/')[1] for p in archive.namelist() if p.endswith('/libapp.so')})
        if abis != ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
            raise RuntimeError('apk_abis_mismatch')
        for name in archive.namelist():
            if name.endswith('/libapp.so') and API.encode() not in archive.read(name):
                raise RuntimeError('compiled_api_mismatch')
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                elf(archive.read(name))
    output = ROOT / 'mobile_app/phase04-proof'
    output.mkdir(exist_ok=True)
    exported = output / 'AQER-UAT-1814-Phase04.apk'
    shutil.copy2(apk, exported)
    record = {'source_commit': source, 'backend_component': call('git', 'rev-parse', 'HEAD:backend-api-runtime').strip(),
              'mobile_component': call('git', 'rev-parse', 'HEAD:mobile_app').strip(), 'package': PACKAGE,
              'version_code': 1814, 'sha256': hashlib.file_digest(exported.open('rb'), 'sha256').hexdigest(),
              'bytes': exported.stat().st_size, 'signer_certificate_sha256': certificates[0].lower(), 'signing': 'disposable CI UAT key',
              'upgrades_owner_1812': False, 'api': API, 'required_ranked_contract': '1',
              'backend_deployed': False, 'physical_phone_acceptance': False, 'abis': abis, 'zip_elf_16kb': 'verified'}
    (output / 'APK_VERIFICATION.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record))


if __name__ == '__main__':
    main()
