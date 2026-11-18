#!/usr/bin/env python3
"""Verify a map UX UAT installer against its pinned compressed predecessor.

UI Dart changes are expected. Assets, Android source/build configuration,
dependencies and backend remain pinned. Never creates/exports a signing key.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

from verify_apk_cleanup import (API, APP_NAME, PACKAGE, ABIS, CERTIFICATE,
    CleanupError, require, digest, regular_input, public_identity,
    verify_android_identity, extract_native_libs, inspect_archive)
from verify_connectivity_fix_apk import android_tools, call
from uat_signing_identity import load_public_identity, verify_imported_environment

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/work/map-search-ux-1820-20261117'
BASE_SOURCE = 'c0629a48c2431748b5d5ac1b5d6edb9318946fa8'
BASE_SHA256 = '13af0b61df2266735030718d8f2354e332ae4d7a2e1f67acfef1b222c3644fdb'
BASE_BYTES = 45190809
VERSION = 1820
ROUND4_VERSION = 1821
ROUND4_BASE_SOURCE = '8cdcc2b6de2146a0eca8390c7db82ae511c5113e'
ROUND4_BASE_SHA256 = '61ef6c5a1598666ab91e74c4552b1cc450cad55548585330bd35bffa517c4b18'
ROUND4_BASE_BYTES = 45222939
UAT1822_VERSION = 1822
UAT1822_BASE_SOURCE = 'd406026d20943d1bb6209da264cb23d6d722ca16'
UAT1822_BASE_SHA256 = '4a4636934af72d82bcfbd0781f751d35fa7925aed353c07b4b0591b2c81b792b'
UAT1822_BASE_BYTES = 45242744
UAT1822_FIX_SOURCE = '647edc35f4957fbfc9e4895adf17685d9a6a41eb'
GENERATED_ICON_SUBSET = 'assets/flutter_assets/fonts/MaterialIcons-Regular.otf'
PROTECTED = ('mobile_app/assets', 'mobile_app/android', 'mobile_app/pubspec.yaml',
             'mobile_app/pubspec.lock', 'backend-api-runtime', 'docs/uat-signing-identity.json')


def guard(env, source, identity):
    require(env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[a-f0-9]{40}', source) and source == env.get('GITHUB_SHA'),
            'explicit_map_search_ux_uat_push_context_required')
    require(identity.get('certificate_sha256') == CERTIFICATE,
            'established_durable_uat_certificate_required')
    verify_imported_environment(identity, env)


def baseline_receipt(path, *, round4=False, uat1822=False):
    require(path.stat().st_size <= 128 * 1024, 'oversized_public_baseline_receipt')
    def unique(pairs):
        out = {}
        for key, value in pairs:
            require(key not in out, 'duplicate_1819_receipt_key')
            out[key] = value
        return out
    value = json.loads(path.read_text(), object_pairs_hook=unique)
    if uat1822:
        source, version, sha, size = UAT1822_BASE_SOURCE, ROUND4_VERSION, UAT1822_BASE_SHA256, UAT1822_BASE_BYTES
    elif round4:
        source, version, sha, size = ROUND4_BASE_SOURCE, VERSION, ROUND4_BASE_SHA256, ROUND4_BASE_BYTES
    else:
        source, version, sha, size = BASE_SOURCE, 1819, BASE_SHA256, BASE_BYTES
    expected = {'source_commit': source, 'version_code': version, 'package': PACKAGE,
                'api': API, 'application_name': APP_NAME,
                'signer_certificate_sha256': CERTIFICATE,
                'sha256': sha, 'bytes': size, 'native_library_compression': 'deflated',
                'extract_native_libs': True, 'approved_for_delivery': True,
                'github_secret_storage_verified': True, 'debug_signing_allowed': False}
    require(isinstance(value, dict) and all(value.get(k) == v and type(value.get(k)) is type(v)
                                          for k, v in expected.items()),
            'exact_verified_baseline_receipt_required')
    return value


def compare_runtime_resources(before, after):
    # Flutter regenerates this SDK icon subset from reachable UI glyphs. The
    # owner authorizes UI changes; original image/font/SVG assets remain exact.
    original = dict(before['protected_assets_sha256'])
    candidate = dict(after['protected_assets_sha256'])
    old_icons = original.pop(GENERATED_ICON_SUBSET, None)
    new_icons = candidate.pop(GENERATED_ICON_SUBSET, None)
    require(old_icons is not None and new_icons is not None,
            'generated_material_icon_subset_missing')
    require(original == candidate, 'ux1820_original_image_font_or_manifest_changed')
    preserved = {name: value for name, value in before['native_library_sha256'].items()
                 if not name.endswith('/libapp.so')}
    require(all(after['native_library_sha256'].get(name) == value for name, value in preserved.items()),
            'ux1820_retained_flutter_maplibre_datastore_changed')
    return preserved, {'path': GENERATED_ICON_SUBSET, 'baseline_sha256': old_icons,
                       'candidate_sha256': new_icons, 'changed': old_icons != new_icons,
                       'scope': 'Generated SDK icon subset may follow authorized UI glyph changes. Source assets/fonts remain pinned; no original photo/font replacement.'}


def source_guards(source, *, baseline_source=BASE_SOURCE):
    protected = {}
    for path in PROTECTED:
        old = call('git', 'rev-parse', f'{baseline_source}:{path}').strip()
        current = call('git', 'rev-parse', f'{source}:{path}').strip()
        require(old == current and re.fullmatch(r'[a-f0-9]{40}', old),
                'ux1820_protected_assets_android_dependencies_or_backend_changed')
        protected[path] = old
    call('git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib', 'mobile_app/assets',
         'mobile_app/android', 'mobile_app/pubspec.yaml', 'backend-api-runtime',
         'docs/uat-signing-identity.json', 'scripts/verify_map_search_ux_apk.py',
         'scripts/verify_v3_dependency_lock.py')
    return protected


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-apk', required=True)
    parser.add_argument('--baseline-receipt', required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--round4', action='store_true')
    modes.add_argument('--uat1822', action='store_true')
    args = parser.parse_args(argv)
    identity = load_public_identity(require_approval=True)
    source = call('git', 'rev-parse', 'HEAD').strip()
    guard(os.environ, source, identity)
    if args.uat1822:
        version, baseline_source = UAT1822_VERSION, UAT1822_BASE_SOURCE
        call('git', 'merge-base', '--is-ancestor', UAT1822_FIX_SOURCE, source)
    else:
        version = ROUND4_VERSION if args.round4 else VERSION
        baseline_source = ROUND4_BASE_SOURCE if args.round4 else BASE_SOURCE
    protected = source_guards(source, baseline_source=baseline_source)
    baseline = regular_input(args.baseline_apk, '.apk')
    metadata = baseline_receipt(regular_input(args.baseline_receipt, '.json'), round4=args.round4, uat1822=args.uat1822)
    require(baseline.stat().st_size == metadata['bytes'] and digest(baseline) == metadata['sha256'],
            'baseline_apk_size_or_digest_mismatch')
    candidate = regular_input(ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', '.apk')
    lock = ROOT / 'mobile_app/pubspec.lock'
    call(sys.executable, ROOT / 'scripts/verify_v3_dependency_lock.py', '--resolved', lock, '--cleanup1818')
    tools = android_tools(Path(os.environ['ANDROID_HOME']))
    for apk, code in ((baseline, metadata['version_code']), (candidate, version)):
        verify_android_identity(apk, tools, code)
        manifest = call(tools / 'aapt', 'dump', 'xmltree', apk, 'AndroidManifest.xml')
        require(extract_native_libs(manifest), 'ux1820_compressed_native_extraction_required')
    # This existing helper's candidate_version parameter selects packaging mode;
    # actual APK version has independently been checked as1819/1820 above.
    before = inspect_archive(baseline, candidate_version=1819)
    after = inspect_archive(candidate, candidate_version=1819)
    preserved, icon_subset = compare_runtime_resources(before, after)
    output = ROOT / 'mobile_app/map-search-ux-proof'
    output.mkdir(mode=0o700)
    try:
        apk = output / f'AQER-UAT-{version}-Map-Search.apk'
        shutil.copy2(candidate, apk)
        record = {'schema': 1, 'source_commit': source, 'version_code': version,
                  'mobile_component': call('git', 'rev-parse', f'{source}:mobile_app').strip(),
                  'backend_component': protected['backend-api-runtime'],
                  'package': PACKAGE, 'application_name': APP_NAME, 'sha256': digest(apk),
                  'bytes': apk.stat().st_size, 'signer_certificate_sha256': CERTIFICATE,
                  'api': API, 'min_sdk': 23, 'target_sdk': 36, 'abis': sorted(ABIS),
                  'approved_for_delivery': True, 'github_secret_storage_verified': True,
                  'debug_signing_allowed': False, 'same_package_and_certificate_as_1819': True,
                  'baseline': public_identity(metadata), 'baseline_actual_digest_verified': True,
                  'baseline_actual_signature_verified': True, 'native_library_compression': 'deflated',
                  'extract_native_libs': True, 'native_zip_16kb_alignment_required': False,
                  'zip_elf_16kb': 'verified', 'compiled_api_verified_for_all_abis': True,
                  'source_component_guards': protected,
                  'original_assets_fonts_android_source_and_backend_unchanged': True,
                  'retained_flutter_maplibre_datastore_sha256': preserved,
                  'generated_material_icon_subset': icon_subset,
                  'dependency_lock_guard_verified': True, 'resolved_dependency_lock_sha256': digest(lock),
                  'intended_change_scope': ('Round four back navigation, inline price validation and map response timing.'
                                            if args.round4 else 'Owner-authorized map/search layout, source-scoped sessions and regional hints.'),
                  'installed_device_upgrade_tested': False,
                  'physical_phone_acceptance': False, 'backend_deployed': False,
                  'private_signing_material_in_artifacts': False,
                  'scope': 'Actual installer signature/identity/content/source guards only; separate Android receipt records replace-install and bounded guest UI smoke. No full native journey or phone acceptance.',
                  **after}
        if args.uat1822:
            record.update(included_fix_commit=UAT1822_FIX_SOURCE,
                          intended_change_scope='Retain valid map results after refresh failure and open the broker saved-search filters in Smart Search.',
                          scope='Verified installer and exact source. Android interface acceptance is assigned to the device tester.')
        (output / 'APK_VERIFICATION.json').write_text(json.dumps(record, indent=2) + '\n')
    except Exception:
        shutil.rmtree(output)
        raise
    print(json.dumps({k: record[k] for k in ('source_commit', 'version_code', 'sha256', 'bytes')}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, CleanupError) else 'map_search_ux_apk_verification_failed', file=sys.stderr)
        raise SystemExit(1) from None
