#!/usr/bin/env python3
"""Reviewed, bounded native UI commands with source-bound encrypted checkpoints.

Commands come only from the execution branch, bind the current run/challenge,
and never contain credentials. Existing Android input and normal OTP are reused.
This collector produces observations; product acceptance is reviewed separately.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
import zipfile

from phase23_preflight import API, BRANCH, GateError, guard, http
from phase1_native_account_readiness import SECRET_NAME, validate_access
from prepare_phase23_native import PRIVATE, CERT, tool_digest
from probe_phase1_native_account import NativeAccount, Blocked, APP, labels

CONTROL = 'docs/phase23-control.json'
REPO = 'JJalal1/real-estate-uat-backend'
AUTH_FIELDS = {'رقم واتساب', 'رمز التحقق', 'كلمة المرور', 'البريد الإلكتروني'}
OPS = {'observe', 'tap', 'set', 'scroll', 'back', 'login', 'logout', 'api_get',
       'record_start', 'record_stop', 'key', 'force_stop', 'touch', 'swipe', 'pinch',
       'double_tap', 'draw_area', 'wait', 'network', 'display', 'open_link', 'batch', 'seed_media', 'finish'}


class Phase23Account(NativeAccount):
    DRAWING_INSTRUCTION = 'ارسم بإصبعك حدود المنطقة المطلوبة مثل القلم. عند رفع إصبعك سيتم عرض العقارات داخل الرسم فقط.'

    def draw_area(self):
        rows=self.nodes()
        if any(field in labels(row) for row in rows for field in AUTH_FIELDS):
            raise Blocked('authentication_gesture_refused')
        visible=[r for r in rows if r.get('package')==APP and r.get('visible')]
        roots=[r for r in visible if r.get('path')=='0' and r.get('bounds')==[0,0,1080,1920]]
        names=set().union(*(labels(r) for r in visible)) if visible else set()
        cancel=[r for r in visible if 'إلغاء' in labels(r)]
        if len(roots)!=1 or len(cancel)!=1 or cancel[0]['bounds'][1]<1500 or not {
                'البحث على الخريطة',self.DRAWING_INSTRUCTION,
                'Showing a Map created with MapLibre. Scroll by dragging two fingers. Zoom by pinching two fingers.'}<=names:
            raise Blocked('fresh_default_drawing_surface_required')
        # Fixed closed stroke, within the observed canvas and outside its controls.
        return self.instrument('phase23-draw-area',phase23_surface='drawing')

    """Keep the historical Phase1 executor unchanged; handle current role shells."""

    def startup_home_binding(self, rows):
        binding = super().startup_home_binding(rows)
        if binding is not None:
            return binding
        if any(field in labels(row) for row in rows for field in AUTH_FIELDS):
            return None
        for anchors in (('لوحة الدعم', 'الوارد', 'مهامي', 'الرسائل', 'حسابي'),
                        ('لوحة الفريق', 'الأعمال', 'الفريق', 'الرسائل', 'حسابي'),
                        ('ماذا تبحث عنه؟', 'ابحث عن عقار أو منطقة…', 'العقارات', 'الخريطة', 'الرسائل', 'حسابي')):
            binding = self.startup_public_binding(rows, anchors)
            if binding is not None:
                return binding
        return None

    def dismiss_keyboard_if_shown(self):
        state = self.adb('shell', 'dumpsys', 'input_method')
        if re.search(r'\b(?:mInputShown|isInputViewShown)=true\b', state):
            self.adb('shell', 'input', 'keyevent', '4')
            return True
        return False

    def set(self, label, value):
        self.act('set', self.field(label), value=value)
        self.dismiss_keyboard_if_shown()

    def gesture(self, operation, x, y):
        rows = self.nodes()
        if any(field in labels(row) for row in rows for field in AUTH_FIELDS):
            raise Blocked('authentication_gesture_refused')
        visible = [r for r in rows if r.get('package') == APP and r.get('visible')]
        names = set().union(*(labels(r) for r in visible)) if visible else set()
        galleries = {tuple(map(int, m.groups())) for name in names
                     if (m := re.fullmatch(r'صورة العقار ([0-9]+) من ([0-9]+)', name))}
        context = {}
        if len(galleries) == 1 and 'إغلاق الصور' in names:
            index, count = next(iter(galleries))
            if not (1 <= index <= count <= 12 and f'{index}/{count}' in names):
                raise Blocked('fresh_gallery_counter_required')
            surfaces = [r for r in visible if f'صورة العقار {index} من {count}' in labels(r)]
            context = {'phase23_surface':'gallery', 'gallery_index':index, 'gallery_count':count}
        elif ('البحث على الخريطة' in names and
              'Showing a Map created with MapLibre. Scroll by dragging two fingers. Zoom by pinching two fingers.' in names):
            surfaces = [r for r in visible if 'Showing a Map created with MapLibre. Scroll by dragging two fingers. Zoom by pinching two fingers.' in labels(r)]
            context = {'phase23_surface':'map'}
        else:
            raise Blocked('fresh_gallery_or_map_context_required')
        if len(surfaces) != 1:
            raise Blocked('unique_gesture_surface_required')
        a,b,c,d = surfaces[0]['bounds']
        if context['phase23_surface'] == 'map':
            panels = [r['bounds'][1] for r in visible if any(
                name.startswith('اسحب لتوسيع الفلاتر والعقارات أو تصغيرها') for name in labels(r))]
            if len(panels) != 1:
                raise Blocked('fresh_map_panel_boundary_required')
            d = min(d,panels[0])
        margin = 270 if operation.startswith('pinch-') else 1
        if not (300 <= x <= 780 and 400 <= y <= 1520 and a <= x-margin and x+margin < c and b < y < d):
            raise Blocked('gesture_outside_observed_surface')
        return self.instrument(operation, x=x, y=y, **context)

    def wait_guest_boundary(self, seconds=60):
        deadline = time.monotonic()+seconds
        while time.monotonic() < deadline:
            rows=self.nodes()
            footer=all(self.matching(rows, name) for name in ('العقارات','الرسائل','إعلاناتي','حسابي'))
            excluded=self.matching(rows,'تسجيل الخروج') or any(
                name in labels(row) for row in rows for name in AUTH_FIELDS)
            if footer and not excluded:
                if self.matching(rows,'تسجيل الدخول أو إنشاء حساب'):
                    return
                if all(self.matching(rows,name) for name in ('ماذا تبحث عنه؟','ابحث عن عقار أو منطقة…')):
                    self.tap('حسابي')
                    self.wait_guest_account(seconds=max(1,deadline-time.monotonic()))
                    return
            time.sleep(.5)
        raise Blocked('native_guest_boundary_not_observed')

    def scroll(self, direction='forward', *, short=False):
        if direction not in {'forward', 'backward'}:
            raise Blocked('native_scroll_refused')
        rows = self.nodes()
        if any(field in labels(row) for row in rows for field in AUTH_FIELDS):
            raise Blocked('authentication_scroll_refused')
        roots = [r for r in rows if r.get('path') == '0' and r.get('package') == APP]
        if len(roots) != 1:
            raise Blocked('fresh_native_viewport_required')
        left, top, right, bottom = roots[0]['bounds']
        left, top, right, bottom = max(0,left), max(0,top), min(1080,right), min(1920,bottom)
        footer = [r['bounds'][1] for r in rows if 'حسابي' in labels(r)
                  and r['bounds'][1] >= 1400]
        if footer:
            bottom = min(bottom, min(footer))
        candidates = []
        for row in rows:
            if row.get('scrollable') and row.get('enabled'):
                a,b,c,d = row['bounds']
                a,b,c,d = max(a,left),max(b,top),min(c,right),min(d,bottom)
                if c-a > 80 and d-b > 160:
                    candidates.append(((c-a)*(d-b), row, (a,b,c,d)))
        if not candidates:
            raise Blocked('scrollable_native_container_missing')
        _, row, (a,b,c,d) = max(candidates, key=lambda item:item[0])
        # Re-read the selected semantic witness before the bounded physical input.
        fresh = [r for r in self.nodes() if r.get('path') == row['path']
                 and r.get('witness') == row['witness'] and r.get('bounds') == row['bounds']]
        if len(fresh) != 1:
            raise Blocked('native_scroll_witness_changed')
        margin = min(100, (d-b)//4)
        start,end = d-margin,b+margin
        if short:
            center=(b+d)//2; half=(d-b-2*margin)//6
            start,end=center+half,center-half
        if direction == 'backward':
            start,end=end,start
        self.adb('shell','input','swipe',(a+c)//2,start,(a+c)//2,end,500)
        time.sleep(.3)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def validate_command(value, run_id, seq, challenge):
    if not isinstance(value, dict) or set(value) != {'run_id', 'seq', 'challenge', 'op', 'args'}:
        raise GateError('command_shape_invalid')
    if value['run_id'] != run_id or value['seq'] != seq or value['challenge'] != challenge:
        raise GateError('stale_or_foreign_command')
    if value['op'] not in OPS or not isinstance(value['args'], dict):
        raise GateError('command_operation_invalid')
    args = value['args']
    if any(re.search(r'phone|otp|token|password|secret|credential', str(k), re.I) for k in args):
        raise GateError('credential_command_refused')
    allowed = {'observe': set(), 'tap': {'label'}, 'set': {'label', 'value'},
               'scroll': {'direction'}, 'back': set(), 'login': {'alias'}, 'logout': set(),
               'api_get': {'alias', 'path'}, 'record_start': set(), 'record_stop': set(),
               'key': {'key'}, 'force_stop': set(), 'touch': {'x', 'y'},
               'swipe': {'x1', 'y1', 'x2', 'y2'}, 'pinch': {'direction', 'x', 'y'},
               'double_tap': {'x','y'}, 'wait': {'label','seconds'}, 'network': {'state'},
               'display': {'mode'}, 'open_link': {'uri'}, 'draw_area': set(),
               'batch': {'steps'}, 'seed_media': set(), 'finish': set()}
    if set(args) != allowed[value['op']]:
        raise GateError('command_arguments_invalid')
    if value['op'] == 'set' and args['label'] in AUTH_FIELDS:
        raise GateError('credential_field_refused')
    if value['op'] in {'tap', 'set'} and (not isinstance(args['label'], str) or not 0 < len(args['label']) <= 200):
        raise GateError('bounded_semantic_label_required')
    if value['op'] == 'set' and (not isinstance(args['value'], str) or len(args['value']) > 3000):
        raise GateError('bounded_form_value_required')
    if value['op'] == 'batch':
        steps = args['steps']
        if not isinstance(steps, list) or not 1 <= len(steps) <= 6:
            raise GateError('bounded_semantic_batch_required')
        for step in steps:
            if not isinstance(step, dict) or set(step) != {'op', 'args'} or step['op'] not in {
                    'tap','set','scroll','api_get','wait','touch','swipe','pinch','double_tap'}:
                raise GateError('semantic_batch_operation_refused')
            validate_command(dict(value, op=step['op'], args=step['args']), run_id, seq, challenge)
    if value['op'] == 'key' and args['key'] not in {'BACK', 'ENTER'}:
        raise GateError('native_key_refused')
    if value['op'] == 'scroll' and args['direction'] not in {'forward', 'backward'}:
        raise GateError('native_scroll_refused')
    if value['op'] == 'wait' and (not isinstance(args['label'],str) or not 0<len(args['label'])<=200
                                 or type(args['seconds']) is not int or not 1<=args['seconds']<=30):
        raise GateError('bounded_native_wait_required')
    if value['op'] == 'network' and args['state'] not in {'offline','online'}:
        raise GateError('fixed_native_network_state_required')
    if value['op'] == 'display' and args['mode'] not in {'default','compact_large','large'}:
        raise GateError('fixed_native_display_mode_required')
    if value['op'] == 'open_link' and args['uri'] != 'realestate://app/properties/106':
        raise GateError('approved_public_fixture_link_required')
    if value['op'] in {'touch', 'swipe', 'pinch', 'double_tap'}:
        for k, v in args.items():
            if k == 'direction':
                if v not in {'in', 'out'}: raise GateError('native_pinch_refused')
            elif type(v) is not int or not 0 <= v < (1080 if k.startswith('x') else 1920):
                raise GateError('bounded_native_coordinate_required')
    return value


class Session:
    def __init__(self, alias, access):
        self.alias, self.token = alias, None
        self.phone, self.otp = access['phones'][alias], access['otp']
        self.identity = None

    def login(self):
        code, _ = http('POST', '/auth/whatsapp/start', {'phone': self.phone, 'intent': 'login'})
        if code != 200: raise GateError('normal_api_start_failed')
        code, body = http('POST', '/auth/whatsapp/verify', {'phone': self.phone, 'code': self.otp})
        self.token = body.get('data', {}).get('token')
        if code != 200 or not isinstance(self.token, str): raise GateError('normal_api_verify_failed')
        code, body = http('GET', '/auth/me', token=self.token)
        user = body.get('data', {}).get('user', {})
        expected = {'broker': 28, 'support': 6, 'regular': 26}
        if code != 200 or user.get('id') != expected.get(self.alias):
            raise GateError('configured_actor_identity_mismatch')
        self.identity = {'id': user['id'], 'roles': user.get('roles', []), 'account_type': user.get('account_type')}

    def close(self):
        if not self.token: return True
        token, self.token = self.token, None
        try:
            code, _ = http('POST', '/auth/logout', {}, token=token)
            revoked, _ = http('GET', '/auth/me', token=token)
            return code == 200 and revoked == 401
        finally:
            self.phone = self.otp = None


class NativeRun:
    def __init__(self, root):
        guard(os.environ)
        if tool_digest() != os.environ['AQER_BRIDGE_TOOLBUNDLE_SHA']:
            raise GateError('native_toolbundle_mismatch')
        self.root, self.seq, self.previous = root, 0, '0' * 64
        self.deadline = time.monotonic() + 6500
        self.access = validate_access(os.environ.get(SECRET_NAME, ''))
        self.private_values = set(self.access['phones'].values()) | {self.access['otp']}
        for phone in self.access['phones'].values():
            digits = phone.lstrip('+')
            self.private_values.update({digits, '+' + digits})
            if digits.startswith('00'): self.private_values.update({digits[2:], '+' + digits[2:]})
        self.driver = Phase23Account(PRIVATE, dict(os.environ))
        self.driver.private_values.update(self.private_values)
        self.driver._active_case = 'P23'
        self.actor = None
        self.native_auth_attempted = False
        self.uploaded_videos = set()
        self.sessions = {}
        self.network_changed = False
        self.display_changed = False
        self.report = {'scope': 'actual API36 UAT observations; acceptance requires review',
                       'source_sha': os.environ['GITHUB_SHA'], 'api': API,
                       'run_id': os.environ['GITHUB_RUN_ID'], 'actions': [],
                       'product_acceptance_claimed': False, 'cleanup': {}}
        self.challenge = None
        self.running = True
        self.control_token = os.environ.pop('GITHUB_TOKEN', '')

    def redact(self, value):
        if isinstance(value, dict):
            return {k: self.redact(v) for k, v in value.items()
                    if not re.search(r'phone|email|token|secret|password|authorization|contact|otp', k, re.I)}
        if isinstance(value, list): return [self.redact(x) for x in value]
        if isinstance(value, str):
            for s in self.private_values:
                if s: value = value.replace(s, '[REDACTED]')
        return value

    PRIVATE_UI_CONTROLS = frozenset({
        'رجوع','تحديث','بلاغ','خيارات المحادثة','حظر الحساب','إلغاء الحظر',
        'حظر هذا الحساب؟','إلغاء الحظر؟','حظر','إلغاء','بلاغ عن المحادثة',
        'تفاصيل البلاغ','إرسال البلاغ','أخرى','اكتب رسالة...','ردود سريعة',
        'المظهر','فاتح','داكن','حسب إعداد الجهاز','البحث الذكي','شوهد مؤخرًا',
        'الأمان والخصوصية','تعديل الملف الشخصي','الملف الشخصي','المفضلة',
        'تسجيل الخروج','الخدمات والأدوات','المساعدة والدعم','نشاطي',
        'العقارات','حسابي','الرسائل','إعلاناتي','إضافة عقار',
    })
    PRIVATE_UI_ANCHORS = frozenset({
        'خيارات المحادثة','اكتب رسالة...','حظر الحساب','إلغاء الحظر',
        'حظر هذا الحساب؟','إلغاء الحظر؟','بلاغ عن المحادثة','تفاصيل البلاغ',
        'شوهد مؤخرًا','تعديل الملف الشخصي','الأمان والخصوصية',
    })

    @classmethod
    def private_ui_controls(cls, rows):
        if not any(cls.PRIVATE_UI_ANCHORS & labels(row) or any(
                re.search(r'[^\s@]+@[^\s@]+\.[^\s@]+',name) for name in labels(row)) for row in rows):
            return rows, False
        controls=[]
        for row in rows:
            names=cls.PRIVATE_UI_CONTROLS & labels(row)
            if names:
                controls.append({'description':'\n'.join(sorted(names)),
                                 'bounds':row.get('bounds'),'editable':row.get('editable',False)})
        return controls, True

    @staticmethod
    def synthetic_thread_metadata(body):
        data=body.get('data',{}) if isinstance(body,dict) else {}
        thread=data.get('thread',{})
        other=thread.get('other_user',{})
        if thread.get('id')!=37 or thread.get('property_id')!=106 or other.get('id') not in {26,28}:
            raise GateError('synthetic_thread_identity_required')
        return {'data':{key:thread[key] for key in
                ('id','property_id','can_send','blocked_by_me') if key in thread} |
                {'other_user_id':other['id'],'message_count_on_page':len(data.get('messages',[]))}}

    def observe(self):
        try:
            rows = self.driver.nodes()
        except Blocked:
            path = '/sdcard/phase23-window.xml'
            self.driver.adb('shell', 'uiautomator', 'dump', path, timeout=20)
            raw = self.driver.adb('exec-out', 'cat', path)
            self.driver.adb('shell', 'rm', '-f', path)
            rows = [{'text': x.get('text', ''), 'description': x.get('content-desc', ''),
                     'package': x.get('package', ''), 'resource_id': x.get('resource-id', ''),
                     'bounds': x.get('bounds', ''), 'enabled': x.get('enabled', ''),
                     'visible': True} for x in ET.fromstring(raw).iter('node')]
        visible = '\n'.join('\n'.join(labels(r)) for r in rows)
        packages = {r.get('package') for r in rows if r.get('package')}
        known = {APP, 'com.android.documentsui', 'com.google.android.documentsui',
                 'com.android.permissioncontroller', 'com.google.android.permissioncontroller',
                 'com.google.android.providers.media.module', 'com.android.providers.media.module',
                 'com.android.systemui'}
        protected = bool(packages - known) or any(s and s in visible for s in self.private_values) or any(
            field in labels(r) for field in AUTH_FIELDS for r in rows)
        rows, private_ui = self.private_ui_controls(rows)
        protected = protected or private_ui
        if protected and self.driver.recorder is not None:
            self.driver.record_tainted = True
        frame = None
        if not protected:
            data = self.driver.adb('exec-out', 'screencap', '-p', binary=True)
            if not data.startswith(b'\x89PNG\r\n\x1a\n'): raise GateError('native_frame_invalid')
            frame = self.root / ('frame-' + str(self.seq).zfill(6) + '.png')
            frame.write_bytes(data)
        return self.redact(rows), frame, protected

    def checkpoint(self, outcome, terminal=False):
        self.root.mkdir(mode=0o700, exist_ok=True)
        rows, frame, protected = ([], None, True) if terminal else self.observe()
        self.challenge = os.urandom(32).hex()
        payload = {'run_id': self.report['run_id'], 'source_sha': self.report['source_sha'],
                   'seq': self.seq, 'challenge': self.challenge, 'actor': self.actor,
                   'outcome': self.redact(outcome), 'capture_refused_for_privacy': protected,
                   'tree': rows, 'report': self.redact(self.report),
                   'apk': json.loads((PRIVATE / 'APK_VERIFICATION.json').read_text())}
        new_videos = [v for v in self.driver.report.get('videos', []) if v['file'] not in self.uploaded_videos]
        payload['videos'] = new_videos
        directory = self.root / 'checkpoints' / str(self.seq).zfill(6)
        directory.mkdir(mode=0o700, parents=True)
        plain = self.root / ('checkpoint-' + str(self.seq) + '.zip')
        with zipfile.ZipFile(plain, 'w', zipfile.ZIP_DEFLATED) as bundle:
            bundle.writestr('OBSERVATION.json', json.dumps(payload, ensure_ascii=False, indent=2))
            if frame: bundle.write(frame, frame.name)
            if self.seq == 0:
                for name in ['phase23-property.jpg','phase23-rotated-exif.jpg','phase23-unsuitable.jpg','phase23-large.jpg']:
                    source=PRIVATE/name
                    if source.is_file(): bundle.write(source,'INPUT-'+name)
            for video in new_videos:
                path = self.driver.out / video['file']
                if path.is_file(): bundle.write(path, path.name)
        cipher = directory / 'checkpoint.cms'
        subprocess.run(['openssl', 'cms', '-encrypt', '-aes-256-cbc', '-binary', '-outform', 'DER',
                        '-in', str(plain), '-out', str(cipher), str(CERT)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        plain.unlink()
        if frame: frame.unlink()
        receipt = {'version': 1, 'repo': REPO, 'run_id': self.report['run_id'],
                   'run_attempt': int(os.environ['GITHUB_RUN_ATTEMPT']), 'source_sha': self.report['source_sha'],
                   'toolbundle_sha': os.environ['AQER_BRIDGE_TOOLBUNDLE_SHA'], 'seq': self.seq,
                   'kind': 'terminal_checkpoint' if terminal else 'fixture_checkpoint' if self.seq == 0 else 'review_checkpoint',
                   'phase': 'R0' if self.seq == 0 else 'R1', 'cursor': 'PHASE23_NATIVE',
                   'checkpoint_challenge': self.challenge, 'prev_result_sha': self.previous,
                   'cipher_sha': hashlib.sha256(cipher.read_bytes()).hexdigest(), 'cipher_bytes': cipher.stat().st_size,
                   'created_utc': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                   'phase1_accepted': False}
        (directory / 'PUBLIC_RECEIPT.json').write_bytes(canonical(receipt))
        print(json.dumps({'event': 'checkpoint_ready', 'seq': self.seq,
                          'checkpoint_dir': 'checkpoints/' + str(self.seq).zfill(6)}), flush=True)
        if not select.select([sys.stdin], [], [], 90)[0]:
            raise GateError('checkpoint_ack_timeout')
        ack = json.loads(sys.stdin.readline())
        if ack.get('seq') != self.seq or not ack.get('success'):
            raise GateError('checkpoint_upload_unconfirmed')
        self.uploaded_videos.update(v['file'] for v in new_videos)

    def poll(self):
        url = 'https://api.github.com/repos/' + REPO + '/contents/' + CONTROL + '?ref=' + BRANCH.removeprefix('refs/heads/')
        headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + self.control_token}
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read(100000))
        value = json.loads(base64.b64decode(body['content']))
        if not value or value.get('run_id') != self.report['run_id'] or value.get('seq') != self.seq:
            return None
        return validate_command(value, self.report['run_id'], self.seq, self.challenge)

    def login(self, alias):
        if alias not in {'broker', 'support', 'regular'} or alias not in self.access['phones']:
            raise GateError('unavailable_test_actor')
        if self.actor is not None: raise GateError('explicit_logout_before_actor_switch_required')
        d = self.driver
        d.tap('حسابي')
        d.tap('تسجيل الدخول أو إنشاء حساب')
        d.wait('مرحبًا بعودتك')
        d.set('رقم واتساب', self.access['phones'][alias])
        d.tap('إرسال رمز واتساب')
        d.wait('تأكيد والدخول', seconds=60)
        d.set('رمز التحقق', self.access['otp'])
        d.auth_attempted = True
        self.native_auth_attempted = True
        d.tap('تأكيد والدخول')
        end = time.monotonic() + 60
        while time.monotonic() < end:
            rows = d.nodes()
            if not any('رمز التحقق' in labels(r) for r in rows) and any(
                    'حسابي' in labels(r) or 'تسجيل الخروج' in labels(r) for r in rows):
                self.actor, d.authenticated = alias, True
                return {'normal_native_login_observed': True, 'alias': alias}
            time.sleep(.7)
        raise GateError('native_login_not_observed')

    def logout(self):
        d = self.driver
        if d.recorder is not None: d.record_stop(export=True)
        d.adb('shell', 'am', 'force-stop', APP)
        d.startup()
        d.tap('حسابي')
        already_guest = d.has('تسجيل الدخول أو إنشاء حساب')
        if not already_guest:
            d.wait_account_logout_control(seconds=30)
            d.tap('تسجيل الخروج', seek=False)
        d.authenticated = False
        d.wait_guest_boundary()
        self.actor = None
        self.native_auth_attempted = False
        return {'native_logout_observed': True, 'already_guest': already_guest}

    def apply(self, command):
        op, args, d = command['op'], command['args'], self.driver
        if d.recorder is not None:
            _, temporary_frame, _ = self.observe()
            if temporary_frame: temporary_frame.unlink()
        if op == 'observe': return {'operation': op}
        if op == 'seed_media': return self.seed_media()
        if op == 'batch':
            results = []
            for step in args['steps']:
                try: results.append(self.apply(step))
                except Exception as error:
                    return {'operation': op, 'status': 'BLOCKED', 'completed_steps': results,
                            'stopped_at': len(results), 'reason': str(error) if isinstance(error, (Blocked, GateError)) else type(error).__name__}
            return {'operation': op, 'completed_steps': results, 'product_acceptance_claimed': False}
        if op == 'tap': d.tap(args['label'],seek=False)
        elif op == 'set': d.set(args['label'], args['value'])
        elif op == 'scroll': d.scroll(args['direction'])
        elif op == 'back': d.adb('shell', 'input', 'keyevent', '4')
        elif op == 'key': d.adb('shell', 'input', 'keyevent', '4' if args['key'] == 'BACK' else '66')
        elif op == 'wait': d.wait(args['label'],seconds=args['seconds'])
        elif op == 'draw_area': d.draw_area()
        elif op in {'touch', 'swipe', 'pinch', 'double_tap'}:
            rows, temporary_frame, protected = self.observe()
            if temporary_frame: temporary_frame.unlink()
            if protected or any(field in labels(r) for field in AUTH_FIELDS for r in rows):
                raise GateError('coordinate_authentication_input_refused')
            if op == 'touch': d.adb('shell', 'input', 'tap', args['x'], args['y'])
            elif op == 'swipe': d.adb('shell', 'input', 'swipe', args['x1'], args['y1'], args['x2'], args['y2'], 500)
            elif op == 'pinch': d.gesture('pinch-' + args['direction'],args['x'],args['y'])
            else: d.gesture('double-tap',args['x'],args['y'])
        elif op == 'network':
            d.require_preauth_runtime()
            enabled = args['state'] == 'online'
            if not enabled: self.network_changed = True
            for service in ('wifi','data'):
                d.adb('shell','svc',service,'enable' if enabled else 'disable')
            if enabled: self.network_changed = False
            return {'operation':op,'requested_state':args['state'],'scope':'disposable API36 device only; outcome requires UI review'}
        elif op == 'display':
            d.require_preauth_runtime()
            if args['mode'] != 'default': self.display_changed = True
            d.adb('shell','settings','put','system','font_scale','1.0' if args['mode']=='default' else '2.4')
            if args['mode']=='compact_large': d.adb('shell','wm','size','840x1493')
            else: d.adb('shell','wm','size','reset')
            if args['mode']=='default': self.display_changed = False
            return {'operation':op,'mode':args['mode'],'scope':'disposable API36 display; outcome requires visual review'}
        elif op == 'open_link':
            d.adb('shell','am','start','-W','-a','android.intent.action.VIEW','-d',args['uri'],APP)
            return {'operation':op,'uri':args['uri'],'scope':'fixed public fixture; destination requires UI review'}
        elif op == 'force_stop':
            d.adb('shell', 'am', 'force-stop', APP)
            d.startup()
        elif op == 'login': return self.login(args['alias'])
        elif op == 'logout': return self.logout()
        elif op == 'record_start':
            if not self.actor: raise GateError('authenticated_recording_required')
            rows, temporary_frame, protected = self.observe()
            if temporary_frame: temporary_frame.unlink()
            if protected: raise GateError('recording_private_surface_refused')
            d.record_start('C1-phase23-' + str(self.seq))
        elif op == 'record_stop': d.record_stop(export=True)
        elif op == 'api_get':
            alias, path = args['alias'], args['path']
            if alias not in self.access['phones'] or not isinstance(path, str) or not re.fullmatch(r'/[A-Za-z0-9_/?=&%.,\[\]-]{1,300}', path):
                raise GateError('bounded_api_read_required')
            private_path=path.startswith(('/messages/threads','/admin/messages'))
            if private_path and path!='/messages/threads/37':
                raise GateError('private_conversation_export_refused')
            if alias not in self.sessions:
                self.sessions[alias] = Session(alias, self.access)
                self.sessions[alias].login()
            session = self.sessions[alias]
            code, body = http('GET', path, token=session.token)
            if private_path:
                body=self.synthetic_thread_metadata(body) if code==200 else {'http_error':code}
            return {'operation': op, 'alias': alias, 'identity': session.identity,
                    'path': path, 'http': code, 'response': self.redact(body)}
        elif op == 'finish': self.running = False
        return {'operation': op, 'input_delivered': op != 'finish', 'product_acceptance_claimed': False}

    def seed_media(self):
        # Match the previously proven timing: app startup precedes picker writes.
        d = self.driver
        d.require_preauth_runtime()
        d.adb('shell', 'mkdir', '-p', '/sdcard/Download')
        files = []
        for name in ['phase23-property.jpg', 'phase23-rotated-exif.jpg', 'phase23-unsuitable.jpg', 'phase23-large.jpg']:
            path = PRIVATE / name
            if not path.is_file(): raise GateError('synthetic_media_source_missing')
            target = '/sdcard/Download/' + name
            d.adb('push', path, target, timeout=30)
            d.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                  '-d', 'file://' + target)
            files.append({'file': name, 'bytes': path.stat().st_size,
                          'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        return {'operation': 'seed_media', 'status': 'OBSERVED', 'files': files,
                'scope': 'disposable OS picker only; no property upload'}

    def cleanup(self):
        if self.network_changed:
            try:
                self.apply({'op':'network','args':{'state':'online'}})
                self.report['cleanup']['network_restored'] = True
            except Exception: self.report['cleanup']['network_restored'] = False
        if self.display_changed:
            try:
                self.apply({'op':'display','args':{'mode':'default'}})
                self.report['cleanup']['display_restored'] = True
            except Exception: self.report['cleanup']['display_restored'] = False
        try:
            self.driver.record_stop(export=False)
        except Exception:
            self.report['cleanup']['recorder_stopped'] = False
        for alias, session in self.sessions.items():
            try: self.report['cleanup']['api_' + alias] = session.close()
            except Exception: self.report['cleanup']['api_' + alias] = False
        if self.actor is not None or self.native_auth_attempted:
            try:
                self.logout()
                self.report['cleanup']['native_logout'] = True
            except Exception:
                self.report['cleanup']['native_logout'] = False
        self.access.clear()

    def execute(self):
        outcome = {'operation': 'startup', 'status': 'NOT RUN'}
        try:
            self.driver.validate_and_install()
            self.driver.startup()
            outcome = {'operation': 'startup', 'status': 'OBSERVED', 'android_api': 36}
            try:
                outcome['media_setup'] = self.seed_media()
            except Exception as error:
                outcome['media_setup'] = {'status': 'BLOCKED', 'reason': type(error).__name__,
                                         'scope': 'synthetic picker setup; app journey not yet tested'}
            while self.running and time.monotonic() < self.deadline:
                self.checkpoint(outcome)
                command = None
                while command is None and time.monotonic() < self.deadline:
                    try: command = self.poll()
                    except (urllib.error.URLError, TimeoutError): pass
                    if command is None: time.sleep(5)
                if command is None: raise GateError('review_deadline_reached')
                self.previous = hashlib.sha256(canonical(command)).hexdigest()
                self.seq += 1
                try:
                    outcome = self.apply(command)
                    outcome.setdefault('status', 'OBSERVED')
                except Exception as error:
                    outcome = {'operation': command['op'], 'status': 'BLOCKED',
                               'reason': str(error) if isinstance(error, (Blocked, GateError)) else type(error).__name__}
                self.report['actions'].append({'seq': self.seq, **self.redact(outcome)})
            if self.running: raise GateError('review_deadline_reached')
        except Exception as error:
            self.report['runtime_blocker'] = str(error) if isinstance(error, (Blocked, GateError)) else type(error).__name__
            raise
        finally:
            self.cleanup()
            if self.seq == 0 or (self.root / 'checkpoints' / str(self.seq).zfill(6)).exists():
                self.seq += 1
            self.checkpoint({'operation': 'cleanup', 'cleanup': self.report['cleanup']}, terminal=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-root', required=True)
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(args.run_root)
    need_root = Path(os.environ['RUNNER_TEMP']) / ('aqer-phase23-bridge-' + os.environ['GITHUB_RUN_ID'] + '-' + os.environ['GITHUB_RUN_ATTEMPT'])
    if root != need_root or list(root.iterdir()): raise GateError('fresh_owned_run_root_required')
    run = NativeRun(root)
    def interrupted(*unused):
        raise GateError('native_review_interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    run.execute()


if __name__ == '__main__':
    main()
