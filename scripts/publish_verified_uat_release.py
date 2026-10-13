#!/usr/bin/env python3
"""Verify the built APK and publish it only inside the existing private repository."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request
import zipfile

repo = os.environ['GITHUB_REPOSITORY']
source = os.environ['SOURCE_COMMIT']
run = int(os.environ['GITHUB_RUN_NUMBER'])
version = 1000 + run
token = os.environ['BUILD_CHECKPOINT_TOKEN']
root = f'https://api.github.com/repos/{repo}'
headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}


def api(path, data=None):
    request = urllib.request.Request(root + path, data=None if data is None else json.dumps(data).encode(), headers={**headers, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


assert api('')['private'] is True, 'UAT installer must stay in the private repository.'
apk = Path(f'dist/real-estate-broker-uat-{run}.apk')
digest = hashlib.sha256(apk.read_bytes()).hexdigest()
expected = Path('dist/SHA256.txt').read_text().split()[0]
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
assert "name='com.example.real_estate_mobile'" in badging
assert f"versionCode='{version}'" in badging
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None
    libraries = {name.split('/')[1]: name for name in archive.namelist() if name.startswith('lib/') and name.endswith('/libapp.so')}
    assert set(libraries) == {'armeabi-v7a', 'arm64-v8a', 'x86_64'}
    for library in libraries.values():
        assert api_url.encode() in archive.read(library)
    for weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']:
        path = f'assets/ebroker/fonts/Manrope-{weight}.ttf'
        authoritative = api('/contents/mobile_app/' + path + '?ref=' + source)
        assert archive.read('assets/flutter_assets/' + path) == base64.b64decode(authoritative['content'])

evidence = {'source_commit': source, 'version_code': version, 'sha256': digest, 'bytes': apk.stat().st_size,
    'package': 'com.example.real_estate_mobile', 'api': api_url, 'architectures': sorted(libraries),
    'fonts_match': 5, 'zip_crc': 'passed', 'apksigner': 'passed', 'certificate_sha256': certificate,
    'handset_acceptance': 'pending'}
Path('dist/APK_VERIFICATION.json').write_text(json.dumps(evidence, indent=2) + '\n')
release = api('/releases', {'tag_name': f'uat-{version}', 'target_commitish': source, 'name': f'REAL ESTATE UAT {version}',
    'draft': False, 'prerelease': True, 'make_latest': 'false',
    'body': f'Private UAT installer from {source}. Backend, PostgreSQL/PostGIS, Docker runtime, Flutter analysis, focused/full Flutter and compiled endpoint gates passed. Handset acceptance remains pending. No Production deployment or main merge.'})
for path in [apk, Path('dist/BUILD_INFO.txt'), Path('dist/APK_VERIFICATION.json'), Path('dist/SHA256.txt')]:
    name = f'real-estate-uat-{version}.apk' if path == apk else path.name
    upload = release['upload_url'].split('{', 1)[0] + '?name=' + urllib.parse.quote(name)
    request = urllib.request.Request(upload, data=path.read_bytes(), method='POST', headers={
        **headers, 'Content-Type': 'application/vnd.android.package-archive' if path == apk else 'application/octet-stream'})
    with urllib.request.urlopen(request, timeout=300) as response:
        result = json.load(response)
    if path == apk:
        evidence['download_url'] = result['browser_download_url']
evidence['release_url'] = release['html_url']
print(json.dumps(evidence))
