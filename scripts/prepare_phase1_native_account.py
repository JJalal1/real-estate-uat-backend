#!/usr/bin/env python3
"""Guard reviewed product trees and privately package native account evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile
import prepare_phase1_close as close

ROOT = Path(__file__).resolve().parents[1]
BASE = '694348c354f230f898dfca42fc8130dd461ce5ff'
REF = 'refs/heads/work/phase1-completion-20261105'
BASE_MOBILE_TREE = 'ef562ae410023046b4abee283f09707051a0e7b6'
MOBILE_TREE = '024db728944157ce50c10b4dce90a8ef6f7b72bf'
BACKEND_TREE = 'b569691cd06df69a2181291f43b419a46400f244'
VERSION_BASE = 1466
API = close.API
PRIVATE = ROOT / 'phase1-native-account-private'
EVIDENCE = ROOT / 'phase1-native-account-evidence'
EXPORT = ROOT / 'phase1-native-account-encrypted'
ALLOWED = {
    'mobile_app/lib/core/widgets/app_components.dart',
    'mobile_app/lib/core/widgets/ebroker_property_card.dart',
    'mobile_app/lib/core/widgets/property_card_gallery.dart',
    'mobile_app/lib/features/properties/presentation/my_listings_screen.dart',
    'mobile_app/test/private_listing_card_photo_test.dart',
    '.github/actions/phase1-review/README.md',
    '.github/actions/phase1-review/action.yml',
    '.github/actions/phase1-review/index.js',
    '.github/actions/phase1-review/package-lock.json',
    '.github/actions/phase1-review/package.json',
    '.github/actions/phase1-review/test_index.js',
    '.github/phase1-close-recipient.pem',
    '.github/workflows/phase1-native-account.yml',
    'scripts/phase1_bridge/adapter/README.md',
    'scripts/phase1_bridge/adapter/build_ci_variants.py',
    'scripts/phase1_bridge/adapter/c1_basics_capture.py',
    'scripts/phase1_bridge/adapter/c1_home_capture.py',
    'scripts/phase1_bridge/adapter/ci_probe_adapter.py',
    'scripts/phase1_bridge/adapter/ci_remote_evidence.py',
    'scripts/phase1_bridge/adapter/test_basics_capture.py',
    'scripts/phase1_bridge/adapter/test_c2_entry.py',
    'scripts/phase1_bridge/adapter/test_promoted_cleanup.py',
    'scripts/phase1_bridge/adapter/test_role_login_readiness.py',
    'scripts/phase1_bridge/adapter/test_c2_list_readiness.py',
    'scripts/phase1_bridge/adapter/test_c2_entry_dispatch.py',
    'scripts/phase1_bridge/adapter/test_home_capture.py',
    'scripts/phase1_bridge/adapter/test_integration.py',
    'scripts/phase1_bridge/adapter/test_logout_home.py',
    'scripts/phase1_bridge/adapter/variants/C2_SOURCE_PROPOSAL/c2_native_roles.py',
    'scripts/phase1_bridge/adapter/variants/LOCAL_REMAINING_PROPOSAL/local_stage_policy.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C4_EXECUTOR/phase_extensions.py',
    'scripts/phase1_bridge/adapter/variants/VARIANT_MANIFEST.json',
    'scripts/phase1_bridge/adapter/variants/ci_remote_evidence.py',
    'scripts/phase1_bridge/adapter/variants/promoted_cleanup.py',
    'scripts/phase1_bridge/adapter/variants/runtime/host_console_capture.py',
    'scripts/phase1_bridge/controller/README.md',
    'scripts/phase1_bridge/controller/bounded_api.py',
    'scripts/phase1_bridge/controller/controller.py',
    'scripts/phase1_bridge/controller/test_bounded_api.py',
    'scripts/phase1_bridge/controller/test_controller.py',
    'scripts/phase1_bridge/controller/test_home_diagnostic.py',
    'scripts/phase1_bridge/entry/README.md',
    'scripts/phase1_bridge/entry/test_entry.py',
    'scripts/phase1_bridge/oneshot/README.md',
    'scripts/phase1_bridge/oneshot/oneshot_adapter.py',
    'scripts/phase1_bridge/oneshot/test_oneshot_adapter.py',
    'scripts/phase1_bridge/owner/README.md',
    'scripts/phase1_bridge/owner/checkpoint_io.py',
    'scripts/phase1_bridge/owner/checkpoint_packager.py',
    'scripts/phase1_bridge/owner/command_transport.py',
    'scripts/phase1_bridge/owner/grants.py',
    'scripts/phase1_bridge/owner/owner_session.py',
    'scripts/phase1_bridge/owner/test_checkpoint_io.py',
    'scripts/phase1_bridge/owner/test_checkpoint_packager.py',
    'scripts/phase1_bridge/owner/test_owner_components.py',
    'scripts/phase1_bridge/protocol/README.md',
    'scripts/phase1_bridge/protocol/review_protocol.py',
    'scripts/phase1_bridge/protocol/test_review_protocol.py',
    'scripts/phase1_bridge/root_review_public.json',
    'scripts/phase1_bridge/runtime/owned_vm.py',
    'scripts/phase1_bridge/runtime/test_owned_vm_review.py',
    'scripts/phase1_bridge/tool_manifest.json',
    'scripts/phase1_device_input/AndroidManifest.xml',
    'scripts/phase1_device_input/Phase1Input.java',
    'scripts/phase1_native_account_readiness.py',
    'scripts/phase1_native_fixture_api.py',
    'scripts/prepare_phase1_close.py',
    'scripts/prepare_phase1_followup.py',
    'scripts/prepare_phase1_native_account.py',
    'scripts/probe_phase1_native_account.py',
    'scripts/run_phase1_native_bridge.py',
    'scripts/tests/test_phase1_native_account.py',
    'scripts/tests/test_phase1_native_account_build.py',
    'scripts/tests/test_phase1_native_account_fixture.py',
    'scripts/tests/test_phase1_native_account_readiness.py',
}


def run(argv, **kwargs):
    return subprocess.run([str(v) for v in argv], cwd=ROOT, check=True,
                          capture_output=True, **kwargs)


def text(argv):
    return run(argv, text=True).stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guard(env):
    if not (env.get('GITHUB_ACTIONS') == 'true'
            and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend'
            and env.get('GITHUB_REF') == REF and env.get('GITHUB_EVENT_NAME') == 'push'
            and env.get('AQER_PHASE1_NATIVE_ACCOUNT') == 'true'
            and re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', ''))
            and env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA')
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_ID', ''))
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_NUMBER', ''))):
        raise RuntimeError('explicit_native_account_ci_context_required')
    if text(['git', 'rev-parse', 'HEAD']) != env['SOURCE_COMMIT']:
        raise RuntimeError('native_account_source_checkout_mismatch')
    changes = set(text(['git', 'diff', '--name-only', BASE, 'HEAD']).splitlines())
    if not changes or changes - ALLOWED:
        raise RuntimeError('native_account_source_scope_mismatch')
    for component, expected, baseline in [('mobile_app', MOBILE_TREE, BASE_MOBILE_TREE),
                                           ('backend-api-runtime', BACKEND_TREE, BACKEND_TREE)]:
        if text(['git', 'rev-parse', 'HEAD:' + component]) != expected:
            raise RuntimeError('native_account_product_component_changed')
        if text(['git', 'rev-parse', BASE + ':' + component]) != baseline:
            raise RuntimeError('native_account_base_component_changed')
    text(['git', 'diff', '--exit-code', 'HEAD', '--', *sorted(ALLOWED),
          'mobile_app/lib', 'mobile_app/android', 'mobile_app/assets', 'mobile_app/pubspec.yaml',
          'backend-api-runtime'])
    recipient = ROOT / close.RECIPIENT
    if digest(recipient) != close.RECIPIENT_SHA256:
        raise RuntimeError('native_evidence_recipient_mismatch')
    run(['openssl', 'x509', '-in', recipient, '-noout', '-checkend', '600'])
    return {'source_commit': env['SOURCE_COMMIT'], 'source_parent': BASE,
            'ci_run_id': env['GITHUB_RUN_ID'], 'ci_run_number': int(env['GITHUB_RUN_NUMBER']),
            'version_code': VERSION_BASE + int(env['GITHUB_RUN_NUMBER']),
            'product_trees': {'mobile_app': MOBILE_TREE, 'backend-api-runtime': BACKEND_TREE},
            'product_base_trees': {'mobile_app': BASE_MOBILE_TREE, 'backend-api-runtime': BACKEND_TREE},
            'recipient_sha256': close.RECIPIENT_SHA256,
            'phase1_accepted': False, 'native_acceptance_tested_in_this_job': False,
            'scope': 'reviewed mobile UAT release with unchanged backend for actual native account journey'}


def prepare(env):
    receipt = guard(env)
    version = receipt['version_code']
    if PRIVATE.exists():
        raise RuntimeError('fresh_native_private_directory_required')
    PRIVATE.mkdir(mode=0o700)
    sdk = Path(env['ANDROID_HOME']); tool = close.android_tools(sdk)
    apk = PRIVATE / 'target.apk'
    shutil.copyfile(ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', apk)
    apk.chmod(0o600)
    signature = text([tool / 'apksigner', 'verify', '--print-certs', apk])
    certificate = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signature)
    badging = text([tool / 'aapt', 'dump', 'badging', apk])
    if not certificate or not ("name='com.aqer.yemen.uat'" in badging
            and f"versionCode='{version}'" in badging and "sdkVersion:'23'" in badging
            and "targetSdkVersion:'36'" in badging and 'application-debuggable' not in badging):
        raise RuntimeError('native_release_badging_or_signature_mismatch')
    run([tool / 'zipalign', '-c', '-P', '16', '4', apk]); native = 0
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('native_release_crc_failed')
        libs = {p.split('/')[1]: p for p in archive.namelist() if p.endswith('/libapp.so')}
        if set(libs) != {'arm64-v8a', 'armeabi-v7a', 'x86_64'}:
            raise RuntimeError('native_release_abis_mismatch')
        if any(API.encode() not in archive.read(p) for p in libs.values()):
            raise RuntimeError('native_release_uat_endpoint_mismatch')
        for name in archive.namelist():
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                close.elf(archive.read(name)); native += 1
        for weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']:
            relative = 'assets/ebroker/fonts/Manrope-' + weight + '.ttf'
            if archive.read('assets/flutter_assets/' + relative) != (ROOT / 'mobile_app' / relative).read_bytes():
                raise RuntimeError('native_release_font_mismatch')
    if native < 4:
        raise RuntimeError('native_release_elf_absent')
    helper = close.build_input(PRIVATE, tool, sdk); helper.chmod(0o600)
    receipt.update(package='com.aqer.yemen.uat', api=API, bytes=apk.stat().st_size,
                   sha256=digest(apk), certificate_sha256=certificate[1].lower(),
                   zip_crc='passed', apksigner='passed', native_16kb_elf='passed',
                   zipalign_16kb='passed', min_sdk=23, target_sdk=36, fonts_match=5,
                   resolved_dependency_lock_sha256=digest(ROOT / 'mobile_app/pubspec.lock'),
                   input_driver={'package': 'com.aqer.phase1.input', 'target': 'self',
                                 'sha256': digest(helper), 'bytes': helper.stat().st_size})
    (PRIVATE / 'APK_VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('AQER_PHASE1_NATIVE_RELEASE_AND_HELPER_VERIFIED')


def encrypt_evidence(env, include_installer=False):
    proof = guard(env)
    installer = installer_proof = None
    if include_installer:
        installer = PRIVATE / 'target.apk'
        metadata = PRIVATE / 'APK_VERIFICATION.json'
        if installer.is_symlink() or metadata.is_symlink() or not installer.is_file() or not metadata.is_file():
            raise RuntimeError('verified_native_installer_required')
        installer_proof = json.loads(metadata.read_text())
        if not (installer_proof.get('source_commit') == proof['source_commit']
                and str(installer_proof.get('ci_run_id')) == str(proof['ci_run_id'])
                and installer_proof.get('version_code') == proof['version_code']
                and installer_proof.get('package') == 'com.aqer.yemen.uat'
                and installer_proof.get('bytes') == installer.stat().st_size
                and installer_proof.get('sha256') == digest(installer)):
            raise RuntimeError('native_installer_identity_mismatch')
    if not EVIDENCE.is_dir() or not (EVIDENCE / 'report.json').is_file():
        raise RuntimeError('native_evidence_report_missing')
    files = sorted(EVIDENCE.iterdir())
    if any(p.is_symlink() or not p.is_file() or p.resolve().parent != EVIDENCE.resolve()
           or not (p.name == 'report.json' or re.fullmatch(r'[A-Za-z0-9_-]+\.(?:png|mp4|webm)', p.name))
           for p in files):
        raise RuntimeError('native_evidence_export_allowlist_failed')
    EXPORT.mkdir(mode=0o700)
    # Even redacted authenticated account evidence must not become public plaintext.
    with tempfile.TemporaryDirectory(prefix='aqer-native-evidence-', dir=env['RUNNER_TEMP']) as directory:
        archive = Path(directory) / 'native-evidence.zip'
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as out:
            for path in files:
                out.write(path, path.name)
        with zipfile.ZipFile(archive) as check:
            if check.testzip() is not None:
                raise RuntimeError('native_evidence_zip_crc_failed')
        result = close.encrypt(archive, EXPORT / 'evidence.cms', ROOT / close.RECIPIENT)
    receipt = {'source_commit': proof['source_commit'], 'ci_run_id': proof['ci_run_id'],
               'ci_run_number': proof['ci_run_number'],
               'version_code': proof['version_code'], 'recipient_sha256': close.RECIPIENT_SHA256,
               'encrypted_evidence': result, 'plaintext_file_count': len(files),
               'native_results_require_private_review': True, 'phase1_accepted': False}
    if include_installer:
        receipt['encrypted_installer'] = close.encrypt(installer, EXPORT / 'installer.cms', ROOT / close.RECIPIENT)
        receipt['installer_identity'] = {key: installer_proof[key] for key in
            ('source_commit', 'ci_run_id', 'version_code', 'package', 'bytes', 'sha256')}
    (EXPORT / 'PUBLIC_RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    expected = {'evidence.cms', 'PUBLIC_RECEIPT.json'} | ({'installer.cms'} if include_installer else set())
    if {p.name for p in EXPORT.iterdir()} != expected:
        raise RuntimeError('native_ciphertext_export_scope_failed')
    print('AQER_PHASE1_NATIVE_ACCOUNT_EVIDENCE_ENCRYPTED')


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--source-only', action='store_true')
    mode.add_argument('--encrypt-evidence', action='store_true')
    parser.add_argument('--include-installer', action='store_true')
    args = parser.parse_args()
    try:
        if args.include_installer and not args.encrypt_evidence:
            raise RuntimeError('explicit_installer_encryption_mode_required')
        if args.source_only:
            guard(os.environ); print('AQER_PHASE1_NATIVE_ACCOUNT_SOURCE_VERIFIED')
        elif args.encrypt_evidence:
            encrypt_evidence(os.environ, include_installer=args.include_installer)
        else:
            prepare(os.environ)
    except Exception:
        # Never expose tool exceptions that may include argv, captured output or paths.
        print('AQER_PHASE1_NATIVE_ACCOUNT_PREPARATION_FAILED'); return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
