#!/usr/bin/env python3
"""Package the reviewed UAT source and smoke-test the delivered bytes."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from zipfile import ZIP_DEFLATED, ZipFile


SOURCE = 'cba6e8ea47833d1fcd56ffb695a8d4e35e368e36'
TREES = {'mobile_app': 'ad06237b7aceaaba2ea4833b822d61753244af41',
         'backend-api-runtime': '681685f020d898405d54dbc76905fb0efe4130f7'}
REF = 'refs/heads/test/uat1555-owner-delivery-20261107'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
PACKAGE = 'com.aqer.yemen.uat'
VERSION = 1555
ROOT = Path(os.environ['GITHUB_WORKSPACE'])
CANDIDATE = ROOT / 'candidate'
SEALED = ROOT / 'owner-apk-sealed'
SMOKE = ROOT / 'owner-smoke-sealed'
PRIVATE = Path(os.environ['RUNNER_TEMP']) / 'aqer-owner-private'
RECIPIENT = ROOT / 'scripts/uat1555_owner_recipient.pem'
RECIPIENT_SHA = '43bab49277723298195475e9b511edb23ea7c9ff8821ed88388be65b69cc9910'
sys.path.insert(0, str(CANDIDATE / 'scripts'))
import prepare_phase1_close as tools
import probe_phase1_android_ui as core
from phase1_native_account_readiness import SECRET_NAME
from probe_phase1_followup import Followup, photo_difference
from probe_phase1_native_account import NativeAccount
from probe_phase1_uat_guest import FIXTURE_ID, FIXTURE_TITLE, get_public, node_bounds


def need(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def call(*args):
    return subprocess.check_output([str(value) for value in args], text=True, timeout=40).strip()


def sha(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def guard():
    need(os.environ.get('GITHUB_ACTIONS') == 'true' and
         os.environ.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
         os.environ.get('GITHUB_REF') == REF and os.environ.get('GITHUB_EVENT_NAME') == 'push',
         'owner_delivery_ci_scope_required')
    need(call('git', '-C', CANDIDATE, 'rev-parse', 'HEAD') == SOURCE, 'candidate_source_mismatch')
    for component, tree in TREES.items():
        need(call('git', '-C', CANDIDATE, 'rev-parse', 'HEAD:' + component) == tree,
             'candidate_product_tree_mismatch')
    need(sha(RECIPIENT) == RECIPIENT_SHA, 'delivery_recipient_mismatch')


def package():
    PRIVATE.mkdir(mode=0o700)
    SEALED.mkdir(mode=0o700)
    apk = PRIVATE / 'target.apk'
    shutil.copyfile(CANDIDATE / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', apk)
    sdk = Path(os.environ['ANDROID_HOME'])
    bt = tools.android_tools(sdk)
    signature = call(bt / 'apksigner', 'verify', '--print-certs', apk)
    cert = re.search(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
    badging = call(bt / 'aapt', 'dump', 'badging', apk)
    version_name = re.search(r"versionName='([^']+)'", badging)
    need(cert and version_name and all(value in badging for value in (
        "name='" + PACKAGE + "'", f"versionCode='{VERSION}'", "sdkVersion:'23'", "targetSdkVersion:'36'"))
         and 'application-debuggable' not in badging, 'release_identity_or_signature_mismatch')
    call(bt / 'zipalign', '-c', '-P', '16', '4', apk)
    with ZipFile(apk) as app:
        need(app.testzip() is None, 'apk_crc_invalid')
        libs = {name.split('/')[1]: name for name in app.namelist() if name.endswith('/libapp.so')}
        need(set(libs) == {'arm64-v8a', 'armeabi-v7a', 'x86_64'}, 'universal_uat_abis_required')
        for name in libs.values():
            need(API.encode() in app.read(name), 'baked_uat_endpoint_missing')
        for name in app.namelist():
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                tools.elf(app.read(name))
    helper = tools.build_input(PRIVATE, bt, sdk)
    report = {'source_commit': SOURCE, 'workflow_commit': os.environ['GITHUB_SHA'],
              'ci_run_id': os.environ['GITHUB_RUN_ID'], 'product_trees': TREES,
              'package': PACKAGE, 'version_code': VERSION, 'version_name': version_name[1],
              'api': API, 'bytes': apk.stat().st_size, 'sha256': sha(apk),
              'certificate_sha256': cert[1].lower(), 'abis': sorted(libs),
              'min_sdk': 23, 'target_sdk': 36, 'apksigner': 'PASS', 'zip_crc': 'PASS',
              'align_16k': 'PASS', 'signing': 'disposable UAT debug key for release flavor',
              'input_driver': {'sha256': sha(helper)}}
    report['encrypted_installer'] = tools.encrypt(apk, SEALED / 'installer.cms', RECIPIENT)
    write(PRIVATE / 'APK_VERIFICATION.json', report)
    write(SEALED / 'APK_VERIFICATION.json', report)


class GuestSmoke(Followup):
    def __init__(self, serial):
        self.root, self.run = CANDIDATE, core.execute
        self.serial, self.live_fixture = serial, False
        self.out = PRIVATE / 'guest-frames'
        self.out.mkdir(mode=0o700)
        self.report = {'frames': [], 'cases': []}

    def search_live(self):
        http, body = get_public('/api/properties/60')
        fixture = body.get('data', {})
        need(http['http_status'] == 200 and fixture.get('id') == FIXTURE_ID
             and fixture.get('title') == FIXTURE_TITLE and fixture.get('status') == 'published',
             'published_synthetic_fixture_required')
        self.home_entry('search')
        self.wait('البحث عن عقار')
        self.native('fixture-query')
        self.tap('تنفيذ')
        self.wait('نتائج «شقة للإيجار»')
        for label in ('شقق', 'إيجار'):
            if not self.selected()[label]:
                self.tap(label)
        self.wait(FIXTURE_TITLE, 70)
        selected = self.selected()
        need(selected['شقق'] and selected['إيجار'] and not selected['بيع'], 'search_filter_scope_mismatch')
        oracle = self.public_oracle()
        self.frame('uat-apartment-rent-results')
        self.tap(FIXTURE_TITLE)
        self.wait('تفاصيل العقار')
        self.wait(FIXTURE_TITLE)
        self.frame('uat-result-details')
        return {'fixture': FIXTURE_ID, 'http': oracle['http_status'],
                'rental_apartment_filter': True, 'matched_result_card_opened': True}

    def gallery_live(self):
        self.tap('تكبير الصور')
        self.dismiss_immersive_tutorial()
        time.sleep(2)
        base = self.frame('uat-photo-before-zoom')
        left, top, right, bottom = node_bounds(self.fullscreen_gallery_image(self.report['frames'][-1]))
        center = ((left + right) // 2, (top + bottom) // 2)
        self.native('pinch-out', center)
        time.sleep(.6)
        expanded = self.frame('uat-photo-enlarged')
        zoom = photo_difference(self.out / base, self.out / expanded)
        self.native('pinch-in', center)
        time.sleep(.6)
        reduced = self.frame('uat-photo-reduced')
        shrink = photo_difference(self.out / expanded, self.out / reduced)
        need(zoom['changed_fraction'] >= .15 and shrink['changed_fraction'] >= .15
             and zoom['mean_absolute_difference'] >= 5, 'rendered_photo_change_not_observed')
        return {'real_two_pointer_gestures': True, 'zoom_delta': zoom, 'reduce_delta': shrink}


def safe_code(error):
    message = str(error)
    if re.fullmatch(r'[a-z][a-z0-9_]{2,90}', message):
        return message
    return type(error).__name__


def smoke():
    proof = json.loads((PRIVATE / 'APK_VERIFICATION.json').read_text())
    report = {'source_commit': SOURCE, 'ci_run_id': proof['ci_run_id'], 'apk_sha256': proof['sha256'],
              'api': API, 'checks': {}}

    def check(name, operation):
        try:
            facts = operation()
            report['checks'][name] = {'status': 'PASS', **(facts or {})}
            return True
        except Exception as error:
            report['checks'][name] = {'status': 'BLOCKED', 'reason': safe_code(error)}
            return False

    guest = broker = None
    try:
        # This legacy install verifier binds the hash to the checked-out
        # application source, which is separate from the workflow commit.
        broker = NativeAccount(PRIVATE, dict(os.environ, GITHUB_SHA=SOURCE, SOURCE_COMMIT=SOURCE))
        installed = check('install_api36_kvm', broker.validate_and_install)
        if installed and check('real_app_launch', broker.startup):
            guest = GuestSmoke(broker.serial)
            if check('live_search_filters_and_details', guest.search_live):
                check('live_image_zoom', guest.gallery_live)
            broker.adb('shell', 'am', 'force-stop', PACKAGE)
            if check('return_to_live_home', broker.startup):
                check('normal_test_broker_login', broker.login)
    except Exception as error:
        report['checks']['smoke_driver'] = {'status': 'BLOCKED', 'reason': safe_code(error)}
    finally:
        if broker is not None and broker.auth_attempted:
            def logout():
                broker.native_logout()
                need(broker.report.get('session_logged_out') is True, 'native_logout_not_confirmed')
            check('test_session_logout', logout)
        SMOKE.mkdir(mode=0o700)
        if guest is not None:
            report['frames'] = guest.report['frames']
        required = {'install_api36_kvm', 'real_app_launch', 'live_search_filters_and_details',
                    'live_image_zoom', 'return_to_live_home', 'normal_test_broker_login', 'test_session_logout'}
        report['status'] = ('PASS' if required == report['checks'].keys()
                            and all(x['status'] == 'PASS' for x in report['checks'].values()) else 'BLOCKED')
        write(PRIVATE / 'SMOKE_VERIFICATION.json', report)
        with ZipFile(PRIVATE / 'smoke.zip', 'w', ZIP_DEFLATED) as bundle:
            bundle.write(PRIVATE / 'SMOKE_VERIFICATION.json', 'SMOKE_VERIFICATION.json')
            for row in report.get('frames', []):
                name = row['file']
                need(re.fullmatch(r'uat-[a-z0-9-]+\.png', name)
                     or name == 'gallery-system-immersive-tutorial.png', 'expected_smoke_frame_required')
                bundle.write(guest.out / name, name)
        sealed = tools.encrypt(PRIVATE / 'smoke.zip', SMOKE / 'smoke.cms', RECIPIENT)
        write(SMOKE / 'SMOKE_RECEIPT.json', {'source_commit': SOURCE, 'ci_run_id': proof['ci_run_id'],
                                           'apk_sha256': proof['sha256'], 'encrypted': sealed})
        print('AQER_OWNER_SMOKE ' + json.dumps({'status': report['status'], 'checks': report['checks']}))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    os.umask(0o077)
    guard()
    if sys.argv[1:] == ['package']:
        package()
    elif sys.argv[1:] == ['smoke']:
        sys.exit(smoke())
    else:
        sys.exit('expected package or smoke')
