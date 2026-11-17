#!/usr/bin/env python3
"""Keyless ordinary1819->1820 update with synthetic private files and guest UI.

Never launches1819, so1820's first Home launch has no introduction-seen marker.
No uninstall/reset fallback, real account, permission grant or business network.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from probe_apk_cleanup_upgrade import (Device, UpgradeError, FORBIDDEN_ENV, PACKAGE,
    API, CERTIFICATE, command, digest, failure_reason, read_receipt, regular_input,
    synthetic_fixtures, verify_apk, public_identity, write_fixtures)
from verify_map_search_ux_apk import BRANCH, BASE_SOURCE, BASE_SHA256, BASE_BYTES, VERSION

ROOT = Path(__file__).resolve().parents[1]
AVD_NAME = 'aqer-map-search-ux-upgrade'


def guard(env, source, serial):
    if not (env.get('GITHUB_ACTIONS') == 'true' and env.get('AQER_MAP_SEARCH_UX_UPGRADE') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch(r'[1-9][0-9]*', env.get('GITHUB_RUN_ID', '')) and
            re.fullmatch(r'[a-f0-9]{40}', source) and source == env.get('GITHUB_SHA') and
            serial == 'emulator-5554'):
        raise UpgradeError('explicit_map_search_ux_upgrade_context_required')
    if any(env.get(key) for key in FORBIDDEN_ENV):
        raise UpgradeError('signing_or_account_material_forbidden_in_ux_upgrade')


def validate_receipts(receipts, source):
    if len(receipts) != 2:
        raise UpgradeError('exact_1819_1820_pair_required')
    for receipt, version in zip(receipts, (1819, VERSION)):
        expected = BASE_SOURCE if version == 1819 else source
        if (receipt.get('source_commit') != expected or receipt.get('package') != PACKAGE or
                type(receipt.get('version_code')) is not int or receipt['version_code'] != version or
                receipt.get('api') != API or receipt.get('signer_certificate_sha256') != CERTIFICATE or
                type(receipt.get('bytes')) is not int or receipt['bytes'] <= 0 or
                not re.fullmatch(r'[a-f0-9]{64}', str(receipt.get('sha256', ''))) or
                receipt.get('native_library_compression') != 'deflated' or
                receipt.get('extract_native_libs') is not True or
                receipt.get('debug_signing_allowed') is not False):
            raise UpgradeError('exact_baseline_and_same_source_candidate_identity_required')
    if receipts[0]['sha256'] != BASE_SHA256 or receipts[0]['bytes'] != BASE_BYTES:
        raise UpgradeError('immutable_1819_installer_required')


def assert_preserved(before, after, hashes, current_hashes):
    if (before.get('version_code') != 1819 or after.get('version_code') != VERSION or
            before.get('uid') != after.get('uid') or
            before.get('first_install_time') != after.get('first_install_time') or
            not hashes or hashes != current_hashes):
        raise UpgradeError('ordinary_update_identity_or_private_files_not_preserved')


def xml_nodes(raw):
    if len(raw.encode()) > 1024 * 1024 or '<!DOCTYPE' in raw:
        raise UpgradeError('bounded_owned_ui_hierarchy_required')
    root = ET.fromstring(raw)
    nodes = list(root.iter('node'))
    if root.tag != 'hierarchy' or len(nodes) > 1500:
        raise UpgradeError('bounded_android_hierarchy_required')
    if any('permissioncontroller' in node.get('package', '') for node in nodes):
        raise UpgradeError('unexpected_system_permission_prompt')
    return [node.attrib for node in nodes if node.get('package') == PACKAGE]


def label(node):
    return ' '.join(node.get(key, '') for key in ('text', 'content-desc', 'hint')).strip()


def contains(nodes, text):
    return any(text in label(node) for node in nodes)


def tap_center(nodes, texts):
    for text in texts:
        options = []
        for node in nodes:
            if node.get('package') != PACKAGE or text not in label(node) or node.get('enabled') == 'false':
                continue
            bounds = re.fullmatch(r'\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]', node.get('bounds', ''))
            if not bounds:
                continue
            left, top, right, bottom = map(int, bounds.groups())
            if 0 <= left < right <= 4096 and 0 <= top < bottom <= 8192:
                options.append(((right-left)*(bottom-top), (left+right)//2, (top+bottom)//2))
        if options:
            _, x, y = min(options)
            return x, y
    raise UpgradeError('owned_expected_ui_action_not_visible')


class UxDevice(Device):
    def adb(self, *values, timeout=60):
        return super().adb(*values, timeout=min(timeout, 60))

    def verify_disposable_root(self):
        self.adb('wait-for-device')
        if (self.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
                self.adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
                self.adb('shell', 'getprop', 'ro.product.cpu.abi') != 'x86_64' or
                self.adb('emu', 'avd', 'name').splitlines()[0] != AVD_NAME):
            raise UpgradeError('exact_fresh_ux1820_emulator_required')
        self.adb('root')
        self.adb('wait-for-device')
        if self.adb('shell', 'id', '-u') != '0':
            raise UpgradeError('rooted_disposable_ux1820_emulator_required')

    def hierarchy(self):
        target = '/data/local/tmp/aqer-ux1820.xml'
        self.adb('shell', 'uiautomator', 'dump', '--compressed', target, timeout=30)
        return xml_nodes(self.adb('shell', 'cat', target, timeout=15))

    def wait_for(self, text, attempts=8):
        for _ in range(attempts):
            nodes = self.hierarchy()
            if contains(nodes, text):
                return nodes
            time.sleep(1)
        raise UpgradeError('expected_guest_ui_not_reached')

    def tap(self, nodes, *texts):
        x, y = tap_center(nodes, texts)
        self.adb('shell', 'input', 'tap', str(x), str(y))

    def screenshot(self, folder, name):
        target = '/data/local/tmp/' + name
        self.adb('shell', 'screencap', '-p', target)
        self.adb('pull', target, str(folder / name))


def guest_smoke(device, output):
    nodes = device.wait_for('عقار اليمن')
    if contains(nodes, 'عقارات في منطقتك'):
        raise UpgradeError('automatic_location_introduction_still_visible')
    device.screenshot(output, '01-home-no-automatic-location.png')
    device.tap(nodes, 'تغيير المنطقة')
    sheet = device.wait_for('أين تبحث؟')
    if not contains(sheet, 'استخدم موقعي'):
        raise UpgradeError('explicit_location_choice_missing')
    device.screenshot(output, '02-explicit-location-picker.png')
    device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    nodes = device.wait_for('عقار اليمن')
    device.tap(nodes, 'بحث ذكي', 'فتح مساعد البحث الذكي')
    smart = device.wait_for('مكان يناسبك')
    if any('صنعاء' in label(node) for node in smart):
        raise UpgradeError('unknown_location_smart_hint_still_assumes_sanaa')
    device.screenshot(output, '03-fresh-smart-search-generic-location.png')
    device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    home = device.wait_for('عقار اليمن')
    device.tap(home, 'الخريطة')
    mapped = device.wait_for('البحث على الخريطة')
    search = tap_center(mapped, ['ابحث عن عقار'])
    draw = tap_center(mapped, ['رسم منطقة على الخريطة'])
    assistant = tap_center(mapped, ['فتح مساعد البحث الذكي'])
    sizes = re.findall(r'(?:Physical|Override) size: ([0-9]+)x([0-9]+)', device.adb('shell', 'wm', 'size'))
    if not sizes:
        raise UpgradeError('bounded_emulator_display_size_required')
    width = int(sizes[-1][0])
    if not (draw[0] < width / 2 and assistant[0] < width / 2 and
            search[1] < min(draw[1], assistant[1])):
        raise UpgradeError('map_search_top_or_floating_left_actions_misplaced')
    device.screenshot(output, '04-map-top-search-floating-actions.png')
    return {'passed': True, 'checks': ['first_ever_1820_home_has_no_automatic_location_introduction',
             'explicit_location_picker_remains_accessible', 'fresh_smart_search_uses_generic_unknown_location_hint',
             'native_map_search_above_lower_left_drawing_and_ai_controls'],
            'map_control_centres': {'search': search, 'draw': draw, 'assistant': assistant},
            'public_locations_rows_unavailable_under_network_isolation': True,
            'dhamar_hint_native_device_tested': False, 'native_map_layout_tested': True,
            'native_map_price_typing_tested': False, 'map_tiles_or_gestures_tested': False,
            'phone_acceptance': False, 'screenshots': ['01-home-no-automatic-location.png',
                '02-explicit-location-picker.png', '03-fresh-smart-search-generic-location.png',
                '04-map-top-search-floating-actions.png']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for role in ('baseline', 'candidate'):
        parser.add_argument('--' + role + '-apk', required=True)
        parser.add_argument('--' + role + '-receipt', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', default='map-search-ux-upgrade-proof')
    args = parser.parse_args()
    guard(os.environ, args.source, args.serial)
    if command('git', 'rev-parse', 'HEAD') != args.source:
        raise UpgradeError('checked_out_ux1820_source_mismatch')
    inputs = [regular_input(getattr(args, role + '_' + kind))
              for role in ('baseline', 'candidate') for kind in ('apk', 'receipt')]
    if len(set(inputs)) != 4:
        raise UpgradeError('distinct_baseline_candidate_files_required')
    output = Path(args.output).absolute()
    if output != output.resolve() or not output.is_relative_to(ROOT):
        raise UpgradeError('regular_ux1820_output_required')
    output.mkdir(mode=0o700)
    device = UxDevice(args.serial)
    rules, cleanup_failures = [], []
    installed = False
    proof = {'passed': False, 'status': 'failed', 'source_commit': args.source,
             'baseline_source_commit': BASE_SOURCE, 'package': PACKAGE,
             'signer_certificate_sha256': CERTIFICATE, 'version_chain': [1819, VERSION],
             'android_api': 36, 'environment': 'disposable_rooted_x86_64_emulator',
             'real_account_data_used': False, 'live_business_api_used': False,
             'physical_phone_acceptance': False, 'keystore_or_signed_in_session_migration_tested': False,
             'map_tiles_or_gestures_tested': False, 'uninstall_or_clear_data_used': False,
             'baseline_app_launched': False, 'cleanup_failures': cleanup_failures}
    stage = 'validate_actual_installers'
    try:
        receipts = [read_receipt(path) for path in inputs[1::2]]
        validate_receipts(receipts, args.source)
        tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
        inspected = [verify_apk(path, receipt, tools) for path, receipt in zip(inputs[::2], receipts)]
        for name, value in inspected[1]['native_sha256'].items():
            if not name.endswith('/libapp.so') and value != inspected[0]['native_sha256'].get(name):
                raise UpgradeError('preserved_native_runtime_changed')
        proof['installers'] = {str(version): public_identity(receipt) for version, receipt in zip((1819, VERSION), receipts)}
        stage = 'verify_fresh_disposable_emulator'
        device.verify_disposable_root()
        if device.adb('shell', 'pm', 'list', 'packages', '--user', '0', PACKAGE).strip():
            raise UpgradeError('fresh_owned_package_absence_required')
        proof['package_absent_before_first_install'] = True
        stage = 'install_unlaunched_1819_baseline'
        proof['baseline_install_host_wall_ms'] = device.install(inputs[0])
        installed = True
        before = device.snapshot()
        if before['version_code'] != 1819 or not 10000 <= before['uid'] <= 99999:
            raise UpgradeError('owned_baseline_uid_or_version_mismatch')
        stage = 'reject_owned_uid_ipv4_ipv6_network_before_first_launch'
        for family in ('iptables', 'ip6tables'):
            device.adb('shell', family, '-w', '5', '-I', 'OUTPUT', '-m', 'owner', '--uid-owner', str(before['uid']), '-j', 'REJECT')
            rules.append((family, str(before['uid'])))
            device.adb('shell', family, '-w', '5', '-C', 'OUTPUT', '-m', 'owner', '--uid-owner', str(before['uid']), '-j', 'REJECT')
        proof['network_isolation'] = 'Verified IPv4 and IPv6 OUTPUT REJECT for fresh application UID before its first ever launch.'
        fixtures = synthetic_fixtures()
        hashes = {key: hashlib.sha256(value).hexdigest() for key, value in fixtures.items()}
        write_fixtures(device, before['uid'], fixtures)
        if device.private_hashes(fixtures) != hashes:
            raise UpgradeError('synthetic_private_setup_failed')
        stage = 'ordinary_replace_install_1820'
        proof['candidate_install_host_wall_ms'] = device.install(inputs[2], replace=True)
        assert_preserved(before, device.snapshot(), hashes, device.private_hashes(fixtures))
        stage = 'ordinary_1820_launches'
        proof['activity_starts'] = device.cold_launches()
        assert_preserved(before, device.snapshot(), hashes, device.private_hashes(fixtures))
        stage = 'bounded_guest_ui_smoke'
        proof['guest_ui_smoke'] = guest_smoke(device, output)
        assert_preserved(before, device.snapshot(), hashes, device.private_hashes(fixtures))
        proof.update({'passed': True, 'status': 'passed', 'baseline_identity': before,
                      'installed_identity': device.snapshot(), 'private_fixture_sha256': hashes,
                      'uid_preserved': True, 'first_install_time_preserved': True,
                      'ordinary_launches_after_upgrade': 3})
    except Exception as error:
        proof.update({'failed_stage': stage, 'reason': failure_reason(error)})
        raise
    finally:
        stopped = not installed
        if installed:
            try:
                device.adb('shell', 'am', 'force-stop', PACKAGE)
                stopped = True
            except Exception as error:
                cleanup_failures.append({'step': 'force_stop', 'reason': failure_reason(error)})
        if stopped:
            for family, uid in reversed(rules):
                try:
                    device.adb('shell', family, '-w', '5', '-D', 'OUTPUT', '-m', 'owner', '--uid-owner', uid, '-j', 'REJECT')
                except Exception as error:
                    cleanup_failures.append({'step': family, 'reason': failure_reason(error)})
        if cleanup_failures:
            proof.update({'passed': False, 'status': 'failed'})
            proof.setdefault('failed_stage', 'cleanup')
        (output / 'ANDROID_MAP_SEARCH_UX_UPGRADE.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof, sort_keys=True), flush=True)
    if cleanup_failures:
        raise UpgradeError('ux1820_device_cleanup_failed')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(failure_reason(error), flush=True)
        raise SystemExit(1) from None
