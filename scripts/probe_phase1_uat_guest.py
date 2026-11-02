#!/usr/bin/env python3
"""Bounded real-APK guest navigation against UAT. No login, tokens or account writes.

Screenshots are native Android frames, never generated widget previews. Reported
UI interactions still require visual review; this is not full phase-one acceptance.
Opening fixture 60 uses the app's normal guest view analytics POST for that
existing fictional listing. No account or listing-editor write is performed.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

import probe_phase1_android_ui as core

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = core.API.removesuffix('/api')
FIXTURE_ID = 60
FIXTURE_TITLE = 'شقة للإيجار في صنعاء — تجريبي'
ACTIVITY = core.PACKAGE + '/com.example.real_estate_mobile.MainActivity'


class Blocked(RuntimeError):
    """Fixed public diagnostic code only."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def get_public(path):
    allowed = ['/api/health', '/api/properties/60', '/api/listing-editor-drafts',
               '/api/admin/workspace/tasks?scope=inbox']
    if path not in allowed:
        raise core.GateError('public_request_path_not_allowlisted')
    started = time.monotonic()
    request = urllib.request.Request(ORIGIN + path, headers={
        'Accept': 'application/json', 'User-Agent': 'Aqer-Phase1-Guest/1.0'})
    try:
        response = urllib.request.build_opener(NoRedirect()).open(request, timeout=25)
    except urllib.error.HTTPError as error:
        if 300 <= error.code < 400:
            error.close()
            raise core.GateError('public_response_redirect_refused') from None
        response = error
    with response:
        if response.geturl() != ORIGIN + path:
            raise core.GateError('public_response_redirect_refused')
        payload = response.read(2 * 1024 * 1024 + 1)
        if len(payload) > 2 * 1024 * 1024:
            raise core.GateError('public_response_too_large')
        receipt = {'path': path, 'method': 'GET', 'http_status': response.status,
                   'elapsed_ms': round((time.monotonic() - started) * 1000),
                   'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
    # Keep actual response content in memory only; never export contact details.
    try:
        data = json.loads(payload)
    except (ValueError, UnicodeDecodeError):
        data = {}
    return receipt, data


def node_labels(node):
    # Flutter may merge a control label and its child value with newlines.
    # Match whole semantic segments, never an arbitrary substring.
    return [line.strip() for key in ['text', 'content-desc']
            for line in node.get(key, '').splitlines() if line.strip()]


def node_bounds(node):
    match = re.fullmatch(r'\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]', node.get('bounds', ''))
    if not match:
        return None
    left, top, right, bottom = map(int, match.groups())
    return (left, top, right, bottom) if right > left and bottom > top else None


class GuestProbe:
    def __init__(self, root, env, run=core.execute):
        if not core.enabled(env):
            raise core.GateError('manual_opt_in_required')
        self.root, self.env, self.run = root, env, run
        self.serial = None
        self.out = root / 'android-uat-guest-evidence'
        self.installed = False
        self.recorder = None
        self.created = False
        self.report = {'scope': 'real-uat-guest-android-navigation', 'cases': [], 'frames': [],
                       'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       'source_commit': env.get('SOURCE_COMMIT'), 'api': core.API,
                       'accounts': ['guest'], 'account_writes': False, 'fixture_ids': [FIXTURE_ID],
                       'permitted_live_side_effects': ['Normal guest view analytics for existing synthetic property 60'],
                       'synthetic_widgets': False, 'offline_fallback': False,
                       'phase1_accepted': False, 'visual_review_required': True,
                       'limitations': ['No authenticated broker/support journeys',
                                       'No FCM, voice, GPS or owner-handset acceptance',
                                       'UI gesture receipts do not prove map/zoom rendering quality']}

    def command(self, argv, codes=(0,), binary=False, timeout=30):
        result = self.run([str(x) for x in argv], binary=binary, timeout=timeout)
        if result.returncode not in codes:
            raise core.GateError('guest_command_failed')
        return result.stdout if binary else result.stdout.strip()

    def adb(self, *args, **kwargs):
        return self.command(['adb', '-s', self.serial, *args], **kwargs)

    def validate_environment(self):
        source, number = self.env.get('SOURCE_COMMIT', ''), self.env.get('GITHUB_RUN_NUMBER', '')
        if source != self.env.get('GITHUB_SHA') or not re.fullmatch('[a-f0-9]{40}', source) or not number.isdigit():
            raise core.GateError('invalid_source_or_run')
        self.proof = json.loads((self.root / 'dist/APK_VERIFICATION.json').read_text())
        self.apk = self.root / f'dist/real-estate-broker-uat-{number}.apk'
        core.validate_proof(self.proof, self.apk.read_bytes(), source, int(number))
        sdk = Path(self.env['ANDROID_HOME'])
        if 'KVM' not in self.command([sdk / 'emulator/emulator', '-accel-check']):
            raise core.GateError('kvm_required')
        tools = sorted((sdk / 'build-tools').glob('*/apksigner'))
        if not tools:
            raise core.GateError('android_build_tools_missing')
        signer = tools[-1]
        signed = self.command([signer, 'verify', '--print-certs', self.apk])
        digest = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signed)
        if not digest or digest[1].lower() != self.proof['certificate_sha256']:
            raise core.GateError('guest_release_certificate_mismatch')
        core.validate_badging(self.command([signer.parent / 'aapt', 'dump', 'badging', self.apk]),
                              core.PACKAGE, self.proof['version_code'], release=True)
        devices = self.command(['adb', 'devices'])
        serials = re.findall(r'^(emulator-[0-9]+)\s+device\s*$', devices, re.M)
        if len(serials) != 1:
            raise core.GateError('one_ready_emulator_required')
        self.serial = serials[0]
        for key, expected in [('ro.boot.qemu', '1'), ('sys.boot_completed', '1'), ('ro.build.version.sdk', '36')]:
            if self.adb('shell', 'getprop', key) != expected:
                raise core.GateError('booted_disposable_api36_emulator_required')
        for package in [core.PACKAGE, core.TEST_PACKAGE]:
            if self.adb('shell', 'pm', 'path', package, codes=(0, 1)):
                raise core.GateError('fresh_guest_install_required')
        for tool in ['iptables', 'ip6tables']:
            result = self.run(['adb', '-s', self.serial, 'shell', tool, '-C', 'OUTPUT', '-j', 'REJECT'])
            if result.returncode != 1:
                raise core.GateError('guest_network_not_restored')
        if ORIGIN.removeprefix('https://') in self.adb('shell', 'cat', '/etc/hosts'):
            raise core.GateError('guest_api_host_override_refused')
        if self.adb('reverse', '--list'):
            raise core.GateError('guest_reverse_proxy_refused')
        self.report.update(android_api=36, serial=self.serial, version_code=self.proof['version_code'],
                           apk_sha256=self.proof['sha256'], certificate_sha256=self.proof['certificate_sha256'])

    def save(self):
        (self.out / 'report.json').write_text(json.dumps(self.report, ensure_ascii=False, indent=2) + '\n')

    def nodes(self):
        target = '/sdcard/aqer-phase1-guest.xml'
        self.adb('shell', 'rm', '-f', target)
        self.adb('shell', 'uiautomator', 'dump', target, timeout=20)
        raw = self.adb('shell', 'cat', target)
        try:
            return list(ET.fromstring(raw).iter('node'))
        except ET.ParseError:
            raise Blocked('fresh_accessibility_tree_unavailable') from None

    def matches(self, nodes, text, prefix=False):
        return [n for n in nodes if n.get('package') == core.PACKAGE and node_bounds(n)
                and any(v.startswith(text) if prefix else v == text for v in node_labels(n))]

    def tap(self, text, prefix=False, bottom=False):
        nodes = self.matches(self.nodes(), text, prefix)
        if not nodes:
            raise Blocked('named_control_not_found')
        def order(node):
            left, top, right, lower = node_bounds(node)
            return -(top + lower) if bottom else (right - left) * (lower - top)
        left, top, right, lower = node_bounds(min(nodes, key=order))
        self.adb('shell', 'input', 'tap', (left + right) // 2, (top + lower) // 2)
        time.sleep(.8)

    def home_entry(self, entry):
        controls = {'search': ('ابحث عن عقار أو منطقة…', (540, 310)),
                    'map': ('الخريطة', (110, 310))}
        if entry not in controls:
            raise Blocked('unknown_home_entry')
        label, point = controls[entry]
        if self.has(label):
            self.tap(label)
            return
        # Grounded in the original CI453/API36 Home frame, not a widget fixture.
        # No coordinate fallback on another size, route, app or modal window.
        frame = self.frame('home-before-' + entry + '-coordinate')
        info = self.report['frames'][-1]
        nodes = self.nodes()
        if ((info['width'], info['height']) != (1080, 1920) or
                not all(self.matches(nodes, text) for text in ['ماذا تبحث عنه؟', 'العقارات', 'حسابي'])):
            raise Blocked('observed_home_coordinate_precondition_failed')
        self.report.setdefault('coordinate_actions', []).append({
            'entry': entry, 'point': list(point), 'fresh_frame': frame,
            'reference_ci': 41501756108,
            'reference_frame_sha256': '6d7915353802ee84a1c472f84a24bf829f4fbe1cefa419cb7aba552266315d85',
            'destination_assertion_required': True})
        self.adb('shell', 'input', 'tap', *point)
        time.sleep(.8)

    def search_input(self):
        nodes = self.nodes()
        if not self.matches(nodes, 'البحث عن عقار'):
            raise Blocked('search_page_not_observed')
        fields = [node for node in nodes if node.get('package') == core.PACKAGE and
                  node.get('class') == 'android.widget.EditText' and node_bounds(node) and
                  node.get('enabled') == 'true']
        if len(fields) != 1:
            raise Blocked('unique_search_input_not_observed')
        left, top, right, lower = node_bounds(fields[0])
        self.adb('shell', 'input', 'tap', (left + right) // 2, (top + lower) // 2)
        time.sleep(.4)

    def has(self, text, prefix=False):
        return bool(self.matches(self.nodes(), text, prefix))

    def frame(self, name):
        data = self.adb('exec-out', 'screencap', '-p', binary=True)
        info = core.validate_png(data)
        (self.out / (name + '.png')).write_bytes(data)
        self.report['frames'].append({'file': name + '.png', **info,
            'captured_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
        self.save()
        return name + '.png'

    def case(self, name, expected, action):
        item = {'id': name, 'expected': expected, 'status': 'NOT RUN', 'evidence': []}
        self.report['cases'].append(item)
        try:
            actual = action() or {}
            item.update(status='PASS', actual=actual)
        except Blocked as error:
            item.update(status='BLOCKED', reason=str(error))
        except Exception as error:
            item.update(status='FAIL', error_type=type(error).__name__)
        try:
            item['evidence'].append(self.frame(name))
        except Exception:
            item.update(status='FAIL', capture_failed=True)
        self.save()

    def back(self):
        self.adb('shell', 'input', 'keyevent', '4')
        time.sleep(.8)

    def home(self):
        if self.has('العقارات'):
            self.tap('العقارات', bottom=True)
        else:
            self.back()
        if not self.has('ماذا تبحث عنه؟'):
            raise Blocked('home_not_observed')

    def startup(self):
        self.adb('shell', 'am', 'start', '-W', '-n', ACTIVITY, timeout=50)
        deadline, continued = time.monotonic() + 35, False
        while time.monotonic() < deadline:
            nodes = self.nodes()
            # Only deny OS permissions in this new disposable guest install.
            for node in nodes:
                if str(node.get('package', '')).endswith('.permissioncontroller') and \
                        node.get('resource-id', '').endswith(':id/permission_deny_button') and node_bounds(node):
                    left, top, right, lower = node_bounds(node)
                    self.adb('shell', 'input', 'tap', (left + right) // 2, (top + lower) // 2)
            if self.matches(nodes, 'المتابعة الآن'):
                self.tap('المتابعة الآن')
                continued = True
            elif continued and self.matches(nodes, 'ماذا تبحث عنه؟') and self.matches(nodes, 'حسابي'):
                return {'first_run_continued': True, 'flutter_home_labels': True}
            time.sleep(.5)
        raise Blocked('guest_first_run_not_ready')

    def search(self):
        self.home()
        self.home_entry('search')
        self.search_input()
        self.adb('shell', 'input', 'text', 'phase1-ci-no-match')
        self.adb('shell', 'input', 'keyevent', '66')
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.has('لا توجد عقارات مطابقة الآن') and self.has('نتائج «phase1-ci-no-match»'):
                return {'entered_query': 'phase1-ci-no-match', 'server_fixture_confirmed': self.live_fixture,
                        'empty_result_visible': True}
            time.sleep(.5)
        raise Blocked('submitted_search_result_not_observed')

    def filters(self):
        self.tap('شقق')
        self.tap('إيجار')
        nodes = self.nodes()
        selected = lambda text: any(n.get('selected') == 'true' or n.get('checked') == 'true'
                                    for n in self.matches(nodes, text))
        if not (selected('شقق') and selected('إيجار') and self.matches(nodes, 'الغرف', prefix=True)
                and self.matches(nodes, 'حمامات') and self.matches(nodes, 'أعلى إيجار')
                and not self.matches(nodes, 'الكل')):
            raise Blocked('dynamic_filter_selection_not_observed')
        return {'apartment_and_rent_selected': True, 'dynamic_rooms_baths_and_price_visible': True,
                'all_chip_absent': True}

    def details(self):
        if not self.live_fixture:
            raise Blocked('live_fixture_precondition_missing')
        # Explicit deep-link entry: does not certify a card tap.
        self.adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW',
                 '-d', 'realestate://app/properties/60', core.PACKAGE)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.has(FIXTURE_TITLE) and self.has('تفاصيل العقار'):
                return {'entry': 'actual_android_deep_link', 'fixture_id': FIXTURE_ID,
                        'live_fixture_title_rendered': True, 'details_header_visible': True,
                        'card_tap_tested': False}
            time.sleep(.5)
        raise Blocked('live_fixture_details_not_observed')

    def gallery(self):
        self.tap('تكبير الصور')
        self.dismiss_immersive_tutorial()
        self.frame('gallery-before-double-tap')
        info = self.report['frames'][-1]
        image = self.fullscreen_gallery_image(info)
        left, top, right, lower = node_bounds(image)
        x, y = (left + right) // 2, (top + lower) // 2
        # One local shell round trip keeps both real taps inside Android's
        # double-tap interval; coordinates are validated numeric node bounds.
        self.adb('shell', f'input tap {x} {y}; input tap {x} {y}')
        time.sleep(.5)
        self.fullscreen_gallery_image(info)
        return {'gallery_opened': True, 'double_tap_at_observed_image': True,
                'fullscreen_witness': 'unique_image_matching_counter_frame_bounds_no_home_or_details',
                'image_and_zoom_quality_need_visual_review': True}

    def fullscreen_gallery_image(self, frame):
        nodes = self.nodes()
        images = self.matches(nodes, 'صورة العقار ', prefix=True)
        if (len(images) != 1 or self.matches(nodes, 'تفاصيل العقار') or self.matches(nodes, 'ماذا تبحث عنه؟')):
            raise Blocked('fullscreen_gallery_not_observed')
        labels = [re.fullmatch(r'صورة العقار ([1-9][0-9]*) من ([1-9][0-9]*)', value)
                  for value in node_labels(images[0])]
        labels = [value for value in labels if value]
        if len(labels) != 1 or not self.matches(nodes, labels[0][1] + '/' + labels[0][2]):
            raise Blocked('fullscreen_gallery_counter_not_observed')
        left, top, right, lower = node_bounds(images[0])
        width, height = frame['width'], frame['height']
        if not (0 <= left < right <= width and 0 <= top < lower <= height and
                right - left >= width * .9 and lower - top >= height * .9):
            raise Blocked('fullscreen_gallery_bounds_not_observed')
        return images[0]

    def dismiss_immersive_tutorial(self):
        nodes = self.nodes()
        owned = [node for node in nodes if node.get('package') == 'com.android.systemui' and node_bounds(node)]
        if not any('Viewing full screen' in node_labels(node) for node in owned):
            return False
        buttons = [node for node in owned if 'Got it' in node_labels(node) and
                   node.get('clickable') == 'true' and node.get('enabled') == 'true']
        if len(buttons) != 1:
            raise Blocked('system_immersive_tutorial_button_not_observed')
        self.frame('gallery-system-immersive-tutorial')
        # Re-read after capture; never acknowledge a stale or foreign dialog.
        fresh = [node for node in self.nodes() if node.get('package') == 'com.android.systemui' and node_bounds(node)]
        if (not any('Viewing full screen' in node_labels(node) for node in fresh) or
                not any(node.attrib == buttons[0].attrib for node in fresh)):
            raise Blocked('system_immersive_tutorial_changed')
        left, top, right, lower = node_bounds(buttons[0])
        self.adb('shell', 'input', 'tap', (left + right) // 2, (top + lower) // 2)
        self.report['system_immersive_tutorial_acknowledged'] = True
        time.sleep(.8)
        return True

    def map(self):
        backs = 0
        for _ in range(3):
            if self.has('ماذا تبحث عنه؟'):
                break
            self.back()
            backs += 1
        self.home()
        self.frame('gallery-return-home')
        self.report['return_home_after_details_gallery'] = {'back_keyevents': backs, 'home_witnesses_visible': True}
        self.home_entry('map')
        time.sleep(6)
        if not (self.has('البحث على الخريطة') or self.has('رسم منطقة على الخريطة')):
            raise Blocked('map_screen_not_observed')
        # Clear the known empty-result query through the real map editor.
        nodes = self.nodes()
        fields = [node for node in nodes if node.get('package') == core.PACKAGE and node_bounds(node) and
                  node.get('class') == 'android.widget.EditText' and node.get('enabled') == 'true']
        if len(fields) != 1 or 'phase1-ci-no-match' not in node_labels(fields[0]):
            raise Blocked('inherited_map_query_not_observed')
        left, top, right, lower = node_bounds(fields[0])
        self.adb('shell', 'input', 'tap', (left + right) // 2, (top + lower) // 2)
        self.adb('shell', 'input', 'keyevent', '123', *(['67'] * len('phase1-ci-no-match')), '66')
        time.sleep(6)
        if any('phase1-ci-no-match' in node_labels(node) for node in self.nodes()):
            raise Blocked('map_query_not_cleared')
        self.collapse_map_panel_and_pan()
        return {'map_screen_opened': True, 'basemap_and_markers_need_visual_review': True,
                'query_cleared_through_ui': True, 'camera_pan_sent_at_observed_map_bounds': True}

    def collapse_map_panel_and_pan(self):
        handle_label = 'اسحب لتوسيع الفلاتر والعقارات أو تصغيرها'
        self.frame('map-before-panel-collapse')
        info = self.report['frames'][-1]
        nodes = self.nodes()
        handles, titles = self.matches(nodes, handle_label), self.matches(nodes, 'البحث على الخريطة')
        if ((info['width'], info['height']) != (1080, 1920) or len(handles) != 1 or len(titles) != 1):
            raise Blocked('map_panel_context_not_observed')
        left, top, right, lower = node_bounds(handles[0])
        title_bottom = node_bounds(titles[0])[3]
        if not (0 <= left < right <= 1080 and title_bottom < top < lower <= 1850):
            raise Blocked('map_panel_bounds_not_observed')
        x, y = (left + right) // 2, (top + lower) // 2
        self.adb('shell', 'input', 'swipe', x, y, x, min(1850, y + 650), '250')
        time.sleep(1)
        self.frame('map-before-pan')
        nodes = self.nodes()
        handles, titles = self.matches(nodes, handle_label), self.matches(nodes, 'البحث على الخريطة')
        if len(handles) != 1 or len(titles) != 1:
            raise Blocked('map_pan_context_not_observed')
        left, sheet_top, right, lower = node_bounds(handles[0])
        title_bottom = node_bounds(titles[0])[3]
        if not (0 <= left < right <= 1080 and 1152 <= sheet_top < lower <= 1850 and title_bottom + 160 < sheet_top):
            raise Blocked('map_panel_not_collapsed_for_pan')
        y = (title_bottom + 100 + sheet_top) // 2
        self.adb('shell', 'input', 'swipe', '390', y, '690', y, '500')
        self.report['map_pan_gesture'] = {'from': [390, y], 'to': [690, y],
                                         'bounds_from_fresh_title_and_sheet': True,
                                         'visual_movement_review_required': True}
        time.sleep(4)

    def account_gate(self):
        self.back()
        self.home()
        self.tap('حسابي', bottom=True)
        if not self.has('تسجيل الدخول أو إنشاء حساب'):
            raise Blocked('guest_account_sign_in_gate_not_observed')
        return {'guest_sign_in_gate_visible': True, 'login_attempted': False}

    def creation_gate(self):
        self.tap('إضافة عقار')
        if not (self.has('تعبئة يدوي') and self.has('ذكاء اصطناعي')):
            raise Blocked('creation_method_menu_not_observed')
        self.frame('creation-method-menu')
        self.tap('تعبئة يدوي')
        if not self.has('سجّل الدخول أولاً'):
            raise Blocked('guest_creation_auth_gate_not_observed')
        return {'method_menu_visible': True, 'manual_selected': True,
                'authentication_gate_visible': True, 'listing_created': False}

    def execute(self):
        self.validate_environment()  # No files or Android mutations before identity guards.
        self.out.mkdir()
        self.created = True
        self.save()
        self.live_fixture = False
        for index, (path, expected) in enumerate([('/api/health', 200), ('/api/properties/60', 200),
                               ('/api/listing-editor-drafts', 401),
                               ('/api/admin/workspace/tasks?scope=inbox', 401)], 1):
            started = time.monotonic()
            row = {'id': 'HTTP-' + str(index), 'path': path, 'method': 'GET', 'expected_status': expected}
            try:
                receipt, data = get_public(path)
                row.update(receipt, status='PASS' if receipt['http_status'] == expected else 'FAIL')
                if path == '/api/health' and data.get('database') is not True:
                    row['status'] = 'FAIL'
                if path == '/api/properties/60':
                    fixture = data.get('data', {})
                    self.live_fixture = (receipt['http_status'] == 200 and fixture.get('id') == FIXTURE_ID and
                                         fixture.get('title') == FIXTURE_TITLE and fixture.get('status') == 'published')
                    if not self.live_fixture:
                        row['status'] = 'FAIL'
            except Exception as error:
                row.update(status='BLOCKED', error_type=type(error).__name__,
                           elapsed_ms=round((time.monotonic() - started) * 1000))
            self.report['cases'].append(row)
            self.save()
            if path == '/api/health' and row['status'] != 'PASS':
                # Retain the original failure and the unchanged25s limit. A
                # recovery receipt cannot turn that failed case/CI into PASS.
                followup = {'id': 'HTTP-1-recheck', 'path': path, 'method': 'GET',
                            'expected_status': 200, 'followup_of': 'HTTP-1'}
                try:
                    receipt, data = get_public(path)
                    followup.update(receipt, status='PASS' if receipt['http_status'] == 200 and
                                    data.get('database') is True else 'FAIL')
                except Exception as error:
                    followup.update(status='BLOCKED', error_type=type(error).__name__)
                self.report['cases'].append(followup)
                self.save()
        try:
            self.adb('install', str(self.apk), timeout=180)
            self.installed = True
            self.case('01-startup', 'Dismiss first-run choice and render actual Flutter Home.', self.startup)
            self.recorder = subprocess.Popen(['adb', '-s', self.serial, 'shell', 'screenrecord', '--bit-rate',
                '2500000', '--time-limit', '180', '/sdcard/aqer-phase1-guest.mp4'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.case('02-search', 'Submit a unique query and show the explicit empty-result state.', self.search)
            self.case('02b-filters', 'Apartment/rent selections reveal rooms, baths and rent budget without an All chip.', self.filters)
            self.case('03-details', 'Render the existing public synthetic UAT property 60.', self.details)
            self.case('04-gallery', 'Open fullscreen images and send double tap to observed image bounds.', self.gallery)
            self.case('05-map', 'Open the real map screen; visually inspect the resulting native frame.', self.map)
            self.case('06-account', 'Guest Account displays the sign-in gate.', self.account_gate)
            self.case('07-add-gate', 'Open add menu and preserve the login requirement before editing.', self.creation_gate)
        finally:
            if self.recorder is not None:
                try:
                    self.adb('shell', 'pkill', '-2', 'screenrecord', codes=(0, 1))
                    self.recorder.wait(timeout=15)
                    self.adb('pull', '/sdcard/aqer-phase1-guest.mp4', self.out / 'navigation.mp4', timeout=30)
                except Exception:
                    self.report['video_unavailable'] = True
                    self.recorder.kill()
            cleanup = True
            if self.installed:
                try:
                    self.adb('shell', 'am', 'force-stop', core.PACKAGE)
                    self.adb('uninstall', core.PACKAGE)
                except Exception:
                    cleanup = False
            self.report['cleanup_passed'] = cleanup
            self.report['ended_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            self.save()
        return self.report


def main():
    if not core.enabled(os.environ):
        print('AQER_PHASE1_GUEST_REFUSED_MANUAL_OPT_IN_REQUIRED')
        return 2
    probe = GuestProbe(ROOT, os.environ)
    try:
        report = probe.execute()
    except Exception as error:
        if probe.created:
            probe.report.update(collection_failed=True, error_type=type(error).__name__)
            probe.save()
        print('AQER_PHASE1_GUEST_COLLECTION_FAILED')
        return 1
    finally:
        if probe.created and os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as handle:
                handle.write('phase1_guest_evidence=true\n')
    passed = report.get('cleanup_passed') and all(c['status'] == 'PASS' for c in report['cases'])
    print('AQER_PHASE1_GUEST_' + ('PASS' if passed else 'INCOMPLETE'))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
