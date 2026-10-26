#!/usr/bin/env python3
"""Read-only verification of the APK produced by the required UAT gates."""
import base64
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import urllib.parse
import urllib.request
import zipfile

repo = os.environ['GITHUB_REPOSITORY']
source = os.environ['SOURCE_COMMIT']
run = int(os.environ['GITHUB_RUN_NUMBER'])
parser = argparse.ArgumentParser()
parser.add_argument('--upgrade-predecessor', action='store_true')
args = parser.parse_args()
version = 1000 + run - int(args.upgrade_predecessor)
token = os.environ['APK_VERIFY_TOKEN']
root = f'https://api.github.com/repos/{repo}'
headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}


def api(path, data=None):
    request = urllib.request.Request(root + path, data=None if data is None else json.dumps(data).encode(), headers={**headers, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


repository = api('')
if not repository['private']:
    policy = json.loads(Path('docs/PUBLIC_UAT_DELIVERY.json').read_text())
    assert repository['full_name'] == policy['repository'] == repo
    assert policy['visibility'] == 'public' and policy['apk_delivery'] == 'recipient-encrypted-cms-only'
    assert policy['plaintext_public_artifacts'] is False
    assert hashlib.sha256(Path(policy['recipient_certificate']).read_bytes()).hexdigest() == policy['recipient_sha256']
apk = Path('dist/uat-upgrade-predecessor.apk') if args.upgrade_predecessor else Path(f'dist/real-estate-broker-uat-{run}.apk')
digest = hashlib.sha256(apk.read_bytes()).hexdigest()
expected = Path('dist/UPGRADE_PREDECESSOR_SHA256.txt' if args.upgrade_predecessor else 'dist/SHA256.txt').read_text().split()[0]
assert digest == expected
info = dict(line.split('=', 1) for line in Path('dist/BUILD_INFO.txt').read_text().splitlines() if '=' in line)
assert info['source_commit'] == info['backend_expected_commit'] == source
assert info['stage1_ui'] == info['flutter_regression'] == 'success'
api_url = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
assert info['api_base_url'] == api_url
tools = sorted((Path(os.environ['ANDROID_HOME']) / 'build-tools').glob('*/apksigner'))
assert tools
signer = subprocess.run([str(tools[-1]), 'verify', '--verbose', '--print-certs', str(apk)], text=True, capture_output=True, check=True)
certificate = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]+)', signer.stdout).group(1).lower()
badging = subprocess.run([str(tools[-1].parent / 'aapt'), 'dump', 'badging', str(apk)], text=True, capture_output=True, check=True).stdout
assert "name='com.aqer.yemen.uat'" in badging
assert f"versionCode='{version}'" in badging
assert "application-label:'عقار UAT'" in badging
target_sdk = int(re.search(r"targetSdkVersion:'(\d+)'", badging).group(1))
min_sdk = int(re.search(r"sdkVersion:'(\d+)'", badging).group(1))
assert target_sdk >= 36, 'Google Play submissions require target API 36 or newer.'
assert min_sdk == 23, 'Preserve the approved older-device support floor.'
subprocess.run([str(tools[-1].parent / 'zipalign'), '-c', '-P', '16', '4', str(apk)],
    text=True, capture_output=True, check=True)


def verify_64bit_elf_alignment(data, name):
    """Check every PT_LOAD using the Android 16 KB ELF alignment contract."""
    assert len(data) >= 64 and data[:6] == b'\x7fELF\x02\x01', f'Invalid ELF64: {name}'
    phoff = struct.unpack_from('<Q', data, 32)[0]
    phsize, phcount = struct.unpack_from('<HH', data, 54)
    assert phsize >= 56 and phcount > 0 and phoff + phsize * phcount <= len(data), f'Invalid program headers: {name}'
    loads = 0
    for index in range(phcount):
        header = phoff + index * phsize
        if struct.unpack_from('<I', data, header)[0] != 1:
            continue
        offset, address = struct.unpack_from('<QQ', data, header + 8)
        alignment = struct.unpack_from('<Q', data, header + 48)[0]
        assert alignment >= 16384 and alignment & (alignment - 1) == 0, f'ELF segment is not 16 KB aligned: {name}'
        assert offset % 16384 == address % 16384, f'ELF mapping is not 16 KB congruent: {name}'
        loads += 1
    assert loads > 0, f'No ELF load segments: {name}'


native_64bit_count = 0
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None
    libraries = {name.split('/')[1]: name for name in archive.namelist() if name.startswith('lib/') and name.endswith('/libapp.so')}
    assert set(libraries) == {'armeabi-v7a', 'arm64-v8a', 'x86_64'}
    for library in libraries.values():
        assert api_url.encode() in archive.read(library)
    for name in archive.namelist():
        if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
            verify_64bit_elf_alignment(archive.read(name), name)
            native_64bit_count += 1
    assert native_64bit_count >= 4, 'Both 64-bit Flutter and application binaries must be verified.'
    for weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']:
        path = f'assets/ebroker/fonts/Manrope-{weight}.ttf'
        authoritative = api('/contents/mobile_app/' + path + '?ref=' + source)
        assert archive.read('assets/flutter_assets/' + path) == base64.b64decode(authoritative['content'])

brand_assets = json.loads(Path('docs/brand/ASSET_MANIFEST.json').read_text())['assets']
brand_paths = [item for item in brand_assets if item['path'].startswith('mobile_app/assets/brand/')]
assert len(brand_paths) == 4
with zipfile.ZipFile(apk) as archive:
    for item in brand_paths:
        embedded = archive.read('assets/flutter_assets/' + item['path'].removeprefix('mobile_app/'))
        assert hashlib.sha256(embedded).hexdigest() == item['sha256']

evidence = {'source_commit': source, 'version_code': version, 'sha256': digest, 'bytes': apk.stat().st_size,
    'target_sdk': target_sdk, 'min_sdk': min_sdk, 'native_16kb_elf': 'passed', 'zipalign_16kb': 'passed',
    'native_64bit_libraries_verified': native_64bit_count,
    'package': 'com.aqer.yemen.uat', 'api': api_url, 'architectures': sorted(libraries),
    'brand_assets_match': len(brand_paths), 'fonts_match': 5, 'zip_crc': 'passed', 'apksigner': 'passed', 'certificate_sha256': certificate,
    'handset_acceptance': 'pending'}
evidence['package_role'] = 'upgrade-predecessor-same-source' if args.upgrade_predecessor else 'current-uat'
Path('dist/UPGRADE_PREDECESSOR_VERIFICATION.json' if args.upgrade_predecessor else 'dist/APK_VERIFICATION.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps(evidence))

