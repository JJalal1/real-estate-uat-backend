#!/usr/bin/env python3
"""Verify a same-job UAT update pair; never export or persist a signing key."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from phase23_preflight import API, TREES, GateError, guard
from phase23_firebase import validate_receipt, verify_compiled_configuration
from prepare_phase23_native import ROOT, PRIVATE, CERT, sha
import prepare_phase1_close as tools


def validate_pair(baseline, upgrade):
    fields = ('source_commit', 'product_source_commit', 'product_trees', 'ci_run_id',
              'package', 'certificate_sha256', 'api', 'target_sdk', 'min_sdk',
              'experiments', 'firebase')
    validate_receipt(baseline.get('firebase'))
    validate_receipt(upgrade.get('firebase'))
    if any(baseline.get(k) != upgrade.get(k) for k in fields):
        raise GateError('upgrade_pair_identity_mismatch')
    if (baseline.get('package') != 'com.aqer.yemen.uat' or baseline.get('api') != API or
            baseline.get('product_trees') != TREES or
            not re.fullmatch(r'[a-f0-9]{64}', baseline.get('certificate_sha256', '')) or
            type(baseline.get('version_code')) is not int or
            type(upgrade.get('version_code')) is not int or
            upgrade['version_code'] != baseline['version_code'] + 1 or
            baseline.get('target_sdk') != 36 or baseline.get('min_sdk') != 23):
        raise GateError('bounded_verified_uat_upgrade_pair_required')


def prepare():
    guard(os.environ)
    baseline = json.loads((PRIVATE / 'APK_VERIFICATION.json').read_text())
    if (baseline['source_commit'] != os.environ['GITHUB_SHA'] or
            baseline['ci_run_id'] != os.environ['GITHUB_RUN_ID']):
        raise GateError('current_run_baseline_required')
    apk = PRIVATE / 'upgrade.apk'
    shutil.copyfile(ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', apk)
    bt = tools.android_tools(Path(os.environ['ANDROID_HOME']))
    def call(*args):
        return subprocess.check_output([str(x) for x in args], text=True, timeout=60)
    signature = call(bt / 'apksigner', 'verify', '--print-certs', apk)
    certificate = re.search(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
    version = baseline['version_code'] + 1
    badging = call(bt / 'aapt', 'dump', 'badging', apk)
    if not certificate or 'application-debuggable' in badging or not all(s in badging for s in
            ["name='com.aqer.yemen.uat'", f"versionCode='{version}'", "sdkVersion:'23'", "targetSdkVersion:'36'"]):
        raise GateError('verified_release_upgrade_required')
    call(bt / 'zipalign', '-c', '-P', '16', '4', apk)
    with zipfile.ZipFile(apk) as app:
        if app.testzip() is not None:
            raise GateError('upgrade_zip_integrity_failed')
        libs = [n for n in app.namelist() if n.endswith('/libapp.so')]
        if {n.split('/')[1] for n in libs} != {'arm64-v8a', 'armeabi-v7a', 'x86_64'} or not all(
                API.encode() in app.read(n) for n in libs):
            raise GateError('upgrade_architecture_or_endpoint_mismatch')
        for name in app.namelist():
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                tools.elf(app.read(name))
        firebase = verify_compiled_configuration(app, ROOT / 'mobile_app/android/firebase-uat.properties')
    upgrade = dict(baseline, version_code=version, sha256=sha(apk), bytes=apk.stat().st_size,
                   certificate_sha256=certificate[1].lower(), firebase=firebase)
    validate_pair(baseline, upgrade)
    pair = {'baseline': baseline, 'upgrade': upgrade, 'same_job_disposable_signing': True,
            'scope': 'UAT emulator update pair only; stable signing and Play remain separate'}
    (PRIVATE / 'UPGRADE_VERIFICATION.json').write_text(json.dumps(pair, indent=2) + '\n')
    out = ROOT / 'phase23-installer-sealed'
    tools.encrypt(apk, out / 'upgrade.cms', CERT)
    shutil.copyfile(PRIVATE / 'UPGRADE_VERIFICATION.json', out / 'UPGRADE_VERIFICATION.json')
    print('AQER_PHASE23_COMPATIBLE_UAT_PAIR_VERIFIED')


if __name__ == '__main__':
    prepare()
