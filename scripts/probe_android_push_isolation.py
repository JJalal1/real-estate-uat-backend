#!/usr/bin/env python3
"""Run synthetic Android instrumentation; never claim real FCM transport."""
import json
import os
from pathlib import Path
import subprocess

PACKAGE = 'com.aqer.yemen.uat'


def run(*args):
    return subprocess.run(list(args), capture_output=True, text=True, timeout=180, check=True).stdout


def main():
    run('adb', 'uninstall', PACKAGE)
    run('adb', 'install', 'android-push-tests/target.apk')
    run('adb', 'install', 'android-push-tests/tests.apk')
    groups = []
    try:
        for name, count in [('PushPermissionDeniedTest', 1), ('PushSessionIsolationTest', 12)]:
            output = run('adb', 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
                         'com.example.real_estate_mobile.' + name,
                         PACKAGE + '.test/androidx.test.runner.AndroidJUnitRunner')
            # adb may return zero even when instrumentation or assertions fail.
            assert f'OK ({count} test' in output, output
            assert 'FAILURES!!!' not in output and 'INSTRUMENTATION_FAILED' not in output, output
            groups.append({'class': name, 'passed': count})
        proof = {'source_commit': os.environ['SOURCE_COMMIT'], 'status': 'passed',
                 'android_api': int(run('adb', 'shell', 'getprop', 'ro.build.version.sdk').strip()),
                 'groups': groups, 'synthetic_android_tests': sum(g['passed'] for g in groups),
                 'real_fcm_delivery_tested': False, 'handset_tested': False,
                 'scope': 'Real Android storage, permission denial, notification display/cancellation, account/session/token fences and deduplication using synthetic envelopes.'}
        Path('dist/ANDROID_PUSH_ISOLATION.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof))
    finally:
        run('adb', 'uninstall', PACKAGE + '.test')
        run('adb', 'uninstall', PACKAGE)


if __name__ == '__main__':
    main()
