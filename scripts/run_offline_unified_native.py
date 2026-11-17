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
    def git(*values):
        return subprocess.check_output(['git', *values], text=True).strip()
    def token(value):
        text = str(value)
        return text if re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}', text) else 'unavailable'
    def failure_reason(error):
        if isinstance(error, subprocess.CalledProcessError):
            return 'adb_command_failed_exit_' + str(error.returncode)
        if isinstance(error, subprocess.TimeoutExpired):
            return 'adb_command_timeout'
        return token(str(error)) if isinstance(error, RuntimeError) else token(type(error).__name__)
    events = []
    network_controls = []
    native_failures = []
    cleanup_failures = []
    receipt = {'passed': False, 'status': 'failed', 'source_commit': git('rev-parse', 'HEAD'),
               'mobile_component': git('rev-parse', 'HEAD:mobile_app'),
               'backend_component': git('rev-parse', 'HEAD:backend-api-runtime'), 'package': PACKAGE,
               'probe_apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
               'api': 'synthetic.invalid; Dart sockets denied', 'process_launches': 0,
               'events': events, 'network_controls': network_controls, 'native_failures': native_failures,
               'cleanup_failures': cleanup_failures, 'checks': [], 'physical_phone_acceptance': False,
               'public_map_tiles_or_gestures_tested': False, 'live_account_or_business_api_used': False}
    stage = 'install'
    try:
        adb('install', '-r', str(apk), timeout=90)
        for phase in (1, 2, 3):
            stage = f'phase_{phase}_force_stop'
            adb('shell', 'am', 'force-stop', PACKAGE)
            mode = 'disable' if phase == 2 else 'enable'
            stage = f'phase_{phase}_wifi_{mode}'
            adb('shell', 'svc', 'wifi', mode)
            network_controls.append({'phase': phase, 'service': 'wifi', 'mode': mode, 'returncode': 0})
            stage = f'phase_{phase}_data_{mode}'
            try:
                adb('shell', 'svc', 'data', mode)
                network_controls.append({'phase': phase, 'service': 'data', 'mode': mode, 'returncode': 0})
            except subprocess.CalledProcessError as error:
                control = {'phase': phase, 'service': 'data', 'mode': mode, 'returncode': error.returncode,
                           'tolerated': error.returncode == 20}
                network_controls.append(control)
                print('AQER_OFFLINE_NETWORK_CONTROL ' + json.dumps(control), flush=True)
                if error.returncode != 20:
                    raise
                # Some emulators have no usable cellular control. This never
                # substitutes for the probe's mandatory native connected-state
                # assertion at the beginning of every phase, including offline.
            stage = f'phase_{phase}_clear_log'
            adb('logcat', '-c')
            stage = f'phase_{phase}_start'
            adb('shell', 'am', 'start', '-n', f'{PACKAGE}/{ACTIVITY}')
            receipt['process_launches'] += 1
            stage = f'phase_{phase}_runtime'
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline:
                lines = adb('logcat', '-d', '-s', 'flutter:I', '*:S')
                parsed = [json.loads(s) for s in re.findall(r'AQER_OFFLINE_NATIVE (\{[^\n]*\})', lines)]
                failures = [event for event in parsed if event.get('failed')]
                if failures:
                    for event in failures:
                        failure = {'phase': phase, 'failed': True,
                                   'error_type': token(event.get('error_type', 'unavailable')),
                                   'code': token(event.get('code', 'unavailable'))}
                        native_failures.append(failure)
                        print('AQER_OFFLINE_NATIVE_FAILURE ' + json.dumps(failure), flush=True)
                    raise RuntimeError('native_assertion_failed_' + str(phase))
                rows = [event for event in parsed if event.get('phase') == phase and event.get('passed') is True]
                if rows:
                    if len(rows) != 1:
                        raise RuntimeError('ambiguous_native_receipt')
                    events.append(rows[0]); break
                time.sleep(1)
            else:
                raise RuntimeError('native_phase_deadline_' + str(phase))
        stage = 'verify_three_phase_receipt'
        if len(events) != 3 or events[1].get('http_calls') != 0:
            raise RuntimeError('incomplete_or_networked_offline_receipt')
        receipt.update({'passed': True, 'status': 'passed',
                   'checks': ['native_keystore_restart', 'native_cipher_tamper_rejected', 'encrypted_snapshots_at_rest',
                              'http_snapshot_restart_without_network', 'small_photo_restart_without_network', 'large_photo_offline_blocked',
                              'manual_fields_and_copied_photos_restart', 'outbox_actor_isolation', 'pending_no_send_offline',
                              'reconnect_same_client_id_after_lost_ack', 'native_map_offline_channel']})
    except Exception as error:
        receipt.update({'passed': False, 'status': 'failed', 'failed_stage': stage,
                        'reason': failure_reason(error)})
        raise
    finally:
        for name, command in [('force_stop', ('shell', 'am', 'force-stop', PACKAGE)),
                              ('wifi_enable', ('shell', 'svc', 'wifi', 'enable')),
                              ('data_enable', ('shell', 'svc', 'data', 'enable'))]:
            try:
                adb(*command)
            except Exception as error:
                failure = {'command': name, 'reason': failure_reason(error)}
                cleanup_failures.append(failure)
                print('AQER_OFFLINE_CLEANUP_FAILURE ' + json.dumps(failure), flush=True)
        (output / 'OFFLINE_NATIVE_RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt), flush=True)

if __name__ == '__main__':
    main()
