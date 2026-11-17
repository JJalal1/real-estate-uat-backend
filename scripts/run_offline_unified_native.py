#!/usr/bin/env python3
"""Three process lifetimes on a disposable emulator; synthetic fixtures only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

PACKAGE = 'com.aqer.yemen.uat.offlineprobe'
ACTIVITY = 'com.example.real_estate_mobile.MainActivity'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', default='offline-native-proof')
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('AQER_OFFLINE_NATIVE_PROBE') != 'true' or not re.fullmatch(r'emulator-\d{4}', args.serial):
        raise RuntimeError('explicit_disposable_emulator_required')
    if any(os.environ.get(k) for k in ('AQER_UAT_KEYSTORE_BASE64', 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', 'AQER_PHASE1_TEST_ACCESS_JSON', 'AQER_RELEASE_KEY_PASSWORD')):
        raise RuntimeError('native_probe_credentials_forbidden')
    apk = Path(args.apk).resolve()
    if apk.is_symlink() or not apk.is_file():
        raise RuntimeError('probe_apk_missing')
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
    badging = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    if f"name='{PACKAGE}'" not in badging:
        raise RuntimeError('isolated_package_required')
    subprocess.run([str(tools / 'apksigner'), 'verify', str(apk)], check=True)
    output = Path(args.output); output.mkdir(exist_ok=True)
    def adb(*values, timeout=25):
        return subprocess.check_output(['adb', '-s', args.serial, *values], timeout=timeout, text=True, stderr=subprocess.STDOUT)
    events = []
    try:
        adb('install', '-r', str(apk), timeout=90)
        for phase in (1, 2, 3):
            adb('shell', 'am', 'force-stop', PACKAGE)
            mode = 'disable' if phase == 2 else 'enable'
            adb('shell', 'svc', 'wifi', mode); adb('shell', 'svc', 'data', mode)
            adb('logcat', '-c')
            adb('shell', 'am', 'start', '-n', f'{PACKAGE}/{ACTIVITY}')
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline:
                lines = adb('logcat', '-d', '-s', 'flutter:I', '*:S')
                parsed = [json.loads(s) for s in re.findall(r'AQER_OFFLINE_NATIVE (\{[^\n]*\})', lines)]
                if any(event.get('failed') for event in parsed):
                    raise RuntimeError('native_assertion_failed_' + str(phase))
                rows = [event for event in parsed if event.get('phase') == phase and event.get('passed') is True]
                if rows:
                    if len(rows) != 1:
                        raise RuntimeError('ambiguous_native_receipt')
                    events.append(rows[0]); break
                time.sleep(1)
            else:
                raise RuntimeError('native_phase_deadline_' + str(phase))
        def git(*values):
            return subprocess.check_output(['git', *values], text=True).strip()
        receipt = {'passed': True, 'source_commit': git('rev-parse', 'HEAD'), 'mobile_component': git('rev-parse', 'HEAD:mobile_app'),
                   'backend_component': git('rev-parse', 'HEAD:backend-api-runtime'), 'package': PACKAGE,
                   'probe_apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(), 'api': 'synthetic.invalid; Dart sockets denied',
                   'process_launches': 3, 'events': events,
                   'checks': ['native_keystore_restart', 'native_cipher_tamper_rejected', 'encrypted_snapshots_at_rest',
                              'http_snapshot_restart_without_network', 'small_photo_restart_without_network', 'large_photo_offline_blocked',
                              'manual_fields_and_copied_photos_restart', 'outbox_actor_isolation', 'pending_no_send_offline',
                              'reconnect_same_client_id_after_lost_ack', 'native_map_offline_channel'],
                   'physical_phone_acceptance': False, 'public_map_tiles_or_gestures_tested': False, 'live_account_or_business_api_used': False}
        (output / 'OFFLINE_NATIVE_RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt))
    finally:
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'svc', 'wifi', 'enable'); adb('shell', 'svc', 'data', 'enable')

if __name__ == '__main__':
    main()
