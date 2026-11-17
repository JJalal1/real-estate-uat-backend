#!/usr/bin/env python3
"""Recheck the immutable 1820 APK on an isolated Android 36 guest."""
import json
import os
from pathlib import Path
import re
import sys
import time

APK_SOURCE = '8cdcc2b6de2146a0eca8390c7db82ae511c5113e'
APK_SHA256 = '61ef6c5a1598666ab91e74c4552b1cc450cad55548585330bd35bffa517c4b18'
PRODUCT = Path.cwd()
sys.path.insert(0, str(PRODUCT / 'scripts'))
import probe_map_search_ux_upgrade as upgrade

original_guard = upgrade.guard
original_validate = upgrade.validate_receipts


def guard(env, source, serial):
    harness = Path(__file__).resolve().parents[1]
    harness_sha = upgrade.command('git', '-C', harness, 'rev-parse', 'HEAD')
    harness_product_base = upgrade.command('git', '-C', harness, 'rev-parse', 'HEAD^^')
    if (source != APK_SOURCE or harness_sha != env.get('GITHUB_SHA') or
            harness_product_base != APK_SOURCE or harness == PRODUCT or
            not re.fullmatch(r'[0-9a-f]{40}', harness_sha)):
        raise upgrade.UpgradeError('exact_product_and_keyless_harness_required')
    # The product checkout is independently checked by the original main.
    original_guard({**env, 'GITHUB_SHA': APK_SOURCE}, source, serial)


def validate_receipts(receipts, source):
    original_validate(receipts, source)
    if receipts[1]['sha256'] != APK_SHA256:
        raise upgrade.UpgradeError('immutable_1820_installer_required')


def bounds(node):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
    if match is None:
        return None
    left, top, right, bottom = map(int, match.groups())
    if right > left and bottom > top:
        return ((left + right) // 2, (top + bottom) // 2, (right-left) * (bottom-top))
    return None


def target(nodes, texts, *, area=None):
    choices = []
    for node in nodes:
        xy = bounds(node)
        if xy is None or node.get('enabled') == 'false':
            continue
        x, y, size = xy
        if area is not None and not area(x, y):
            continue
        label = upgrade.label(node)
        for priority, text in enumerate(texts):
            if text in label:
                choices.append((node.get('clickable') != 'true', priority, size, x, y))
                break
    if not choices:
        return None
    _, _, _, x, y = min(choices)
    return x, y


class Device(upgrade.UxDevice):
    def hierarchy(self):
        # Keep the contents of the dialog and its accessible ancestors.
        path = '/data/local/tmp/aqer-ux1820-recheck.xml'
        self.adb('shell', 'uiautomator', 'dump', path, timeout=30)
        return upgrade.xml_nodes(self.adb('shell', 'cat', path, timeout=15))


def wait_for(device, predicate, *, attempts=5):
    for _ in range(attempts):
        nodes = device.hierarchy()
        if predicate(nodes):
            return nodes
        time.sleep(1)
    return None


def tap(device, point):
    device.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))


def open_page(device, nodes, labels, predicate, stage, output, *, fixed_point=None, area=None):
    semantic_point = target(nodes, labels, area=area)
    points = list(dict.fromkeys(p for p in (semantic_point, fixed_point) if p is not None))
    for point in points:
        tap(device, point)
        reached = wait_for(device, predicate, attempts=3)
        if reached is not None:
            print(json.dumps({'stage': stage, 'tap': point, 'method': 'semantics' if point == semantic_point else 'observed_control'}))
            return reached
    device.screenshot(output, 'failed-' + stage + '.png')
    raise upgrade.UpgradeError('guest_' + stage + '_not_reached')


