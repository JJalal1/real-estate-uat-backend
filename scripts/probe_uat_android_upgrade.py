#!/usr/bin/env python3
"""Disposable rooted API36 emulator: real package upgrade and private fixture preservation.

No credentials, account data, UAT writes or handset acceptance claim.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

PACKAGE = 'com.example.real_estate_mobile'
ROOT = Path('dist')


def command(*args, timeout=120):
    return subprocess.run(list(args), text=True, capture_output=True, check=True, timeout=timeout).stdout.strip()


def adb(*args, timeout=120):
    return command('adb', *args, timeout=timeout)


def version():
    rows = adb('shell', 'dumpsys', 'package', PACKAGE).splitlines()
    return int(next(line.split('versionCode=')[1].split()[0] for line in rows if 'versionCode=' in line))


def launch():
    adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity', timeout=60)
    for _ in range(30):
        if adb('shell', 'pidof', PACKAGE):
            return
        time.sleep(1)
    raise RuntimeError('UAT package did not remain running')


def main():
    before = json.loads((ROOT / 'UPGRADE_PREDECESSOR_VERIFICATION.json').read_text())
    after = json.loads((ROOT / 'APK_VERIFICATION.json').read_text())
    assert before['source_commit'] == after['source_commit'] == os.environ['SOURCE_COMMIT']
    assert before['certificate_sha256'] == after['certificate_sha256']
    assert before['version_code'] + 1 == after['version_code']
    assert before['package'] == after['package'] == PACKAGE
    adb('wait-for-device'); adb('root'); adb('wait-for-device')
    assert adb('shell', 'id', '-u') == '0', 'A disposable rooted emulator is required'
    assert int(adb('shell', 'getprop', 'ro.build.version.sdk')) >= 36
    # Keep startup entirely offline so no arbitrary marketplace data is tested.
    adb('shell', 'iptables', '-I', 'OUTPUT', '-j', 'REJECT')
    try:
        adb('install', str(ROOT / 'uat-upgrade-predecessor.apk'), timeout=180)
        assert version() == before['version_code']
        launch(); adb('shell', 'am', 'force-stop', PACKAGE)
        private = '/data/user/0/' + PACKAGE
        uid = adb('shell', 'stat', '-c', '%u', private)
        assert uid.isdigit() and int(uid) >= 10000
        fixtures = {
            'files/aqer_theme_mode.txt': b'dark',
            'no_backup/listing_recovery/u999999/p0/state.json': json.dumps({
                'version': 1, 'user_id': 999999, 'listing_id': 0,
                'data': {'fields': {'title': 'Synthetic upgrade preservation fixture'}},
                'image_files': [], 'image_keys': [],
            }, sort_keys=True).encode(),
        }
        hashes = {}
        with tempfile.TemporaryDirectory() as temporary:
            for index, (relative, data) in enumerate(fixtures.items()):
                local = Path(temporary) / str(index); local.write_bytes(data)
                destination = private + '/' + relative
                adb('shell', 'mkdir', '-p', destination.rsplit('/', 1)[0])
                adb('push', str(local), destination)
                adb('shell', 'chown', uid + ':' + uid, destination)
                adb('shell', 'chmod', '600', destination)
                hashes[relative] = hashlib.sha256(data).hexdigest()
        adb('install', '-r', str(ROOT / f"real-estate-broker-uat-{os.environ['GITHUB_RUN_NUMBER']}.apk"), timeout=180)
        assert version() == after['version_code']
        actual = {relative: adb('shell', 'sha256sum', private + '/' + relative).split()[0] for relative in fixtures}
        assert actual == hashes, 'Upgrade changed app-private theme or recovery fixture'
        adb('logcat', '-c'); launch(); time.sleep(3)
        assert adb('shell', 'pidof', PACKAGE)
        crash = adb('logcat', '-d', '-b', 'crash')
        assert PACKAGE not in crash, 'UAT process crashed during offline startup'
        (ROOT / 'ANDROID_UPGRADE_VERIFICATION.json').write_text(json.dumps({
            'source_commit': after['source_commit'], 'status': 'passed', 'environment': 'disposable-rooted-Android-emulator',
            'android_api': int(adb('shell', 'getprop', 'ro.build.version.sdk')),
            'kernel_page_bytes': int(adb('shell', 'getconf', 'PAGESIZE')),
            'predecessor': before, 'current': after, 'same_certificate': True,
            'install_replace_preserved_private_fixture_sha256': actual,
            'offline_startup_without_process_crash': True,
            'limits': 'Same source with consecutive build codes; no signed-in session migration, official store signing, handset or FCM delivery acceptance.',
        }, indent=2) + '\n')
        print('AQER_ANDROID_UPGRADE_PASS', before['version_code'], after['version_code'])
    finally:
        adb('shell', 'iptables', '-D', 'OUTPUT', '-j', 'REJECT')


if __name__ == '__main__':
    main()
