"""Replay reported map defects and capture numeric timings on the signed UAT APK."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from probe_apk_cleanup_upgrade import ACTIVITY, command, failure_reason, read_receipt
from probe_map_search_ux_upgrade import PACKAGE, UxDevice, UpgradeError, contains, guard, label
from verify_map_search_ux_apk import ROUND4_VERSION

MAP = 'البحث على الخريطة'
SMART = 'البحث الذكي'
DETAILS = 'تفاصيل العقار'
PROPERTY_147 = 'عمارة للإيجار في ذمار — تجريبي 20'
PRICE_ERROR = 'الحد الأدنى يجب ألا يتجاوز الحد الأعلى.'
MAP_CANVAS = 'Showing a Map created with MapLibre'
NORMAL = (1080, 1920, 420, '1.0')
SMALL = (720, 1280, 360, '1.8')
TRACE = re.compile(r'^\s*(\d+\.\d+)\s+.*?\bAQER_NET:\s*(\{.*\})$')


def bounds(node):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
    if not match:
        raise UpgradeError('expected_visible_android_bounds')
    return tuple(map(int, match.groups()))


def identified(nodes, key):
    return next((node for node in nodes if node.get('resource-id', '').split('/')[-1] == key), None)


def matching(nodes, text):
    return [node for node in nodes if text in label(node)]


def wait(device, predicate, stage, timeout=50):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            nodes = device.hierarchy()
            if predicate(nodes):
                return nodes
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pass
        time.sleep(.4)
    raise UpgradeError(stage)


def tap_node(device, node):
    left, top, right, bottom = bounds(node)
    device.adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))


def tap(device, x, y):
    device.adb('shell', 'input', 'tap', str(x), str(y))


def swipe(device, x, start, end, ms=430):
    device.adb('shell', 'input', 'swipe', str(x), str(start), str(x), str(end), str(ms))


def back(device, nodes=None):
    if nodes is None:
        device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    else:
        try:
            device.tap(nodes, 'رجوع')
        except UpgradeError:
            tap(device, 1006, 137)


def display(device, geometry):
    width, height, density, scale = geometry
    device.adb('shell', 'wm', 'size', f'{width}x{height}')
    device.adb('shell', 'wm', 'density', str(density))
    device.adb('shell', 'settings', 'put', 'system', 'font_scale', scale)
    return {
        'size': device.adb('shell', 'wm', 'size'),
        'density': device.adb('shell', 'wm', 'density'),
        'fontScale': device.adb('shell', 'settings', 'get', 'system', 'font_scale'),
    }


def home_query(device):
    nodes = wait(device, lambda n: contains(n, 'تغيير المنطقة'), 'home_missing')
    device.tap(nodes, 'تغيير المنطقة')
    try:
        nodes = wait(device, lambda n: contains(n, 'أين تبحث'), 'governorate_picker_missing', timeout=8)
    except UpgradeError:
        tap(device, 795, 137)
        nodes = wait(device, lambda n: contains(n, 'أين تبحث'), 'governorate_picker_missing')
    for _ in range(4):
        if matching(nodes, 'ذمار'):
            break
        swipe(device, 540, 1760, 1250, 540)
        nodes = device.hierarchy()
    device.tap(nodes, 'ذمار')
    nodes = wait(device, lambda n: contains(n, 'تغيير المنطقة') and contains(n, 'ذمار'), 'dhamar_not_selected')
    device.tap(nodes, 'إيجار')
    tap(device, 540, 298)
    nodes = wait(device, lambda n: contains(n, 'البحث عن عقار'), 'home_search_missing')
    edit = next(node for node in nodes if node.get('class') == 'android.widget.EditText')
    tap_node(device, edit)
    device.adb('shell', 'input', 'text', '20')
    device.tap(wait(device, lambda n: contains(n, 'تنفيذ'), 'home_submit_missing'), 'تنفيذ')
    return wait(device, lambda n: contains(n, 'نتائج «20»') and contains(n, PROPERTY_147), 'home_search_20_unavailable')


def open_map(device, nodes=None):
    if keyboard_shown(device):
        back(device)
        nodes = None
    found = None
    for _ in range(3):
        nodes = nodes or wait(device, lambda n: contains(n, 'عرض على الخريطة'), 'home_map_action_missing')
        action = matching(nodes, 'عرض على الخريطة')[0]
        left, top, right, bottom = bounds(action)
        # Tap the label itself. An accessibility node can straddle a clipped
        # list or still carry the geometry from before the IME closed.
        tap(device, left + (right - left) // 2, top + (bottom - top) // 2)
        try:
            found = wait(device, lambda n: contains(n, MAP), 'ordinary_map_missing', timeout=9)
            break
        except UpgradeError:
            if keyboard_shown(device):
                back(device)
            nodes = None
    if found is None:
        raise UpgradeError('ordinary_map_missing')
    return found


def smart_navigation(device, folder, app_arrow):
    suffix = 'app-arrow' if app_arrow else 'android-back'
    nodes = wait(device, lambda n: contains(n, MAP) and contains(n, 'الإيجار الشهري'), 'ordinary_rent_map_missing')
    device.tap(nodes, 'فتح مساعد البحث الذكي')
    nodes = wait(device, lambda n: contains(n, 'تعديل للإيجار'), 'copied_rent_missing')
    remove = identified(nodes, 'smart-chip-remove-purpose')
    if remove is None:
        chip = matching(nodes, 'تعديل للإيجار')[0]
        left, top, _, bottom = bounds(chip)
        tap(device, left - 58, (top + bottom) // 2)
    else:
        tap_node(device, remove)
    nodes = wait(device, lambda n: contains(n, 'تعديل 20') and not contains(n, 'تعديل للإيجار'), 'edited_smart_scope_missing')
    device.tap(nodes, 'الخريطة')
    nodes = wait(device, lambda n: contains(n, MAP) and contains(n, 'القائمة') and
                 contains(n, 'اسحب لتوسيع العقارات'), 'smart_child_map_missing')
    handle = matching(nodes, 'اسحب لتوسيع العقارات')[0]
    left, top, right, _ = bounds(handle)
    swipe(device, (left + right) // 2, top + 22, max(470, top - 710))
    nodes = wait(device, lambda n: contains(n, PROPERTY_147), 'map_drawer_property_147_missing')
    device.tap(nodes, PROPERTY_147)
    nodes = wait(device, lambda n: contains(n, DETAILS) and contains(n, PROPERTY_147), 'property_147_details_missing')
    device.screenshot(folder, suffix + '-147-details.png')
    back(device, nodes if app_arrow else None)
    nodes = wait(device, lambda n: contains(n, 'القائمة') and contains(n, MAP) and not contains(n, DETAILS),
                 'smart_map_not_restored_after_details')
    back(device, nodes if app_arrow else None)
    nodes = wait(device, lambda n: contains(n, SMART) and contains(n, 'تعديل 20') and not contains(n, 'تعديل للإيجار')
                 and not contains(n, MAP), 'edited_smart_list_not_restored')
    device.screenshot(folder, suffix + '-edited-smart-list.png')
    back(device, nodes if app_arrow else None)
    wait(device, lambda n: contains(n, MAP) and contains(n, 'الإيجار الشهري') and not contains(n, 'القائمة'),
         'parent_rent_map_not_restored_on_journey_exit')
    device.screenshot(folder, suffix + '-parent-rent-map.png')


def keyboard_shown(device):
    return bool(re.search(r'\bm(?:InputShown|IsInputViewShown)\s*=\s*true\b',
                          device.adb('shell', 'dumpsys', 'input_method')))


def price_node(device, key, geometry, keyboard=False):
    width, height, _, _ = geometry
    for attempt in range(8):
        nodes = device.hierarchy()
        node = identified(nodes, key)
        if node:
            _, top, _, bottom = bounds(node)
            if bottom - top > 72:
                return node
        y = 405 if geometry == SMALL else 700
        if geometry == SMALL and not keyboard:
            y = 530
        distance = 130 if height == 1280 else 310
        if attempt >= 4:
            swipe(device, width // 2, y - distance, y)
        else:
            swipe(device, width // 2, y, y - distance)
    raise UpgradeError('price_control_not_reachable_' + key)


def price(device, folder, geometry):
    width, _, density, scale = geometry
    minimum = '177000' if geometry == SMALL else '1000000'
    node = price_node(device, 'published-filter-min-price', geometry)
    tap_node(device, node)
    device.adb('shell', 'input', 'text', minimum)
    node = price_node(device, 'published-filter-max-price', geometry, keyboard=True)
    tap_node(device, node)
    device.adb('shell', 'input', 'text', '100000')
    if geometry == NORMAL and keyboard_shown(device):
        back(device)
    has_keyboard = keyboard_shown(device)
    if has_keyboard != (geometry == SMALL):
        raise UpgradeError('price_keyboard_profile_mismatch')
    node = price_node(device, 'published-price-apply', geometry, keyboard=has_keyboard)
    tap_node(device, node)
    nodes = wait(device, lambda n: contains(n, PRICE_ERROR), 'price_error_missing')
    error = matching(nodes, PRICE_ERROR)[0]
    canvas = matching(nodes, MAP_CANVAS)
    _, top, _, bottom = bounds(error)
    if bottom - top < 12 * density / 160 * float(scale) or (canvas and bottom > bounds(canvas[0])[1] + 2):
        raise UpgradeError('price_error_visually_clipped')
    for key, value in [('published-filter-min-price', minimum), ('published-filter-max-price', '100000')]:
        field = identified(nodes, key)
        if not field or value not in label(field):
            raise UpgradeError('price_value_not_visible_' + key)
    device.screenshot(folder, f'price-error-{width}.png')
    if has_keyboard:
        back(device)
    return {'keyboard_visible': has_keyboard, 'message_bounds_pixels': bounds(error)}


def net_profile(device, weak):
    device.adb('emu', 'network', 'speed', '96:256' if weak else 'full')
    device.adb('emu', 'network', 'delay', '350:550' if weak else 'none')
    status = device.adb('emu', 'network', 'status')
    if weak and not all(value in status for value in ('256000', '96000', '350', '550')):
        raise UpgradeError('weak_emulator_network_settings_not_confirmed')
    return status


def timings(device):
    records = []
    for line in device.adb('logcat', '-d', '-v', 'epoch', '-s', 'AQER_NET:I', '*:S').splitlines():
        match = TRACE.fullmatch(line)
        if not match:
            continue
        row = json.loads(match[2])
        keys = {'resource', 'page', 'phase', 'seq', 'elapsedMs', 'status'}
        if set(row) == keys and row['resource'] == 3 and all(type(row[key]) is int for key in keys):
            records.append({'deviceEpoch': float(match[1]), **row})
    return records


def network(device, folder, evidence):
    for weak in (False, True):
        profile = 'weak' if weak else 'normal'
        settings = net_profile(device, weak)
        for index in range(1, 4):
            if evidence:
                # Keep Home intact while letting the short repository cache
                # expire so each viewport sample can include the transport.
                time.sleep(21)
            trial = {'profile': profile, 'settings': settings, 'trial': index}
            evidence.append(trial)
            nodes = wait(device, lambda n: contains(n, 'عرض على الخريطة') and contains(n, PROPERTY_147), 'benchmark_home_missing')
            device.adb('logcat', '-c')
            t0 = time.monotonic()
            device.tap(nodes, 'عرض على الخريطة')
            trial['tap_dispatch_ms'] = round((time.monotonic() - t0) * 1000)
            first_ten = None
            last_nodes = []
            deadline = t0 + 55
            while time.monotonic() < deadline:
                before_ms = round((time.monotonic() - t0) * 1000)
                try:
                    last_nodes = device.hierarchy()
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    continue
                after_ms = round((time.monotonic() - t0) * 1000)
                if contains(last_nodes, '10 عقار في النطاق') and first_ten is None:
                    first_ten = [before_ms, after_ms]
                events = timings(device)
                complete = {r['seq'] for r in events if r['phase'] == 5}
                decoded = {r['seq'] for r in events if r['phase'] == 3 and r['status'] == 200}
                if first_ten and complete & decoded:
                    break
                time.sleep(.6)
            trial.update(first_ten_observation_ms=first_ten, observed_ms=round((time.monotonic() - t0) * 1000),
                         trace=timings(device), indicator_visible=contains(last_nodes, 'جارٍ تحديث النطاق'))
            device.screenshot(folder, f'{profile}-{index}.png')
            back(device)
            wait(device, lambda n: contains(n, 'عرض على الخريطة'), 'benchmark_home_not_restored')
    net_profile(device, False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--ui-only', action='store_true')
    args = parser.parse_args()
    source = command('git', 'rev-parse', 'HEAD')
    serial = 'emulator-5554'
    guard(os.environ, source, serial)
    device = UxDevice(serial)
    device.verify_disposable_root()
    receipt = read_receipt(Path(args.receipt))
    installed = device.adb('shell', 'pm', 'path', PACKAGE).removeprefix('package:')
    installed_digest = device.adb('shell', 'sha256sum', installed).split()[0]
    if receipt['source_commit'] != source or receipt['version_code'] != ROUND4_VERSION or receipt['sha256'] != installed_digest:
        raise UpgradeError('installed_signed_candidate_mismatch')
    output = Path(args.output)
    proof = {'source_commit': source, 'sha256': installed_digest, 'version': ROUND4_VERSION,
             'actor': 'guest', 'android_api': 36, 'cases': {}, 'network': []}
    stage = 'prepare_guest'
    try:
        proof['normal_display'] = display(device, NORMAL)
        device.adb('shell', 'settings', 'put', 'secure', 'show_ime_with_hard_keyboard', '1')
        device.adb('shell', 'svc', 'wifi', 'disable')
        device.adb('shell', 'svc', 'data', 'enable')
        net_profile(device, False)
        device.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/' + ACTIVITY)
        home_query(device)
        if not args.ui_only:
            stage = 'network'
            network(device, output, proof['network'])
            proof['cases'][stage] = {'trials': len(proof['network'])}
        stage = 'open_ordinary_map'
        open_map(device)
        for app_arrow in (False, True):
            stage = 'app_arrow' if app_arrow else 'android_back'
            print('ROUND4 ' + stage, flush=True)
            smart_navigation(device, output, app_arrow)
            proof['cases'][stage] = {'passed': True}
        stage = 'normal_price'
        print('ROUND4 ' + stage, flush=True)
        proof['cases'][stage] = {'passed': True, **price(device, output, NORMAL)}
        back(device)
        wait(device, lambda n: contains(n, 'عرض على الخريطة'), 'home_before_small_display_missing')
        proof['small_display'] = display(device, SMALL)
        open_map(device)
        stage = 'small_price'
        print('ROUND4 ' + stage, flush=True)
        proof['cases'][stage] = {'passed': True, **price(device, output, SMALL)}
    except Exception as error:
        proof['failure'] = {'stage': stage, 'reason': failure_reason(error)}
        device.screenshot(output, f'failure-{stage}.png')
        raise
    finally:
        (output / 'ANDROID_ROUND4.json').write_text(json.dumps(proof, indent=2) + '\n')
        net_profile(device, False)
        display(device, NORMAL)
        device.adb('shell', 'svc', 'wifi', 'enable')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit(failure_reason(error)) from None