def verify_guest(device, output):
    tests = upgrade.contains
    home = wait_for(device, lambda n: tests(n, 'عقار اليمن'))
    if home is None or tests(home, 'عقارات في منطقتك'):
        raise upgrade.UpgradeError('guest_home_has_unexpected_location_intro')
    sizes = re.findall(r'(?:Physical|Override) size: ([0-9]+)x([0-9]+)', device.adb('shell', 'wm', 'size'))
    if not sizes or tuple(map(int, sizes[-1])) != (540, 960):
        raise upgrade.UpgradeError('observed_guest_screen_dimensions_required')
    shots = ['01-home-no-automatic-location.png', '02-explicit-location-picker.png',
             '03-fresh-smart-search-generic-location.png', '04-map-top-search-floating-actions.png']
    device.screenshot(output, shots[0])

    # The first attempt reached Home in dark mode and showed this real region
    # button at (379, 174) on the same controlled AVD, above the results.
    open_page(device, home, ('تغيير المنطقة', 'صنعاء'),
              lambda n: tests(n, 'استخدم موقعي'), 'location_picker', output,
              fixed_point=(379, 174), area=lambda x, y: 275 <= x <= 460 and 100 <= y <= 210)
    device.screenshot(output, shots[1])
    device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    home = wait_for(device, lambda n: tests(n, 'عقار اليمن') and not tests(n, 'استخدم موقعي'))
    if home is None:
        raise upgrade.UpgradeError('guest_home_after_location_missing')

    smart = open_page(device, home, ('بحث ذكي', 'فتح مساعد البحث الذكي'),
                      lambda n: tests(n, 'مكان يناسبك'), 'smart_search', output,
                      fixed_point=(407, 388))
    if tests(smart, 'صنعاء') or not tests(smart, 'شقة للإيجار'):
        device.screenshot(output, 'failed-generic-hint.png')
        raise upgrade.UpgradeError('guest_smart_search_generic_hint_required')
    device.screenshot(output, shots[2])
    device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    home = wait_for(device, lambda n: tests(n, 'عقار اليمن'))
    if home is None:
        raise upgrade.UpgradeError('guest_home_after_smart_search_missing')
    mapped = open_page(device, home, ('الخريطة',), lambda n: tests(n, 'البحث على الخريطة'),
                       'map_search', output, fixed_point=(54, 683))
    device.screenshot(output, shots[3])
    # These physical centres are from the captured 540x960 map. Activate both
    # controls to verify their hit targets even when Android merges their labels.
    search = (314, 263)
    draw = (54, 780)
    assistant = (140, 780)
    open_page(device, mapped, (), lambda n: tests(n, 'إلغاء') or tests(n, 'ارسم بإصبعك'),
              'map_drawing_action', output, fixed_point=draw)
    device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    mapped = wait_for(device, lambda n: tests(n, 'البحث على الخريطة') and not tests(n, 'ارسم بإصبعك'))
    if mapped is None:
        raise upgrade.UpgradeError('guest_map_after_drawing_cancel_missing')
    open_page(device, mapped, (), lambda n: tests(n, 'البحث الذكي') and not tests(n, 'البحث على الخريطة'),
              'map_assistant_action', output, fixed_point=assistant)
    return {
        'passed': True,
        'checks': ['first_ever_1820_home_has_no_automatic_location_introduction',
                   'explicit_location_picker_remains_accessible',
                   'fresh_smart_search_uses_generic_unknown_location_hint',
                   'native_map_search_above_lower_left_drawing_and_ai_controls',
                   'both_lower_left_map_actions_activated_on_device'],
        'map_control_centres': {'search': search, 'draw': draw, 'assistant': assistant},
        'public_locations_rows_unavailable_under_network_isolation': True,
        'dhamar_hint_native_device_tested': False, 'native_map_layout_tested': True,
        'native_map_price_typing_tested': False, 'map_tiles_or_gestures_tested': False,
        'phone_acceptance': False, 'screenshots': shots,
    }


if __name__ == '__main__':
    upgrade.guard = guard
    upgrade.validate_receipts = validate_receipts
    upgrade.UxDevice = Device
    upgrade.guest_smoke = verify_guest
    try:
        upgrade.main()
    except Exception as error:
        print(upgrade.failure_reason(error), flush=True)
        raise SystemExit(1) from None
