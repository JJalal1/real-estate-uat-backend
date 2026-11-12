#!/usr/bin/env python3
"""Exact-source UAT installer and the existing self-targeted Android input helper."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from phase23_preflight import guard, API, TREES
import prepare_phase1_close as tools

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / 'phase23-native-private'
CERT = ROOT / 'scripts/phase23_recipient.pem'


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tool_digest():
    paths = ['scripts/run_phase23_native.py', 'scripts/prepare_phase23_native.py',
             'scripts/phase23_preflight.py', 'scripts/phase23_recipient.pem',
             'scripts/probe_phase1_native_account.py', 'scripts/phase1_device_input/Phase1Input.java',
             'scripts/prepare_phase23_upgrade.py',
             '.github/actions/phase1-review/index.js']
    return hashlib.sha256(json.dumps({p: sha(ROOT / p) for p in paths}, sort_keys=True).encode()).hexdigest()


def prepare():
    guard(os.environ)
    PRIVATE.mkdir(mode=0o700)
    apk = PRIVATE / 'target.apk'
    shutil.copyfile(ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', apk)
    sdk = Path(os.environ['ANDROID_HOME'])
    bt = tools.android_tools(sdk)
    def call(*args):
        return subprocess.check_output([str(x) for x in args], text=True, timeout=60)
    signature = call(bt / 'apksigner', 'verify', '--print-certs', apk)
    certificate = re.search(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
    badging = call(bt / 'aapt', 'dump', 'badging', apk)
    version = int(os.environ['PHASE23_BUILD'])
    assert certificate and all(s in badging for s in ["name='com.aqer.yemen.uat'", f"versionCode='{version}'", "sdkVersion:'23'", "targetSdkVersion:'36'"])
    assert 'application-debuggable' not in badging
    call(bt / 'zipalign', '-c', '-P', '16', '4', apk)
    with zipfile.ZipFile(apk) as app:
        assert app.testzip() is None
        libs = [n for n in app.namelist() if n.endswith('/libapp.so')]
        assert {n.split('/')[1] for n in libs} == {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
        assert all(API.encode() in app.read(n) for n in libs)
        for n in app.namelist():
            if n.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and n.endswith('.so'):
                tools.elf(app.read(n))
    helper = tools.build_input(PRIVATE, bt, sdk)
    receipt = {'source_commit': os.environ['GITHUB_SHA'], 'product_source_commit': os.environ['GITHUB_SHA'],
               'product_trees': TREES, 'ci_run_id': os.environ['GITHUB_RUN_ID'],
               'package': 'com.aqer.yemen.uat', 'version_code': version,
               'sha256': sha(apk), 'bytes': apk.stat().st_size,
               'certificate_sha256': certificate[1].lower(), 'api': API,
               'target_sdk': 36, 'min_sdk': 23, 'signing': 'disposable UAT release signing',
               'input_driver': {'sha256': sha(helper)},
               'experiments': {'conditional_prefetch': os.environ.get('PHASE23_PREFETCH_ON') == 'true'}}
    (PRIVATE / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    out = ROOT / 'phase23-installer-sealed'
    out.mkdir(mode=0o700)
    tools.encrypt(apk, out / 'installer.cms', CERT)
    shutil.copyfile(PRIVATE / 'APK_VERIFICATION.json', out / 'APK_VERIFICATION.json')
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('AQER_BRIDGE_TOOLBUNDLE_SHA=' + tool_digest() + '\n')
    print('AQER_PHASE23_NATIVE_RELEASE_VERIFIED')


if __name__ == '__main__':
    prepare()
