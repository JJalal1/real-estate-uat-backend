#!/usr/bin/env python3
"""Verify a scoped task build and export only current-recipient ciphertext."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from prepare_phase1_followup import elf

ROOT = Path(__file__).resolve().parents[1]
BASE = 'dfe667fa6607f031a44a40a5020ce6678b716019'
REF = 'refs/heads/work/phase1-close-20261103'
MOBILE_TREE = 'ef562ae410023046b4abee283f09707051a0e7b6'
RECIPIENT = '.github/phase1-close-recipient.pem'
RECIPIENT_SHA256 = '3fb44e23932f22595734a591d6a4b5fac7a76b62ab25413ff6266d88d7827825'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
ALLOWED = {
    RECIPIENT, '.github/workflows/phase1-close.yml',
    'scripts/prepare_phase1_close.py', 'scripts/tests/test_phase1_close.py',
    'scripts/phase1_device_input/Phase1Input.java',
    'backend-api-runtime/app/Services/ExplicitListingFacts.php',
    'backend-api-runtime/app/Services/ListingAiService.php',
    'backend-api-runtime/app/Services/ListingDraftService.php',
    'backend-api-runtime/tests/Feature/BrokerListingAssistantTest.php',
}
CONTROL_SERVICES = (
    'backend-api-runtime/app/Services/ExplicitListingFacts.php',
    'backend-api-runtime/app/Services/ListingAiService.php',
)
RED_METHOD = 'test_floor_does_not_propose_a_unit_in_prepare_or_direct_extraction'
RED_WITNESS = 'AQER_UNIT_NUMBER_GROUNDING: unit_number must be absent when only a floor is supplied'


def run(argv, cwd=ROOT, **kwargs):
    return subprocess.run([str(v) for v in argv], cwd=cwd, check=True,
                          capture_output=True, **kwargs)


def text_run(argv):
    return run(argv, text=True).stdout.strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guard(env):
    if not (env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend'
            and env.get('GITHUB_REF') == REF and env.get('GITHUB_EVENT_NAME') == 'push'
            and env.get('AQER_PHASE1_CLOSE') == 'true'
            and re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', ''))
            and env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA')
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_ID', ''))
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_NUMBER', ''))):
        raise RuntimeError('explicit_phase1_close_context_required')
    return 1464 + int(env['GITHUB_RUN_NUMBER'])


def source_receipt(env):
    version = guard(env)
    if text_run(['git', 'rev-parse', 'HEAD']) != env['SOURCE_COMMIT']:
        raise RuntimeError('checkout_source_mismatch')
    text_run(['git', 'diff', '--exit-code', 'HEAD', '--', *sorted(ALLOWED)])
    changed = set(text_run(['git', 'diff', '--name-only', BASE, 'HEAD']).splitlines())
    if not changed or changed - ALLOWED:
        raise RuntimeError('task_source_scope_mismatch')
    mobile = text_run(['git', 'rev-parse', 'HEAD:mobile_app'])
    if mobile != MOBILE_TREE or text_run(['git', 'rev-parse', BASE + ':mobile_app']) != mobile:
        raise RuntimeError('mobile_component_changed')
    text_run(['git', 'diff', '--exit-code', 'HEAD', '--',
              'mobile_app/lib', 'mobile_app/android', 'mobile_app/assets', 'mobile_app/pubspec.yaml'])
    certificate = ROOT / RECIPIENT
    if sha256(certificate) != RECIPIENT_SHA256:
        raise RuntimeError('current_recipient_mismatch')
    if '-----BEGIN CERTIFICATE-----' not in certificate.read_text():
        raise RuntimeError('recipient_is_not_public_certificate')
    return {'source_commit': env['SOURCE_COMMIT'], 'source_parent': BASE,
            'version_code': version, 'ci_run_id': env['GITHUB_RUN_ID'],
            'ci_run_number': int(env['GITHUB_RUN_NUMBER']),
            'product_trees': {'mobile_app': mobile,
                              'backend-api-runtime': text_run(['git', 'rev-parse', 'HEAD:backend-api-runtime'])},
            'recipient_sha256': RECIPIENT_SHA256,
            'scope': 'release for local native acceptance; no account credentials in CI',
            'native_acceptance_tested_in_this_job': False, 'phase1_accepted': False}


def red_control(env):
    proof = source_receipt(env)
    originals = {name: (ROOT / name).read_bytes() for name in CONTROL_SERVICES}
    original_hashes = {name: hashlib.sha256(data).hexdigest() for name, data in originals.items()}
    with tempfile.TemporaryDirectory(prefix='phase1-red-', dir=os.environ['RUNNER_TEMP']) as directory:
        junit = Path(directory) / 'control.xml'
        try:
            for name in CONTROL_SERVICES:
                (ROOT / name).write_bytes(run(['git', 'show', BASE + ':' + name]).stdout)
            completed = subprocess.run(
                ['php', 'artisan', 'test', '--filter=' + RED_METHOD, '--log-junit=' + str(junit),
                 '--display-warnings', '--fail-on-warning', '--fail-on-risky'],
                cwd=ROOT / 'backend-api-runtime', capture_output=True, text=True)
            if completed.returncode == 0 or not junit.is_file():
                raise RuntimeError('old_source_did_not_produce_expected_regression_failure')
            suites = ET.parse(junit).getroot()
            cases = list(suites.iter('testcase'))
            if (len(cases) != 1 or cases[0].get('name') != RED_METHOD
                    or len(list(cases[0].iter('failure'))) != 1
                    or list(suites.iter('error')) or list(suites.iter('skipped'))):
                raise RuntimeError('old_source_control_failed_for_unexpected_reason')
            failure_text = ''.join(cases[0].find('failure').itertext())
            if RED_WITNESS not in failure_text:
                raise RuntimeError('old_source_control_did_not_witness_unit_proposal')
        finally:
            for name, data in originals.items():
                (ROOT / name).write_bytes(data)
            if any(sha256(ROOT / name) != digest for name, digest in original_hashes.items()):
                raise RuntimeError('candidate_restore_mismatch')
    source_receipt(env)
    out = ROOT / 'phase1-close-regression'
    out.mkdir(exist_ok=True)
    (out / 'RED_CONTROL.json').write_text(json.dumps({
        'source_commit': proof['source_commit'], 'old_source': BASE,
        'method': RED_METHOD, 'tests': 1, 'expected_failures': 1, 'errors': 0,
        'skipped': 0, 'unit_number_failure_witnessed': True,
        'candidate_source_restored': True}, indent=2) + '\n')
    print('AQER_PHASE1_OLD_UNIT_FAILURE_VERIFIED_AND_CANDIDATE_RESTORED')


def android_tools(sdk):
    preferred = sdk / 'build-tools/36.0.0'
    required = ['apksigner', 'aapt', 'zipalign', 'd8']
    if not all((preferred / tool).is_file() for tool in required):
        raise RuntimeError('pinned_android_build_tools_unavailable')
    if not (sdk / 'platforms/android-36/android.jar').is_file():
        raise RuntimeError('android36_platform_unavailable')
    return preferred


def encrypt(apk, destination, recipient):
    run(['openssl', 'cms', '-encrypt', '-binary', '-aes-256-gcm', '-outform', 'DER',
         '-recip', recipient, '-keyopt', 'rsa_padding_mode:oaep',
         '-keyopt', 'rsa_oaep_md:sha256', '-in', apk, '-out', destination])
    with destination.open('rb') as stream:
        if stream.read(1) != b'\x30':
            raise RuntimeError('ciphertext_format_mismatch')
    return {'file': destination.name, 'bytes': destination.stat().st_size,
            'sha256': sha256(destination), 'cipher': 'CMS-AES256GCM-RSAOAEP-SHA256'}


def build_input(private, tool, sdk):
    source = ROOT / 'scripts/phase1_device_input'
    android = sdk / 'platforms/android-36/android.jar'
    classes, dex = private / 'classes', private / 'dex'
    classes.mkdir(); dex.mkdir()
    run(['javac', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-classpath', android,
         '-d', classes, source / 'Phase1Input.java'])
    run([tool / 'd8', '--lib', android, '--min-api', '23', '--output', dex,
         *sorted(classes.rglob('*.class'))])
    unsigned, aligned, target = private / 'input-unsigned.apk', private / 'input-aligned.apk', private / 'input.apk'
    run([tool / 'aapt', 'package', '-f', '-M', source / 'AndroidManifest.xml', '-I', android, '-F', unsigned])
    with zipfile.ZipFile(unsigned, 'a') as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    run([tool / 'zipalign', '-f', '4', unsigned, aligned])
    signer = private / 'input-one-day.jks'
    run(['keytool', '-genkeypair', '-keystore', signer, '-storetype', 'JKS',
         '-storepass', 'android', '-keypass', 'android', '-alias', 'androiddebugkey',
         '-dname', 'CN=Phase1 Disposable Input', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1'])
    signer.chmod(0o600)
    run([tool / 'apksigner', 'sign', '--ks', signer, '--ks-key-alias', 'androiddebugkey',
         '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', target, aligned])
    run([tool / 'apksigner', 'verify', target])
    badging = text_run([tool / 'aapt', 'dump', 'badging', target])
    if "name='com.aqer.phase1.input'" not in badging:
        raise RuntimeError('input_package_mismatch')
    manifest = (source / 'AndroidManifest.xml').read_text()
    if 'android:targetPackage="com.aqer.phase1.input"' not in manifest:
        raise RuntimeError('input_must_target_itself')
    signer.unlink()
    return target


def prepare(env):
    receipt = source_receipt(env)
    private = ROOT / 'phase1-close-private'
    private.mkdir(mode=0o700)
    out = ROOT / 'phase1-close-encrypted'
    out.mkdir(mode=0o700)
    sdk = Path(env['ANDROID_HOME'])
    tool = android_tools(sdk)
    app = ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
    apk = private / 'target.apk'
    shutil.copyfile(app, apk)
    signature = text_run([tool / 'apksigner', 'verify', '--print-certs', apk])
    certificate = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signature)
    badging = text_run([tool / 'aapt', 'dump', 'badging', apk])
    if not certificate or not ("name='com.aqer.yemen.uat'" in badging
            and f"versionCode='{receipt['version_code']}'" in badging
            and "sdkVersion:'23'" in badging and "targetSdkVersion:'36'" in badging
            and 'application-debuggable' not in badging):
        raise RuntimeError('release_signature_or_badging_failed')
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
                   sha256=sha256(apk), certificate_sha256=certificate[1].lower(),
                   zip_crc='passed', apksigner='passed', native_16kb_elf='passed',
                   zipalign_16kb='passed', min_sdk=23, target_sdk=36, fonts_match=5,
                   resolved_dependency_lock_sha256=sha256(ROOT / 'mobile_app/pubspec.lock'))
    driver = build_input(private, tool, sdk)
    receipt['input_driver'] = {'package': 'com.aqer.phase1.input', 'target': 'self',
                               'sha256': sha256(driver), 'bytes': driver.stat().st_size,
                               'test_certificate_scope': 'independent-disposable-one-day'}
    recipient = ROOT / RECIPIENT
    receipt['encrypted_app'] = encrypt(apk, out / 'target.cms', recipient)
    receipt['encrypted_input'] = encrypt(driver, out / 'input.cms', recipient)
    (out / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    apk.unlink(); driver.unlink()
    if {p.name for p in out.iterdir()} != {'target.cms', 'input.cms', 'APK_VERIFICATION.json'}:
        raise RuntimeError('unexpected_delivery_artifact')
    print('AQER_PHASE1_RELEASE_AND_INPUT_VERIFIED_RECIPIENT_ENCRYPTED')


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--source-only', action='store_true')
    mode.add_argument('--red-control', action='store_true')
    args = parser.parse_args()
    if args.source_only:
        source_receipt(os.environ)
        print('AQER_PHASE1_SCOPED_SOURCE_VERIFIED')
    elif args.red_control:
        red_control(os.environ)
    else:
        prepare(os.environ)


if __name__ == '__main__':
    main()
