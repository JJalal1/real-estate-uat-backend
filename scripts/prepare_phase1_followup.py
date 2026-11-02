#!/usr/bin/env python3
"""CI-only, unchanged product source; verify the new APK and build a disposable input driver."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = 'cc9e11a8713aa971da761dde286073473fc06786'
REF = 'refs/heads/work/phase1-journeys-20261103'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'


def run(argv):
    return subprocess.run([str(v) for v in argv], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def guard(env):
    if not (env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == REF and env.get('GITHUB_EVENT_NAME') == 'push' and
            env.get('AQER_PHASE1_FOLLOWUP') == 'true' and
            re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', '')) and
            env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA') and
            env.get('GITHUB_RUN_ID', '').isdigit() and
            env.get('GITHUB_RUN_NUMBER', '').isdigit()):
        raise RuntimeError('explicit_followup_context_required')
    return 1457 + int(env['GITHUB_RUN_NUMBER'])


def source_receipt(env):
    version = guard(env)
    if run(['git', 'rev-parse', 'HEAD']).strip() != env['SOURCE_COMMIT']:
        raise RuntimeError('checkout_source_mismatch')
    run(['git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib', 'mobile_app/android',
         'mobile_app/assets', 'mobile_app/pubspec.yaml', 'backend-api-runtime'])
    trees = {}
    for component in ['mobile_app', 'backend-api-runtime']:
        baseline = run(['git', 'rev-parse', BASE + ':' + component]).strip()
        current = run(['git', 'rev-parse', 'HEAD:' + component]).strip()
        if baseline != current:
            raise RuntimeError('product_component_changed_requires_affected_regression')
        trees[component] = current
    return {'source_commit': env['SOURCE_COMMIT'], 'version_code': version,
            'ci_run_id': env['GITHUB_RUN_ID'], 'ci_run_number': int(env['GITHUB_RUN_NUMBER']),
            'product_baseline': BASE, 'product_trees': trees,
            'reused_ci': 'https://github.com/JJalal1/real-estate-uat-backend/actions/runs/41531180329',
            'scope': 'new native journey evidence with unchanged product components',
            'original_apk1457_bytes_reused': False}


def elf(data):
    if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01':
        raise RuntimeError('invalid_elf64')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    if size < 56 or not count or offset + size * count > len(data):
        raise RuntimeError('invalid_elf_program_headers')
    loads = 0
    for i in range(count):
        header = offset + i * size
        if struct.unpack_from('<I', data, header)[0] != 1:
            continue
        file_offset, address = struct.unpack_from('<QQ', data, header + 8)
        alignment = struct.unpack_from('<Q', data, header + 48)[0]
        if alignment < 16384 or alignment & (alignment - 1) or file_offset % 16384 != address % 16384:
            raise RuntimeError('elf16kb_alignment_failed')
        loads += 1
    if not loads:
        raise RuntimeError('elf_load_segments_absent')


def prepare(env):
    receipt = source_receipt(env)
    out = ROOT / 'phase1-followup-private'
    out.mkdir()
    sdk = Path(env['ANDROID_HOME'])
    tool = sorted((sdk / 'build-tools').glob('*/apksigner'))[-1].parent
    android = sdk / 'platforms/android-36/android.jar'
    app = ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
    apk = out / 'target.apk'
    shutil.copyfile(app, apk)
    signature = run([tool / 'apksigner', 'verify', '--print-certs', apk])
    certificate = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signature)
    if not certificate:
        raise RuntimeError('release_signature_failed')
    badging = run([tool / 'aapt', 'dump', 'badging', apk])
    if not ("name='com.aqer.yemen.uat'" in badging and
            f"versionCode='{receipt['version_code']}'" in badging and
            "sdkVersion:'23'" in badging and "targetSdkVersion:'36'" in badging and
            'application-debuggable' not in badging):
        raise RuntimeError('release_badging_failed')
    run([tool / 'zipalign', '-c', '-P', '16', '4', apk])
    native = 0
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('release_zip_crc_failed')
        libs = {name.split('/')[1]: name for name in archive.namelist() if name.endswith('/libapp.so')}
        if set(libs) != {'arm64-v8a', 'armeabi-v7a', 'x86_64'} or any(API.encode() not in archive.read(n) for n in libs.values()):
            raise RuntimeError('release_endpoint_or_abis_failed')
        for name in archive.namelist():
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                elf(archive.read(name)); native += 1
        for weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']:
            relative = 'assets/ebroker/fonts/Manrope-' + weight + '.ttf'
            if archive.read('assets/flutter_assets/' + relative) != (ROOT / 'mobile_app' / relative).read_bytes():
                raise RuntimeError('release_font_mismatch')
    if native < 4:
        raise RuntimeError('release_native_libraries_absent')
    receipt.update(package='com.aqer.yemen.uat', api=API, bytes=apk.stat().st_size,
        sha256=hashlib.sha256(apk.read_bytes()).hexdigest(), certificate_sha256=certificate[1].lower(),
        package_role='current-uat', zip_crc='passed', apksigner='passed', native_16kb_elf='passed',
        zipalign_16kb='passed', target_sdk=36, min_sdk=23,
        firebase={'client_configured': False, 'real_fcm_delivery_tested': False})
    receipt['resolved_dependency_lock_sha256'] = hashlib.sha256((ROOT/'mobile_app/pubspec.lock').read_bytes()).hexdigest()
    source = ROOT / 'scripts/phase1_device_input'
    classes, dex = out / 'classes', out / 'dex'
    classes.mkdir(); dex.mkdir()
    run(['javac', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-classpath', android,
         '-d', classes, source / 'Phase1Input.java'])
    run([tool / 'd8', '--lib', android, '--min-api', '23', '--output', dex,
         *sorted(classes.rglob('*.class'))])
    unsigned, aligned, driver = out / 'input-unsigned.apk', out / 'input-aligned.apk', out / 'input.apk'
    run([tool / 'aapt', 'package', '-f', '-M', source / 'AndroidManifest.xml', '-I', android, '-F', unsigned])
    with zipfile.ZipFile(unsigned, 'a') as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    run([tool / 'zipalign', '-f', '4', unsigned, aligned])
    # Reuse this disposable job's ordinary Android debug certificate, never a delivery key.
    key = Path.home() / '.android/debug.keystore'
    if not key.is_file():
        raise RuntimeError('disposable_build_debug_signer_missing')
    run([tool / 'apksigner', 'sign', '--ks', key,
         '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
         '--out', driver, aligned])
    run([tool / 'apksigner', 'verify', driver])
    receipt['input_driver'] = {'package': 'com.aqer.phase1.input', 'target': 'self',
                              'sha256': hashlib.sha256(driver.read_bytes()).hexdigest()}
    (out / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print('AQER_PHASE1_FOLLOWUP_PREPARED')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-only', action='store_true')
    args = parser.parse_args()
    if args.source_only:
        source_receipt(os.environ)
        print('AQER_PHASE1_UNCHANGED_PRODUCT_SOURCE_VERIFIED')
    else:
        prepare(os.environ)


if __name__ == '__main__':
    main()
