#!/usr/bin/env python3
"""Verify the scoped 1818/1819 cleanup builds against the original 1817 APK.

Only a verified APK and public receipt are exported. This script never imports,
creates, modifies or exports signing material and never rewrites an APK.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import zipfile

from verify_connectivity_fix_apk import API, APP_NAME, PACKAGE, ABIS, android_tools, call, elf
from uat_signing_identity import load_public_identity, verify_imported_environment

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/work/apk-cleanup-1817-20261117'
BASELINE_SOURCE = 'e91927e9d14994c9101d6f11b8886e666bb930d1'
BASELINE_SHA256 = '4c6141d08c045a23c63ee183b3bdb339de51ec1f58ae3f34aec014685764eda1'
BASELINE_BYTES = 120125414
CERTIFICATE = '8d878aa972d1b101025b2f1b6b8c60c0783f5f80d901e1e57de97b718f6726f3'
LIBRARIES = {'libapp.so', 'libflutter.so', 'libmaplibre.so', 'libdatastore_shared_counter.so'}
EXPECTED_NATIVE = {f'lib/{abi}/{name}' for abi in ABIS for name in LIBRARIES}
REMOVED_NATIVE = {'lib/x86/libmaplibre.so', 'lib/x86/libdatastore_shared_counter.so',
                  *(f'lib/{abi}/libsqlite3.so' for abi in ABIS)}
GENERATED_LICENSE = 'assets/flutter_assets/NOTICES.Z'
PROTECTED_TREES = ('mobile_app/lib', 'mobile_app/assets', 'mobile_app/android/app/src',
                   'backend-api-runtime')


class CleanupError(ValueError):
    """Fixed public error codes only; never include arbitrary input contents."""


def require(condition, code):
    if not condition:
        raise CleanupError(code)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def guard(env, source, identity):
    require(env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[a-f0-9]{40}', source) and source == env.get('GITHUB_SHA'),
            'explicit_cleanup_uat_push_context_required')
    require(identity.get('certificate_sha256') == CERTIFICATE, 'established_1817_certificate_required')
    verify_imported_environment(identity, env)


def regular_input(value, suffix):
    path = Path(value).absolute()
    require(path == path.resolve() and path.is_relative_to(ROOT) and path.is_file()
            and path.suffix.lower() == suffix, 'regular_workspace_cleanup_input_required')
    return path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate_public_receipt_key')
        result[key] = value
    return result


def baseline_receipt(path):
    require(path.stat().st_size <= 65536, 'oversized_baseline_public_receipt')
    value = json.loads(path.read_text(), object_pairs_hook=unique_object)
    require(isinstance(value, dict) and value.get('source_commit') == BASELINE_SOURCE and
            value.get('version_code') == 1817 and type(value.get('version_code')) is int and
            value.get('package') == PACKAGE and value.get('api') == API and
            value.get('application_name') == APP_NAME and
            value.get('signer_certificate_sha256') == CERTIFICATE and
            value.get('sha256') == BASELINE_SHA256 and value.get('bytes') == BASELINE_BYTES and
            type(value.get('bytes')) is int and value.get('debug_signing_allowed') is False and
            value.get('approved_for_delivery') is True and
            value.get('github_secret_storage_verified') is True,
            'exact_verified_1817_baseline_receipt_required')
    return value


def public_identity(receipt):
    return {key: receipt[key] for key in ('source_commit', 'package', 'version_code', 'api',
                                         'signer_certificate_sha256', 'sha256', 'bytes')}


def verify_android_identity(path, tools, version):
    signature = call(tools / 'apksigner', 'verify', '--print-certs', path)
    certificates = re.findall(
        r'^Signer #([1-9][0-9]*) certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*$',
        signature, re.MULTILINE)
    require([(number, value.lower()) for number, value in certificates] == [('1', CERTIFICATE)],
            'actual_cleanup_apk_signer_mismatch')
    badging = call(tools / 'aapt', 'dump', 'badging', path)
    require(re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", badging, re.MULTILINE)
            == [(PACKAGE, str(version))] and
            re.findall(r"^sdkVersion:'([0-9]+)'$", badging, re.MULTILINE) == ['23'] and
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", badging, re.MULTILINE) == ['36'] and
            f"application-label:'{APP_NAME}'" in badging and 'application-debuggable' not in badging,
            'actual_cleanup_apk_package_version_sdk_mismatch')
    call(tools / 'zipalign', '-c', '-P', '16', '4', path)


def extract_native_libs(manifest):
    values = re.findall(
        r'^\s*A: android:extractNativeLibs(?:\([^\n)]*\))?=\(type 0x12\)(0x[0-9a-fA-F]+)\s*$',
        manifest, re.MULTILINE)
    require(len(values) == 1 and values[0].lower() in ('0x0', '0xffffffff'),
            'explicit_extract_native_libs_boolean_required')
    return values[0].lower() == '0xffffffff'


def inspect_archive(path, *, candidate_version=None):
    """Return bounded public content hashes; validate actual packaging and API."""
    with zipfile.ZipFile(path) as archive, Path(path).open('rb') as raw:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)) and archive.testzip() is None,
                'cleanup_apk_archive_integrity_failed')
        require(not any(name.lower().endswith(('.jks', '.keystore', '.p12', '.pfx', '.key'))
                        for name in names), 'private_signing_file_forbidden_in_apk')
        native = {entry.filename for entry in entries if entry.filename.startswith('lib/')
                  and not entry.is_dir()}
        expected = EXPECTED_NATIVE if candidate_version else EXPECTED_NATIVE | REMOVED_NATIVE
        require(native == expected, 'cleanup_exact_native_library_set_required')
        native_hashes, methods, alignment, assets, dex, profiles = {}, {}, {}, {}, {}, {}
        compressed, uncompressed = 0, 0
        for entry in entries:
            name = entry.filename
            if name in native:
                data = archive.read(name)
                native_hashes[name] = hashlib.sha256(data).hexdigest()
                methods[name] = entry.compress_type
                compressed += entry.compress_size
                uncompressed += entry.file_size
                if name.endswith('/libapp.so'):
                    require(API.encode() in data, 'cleanup_compiled_uat_api_mismatch')
                if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')):
                    elf(data)
                raw.seek(entry.header_offset)
                header = raw.read(30)
                require(header[:4] == b'PK\x03\x04', 'cleanup_local_zip_header_invalid')
                name_length, extra_length = struct.unpack_from('<HH', header, 26)
                alignment[name] = (entry.header_offset + 30 + name_length + extra_length) % 16384 == 0
            elif name.startswith('assets/flutter_assets/') and name != GENERATED_LICENSE and not entry.is_dir():
                assets[name] = hashlib.sha256(archive.read(name)).hexdigest()
            elif re.fullmatch(r'classes(?:[2-9][0-9]*)?\.dex', name):
                dex[name] = hashlib.sha256(archive.read(name)).hexdigest()
            elif name.startswith('assets/dexopt/') and not entry.is_dir():
                profiles[name] = hashlib.sha256(archive.read(name)).hexdigest()
        require(bool(assets) and bool(dex), 'cleanup_assets_and_dex_required')
        require(GENERATED_LICENSE in names and archive.getinfo(GENERATED_LICENSE).file_size > 0,
                'cleanup_generated_licenses_required')
        wanted = zipfile.ZIP_DEFLATED if candidate_version == 1819 else zipfile.ZIP_STORED
        require(all(method == wanted for method in methods.values()),
                'cleanup_native_compression_does_not_match_version')
        if wanted == zipfile.ZIP_STORED:
            require(all(alignment.values()), 'cleanup_stored_native_zip_16kb_alignment_required')
        return {'native_library_sha256': native_hashes, 'native_library_methods': methods,
                'native_zip_16kb_aligned': alignment, 'protected_assets_sha256': assets,
                'dex_sha256': dex, 'android_dex_profile_sha256': profiles,
                'native_payload_bytes': compressed, 'native_uncompressed_bytes': uncompressed}


def compare_baseline(before, after):
    require(before['protected_assets_sha256'] == after['protected_assets_sha256'],
            'cleanup_original_assets_fonts_manifests_changed')
    preserved = {name: digest for name, digest in before['native_library_sha256'].items()
                 if name in EXPECTED_NATIVE and not name.endswith('/libapp.so')}
    require(all(after['native_library_sha256'].get(name) == value for name, value in preserved.items()),
            'cleanup_retained_flutter_maplibre_datastore_bytes_changed')
    return preserved


def source_guards(source):
    guarded = {}
    for path in PROTECTED_TREES:
        before = call('git', 'rev-parse', f'{BASELINE_SOURCE}:{path}').strip()
        after = call('git', 'rev-parse', f'{source}:{path}').strip()
        require(before == after and re.fullmatch(r'[a-f0-9]{40}', before),
                'cleanup_protected_runtime_or_assets_tree_changed')
        guarded[path] = before
    call('git', 'diff', '--exit-code', 'HEAD', '--', 'mobile_app/lib', 'mobile_app/android',
         'mobile_app/assets', 'mobile_app/pubspec.yaml', 'backend-api-runtime',
         'docs/uat-signing-identity.json', 'scripts/uat_signing_identity.py',
         'scripts/verify_apk_cleanup.py', 'scripts/verify_v3_dependency_lock.py')
    return guarded


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', type=int, choices=(1818, 1819), required=True)
    parser.add_argument('--baseline-apk', required=True)
    parser.add_argument('--baseline-receipt', required=True)
    args = parser.parse_args(argv)
    identity = load_public_identity(require_approval=True)
    source = call('git', 'rev-parse', 'HEAD').strip()
    guard(os.environ, source, identity)
    protected = source_guards(source)
    baseline = regular_input(args.baseline_apk, '.apk')
    metadata = baseline_receipt(regular_input(args.baseline_receipt, '.json'))
    require(baseline.stat().st_size == BASELINE_BYTES and digest(baseline) == BASELINE_SHA256,
            'cleanup_baseline_apk_bytes_or_digest_mismatch')
    candidate = regular_input(ROOT / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk', '.apk')
    require(candidate.stat().st_size < BASELINE_BYTES, 'cleanup_apk_must_be_smaller_than_1817')
    lock = ROOT / 'mobile_app/pubspec.lock'
    call(sys.executable, ROOT / 'scripts/verify_v3_dependency_lock.py', '--resolved', lock, '--cleanup1818')
    tools = android_tools(Path(os.environ['ANDROID_HOME']))
    verify_android_identity(baseline, tools, 1817)
    verify_android_identity(candidate, tools, args.version)
    manifest = call(tools / 'aapt', 'dump', 'xmltree', candidate, 'AndroidManifest.xml')
    extracted = extract_native_libs(manifest)
    require(extracted == (args.version == 1819), 'cleanup_native_extraction_policy_mismatch')
    before = inspect_archive(baseline)
    after = inspect_archive(candidate, candidate_version=args.version)
    preserved = compare_baseline(before, after)
    output = ROOT / 'mobile_app/apk-cleanup-proof' / str(args.version)
    output.parent.mkdir(mode=0o700, exist_ok=True)
    output.mkdir(mode=0o700)
    try:
        exported = output / f'AQER-UAT-{args.version}-Clean.apk'
        shutil.copy2(candidate, exported)
        size = exported.stat().st_size
        record = {
            'schema': 1, 'source_commit': source,
            'mobile_component': call('git', 'rev-parse', f'{source}:mobile_app').strip(),
            'backend_component': protected['backend-api-runtime'],
            'package': PACKAGE, 'application_name': APP_NAME, 'version_code': args.version,
            'sha256': digest(exported), 'bytes': size, 'signer_certificate_sha256': CERTIFICATE,
            'api': API, 'min_sdk': 23, 'target_sdk': 36, 'abis': sorted(ABIS),
            'approved_for_delivery': True, 'github_secret_storage_verified': True,
            'debug_signing_allowed': False, 'same_package_and_certificate_as_1817': True,
            'upgrade_from_1817_expected_identity_compatible': True,
            'baseline': public_identity(metadata), 'baseline_actual_digest_verified': True,
            'baseline_actual_signature_verified': True,
            'baseline_native_paths_removed': sorted(REMOVED_NATIVE),
            'native_library_compression': 'deflated' if extracted else 'stored',
            'extract_native_libs': extracted,
            'native_zip_16kb_alignment_required': not extracted,
            'zip_elf_16kb': 'verified',
            'alignment_scope': 'All retained 64-bit ELF segments support16KiB; ZIP16KiB alignment is required for stored native entries only. Compressed native entries are extracted before loading.',
            'compiled_api_verified_for_all_abis': True,
            'source_component_guards': protected, 'original_dart_and_assets_unchanged': True,
            'retained_flutter_maplibre_datastore_sha256': preserved,
            'baseline_dex_sha256': before['dex_sha256'],
            'dex_change_scope': 'Recorded, not asserted identical: removal of the unused SQLite plugin and build number may change generated/optimized Android code. Runtime Dart/native source and original assets are pinned.',
            'generated_license_change_allowed': GENERATED_LICENSE,
            'resolved_dependency_lock_sha256': digest(lock), 'dependency_lock_guard_verified': True,
            'dependency_cleanup_opt_in': 'cleanup1818',
            'savings_bytes_vs_1817': BASELINE_BYTES - size,
            'savings_percent_vs_1817': round((BASELINE_BYTES - size) / BASELINE_BYTES * 100, 5),
            'installed_device_upgrade_tested': False, 'native_acceptance_tested_in_this_job': False,
            'physical_phone_acceptance': False, 'installed_footprint_measured_in_this_job': False,
            'startup_performance_measured_in_this_job': False, 'backend_deployed': False,
            'private_signing_material_in_artifacts': False,
            'scope': 'Actual APK identity/signature/content/packaging and baseline comparison only. Android update, data preservation and installed-size/startup measurements require a separate device receipt.',
            **after,
        }
        (output / 'APK_VERIFICATION.json').write_text(json.dumps(record, indent=2) + '\n')
    except Exception:
        shutil.rmtree(output)
        raise
    print(json.dumps({key: record[key] for key in ('source_commit', 'version_code', 'sha256', 'bytes',
                                                   'native_library_compression', 'savings_percent_vs_1817')}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, CleanupError) else 'cleanup_apk_verification_failed', file=sys.stderr)
        raise SystemExit(1) from None
