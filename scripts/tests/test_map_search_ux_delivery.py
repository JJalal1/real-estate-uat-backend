"""Focused1820 source/signing/upgrade/UI guards with public synthetic inputs."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import verify_map_search_ux_apk as build
import probe_map_search_ux_upgrade as upgrade
import verify_v3_dependency_lock as lock
import import_ci_uat_signing as signing

SOURCE = 'a' * 40


def context():
    return {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
            'GITHUB_REF': build.BRANCH, 'GITHUB_EVENT_NAME': 'push', 'GITHUB_SHA': SOURCE,
            'GITHUB_RUN_ID': '123', 'AQER_MAP_SEARCH_UX_UPGRADE': 'true',
            'AQER_SIGNING_ENVIRONMENT': 'uat'}


def receipt(version):
    return {'source_commit': build.BASE_SOURCE if version == 1819 else SOURCE,
            'version_code': version, 'package': build.PACKAGE, 'api': build.API,
            'application_name': build.APP_NAME, 'signer_certificate_sha256': build.CERTIFICATE,
            'bytes': build.BASE_BYTES if version == 1819 else 45000000,
            'sha256': build.BASE_SHA256 if version == 1819 else 'b' * 64,
            'native_library_compression': 'deflated', 'extract_native_libs': True,
            'approved_for_delivery': True, 'github_secret_storage_verified': True,
            'debug_signing_allowed': False}


class ContextGuards(unittest.TestCase):
    def test_new_branch_inherits_finite_lock_push_and_its_exact_internal_pr_only(self):
        env = context()
        lock.cleanup_context(env)
        pr = {**env, 'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF': 'refs/pull/193/merge',
              'GITHUB_HEAD_REF': lock.UX1820_BRANCH, 'GITHUB_BASE_REF': lock.UX1820_PR_BASE,
              'AQER_CLEANUP_PR_HEAD_REPO': lock.CLEANUP_REPOSITORY}
        lock.cleanup_context(pr)
        for field, value in [('GITHUB_BASE_REF', 'main'), ('AQER_CLEANUP_PR_HEAD_REPO', 'fork/repo'),
                             ('GITHUB_HEAD_REF', lock.CLEANUP_BRANCH), ('GITHUB_REF', 'refs/heads/main')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                lock.cleanup_context({**pr, field: value})
        self.assertEqual(lock.CLEANUP_REMOVALS, {'charcode', 'cli_util', 'drift', 'drift_dev', 'recase', 'sqlite3', 'sqlite3_flutter_libs', 'sqlparser'})

    def test_new_branch_signing_stays_push_only_and_uat_only(self):
        signing.guard(context())
        for key, value in [('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'),
                           ('GITHUB_REPOSITORY', 'other/repo'), ('AQER_SIGNING_ENVIRONMENT', 'production')]:
            with self.subTest(key=key), self.assertRaises(signing.SigningError):
                signing.guard({**context(), key: value})

    def test_build_guard_requires_current_source_and_existing_approved_certificate(self):
        identity = {'certificate_sha256': build.CERTIFICATE}
        with mock.patch.object(build, 'verify_imported_environment') as verify:
            build.guard(context(), SOURCE, identity)
            verify.assert_called_once_with(identity, context())
            for field, value in [('GITHUB_REF', 'refs/heads/main'), ('GITHUB_SHA', 'c' * 40),
                                 ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_ACTIONS', 'false')]:
                with self.subTest(field=field), self.assertRaises(build.CleanupError):
                    build.guard({**context(), field: value}, SOURCE, identity)
            with self.assertRaises(build.CleanupError):
                build.guard(context(), SOURCE, {'certificate_sha256': '0' * 64})

    def test_keyless_upgrade_rejects_real_credentials_wrong_source_or_other_emulator(self):
        upgrade.guard(context(), SOURCE, 'emulator-5554')
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REF', 'refs/heads/main'),
                           ('GITHUB_SHA', 'c' * 40), ('AQER_MAP_SEARCH_UX_UPGRADE', 'false')]:
            with self.subTest(key=key), self.assertRaises(upgrade.UpgradeError):
                upgrade.guard({**context(), key: value}, SOURCE, 'emulator-5554')
        for key in upgrade.FORBIDDEN_ENV:
            with self.subTest(key=key), self.assertRaises(upgrade.UpgradeError):
                upgrade.guard({**context(), key: 'SYNTHETIC_FORBIDDEN'}, SOURCE, 'emulator-5554')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.guard(context(), SOURCE, 'serial-of-real-phone')


class InstallerAndSourceGuards(unittest.TestCase):
    def test_1824_requires_the_exact_signed_1823_receipt(self):
        original = {**receipt(build.UAT1823_VERSION), 'source_commit': build.UAT1824_BASE_SOURCE,
                    'sha256': build.UAT1824_BASE_SHA256, 'bytes': build.UAT1824_BASE_BYTES}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            path.write_text(json.dumps(original))
            self.assertEqual(build.baseline_receipt(path, uat1824=True), original)
            path.write_text(json.dumps({**original, 'sha256': build.UAT1823_BASE_SHA256}))
            with self.assertRaises(build.CleanupError):
                build.baseline_receipt(path, uat1824=True)

    def test_1823_requires_the_exact_signed_1822_receipt(self):
        original = {**receipt(build.UAT1822_VERSION), 'source_commit': build.UAT1823_BASE_SOURCE,
                    'sha256': build.UAT1823_BASE_SHA256, 'bytes': build.UAT1823_BASE_BYTES}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            path.write_text(json.dumps(original))
            self.assertEqual(build.baseline_receipt(path, uat1823=True), original)
            for key, value in [('version_code', 1821), ('sha256', '1' * 64), ('source_commit', SOURCE)]:
                with self.subTest(key=key), self.assertRaises(build.CleanupError):
                    path.write_text(json.dumps({**original, key: value}))
                    build.baseline_receipt(path, uat1823=True)

    def test_1822_requires_the_exact_signed_1821_receipt(self):
        original = {**receipt(build.ROUND4_VERSION), 'source_commit': build.UAT1822_BASE_SOURCE,
                    'sha256': build.UAT1822_BASE_SHA256, 'bytes': build.UAT1822_BASE_BYTES}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            path.write_text(json.dumps(original))
            self.assertEqual(build.baseline_receipt(path, uat1822=True), original)
            for key, value in [('version_code', 1820), ('signer_certificate_sha256', '0' * 64),
                               ('sha256', '1' * 64), ('source_commit', SOURCE)]:
                with self.subTest(key=key), self.assertRaises(build.CleanupError):
                    path.write_text(json.dumps({**original, key: value}))
                    build.baseline_receipt(path, uat1822=True)

    def test_round_four_requires_the_exact_signed_1820_predecessor(self):
        absolute = {**receipt(1820), 'source_commit': build.ROUND4_BASE_SOURCE,
                    'bytes': build.ROUND4_BASE_BYTES, 'sha256': build.ROUND4_BASE_SHA256}
        candidate = receipt(build.ROUND4_VERSION)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            path.write_text(json.dumps(absolute))
            self.assertEqual(build.baseline_receipt(path, round4=True), absolute)
            upgrade.validate_receipts([absolute, candidate], SOURCE, round4=True)
            path.write_text(json.dumps({**absolute, 'sha256': 'c' * 64}))
            with self.assertRaises(build.CleanupError):
                build.baseline_receipt(path, round4=True)
            with self.assertRaises(upgrade.UpgradeError):
                upgrade.validate_receipts([receipt(1819), candidate], SOURCE, round4=True)

    def test_baseline_public_receipt_is_immutable_and_duplicate_keys_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            value = receipt(1819)
            path.write_text(json.dumps(value))
            self.assertEqual(build.baseline_receipt(path), value)
            for key, bad in [('version_code', 1820), ('sha256', 'c' * 64), ('bytes', True),
                             ('native_library_compression', 'stored'), ('debug_signing_allowed', True),
                             ('github_secret_storage_verified', False)]:
                with self.subTest(key=key):
                    path.write_text(json.dumps({**value, key: bad}))
                    with self.assertRaises(build.CleanupError):
                        build.baseline_receipt(path)
            path.write_text('{"bytes":1,"bytes":2}')
            with self.assertRaises(build.CleanupError):
                build.baseline_receipt(path)

    def test_update_receipts_cannot_mix_versions_sources_identity_or_packaging(self):
        values = [receipt(1819), receipt(1820)]
        upgrade.validate_receipts(values, SOURCE)
        for index, field, value in [(0, 'sha256', 'c' * 64), (1, 'source_commit', build.BASE_SOURCE),
             (1, 'version_code', True), (1, 'api', 'https://wrong.invalid'), (1, 'extract_native_libs', False),
             (1, 'package', 'wrong.app'), (1, 'bytes', 0), (1, 'signer_certificate_sha256', 'c' * 64)]:
            changed = copy.deepcopy(values);changed[index][field] = value
            with self.subTest(field=field), self.assertRaises(upgrade.UpgradeError):
                upgrade.validate_receipts(changed, SOURCE)

    def test_source_guards_allow_dart_ux_changes_but_pin_native_assets_deps_backend(self):
        self.assertNotIn('mobile_app/lib', build.PROTECTED)
        self.assertIn('mobile_app/assets', build.PROTECTED)
        self.assertIn('mobile_app/android', build.PROTECTED)
        self.assertIn('backend-api-runtime', build.PROTECTED)
        with mock.patch.object(build, 'call', return_value='b' * 40):
            self.assertEqual(len(build.source_guards(SOURCE)), len(build.PROTECTED))
        def mismatch(*args):
            return 'c' * 40 if any(str(arg).startswith(SOURCE + ':') for arg in args) else 'b' * 40
        with mock.patch.object(build, 'call', side_effect=mismatch), self.assertRaises(build.CleanupError):
            build.source_guards(SOURCE)

    def test_1824_pins_tested_backend_and_refuses_authentication_changes(self):
        tested_source = 'd' * 40
        backend_tree = 'e' * 40
        paths = sorted(build.UAT1824_BACKEND_PATHS)

        def git(*args):
            if args[1] == 'rev-parse':
                if args[2] in (f'{tested_source}:backend-api-runtime', f'{SOURCE}:backend-api-runtime'):
                    return backend_tree
                return 'b' * 40
            if args[2] == '--name-only':
                return '\n'.join(paths)
            return ''

        with mock.patch.object(build, 'call', side_effect=git) as call:
            protected = build.source_guards(SOURCE, baseline_source=build.UAT1824_BASE_SOURCE, tested_source=tested_source)
            self.assertEqual(protected['backend-api-runtime'], backend_tree)
            call.assert_any_call('git', 'diff', '--exit-code', tested_source, SOURCE, '--', 'mobile_app', 'backend-api-runtime')
            paths.append('backend-api-runtime/config/auth.php')
            with self.assertRaises(build.CleanupError):
                build.source_guards(SOURCE, baseline_source=build.UAT1824_BASE_SOURCE, tested_source=tested_source)

    def test_only_generated_sdk_icon_subset_may_change_but_not_original_fonts_or_natives(self):
        before = {'protected_assets_sha256': {build.GENERATED_ICON_SUBSET: 'a' * 64,
                   'assets/flutter_assets/assets/fonts/NotoSansArabic-Regular.ttf': 'b' * 64},
                  'native_library_sha256': {'lib/arm64-v8a/libmaplibre.so': 'c' * 64,
                   'lib/arm64-v8a/libapp.so': 'd' * 64}}
        after = copy.deepcopy(before)
        after['protected_assets_sha256'][build.GENERATED_ICON_SUBSET] = 'e' * 64
        after['native_library_sha256']['lib/arm64-v8a/libapp.so'] = 'f' * 64
        preserved, icons = build.compare_runtime_resources(before, after)
        self.assertTrue(icons['changed']);self.assertEqual(len(preserved), 1)
        changed = copy.deepcopy(after)
        changed['protected_assets_sha256']['assets/flutter_assets/assets/fonts/NotoSansArabic-Regular.ttf'] = '0' * 64
        with self.assertRaises(build.CleanupError):build.compare_runtime_resources(before, changed)
        changed = copy.deepcopy(after)
        changed['native_library_sha256']['lib/arm64-v8a/libmaplibre.so'] = '0' * 64
        with self.assertRaises(build.CleanupError):build.compare_runtime_resources(before, changed)

    def test_update_identity_and_every_private_fixture_hash_must_survive(self):
        before = {'uid': 10123, 'version_code': 1819, 'first_install_time': 'same'}
        after = {**before, 'version_code': 1820};hashes = {'fixture': 'b' * 64}
        upgrade.assert_preserved(before, after, hashes, dict(hashes))
        for change in [{'uid': 10124}, {'first_install_time': 'new'}, {'version_code': 1819}]:
            with self.subTest(change=change), self.assertRaises(upgrade.UpgradeError):
                upgrade.assert_preserved(before, {**after, **change}, hashes, hashes)
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.assert_preserved(before, after, hashes, {})


class NativeUiGuards(unittest.TestCase):
    def node(self, text, bounds='[10,20][80,60]', package=upgrade.PACKAGE, enabled='true'):
        return {'text': text, 'bounds': bounds, 'package': package, 'enabled': enabled}

    def test_hierarchy_uses_only_owned_app_nodes_and_rejects_permission_prompts(self):
        nodes = upgrade.xml_nodes('<hierarchy><node package="' + upgrade.PACKAGE + '" text="عقار اليمن"/><node package="other.app" text="SYNTHETIC_PRIVATE"/></hierarchy>')
        self.assertEqual(len(nodes), 1)
        self.assertEqual(upgrade.label(nodes[0]), 'عقار اليمن')
        for invalid in ['<!DOCTYPE hierarchy><hierarchy/>', '<wrong/>',
                        '<hierarchy><node package="com.google.android.permissioncontroller"/></hierarchy>']:
            with self.subTest(invalid=invalid), self.assertRaises(upgrade.UpgradeError):
                upgrade.xml_nodes(invalid)

    def test_taps_require_owned_visible_bounded_action_and_choose_smallest_match(self):
        large = self.node('تغيير المنطقة صنعاء', '[0,0][400,400]')
        small = self.node('تغيير المنطقة', '[20,30][100,70]')
        self.assertEqual(upgrade.tap_center([large, small], ['تغيير المنطقة']), (60, 50))
        for nodes in [[self.node('تغيير المنطقة', enabled='false')],
                      [self.node('تغيير المنطقة', '[100,50][20,30]')], [self.node('other')]]:
            with self.assertRaises(upgrade.UpgradeError):
                upgrade.tap_center(nodes, ['تغيير المنطقة'])

    def test_fresh_emulator_and_all_individual_adb_calls_are_bounded(self):
        device = upgrade.UxDevice('emulator-5554')
        with mock.patch.object(upgrade.Device, 'adb', return_value='ok') as adb:
            device.adb('wait-for-device', timeout=300)
            self.assertEqual(adb.call_args.kwargs['timeout'], 60)
        def output(*args, **kwargs):
            answers = {('wait-for-device',): '', ('root',): '', ('shell', 'id', '-u'): '0',
                ('shell', 'getprop', 'ro.kernel.qemu'): '1', ('shell', 'getprop', 'ro.build.version.sdk'): '36',
                ('shell', 'getprop', 'ro.product.cpu.abi'): 'x86_64', ('emu', 'avd', 'name'): upgrade.AVD_NAME}
            return answers[args]
        with mock.patch.object(device, 'adb', side_effect=output):device.verify_disposable_root()
        with mock.patch.object(device, 'adb', side_effect=lambda *a, **k: '0' if a == ('shell', 'getprop', 'ro.kernel.qemu') else output(*a, **k)):
            with self.assertRaises(upgrade.UpgradeError):device.verify_disposable_root()

    def test_guest_smoke_checks_first_launch_picker_ai_and_map_positions_without_dhamar_claim(self):
        home = [self.node('عقار اليمن'), self.node('تغيير المنطقة'), self.node('بحث ذكي'), self.node('الخريطة')]
        picker = [self.node('أين تبحث؟'), self.node('استخدم موقعي')]
        ai = [self.node('مكان يناسبك'), self.node('شقة للإيجار')]
        mapped = [self.node('البحث على الخريطة'), self.node('ابحث عن عقار', '[20,90][450,150]'),
                  self.node('رسم منطقة على الخريطة', '[10,500][80,560]'),
                  self.node('فتح مساعد البحث الذكي', '[10,580][80,640]')]
        device = mock.Mock()
        device.wait_for.side_effect = [home, picker, home, ai, home, mapped]
        device.adb.return_value = 'Physical size: 1080x1920\nOverride size: 540x960'
        with tempfile.TemporaryDirectory() as directory:
            result = upgrade.guest_smoke(device, Path(directory))
        self.assertTrue(result['passed']);self.assertTrue(result['native_map_layout_tested'])
        self.assertFalse(result['dhamar_hint_native_device_tested'])
        self.assertEqual(device.screenshot.call_count, 4)
        self.assertEqual(result['map_control_centres']['assistant'], (45, 610))

    def test_automatic_intro_or_static_sanaa_in_unknown_ai_blocks_acceptance(self):
        device = mock.Mock()
        device.wait_for.return_value = [self.node('عقار اليمن'), self.node('عقارات في منطقتك')]
        with self.assertRaises(upgrade.UpgradeError):upgrade.guest_smoke(device, Path('/synthetic'))
        device.wait_for.side_effect = [[self.node('عقار اليمن')], [self.node('أين تبحث؟'), self.node('استخدم موقعي')],
                                     [self.node('عقار اليمن')], [self.node('مكان يناسبك'), self.node('شقة في صنعاء')]]
        with self.assertRaises(upgrade.UpgradeError):upgrade.guest_smoke(device, Path('/synthetic'))


if __name__ == '__main__':unittest.main()
