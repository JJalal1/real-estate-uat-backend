#!/usr/bin/env python3
"""Actual C1 UI journey, using runtime-only Actions test credentials.

Normal API setup labels a new empty draft; all property facts/photo/recovery use UI.
No stored-session injection, test widgets, TLS/DNS changes or submission.
All artifact export is performed separately, encrypted to the current recipient.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import xml.etree.ElementTree as ET

from phase1_native_account_readiness import preflight, validate_access, SECRET_NAME
from phase1_native_fixture_api import FixtureApi, FixtureError, read_public_reference, digest

ROOT = Path(__file__).resolve().parents[1]
APP = 'com.aqer.yemen.uat'
ACTIVITY = APP + '/com.example.real_estate_mobile.MainActivity'
HELPER = 'com.aqer.phase1.input/.Phase1Input'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
AUTH_LABELS = {'مرحبًا بعودتك', 'رقم واتساب', 'رمز التحقق',
               'رمز التحقق عبر واتساب', 'تأكيد والدخول', 'إرسال رمز واتساب'}
AUTH_PHASES = frozenset({'account_open', 'login_open', 'phone_entry', 'code_request',
                         'otp_entry', 'confirm', 'postcondition'})
AUTH_INPUT_OPS = frozenset({'account-snapshot', 'account-click', 'account-set', 'account-scroll'})
# Literal account-operation stages from the unchanged Phase1Input.java helper.
AUTH_JAVA_STAGES = frozenset({'guard', 'automation', 'root_ready', 'account_click',
                             'account_pointer_tap', 'account_scroll', 'account_pointer_swipe',
                             'account_focus', 'account_focus_pointer', 'account_set', 'complete'})
INPUT_FAILURE_REASONS = frozenset({'native_input_not_delivered', 'ambiguous_native_input_receipt',
                                  'device_command_timeout', 'device_command_failed',
                                  'native_instrumentation_unobserved'})


class Blocked(RuntimeError):
    """Fixed diagnostic identifiers only; never interpolate a command or value."""


def labels(row):
    return {s.strip() for key in ('text', 'description', 'hint')
            for s in str(row.get(key, '')).splitlines() if s.strip()}


def common_depth(a, b):
    count = 0
    for left, right in zip(a.split('.'), b.split('.')):
        if left != right:
            break
        count += 1
    return count


def account_delivery(result, kind):
    """Accept only complete, unambiguous receipts from the pinned input helper."""
    if result.get('account_action_delivered') != 'true':
        raise Blocked('native_action_not_delivered')
    if kind not in {'click', 'scroll', 'set'}:
        raise Blocked('native_action_kind_invalid')
    for flag in ['native_pointer_used', 'semantic_action_used']:
        if flag in result and result[flag] not in {'true', 'false'}:
            raise Blocked('native_delivery_receipt_invalid')
    pointer = result.get('native_pointer_used') == 'true'
    semantic = result.get('semantic_action_used') == 'true'
    if pointer and semantic:
        raise Blocked('native_delivery_receipt_ambiguous')
    if kind == 'set' and result.get('set_text_delivered') != 'true':
        raise Blocked('native_set_text_not_delivered')
    if kind in {'click', 'scroll'} and not (pointer or semantic):
        raise Blocked('native_delivery_mode_missing')
    if pointer:
        expected = 14 if kind == 'scroll' else 2
        if result.get('native_pointer_events') != str(expected):
            raise Blocked('native_pointer_event_count_mismatch')
        return {'delivery': 'pointer_swipe' if kind == 'scroll' else
                            'pointer_focus' if kind == 'set' else 'pointer_tap',
                'native_pointer_events': expected}
    if 'native_pointer_events' in result:
        raise Blocked('unexpected_native_pointer_events')
    return {'delivery': 'semantic_text' if kind == 'set' else 'semantic_action',
            'native_pointer_events': 0}


class NativeAccount:
    def __init__(self, private, env):
        self.env = {key: value for key, value in env.items() if key != SECRET_NAME}
        self.private = private
        self.out = ROOT / 'phase1-native-account-evidence'
        self.out.mkdir(mode=0o700, exist_ok=True)
        validated = validate_access(env.get(SECRET_NAME, ''))
        # This collector exercises only the broker. Optional known actors may
        # exist in the configured secret, but are not retained or logged in.
        self.access = {'otp': validated['otp'], 'phones': {'broker': validated['phones']['broker']}}
        del validated
        # Credentials are needed only by this in-memory driver, never its tools.
        os.environ.pop(SECRET_NAME, None)
        self.private_values = {self.access['otp']}
        for phone in self.access['phones'].values():
            digits = phone.lstrip('+')
            self.private_values.update({phone, digits, '+' + digits})
            # The backend interprets an international 00 prefix; retain that
            # full-number display alias without stripping a guessed country.
            if digits.startswith('00'):
                self.private_values.update({digits[2:], '+' + digits[2:]})
        self.authenticated = False
        self.auth_attempted = False
        self._auth_phase = None
        self.serial = None
        self.recorder = None
        self.record_tainted = False
        self.fixture_possible = False
        self.fixture_api = None
        self.bootstrap_title = None
        self.title = 'اختبار استعادة المسودة ' + env['GITHUB_RUN_ID']
        self.photo_name = 'phase1-account-' + env['GITHUB_RUN_ID'] + '.jpg'
        self.report = {'scope': 'C1 actual Android account draft recovery only',
                       'source_commit': env['GITHUB_SHA'], 'ci_run_id': env['GITHUB_RUN_ID'],
                       'api': API, 'synthetic_widgets': False, 'phase1_accepted': False,
                       'c1_accepted': False, 'manual_review_completed': False,
                       'native_auth_executed': False, 'authentication_captures': False,
                       'native_auth_attempted': False,
                       'api_bootstrap_is_not_native_creation': True,
                       'submission_executed': False, 'financial_acceptance_executed': False,
                       'cases': [], 'actions': [], 'frames': [], 'videos': [],
                       'visual_review_required': True, 'fixture_title': self.title,
                       'limitations': ['C2 support/isolation and C4 AI are not tested here',
                                       'API36 KVM functional evidence, not a physical handset/performance claim']}
        for key in ('C1-native-network', 'C1-api-empty-fixture', 'C1-auth',
                    'C1-photo-save', 'C1-force-stop-restore', 'C1-cleanup'):
            self.report['cases'].append({'id': key, 'status': 'NOT RUN'})
        self.save()

    def command(self, args, timeout=90, codes=(0,), binary=False):
        try:
            result = subprocess.run([str(s) for s in args], capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise Blocked('device_command_timeout') from None
        if result.returncode not in codes:
            raise Blocked('device_command_failed')
        return result.stdout if binary else result.stdout.decode('utf-8', errors='replace').strip()

    def adb(self, *args, **kwargs):
        return self.command(['adb', '-s', self.serial, *args], **kwargs)

    def save(self):
        # Defense in depth: arbitrary framework output never enters this object.
        data = json.dumps(self.report, ensure_ascii=False, indent=2)
        if any(value and value in data for value in self.private_values):
            raise Blocked('private_value_in_receipt_refused')
        (self.out / 'report.json').write_text(data + '\n')

    def mark(self, case, status, **facts):
        row = next(c for c in self.report['cases'] if c['id'] == case)
        row.update(status=status, **facts)
        self.save()

    def auth_phase(self, phase):
        if phase not in AUTH_PHASES:
            raise Blocked('fixed_native_auth_phase_required')
        self._auth_phase = phase
        self.report['native_auth_phase'] = phase
        self.save()

    def auth_input_failure(self, op, result, output, reason):
        if self.authenticated or self._auth_phase not in AUTH_PHASES or op not in AUTH_INPUT_OPS or \
                'native_auth_input_failure' in self.report:
            return
        self.report['native_auth_input_failure'] = {
            'phase': self._auth_phase, 'op': op,
            'java_stage': result.get('stage') if result.get('stage') in AUTH_JAVA_STAGES else None,
            'passed_true': result.get('passed') == 'true',
            'passed_false': result.get('passed') == 'false',
            'code_minus_one': bool(re.search(r'^INSTRUMENTATION_CODE: -1\s*$', output, re.M)),
            'code_zero': bool(re.search(r'^INSTRUMENTATION_CODE: 0\s*$', output, re.M)),
            'reason': reason if reason in INPUT_FAILURE_REASONS else 'native_instrumentation_unobserved',
        }
        self.save()

    def instrument(self, op, **extras):
        output, result = '', {}
        try:
            args = ['shell', 'am', 'instrument', '-w', '-e', 'op', op]
            for key, value in extras.items():
                args.extend(['-e', key, str(value)])
            output = self.adb(*args, HELPER, timeout=45)
            for line in output.splitlines():
                if line.startswith('INSTRUMENTATION_RESULT: '):
                    key, _, value = line.removeprefix('INSTRUMENTATION_RESULT: ').partition('=')
                    if key in result:
                        raise Blocked('ambiguous_native_input_receipt')
                    result[key] = value
            if result.get('passed') != 'true' or result.get('op') != op or not re.search(
                    r'^INSTRUMENTATION_CODE: -1\s*$', output, re.M):
                raise Blocked('native_input_not_delivered')
            return result
        except Exception as error:
            if self.authenticated or self._auth_phase not in AUTH_PHASES:
                raise
            reason = str(error) if isinstance(error, Blocked) and str(error) in INPUT_FAILURE_REASONS \
                else 'native_instrumentation_unobserved'
            self.auth_input_failure(op, result, output, reason)
            raise Blocked(reason) from None

    def nodes(self):
        result = self.instrument('account-snapshot')
        try:
            rows = json.loads(base64.b64decode(result['tree_b64'], validate=True))
        except (ValueError, KeyError, TypeError):
            raise Blocked('fresh_native_tree_unavailable') from None
        if not isinstance(rows, list) or len(rows) > 1200:
            raise Blocked('native_tree_shape_invalid')
        visible = [r for r in rows if r.get('package') == APP and r.get('visible')]
        if self.recorder is not None and any(label in labels(r) for r in visible for label in AUTH_LABELS):
            self.record_tainted = True
            raise Blocked('authentication_transition_during_recording')
        return visible

    def matching(self, rows, label):
        return [r for r in rows if label in labels(r) and r.get('enabled')]

    def has(self, label):
        return bool(self.matching(self.nodes(), label))

    def wait(self, label, seconds=45):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.has(label):
                return
            time.sleep(.6)
        raise Blocked('expected_native_state_not_observed')

    def act(self, kind, row, value=None, direction='forward'):
        extra = {'node_path': row['path'], 'node_witness': row['witness']}
        if kind == 'set':
            extra['value_b64'] = base64.b64encode(value.encode()).decode()
        if kind == 'scroll':
            extra['direction'] = direction
        result = self.instrument('account-' + kind, **extra)
        receipt = account_delivery(result, kind)
        if self.authenticated:
            self.report['actions'].append({'kind': kind, 'witness': row['witness'],
                                           'authenticated': True, **receipt})
        else:
            # Even a UI witness hash can fingerprint a low-entropy phone field.
            # Authentication receipts retain only a count, never node hashes.
            self.report['auth_input_operations_delivered'] = self.report.get('auth_input_operations_delivered', 0) + 1
        self.save()
        time.sleep(.25)

    def scroll(self, direction='forward'):
        rows = [r for r in self.nodes() if r.get('scrollable') and r.get('enabled')]
        if not rows:
            raise Blocked('scrollable_native_container_missing')
        def area(r):
            a, b, c, d = r['bounds']
            return (c - a) * (d - b)
        self.act('scroll', max(rows, key=area), direction=direction)

    def seek(self, label, attempts=12):
        for direction in ('forward', 'backward'):
            for _ in range(attempts):
                rows = self.nodes()
                matched = self.matching(rows, label)
                if matched:
                    return rows, matched
                self.scroll(direction)
        raise Blocked('named_native_control_not_found')

    def tap(self, label, seek=True):
        rows = self.nodes()
        matched = self.matching(rows, label)
        if not matched and seek:
            rows, matched = self.seek(label)
        if not matched:
            raise Blocked('named_native_control_not_found')
        candidates = [r for r in matched if r.get('clickable')]
        if not candidates:
            for item in matched:
                ancestors = [r for r in rows if r.get('clickable') and
                             item['path'].startswith(r['path'] + '.')]
                if ancestors:
                    candidates.append(max(ancestors, key=lambda r: len(r['path'])))
        if not candidates:
            # Original template Buttons can lack accessibility ACTION_CLICK.
            # The helper still revalidates this named node/witness and injects
            # a bounded physical tap; never fall back to an unnamed View.
            candidates = [r for r in matched if r.get('class') == 'android.widget.Button']
            if len(candidates) > 1:
                raise Blocked('ambiguous_native_pointer_target')
        unique = {r['path']: r for r in candidates}
        if not unique:
            raise Blocked('semantic_native_click_unavailable')
        # Smaller actionable semantic bounds distinguish raised Add from an account row.
        row = min(unique.values(), key=lambda r: (r['bounds'][2] - r['bounds'][0]) *
                                                 (r['bounds'][3] - r['bounds'][1]))
        self.act('click', row)

    def field(self, label, seek=True):
        rows = self.nodes()
        matched = self.matching(rows, label)
        if not matched and seek:
            rows, matched = self.seek(label)
        direct = [r for r in matched if r.get('editable')]
        if len(direct) == 1:
            return direct[0]
        if len(matched) != 1:
            raise Blocked('unique_native_field_label_missing')
        # Some Flutter versions expose a separate label immediately above the editor.
        label_row = matched[0]
        a, b, c, d = label_row['bounds']
        near = [r for r in rows if r.get('editable') and r.get('enabled') and
                abs(r['bounds'][1] - b) <= 150 and
                min(c, r['bounds'][2]) > max(a, r['bounds'][0])]
        if len(near) != 1:
            raise Blocked('unique_labelled_native_field_missing')
        return near[0]

    def set(self, label, value):
        self.act('set', self.field(label), value=value)
        self.adb('shell', 'input', 'keyevent', '4')  # dismiss IME only after focused set

    def require_value(self, label, expected):
        if expected not in labels(self.field(label)):
            raise Blocked('restored_native_field_value_mismatch')

    def safe_capture(self, name):
        if not self.authenticated or not re.fullmatch(r'C1-[a-z0-9-]+', name):
            raise Blocked('authentication_capture_refused')
        rows = self.nodes()
        visible = '\n'.join('\n'.join(labels(r)) for r in rows)
        if any(label in labels(r) for r in rows for label in AUTH_LABELS) or any(
                secret and secret in visible for secret in self.private_values):
            raise Blocked('private_native_capture_refused')
        data = self.adb('exec-out', 'screencap', '-p', binary=True)
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise Blocked('native_frame_invalid')
        name += '.png'
        (self.out / name).write_bytes(data)
        self.report['frames'].append({'file': name, 'sha256': hashlib.sha256(data).hexdigest(),
                                       'bytes': len(data), 'authenticated_editor_only': True})
        self.save()

    def record_start(self, name):
        self.safe_capture(name + '-start')
        if self.recorder is not None:
            raise Blocked('recorder_already_active')
        self.video_name = name
        self.record_tainted = False
        self.recorder = subprocess.Popen(['adb', '-s', self.serial, 'shell', 'screenrecord',
            '--bit-rate', '2000000', '--time-limit', '180', '/sdcard/phase1-account.mp4'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def record_stop(self, export=False):
        if self.recorder is None:
            return
        recorder, self.recorder = self.recorder, None
        try:
            self.adb('shell', 'pkill', '-2', 'screenrecord', codes=(0, 1))
            recorder.wait(timeout=15)
            if export:
                if self.record_tainted:
                    raise Blocked('tainted_native_video_discarded')
                self.safe_capture(self.video_name + '-end')
                data = self.adb('exec-out', 'cat', '/sdcard/phase1-account.mp4', binary=True)
                if len(data) < 1024 or data[4:8] != b'ftyp':
                    raise Blocked('native_video_invalid')
                name = self.video_name + '.mp4'
                (self.out / name).write_bytes(data)
                self.report['videos'].append({'file': name, 'bytes': len(data),
                                              'sha256': hashlib.sha256(data).hexdigest(),
                                              'authentication_frames': False})
        finally:
            if recorder.poll() is None:
                recorder.kill()
            self.adb('shell', 'rm', '-f', '/sdcard/phase1-account.mp4', codes=(0, 1))
        self.save()

    def require_preauth_runtime(self):
        # Fresh framework observations only; no app storage, UID, or credentials.
        for key, wanted in [('sys.boot_completed', '1'), ('sys.user.0.ce_available', 'true')]:
            if self.adb('shell', 'getprop', key, timeout=10) != wanted:
                raise Blocked('native_boot_CE_not_ready')
        if self.adb('shell', 'service', 'check', 'package', timeout=10) != 'Service package: found':
            raise Blocked('native_package_service_not_ready')
        pids = self.adb('shell', 'pidof', 'system_server', timeout=10).split()
        if not pids or len(pids) > 16 or len(set(pids)) != len(pids) or any(
                not re.fullmatch(r'[1-9][0-9]*', pid) for pid in pids):
            raise Blocked('native_system_server_not_ready')

    def require_fresh_package_absent(self, package):
        if package not in {APP, 'com.aqer.phase1.input'}:
            raise Blocked('fixed_native_package_required')
        try:
            result = subprocess.run(['adb', '-s', self.serial, 'shell', 'pm', 'path', package],
                                    capture_output=True, timeout=20)
        except (subprocess.TimeoutExpired, OSError):
            raise Blocked('fresh_package_state_unobserved') from None
        # ABSENT is an exact successful observation of pm's missing-package result.
        # Error output, an empty success, and transport failures are UNOBSERVED.
        if result.returncode == 1 and result.stdout == b'' and result.stderr == b'':
            self.require_preauth_runtime()
            return
        if result.returncode == 0 and result.stdout.startswith(b'package:') and result.stderr == b'':
            raise Blocked('fresh_native_install_required')
        raise Blocked('fresh_package_state_unobserved')

    def validate_and_install(self):
        proof = json.loads((self.private / 'APK_VERIFICATION.json').read_text())
        if proof['source_commit'] != self.env['GITHUB_SHA'] or proof['package'] != APP:
            raise Blocked('verified_apk_source_mismatch')
        apk, helper = self.private / 'target.apk', self.private / 'input.apk'
        if hashlib.sha256(apk.read_bytes()).hexdigest() != proof['sha256'] or \
                hashlib.sha256(helper.read_bytes()).hexdigest() != proof['input_driver']['sha256']:
            raise Blocked('verified_apk_bytes_mismatch')
        output = self.command(['adb', 'devices'])
        devices = re.findall(r'^(emulator-[0-9]+)\s+device\s*$', output, re.M)
        if len(devices) != 1:
            raise Blocked('one_fresh_emulator_required')
        self.serial = devices[0]
        for key, wanted in [('ro.boot.qemu', '1'), ('ro.build.version.sdk', '36')]:
            if self.adb('shell', 'getprop', key) != wanted:
                raise Blocked('disposable_booted_api36_required')
        if 'KVM' not in self.command([Path(self.env['ANDROID_HOME']) / 'emulator/emulator', '-accel-check']):
            raise Blocked('kvm_required')
        if self.adb('reverse', '--list') or API.split('/')[2] in self.adb('shell', 'cat', '/etc/hosts'):
            raise Blocked('unaltered_uat_network_required')
        self.require_preauth_runtime()
        for package in (APP, 'com.aqer.phase1.input'):
            self.require_fresh_package_absent(package)
        self.require_preauth_runtime()
        self.adb('install', '--no-streaming', apk, timeout=180)
        self.require_preauth_runtime()
        self.adb('install', '--no-streaming', '-t', helper, timeout=90)
        self.report.update(version_code=proof['version_code'], apk_sha256=proof['sha256'],
                           android_api=36, acceleration='KVM', network_modified=False)
        self.save()

    def startup(self):
        self.adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                rows = self.nodes()
            except Blocked:
                # A fresh install may show the OS notification prompt. Deny only
                # that observed permissioncontroller control; never grant access.
                target = '/sdcard/phase1-startup-permission.xml'
                self.adb('shell', 'uiautomator', 'dump', target, timeout=20)
                raw = self.adb('exec-out', 'cat', target)
                self.adb('shell', 'rm', '-f', target)
                try:
                    os_rows = list(ET.fromstring(raw).iter('node'))
                except ET.ParseError:
                    raise Blocked('native_startup_not_ready') from None
                deny = [n for n in os_rows if n.get('package') in
                        {'com.google.android.permissioncontroller', 'com.android.permissioncontroller'}
                        and n.get('resource-id', '').endswith(':id/permission_deny_button')]
                if len(deny) != 1:
                    raise Blocked('native_startup_window_unexpected')
                match = re.fullmatch(r'\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]', deny[0].get('bounds', ''))
                if not match:
                    raise Blocked('native_permission_bounds_invalid')
                a, b, c, d = map(int, match.groups())
                self.adb('shell', 'input', 'tap', (a+c)//2, (b+d)//2)
                continue
            if self.matching(rows, 'المتابعة الآن'):
                self.tap('المتابعة الآن', seek=False)
            elif self.matching(rows, 'حسابي'):
                return
            time.sleep(.5)
        raise Blocked('native_startup_not_ready')

    def login(self):
        try:
            self.auth_phase('account_open')
            self.tap('حسابي')
            self.auth_phase('login_open')
            self.tap('تسجيل الدخول أو إنشاء حساب')
            self.wait('مرحبًا بعودتك')
            self.auth_phase('phone_entry')
            self.set('رقم واتساب', self.access['phones']['broker'])
            self.auth_phase('code_request')
            self.tap('إرسال رمز واتساب')
            self.wait('تأكيد والدخول', seconds=60)
            self.auth_phase('otp_entry')
            self.set('رمز التحقق', self.access['otp'])
            self.auth_phase('confirm')
            self.auth_attempted = True
            self.report['native_auth_attempted'] = True
            self.tap('تأكيد والدخول')
            self.auth_phase('postcondition')
            evidence = self.authenticated_account_evidence()
            self.authenticated = True
            self.report['native_auth_executed'] = True
            self.mark('C1-auth', 'PASS', normal_whatsapp_ui=True, secret_capture=False, **evidence)
        finally:
            self._auth_phase = None

    def authenticated_account_evidence(self, seconds=90):
        bootstrap = self.report.get('api_bootstrap') or {}
        identity = bootstrap.get('identity') or {}
        api_pinned = (bootstrap.get('status') == 'PASS' and bootstrap.get('fresh_session_cleaned') is True
                      and identity.get('actor_id') == 28 and identity.get('account_type') == 'broker')
        deadline = time.monotonic() + seconds
        profile_opened = False
        while time.monotonic() < deadline:
            rows = self.nodes()
            if any(label in labels(r) for r in rows for label in AUTH_LABELS):
                time.sleep(.7)
                continue
            if self.matching(rows, 'عملي') and self.matching(rows, 'العملاء'):
                return {'native_auth_witness': 'broker_footer', 'broker_role_ui_witness': True,
                        'broker_role_api_pinned': api_pinned}
            profile_role = bool(self.matching(rows, 'نوع الحساب: دلال'))
            professional_controls = any(self.matching(rows, label) for label in ['إدارة العملاء', 'عقاراتي'])
            if self.matching(rows, 'تسجيل الخروج') and (profile_role or api_pinned):
                return {'native_auth_witness': 'authenticated_profile_logout_control',
                        'broker_role_ui_witness': profile_role, 'broker_role_api_pinned': api_pinned,
                        'professional_controls_visible': professional_controls}
            if self.matching(rows, 'حسابي') and not profile_opened:
                self.tap('حسابي')
                profile_opened = True
            elif profile_opened:
                try:
                    self.seek('تسجيل الخروج', attempts=2)
                except Blocked:
                    pass
            time.sleep(.7)
        raise Blocked('native_broker_auth_not_observed')

    def public_network_readiness(self):
        # Fresh install, default networking, and a real published UAT card are
        # prerequisites only; previous guest-search acceptance is not repeated.
        references = read_public_reference()
        deadline = time.monotonic() + 60
        scrolls = 0
        while time.monotonic() < deadline:
            rows = self.nodes()
            matches = [reference for reference in references if self.matching(rows, reference['title'])]
            if matches:
                self.mark('C1-native-network', 'PASS', real_published_card_observed=True,
                          public_reference_count=len(references), public_reference_sha256=digest(references),
                          visible_match_count=len(matches), visible_match_sha256=digest(matches),
                          default_network=True, host_reference_is_not_native_network_trace=True,
                          acceptance_scope='prerequisite only')
                return
            if scrolls < 4:
                try:
                    self.scroll()
                    scrolls += 1
                except Blocked:
                    pass
            time.sleep(1)
        raise Blocked('native_public_uat_response_not_observed')

    def bootstrap_fixture(self):
        self.require_preauth_runtime()
        self.fixture_api = FixtureApi(self.access['phones']['broker'], self.access['otp'],
                                      self.env['GITHUB_RUN_ID'])
        try:
            self.fixture_api.bootstrap()
        finally:
            if self.fixture_api.state:
                state = self.fixture_api.state
                self.fixture_possible = bool(state.get('creation_request_sent'))
                self.report['fixture_key'] = state.get('key')
                self.report['fixture_tag'] = state.get('tag')
            self.report['api_bootstrap'] = self.fixture_api.last_receipt
            self.save()
        state = self.fixture_api.state
        self.bootstrap_title = state['title']
        self.title = 'اختبار استعادة المسودة ' + state['tag']
        self.report['fixture_title'] = self.title
        self.mark('C1-api-empty-fixture', 'PASS', native_creation_claim=False,
                  bootstrap_fields=['synthetic_title_label_only'],
                  property_created=False, photos_uploaded=False,
                  facts_entered=False, api_session_logged_out=True)

    def manual_entry(self, expected_title):
        if not self.fixture_api or not self.fixture_api.state or not expected_title or \
                self.fixture_api.state['tag'] not in expected_title:
            raise Blocked('known_new_fixture_required_before_native_entry')
        self.tap('إضافة عقار')
        if self.has('تعبئة يدوي'):
            self.tap('تعبئة يدوي')
        elif self.has('تعبئة يدوية'):
            self.tap('تعبئة يدوية')
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            rows = self.nodes()
            if self.matching(rows, 'لديك إعلان غير مكتمل'):
                # The default recovery candidate may be an old protected draft.
                # Never continue it or start a new draft that retires it.
                self.tap('مسوداتي')
                self.wait('مسوداتي')
                rows, matches = self.seek(expected_title)
                if len(matches) != 1:
                    raise Blocked('unique_owned_saved_fixture_not_observed')
                self.tap(expected_title)
                return
            time.sleep(.5)
        raise Blocked('native_owned_saved_fixture_not_observed')

    def photo_picker(self):
        from PIL import Image, ImageDraw
        path = self.private / self.photo_name
        picture = Image.new('RGB', (800, 600), (32, 111, 113))
        draw = ImageDraw.Draw(picture)
        draw.rectangle((100, 90, 700, 510), outline=(255, 255, 255), width=12)
        draw.text((180, 290), 'PHASE1 SYNTHETIC RECOVERY FIXTURE', fill=(255, 255, 255))
        picture.save(path, 'JPEG', quality=85)
        self.adb('push', path, '/sdcard/Download/' + self.photo_name)
        self.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                 '-d', 'file:///sdcard/Download/' + self.photo_name)
        self.tap('إضافة صور')
        # The OS picker is outside our self-targeted helper. Use fresh, observed nodes.
        deadline = time.monotonic() + 45
        selected = False
        while time.monotonic() < deadline:
            target = '/sdcard/phase1-os-picker.xml'
            self.adb('shell', 'uiautomator', 'dump', target, timeout=20)
            raw = self.adb('exec-out', 'cat', target)
            try:
                rows = list(ET.fromstring(raw).iter('node'))
            except ET.ParseError:
                raise Blocked('fresh_os_picker_tree_unavailable') from None
            self.adb('shell', 'rm', '-f', target)
            candidates = [n for n in rows if n.get('package') in
                          {'com.google.android.documentsui', 'com.android.documentsui',
                           'com.google.android.providers.media.module', 'com.android.providers.media.module'}]
            def tap_os(node):
                found = re.fullmatch(r'\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]', node.get('bounds', ''))
                if not found:
                    raise Blocked('os_picker_bounds_invalid')
                a, b, c, d = map(int, found.groups())
                self.adb('shell', 'input', 'tap', (a+c)//2, (b+d)//2)
            files = [n for n in candidates if self.photo_name in
                     {n.get('text', ''), n.get('content-desc', '')}]
            if len(files) == 1 and not selected:
                tap_os(files[0]); selected = True; time.sleep(.6)
                # Multiple mode may require a visible final Open/Select action.
                continue
            done = [n for n in candidates if selected and n.get('text', '') in
                    {'OPEN', 'Open', 'SELECT', 'Select', 'فتح', 'اختيار'} and n.get('enabled') == 'true']
            if len(done) == 1:
                tap_os(done[0]); time.sleep(.6)
                break
            if selected and not candidates:
                break
            downloads = [n for n in candidates if n.get('text', '') in {'Downloads', 'التنزيلات'}]
            if len(downloads) == 1 and not selected:
                tap_os(downloads[0])
            else:
                menus = [n for n in candidates if n.get('content-desc', '') in
                         {'Show roots', 'Open navigation drawer', 'عرض الجذور', 'فتح قائمة التنقل'}]
                if len(menus) == 1 and not selected:
                    tap_os(menus[0])
            time.sleep(.7)
        if not selected:
            raise Blocked('genuine_os_photo_selection_not_observed')
        self.wait('صور الإعلان (1/12)', seconds=30)

    def create_and_save(self):
        self.manual_entry(self.bootstrap_title)
        self.tap('للإيجار')
        self.tap('شقة')
        self.set('عنوان الإعلان *', self.title)
        self.record_start('C1-create-photo')
        self.tap('التالي')
        self.tap('تأكيد الموقع على الخريطة')
        self.wait('تأكيد هذا الموقع', seconds=60)
        self.tap('تأكيد هذا الموقع')
        self.wait('تم تحديد موقع العقار على الخريطة', seconds=45)
        self.set('المحافظة *', 'صنعاء')
        self.set('المدينة', 'صنعاء')
        self.tap('التالي')
        self.tap('الشقة في الدور *')
        self.tap('الثاني')
        self.set('غرف النوم *', '3')
        self.set('الحمامات *', '2')
        self.tap('موقف سيارة *')
        self.tap('لا يوجد')
        self.tap('واجهة البناء *')
        self.tap('شمالية')
        self.photo_picker()
        self.safe_capture('C1-photo-selected')
        self.record_stop(export=True)  # Never record step4's contact fields.
        self.tap('التالي')
        self.wait('خيارات المسودة')
        if any(v.isdigit() and int(v) > 0 for v in labels(self.field('الإيجار الشهري بالريال اليمني *'))):
            raise Blocked('incomplete_draft_guard_not_observed')
        self.tap('خيارات المسودة')
        self.tap('حفظ مسودة')
        self.wait('حُفظت المسودة على حسابك. يمكنك إكمالها لاحقًا.', seconds=120)
        self.mark('C1-photo-save', 'PASS', explicit_save=True, image_count=1,
                  normal_os_picker=True, monthly_rent_deliberately_unfilled=True,
                  property_created=False, submitted=False)

    def restore(self):
        self.adb('shell', 'am', 'force-stop', APP)
        time.sleep(1)
        self.authenticated = False
        self.startup()
        # Normal saved session restoration; never inject or read its storage.
        self.authenticated_account_evidence(seconds=45)
        self.authenticated = True
        self.manual_entry(self.title)
        self.wait('خيارات المسودة')
        self.tap('السابق')
        self.wait('المواصفات')
        self.record_start('C1-restored-facts')
        self.require_value('غرف النوم *', '3')
        self.require_value('الحمامات *', '2')
        self.seek('الثاني')
        self.seek('لا يوجد')
        self.seek('شمالية')
        self.seek('صور الإعلان (1/12)')
        self.wait('مكتمل', seconds=90)
        self.safe_capture('C1-restored-complete-photo')
        self.tap('السابق')
        self.wait('تم تحديد موقع العقار على الخريطة')
        self.require_value('المحافظة *', 'صنعاء')
        self.tap('السابق')
        self.require_value('عنوان الإعلان *', self.title)
        self.safe_capture('C1-restored-title')
        self.record_stop(export=True)
        if len(self.report['videos']) != 2:
            raise Blocked('native_recovery_video_missing')
        self.mark('C1-force-stop-restore', 'PASS', force_stop_without_reset=True,
                  same_unique_title=True, location_restored=True, bedroom_count=3,
                  bathroom_count=2, floor='2', photo_count=1, photo_state='complete')

    def native_logout(self):
        self.record_stop()
        # A known retained session avoids a Back dialog that might save/retire
        # an unrelated recovery candidate. Do not reset or read app storage.
        self.adb('shell', 'am', 'force-stop', APP)
        self.authenticated = False
        self.startup()
        self.tap('حسابي')
        self.tap('تسجيل الخروج')
        self.authenticated = False
        self.wait('تسجيل الدخول أو إنشاء حساب', seconds=45)
        self.report['session_logged_out'] = True

    def cleanup(self):
        errors = []
        try:
            self.record_stop()
            if self.auth_attempted:
                try:
                    self.native_logout()
                except Blocked as error:
                    errors.append(str(error))
                except Exception:
                    errors.append('native_logout_not_confirmed')
        finally:
            # Halt any delayed native writer before deleting the only new UUID.
            if self.serial:
                try:
                    self.adb('shell', 'am', 'force-stop', APP)
                except Exception:
                    errors.append('native_writer_stop_not_confirmed')
            if self.fixture_api and self.fixture_api.state:
                try:
                    self.fixture_api.cleanup()
                except FixtureError as error:
                    errors.append(str(error))
                except Exception:
                    errors.append('api_fixture_cleanup_not_confirmed')
                finally:
                    self.report['api_cleanup'] = self.fixture_api.last_receipt
                    self.fixture_possible = self.fixture_api.has_pending_fixture
                    self.save()
        if errors:
            self.report['cleanup_reasons'] = errors
            raise Blocked('native_or_api_cleanup_incomplete')
        bootstrap = self.report.get('api_bootstrap') or {}
        cleaned = self.report.get('api_cleanup') or {}
        protected = cleaned.get('protected_after') or {}
        self.mark('C1-cleanup', 'PASS', only_known_new_uuid_cleaned=cleaned.get('fixture_removed', False),
                  protected_preexisting_rows_unchanged=bool(protected) and all(
                      row.get('all_preexisting_unchanged') and row.get('all_preexisting_present')
                      for row in protected.values()),
                  native_logout_confirmed=self.report.get('session_logged_out', False),
                  bootstrap_api_session_revoked=bootstrap.get('fresh_session_cleaned', False),
                  cleanup_api_session_revoked=cleaned.get('fresh_session_cleaned', False))

    def execute(self):
        stage = 'C1-native-network'
        try:
            self.validate_and_install()
            self.startup()
            self.public_network_readiness()
            stage = 'C1-api-empty-fixture'
            self.bootstrap_fixture()
            stage = 'C1-auth'
            self.login()
            stage = 'C1-photo-save'
            self.create_and_save()
            stage = 'C1-force-stop-restore'
            self.restore()
        except Blocked as error:
            self.mark(stage, 'BLOCKED', reason=str(error))
        except FixtureError as error:
            self.mark(stage, 'BLOCKED', reason=str(error))
        except Exception as error:
            self.mark(stage, 'FAIL', error_type=type(error).__name__)
        finally:
            try:
                self.record_stop()
            except Exception:
                self.report['video_finalization_failed'] = True
            if self.fixture_api or self.authenticated or self.auth_attempted:
                try:
                    self.cleanup()
                except Blocked as error:
                    self.mark('C1-cleanup', 'BLOCKED', reason=str(error))
                except Exception as error:
                    self.mark('C1-cleanup', 'FAIL', error_type=type(error).__name__)
            self.report['fixture_may_remain'] = self.fixture_possible
            native_session_pending = self.auth_attempted and not self.report.get('session_logged_out', False)
            api_session_pending = False
            for receipt in [self.report.get('api_bootstrap'), self.report.get('api_cleanup')]:
                if not isinstance(receipt, dict):
                    continue
                verify = receipt.get('normal_login_verify')
                possible_issue = (isinstance(verify, dict) and verify.get('http') == 200) or (
                    verify is None and receipt.get('normal_login_start', {}).get('http') == 200)
                api_session_pending = api_session_pending or receipt.get('session_cleanup_unproven', False) or (
                    possible_issue and receipt.get('fresh_session_cleaned') is not True)
            self.report['native_session_may_remain'] = native_session_pending
            self.report['api_session_may_remain'] = api_session_pending
            self.report['session_may_remain'] = native_session_pending or api_session_pending
            self.report['ended_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            try:
                self.save()
            finally:
                self.access.clear()
                if self.fixture_api:
                    self.fixture_api.clear_credentials()
        return all(row['status'] == 'PASS' for row in self.report['cases'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--private-dir', required=True)
    args = parser.parse_args()
    try:
        if preflight(os.environ)['status'] == 'BLOCKED':
            raise Blocked('secure_test_access_missing_or_invalid')
        private = (ROOT / args.private_dir).resolve()
        if ROOT not in private.parents:
            raise Blocked('runner_private_directory_required')
        probe = NativeAccount(private, os.environ)
        previous_handlers = {}
        def interrupted(signum, frame):
            raise Blocked('native_run_interrupted')
        for signum in (signal.SIGTERM, signal.SIGINT):
            previous_handlers[signum] = signal.signal(signum, interrupted)
        try:
            passed = probe.execute()
        finally:
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)
        print('AQER_PHASE1_NATIVE_ACCOUNT_C1_' + ('COLLECTED' if passed else 'INCOMPLETE'))
        return 0 if passed else 2
    except Exception:
        # Do not print exception text, environment, command arguments or traceback.
        print('AQER_PHASE1_NATIVE_ACCOUNT_REFUSED_OR_INCOMPLETE')
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
