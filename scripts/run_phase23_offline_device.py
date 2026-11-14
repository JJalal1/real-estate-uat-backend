#!/usr/bin/env python3
"""Bounded synthetic Android device paths; native public map connectivity is allowed.

No credential is loaded and no business API write is possible in the separate target.
Only this collector permits the resolved, allowlisted Android permission/camera/picker
surfaces. The ordinary application's private-page collector remains unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
import zipfile
import zlib

from phase23_preflight import GateError
from phase23_visual_revision import guard, TREES
from prepare_phase1_close import encrypt
from run_phase23_offline_visual import Device as BaseDevice, bounds, digest, verify_badging

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.aqer.yemen.uat'
TARGET = 'AQER_OFFLINE_DEVICE_TARGET_V1'
BANNER = 'SYNTHETIC DEVICE SESSION · Native map/device network · API denied'
RECIPIENT = ROOT / 'scripts/phase23_recipient.pem'
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
NETWORK_SCOPE = 'native public map/device provider connectivity; business API denied'
SCOPE = ('Actual unchanged Android providers on a disposable API36 emulator with synthetic '
         'coordinates and images; no physical GPS, audible ASR, live account, ordinary APK, '
         'upload, or full Phase23 acceptance claim')
SEED = '/sdcard/Download/phase23-device.png'
SIZE = (1080, 1920)
CANDIDATES = {
    'permission': {'com.google.android.permissioncontroller', 'com.android.permissioncontroller'},
    'camera': {'com.android.camera2', 'com.android.camera'},
    'picker': {'com.google.android.documentsui', 'com.android.documentsui'},
    'keyboard': {'com.google.android.inputmethod.latin', 'com.android.inputmethod.latin'},
}
FIELDS = set(('v case failures dioBlocked authBlocked socketBlocked fixtureReads voicePhase '
              'voiceReadyCount voiceDictation voicePermissionDenied voiceTranscriptChars '
              'voicePreviewChars typedBaseKept searchStarted mapReady gpsConfirmations gpsPhase '
              'gpsError gpsMethod latE6 lonE6 accuracyCm mediaSelected cameraFiles pickerFiles '
              'mediaBytes mediaDecodable snapshotSeq').split())
BOOL_FIELDS = {'voiceDictation', 'voicePermissionDenied', 'typedBaseKept', 'searchStarted', 'mapReady', 'gpsMethod'}
STAGES = {'launch', 'voice_deny', 'voice_grant', 'voice_cancel', 'location_deny',
          'location_grant', 'location_confirm', 'camera_cancel', 'camera_capture',
          'picker_cancel', 'picker_select', 'finish'}
FAILURES = {'target_failure', 'metadata_invalid', 'unknown_surface', 'surface_unavailable',
            'control_missing', 'control_ambiguous', 'bounds_invalid', 'xml_invalid',
            'capture_changed', 'png_invalid', 'deadline', 'command_failed',
            'voice_not_ready', 'voice_cancel_unproven', 'permission_unproven',
            'gps_unproven', 'media_unproven', 'cleanup_failed'}
STAGE = 'context'
STARTUP_FIELDS = {'hasTarget', 'hasBanner', 'metaCount', 'validLogEventCount',
                  'focusedActivity', 'frameRetained'}
STARTUP_FILES = {'STARTUP_DIAGNOSTIC.png', 'STARTUP_DIAGNOSTIC.xml', 'STARTUP_DIAGNOSTIC.json'}


class Incomplete(GateError):
    pass


def context(env):
    guard(env)
    if env.get('PHASE23_OFFLINE_DEVICE') != 'true':
        raise GateError('explicit_device_ci_context_required')
    forbidden = ('AQER_PHASE1_TEST_ACCESS_JSON', 'AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION',
                 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', 'AQER_UAT_KEYSTORE_BASE64',
                 'AQER_UAT_KEYSTORE_PASSWORD', 'AQER_UAT_KEY_PASSWORD',
                 'AQER_RELEASE_STORE_PASSWORD', 'AQER_RELEASE_KEY_PASSWORD')
    if any(env.get(key) for key in forbidden):
        raise GateError('device_credentials_forbidden')
    if RECIPIENT.is_symlink() or not RECIPIENT.is_file() or digest(RECIPIENT) != RECIPIENT_SHA256:
        raise GateError('device_recipient_mismatch')


def metadata(raw):
    try:
        value = json.loads(raw)
    except (ValueError, TypeError):
        raise Incomplete('metadata_invalid') from None
    if (not isinstance(value, dict) or set(value) != FIELDS or
            any(type(number) is not int for number in value.values()) or
            any(not 0 <= value[key] <= 100_000_000 for key in FIELDS - {'latE6', 'lonE6'}) or
            value['v'] != 1 or value['case'] not in range(4) or value['voicePhase'] not in range(4) or
            value['gpsPhase'] not in (0, 2, 3) or value['gpsError'] not in range(5) or
            any(value[key] not in (0, 1) for key in BOOL_FIELDS) or
            not -90_000_000 <= value['latE6'] <= 90_000_000 or
            not -180_000_000 <= value['lonE6'] <= 180_000_000):
        raise Incomplete('metadata_invalid')
    if value['failures'] or value['authBlocked'] or value['socketBlocked'] or value['searchStarted']:
        raise Incomplete('target_failure')
    return value


def events(log):
    result = []
    for line in log.splitlines():
        if 'AQER_DEVICE ' in line:
            result.append(metadata(line.split('AQER_DEVICE ', 1)[1]))
    return result


def focused_activity(raw, packages):
    """Return an enum only; never retain dumpsys text or an unknown component."""
    components = set(re.findall(
        r'^\s*(?:mResumedActivity|topResumedActivity)\s*[:=]\s*ActivityRecord\{[^\n]*?\s'
        r'([A-Za-z0-9_.]+)/([A-Za-z0-9_.$]+)(?:\s|\})', raw, re.M))
    if not components:
        return 'unavailable'
    if len(components) != 1:
        return 'unknown'
    package, activity = components.pop()
    if (package, activity) == (PACKAGE, 'com.example.real_estate_mobile.MainActivity'):
        return 'target'
    return 'known_system' if package in packages.values() else 'unknown'


def startup_tree(value):
    """Diagnostic-only app XML, with no relaxation of surface() acceptance."""
    if len(value.encode()) > 2_000_000 or '<!DOCTYPE' in value or '<!ENTITY' in value:
        raise Incomplete('xml_invalid')
    try:
        root = ET.fromstring(value)
    except ET.ParseError:
        raise Incomplete('xml_invalid') from None
    if root.tag != 'hierarchy':
        raise Incomplete('xml_invalid')
    nodes = list(root.iter('node'))
    seen = {node.get('package') for node in nodes if node.get('package')}
    if seen != {PACKAGE}:
        raise Incomplete('unknown_surface')
    return root


def startup_diagnostics(device, private, packages, *, verified_install=False):
    """One bounded launch-failure observation; never an accepted test frame."""
    if verified_install is not True:
        raise GateError('device_startup_identity_unverified')
    result = {'hasTarget': 0, 'hasBanner': 0, 'metaCount': 0,
              'validLogEventCount': 0, 'focusedActivity': 'unavailable', 'frameRetained': 0}
    expected_errors = (Incomplete, GateError, OSError, subprocess.SubprocessError, UnicodeError)
    def focus():
        return focused_activity(device.adb('shell', 'dumpsys', 'activity', 'activities', timeout=5), packages)
    try:
        result['focusedActivity'] = focus()
    except expected_errors:
        pass
    try:
        raw_log = device.adb('logcat', '-d', '-v', 'brief', timeout=5)
        for line in raw_log.splitlines():
            if 'AQER_DEVICE ' not in line:
                continue
            try:
                metadata(line.split('AQER_DEVICE ', 1)[1])
            except Incomplete:
                continue
            result['validLogEventCount'] = min(100_000, result['validLogEventCount'] + 1)
    except expected_errors:
        pass
    try:
        value = device.xml(timeout=5)
        root = startup_tree(value)
        names = set().union(*(labels(node) for node in root.iter('node')))
        result['hasTarget'] = int(TARGET in names)
        result['hasBanner'] = int(BANNER in names)
        result['metaCount'] = min(100_000, sum(name.startswith('DEVICE_META ') for name in names))
        if result['focusedActivity'] != 'target' or focus() != 'target':
            return result
        png = device.adb('exec-out', 'screencap', '-p', binary=True, timeout=5)
        after = device.xml(timeout=5)
        startup_tree(after)
        if focus() != 'target':
            return result
        if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', png[16:24]) != SIZE:
            return result
        record = {'diagnostic_only': True, 'png_sha256': hashlib.sha256(png).hexdigest(),
                  'xml_sha256': hashlib.sha256(value.encode()).hexdigest()}
        for suffix, data in (('png', png), ('xml', value.encode()),
                             ('json', json.dumps(record).encode())):
            (private / ('STARTUP_DIAGNOSTIC.' + suffix)).write_bytes(data)
        result['frameRetained'] = 1
    except expected_errors:
        for name in STARTUP_FILES:
            (private / name).unlink(missing_ok=True)
    return result


def labels(node):
    return {s.strip() for field in ('text', 'content-desc')
            for s in node.get(field, '').splitlines() if s.strip()}


def surface(xml, role, packages):
    if role not in {'app', *CANDIDATES}:
        raise Incomplete('unknown_surface')
    if len(xml.encode()) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        raise Incomplete('xml_invalid')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise Incomplete('xml_invalid') from None
    if root.tag != 'hierarchy':
        raise Incomplete('xml_invalid')
    allowed = {PACKAGE}
    if role != 'app':
        package = packages.get(role)
        if package not in CANDIDATES[role]:
            raise Incomplete('unknown_surface')
        allowed.add(package)
    nodes = list(root.iter('node'))
    seen = {node.get('package') for node in nodes if node.get('package')}
    if not seen or not seen <= allowed:
        raise Incomplete('unknown_surface')
    names = set().union(*(labels(node) for node in nodes))
    values = [s[len('DEVICE_META '):] for s in names if s.startswith('DEVICE_META ')]
    data = metadata(values[0]) if len(values) == 1 else None
    if role in ('app', 'keyboard'):
        if not {TARGET, BANNER} <= names or data is None:
            raise Incomplete('surface_unavailable')
    elif packages[role] not in seen:
        raise Incomplete('surface_unavailable')
    return root, data


def control(xml, role, packages, *, names=(), ids=(), clazz=None, size=SIZE):
    root, _ = surface(xml, role, packages)
    parent = {child: node for node in root.iter() for child in node}
    matches = []
    expected = PACKAGE if role in ('app', 'keyboard') else packages[role]
    for node in root.iter('node'):
        hit = bool(set(names) & labels(node)) or node.get('resource-id') in ids
        if clazz is not None:
            hit = node.get('class') == clazz
        if not hit or node.get('package') != expected:
            continue
        action = node
        while action is not None and action.get('clickable') != 'true':
            action = parent.get(action)
        if (action is None or action.get('package') != expected or
                action.get('enabled') != 'true' or action.get('visible-to-user', 'true') != 'true'):
            continue
        try:
            box = bounds(action.get('bounds'), size)
        except GateError:
            raise Incomplete('bounds_invalid') from None
        matches.append(box)
    matches = set(matches)
    if not matches:
        raise Incomplete('control_missing')
    if len(matches) != 1:
        raise Incomplete('control_ambiguous')
    left, top, right, bottom = matches.pop()
    return ((left + right) // 2, (top + bottom) // 2)


def resolved_package(output, role, installed):
    values = re.findall(r'^([A-Za-z0-9_.]+)/[A-Za-z0-9_.$]+$', output, re.M)
    if len(values) != 1 or values[0] not in CANDIDATES[role] or values[0] not in installed:
        raise GateError('device_system_component_not_allowlisted')
    return values[0]


def verify_archive(apk):
    if apk.is_symlink() or not apk.is_file():
        raise GateError('device_apk_missing')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        libs = [name for name in names if name.endswith('/libapp.so')]
        if len(names) != len(set(names)) or libs != ['lib/x86_64/libapp.so'] or archive.testzip() is not None:
            raise GateError('device_x86_target_required')
        app = archive.read(libs[0])
        if any(marker not in app for marker in (TARGET.encode(), b'SYNTHETIC DEVICE SESSION', b'DEVICE_TARGET_API_FORBIDDEN')):
            raise GateError('device_compiled_target_missing')
        if any(marker in app for marker in (b'AQER_NATIVE_TEST_ACCESS', b'AQER_CALLBACK_ISOLATION', b'AQER_OFFLINE_VISUAL_TARGET_V1', b'AQER_OFFLINE_JOURNEYS_TARGET_V1')):
            raise GateError('device_other_target_refused')


def synthetic_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    # Fixed opaque synthetic checkerboard, never a user image.
    rows = b''.join(b'\0' + b''.join(bytes((40, 140, 210) if (x//32+y//32)%2 else (240, 180, 60))
                                     for x in range(256)) for y in range(256))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


class Device(BaseDevice):
    def xml(self, timeout=20):
        path = '/sdcard/aqer-device-window.xml'
        self.adb('shell', 'rm', '-f', path, timeout=timeout)
        self.adb('shell', 'uiautomator', 'dump', '--compressed', path, timeout=timeout)
        return self.adb('exec-out', 'cat', path, timeout=timeout)

    def wait(self, role, packages, predicate=lambda _: True, seconds=20):
        until = min(self.deadline, time.monotonic() + seconds)
        while time.monotonic() < until:
            events(self.log())
            xml = self.xml()
            try:
                _, data = surface(xml, role, packages)
                if predicate(data):
                    return xml, data
            except Incomplete as error:
                if str(error) not in {'surface_unavailable', 'unknown_surface'}:
                    raise
                # Never input or capture an unknown transition. Bounded wait only.
            time.sleep(.25)
        raise Incomplete('surface_unavailable')

    def tap(self, role, packages, **selector):
        until = min(self.deadline, time.monotonic() + 20)
        while time.monotonic() < until:
            xml, _ = self.wait(role, packages, seconds=max(.1, until-time.monotonic()))
            try:
                point = control(xml, role, packages, **selector)
            except Incomplete as error:
                if str(error) != 'control_missing':
                    raise
                time.sleep(.25)
                continue
            self.adb('shell', 'input', 'tap', *map(str, point))
            return
        raise Incomplete('control_missing')

    def back(self, role, packages):
        surface(self.xml(), role, packages)
        self.adb('shell', 'input', 'keyevent', '4')

    def app(self, packages, **conditions):
        return self.wait('app', packages, lambda data: all(data[key] == value for key, value in conditions.items()))

    def snapshot(self, packages):
        before = self.app(packages)[1]['snapshotSeq']
        self.tap('app', packages, names=('DEVICE_SNAPSHOT',))
        return self.wait('app', packages, lambda data: data['snapshotSeq'] > before)[1]

    def permission(self, packages, allow):
        self.tap('permission', packages, ids=(packages['permission'] + ':id/' +
                 ('permission_allow_foreground_only_button' if allow else 'permission_deny_button'),))

    def granted(self, permission):
        value = self.adb('shell', 'dumpsys', 'package', PACKAGE)
        matches = re.findall(re.escape(permission) + r': granted=(true|false)(?:,|\s)', value)
        return bool(matches) and set(matches) == {'true'}

    def geo(self):
        self.adb('emu', 'geo', 'fix', '44.2051', '15.3729')

    def scroll_to(self, packages, name, attempts=5, upward=False):
        for index in range(attempts + 1):
            xml, _ = self.app(packages)
            try:
                point = control(xml, 'app', packages, names=(name,))
                self.adb('shell', 'input', 'tap', *map(str, point))
                return
            except Incomplete as error:
                if str(error) != 'control_missing' or index == attempts:
                    raise
            root, _ = surface(xml, 'app', packages)
            boxes = {bounds(node.get('bounds'), SIZE) for node in root.iter('node')
                     if node.get('package') == PACKAGE and node.get('scrollable') == 'true'
                     and node.get('enabled') == 'true'}
            if len(boxes) != 1:
                raise Incomplete('control_ambiguous')
            left, top, right, bottom = boxes.pop()
            start, end = (top+(bottom-top)//5, top+(bottom-top)*4//5) if upward else (top+(bottom-top)*4//5, top+(bottom-top)//5)
            self.adb('shell', 'input', 'swipe', str((left+right)//2), str(start),
                     str((left+right)//2), str(end), '350')


def capture(device, private, frames, packages, role='app'):
    xml, data = device.wait(role, packages)
    png = device.adb('exec-out', 'screencap', '-p', binary=True)
    after = device.xml()
    _, after_data = surface(after, role, packages)
    if role == 'app' and (data['case'] != after_data['case']):
        raise Incomplete('capture_changed')
    if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', png[16:24]) != SIZE:
        raise Incomplete('png_invalid')
    stem = f'frame-{len(frames):02d}'
    record = {'frame': stem, 'stage': STAGE, 'role': role, 'metadata': data,
              'png_sha256': hashlib.sha256(png).hexdigest(), 'xml_sha256': hashlib.sha256(xml.encode()).hexdigest()}
    for suffix, value in (('png', png), ('xml', xml.encode()), ('json', json.dumps(record, ensure_ascii=False).encode())):
        (private / (stem + '.' + suffix)).write_bytes(value)
    frames.append(record)


def checks_complete(checks):
    return set(checks) == {'voice_denied', 'voice_permission_granted', 'voice_retry_ready', 'voice_cancel', 'location_denied', 'location_permission_granted',
                           'location_retry_gps', 'camera_cancel', 'camera_capture', 'picker_cancel', 'picker_select'} and all(value is True for value in checks.values())


def validate_receipt(receipt):
    expected = {'schema', 'source_sha', 'run_id', 'product_trees', 'target_marker', 'package',
                'version_code', 'apk_sha256', 'api_level', 'network_scope', 'system_packages',
                'stage', 'failure', 'case_failures', 'checks', 'cleanup', 'complete', 'startup_diagnostics'}
    check_names = {'voice_denied', 'voice_permission_granted', 'voice_retry_ready', 'voice_cancel', 'location_denied', 'location_permission_granted',
                   'location_retry_gps', 'camera_cancel', 'camera_capture', 'picker_cancel', 'picker_select'}
    if not isinstance(receipt, dict) or set(receipt) != expected:
        raise GateError('device_receipt_invalid')
    startup = receipt['startup_diagnostics']
    if startup is not None and (
            not isinstance(startup, dict) or set(startup) != STARTUP_FIELDS or
            any(type(startup[key]) is not int or not 0 <= startup[key] <= 100_000
                for key in STARTUP_FIELDS - {'focusedActivity'}) or
            any(startup[key] not in (0, 1) for key in ('hasTarget', 'hasBanner', 'frameRetained')) or
            startup['focusedActivity'] not in ('target', 'known_system', 'unknown', 'unavailable') or
            (startup['frameRetained'] and startup['focusedActivity'] != 'target') or
            receipt['stage'] != 'launch' or receipt['failure'] is None or
            receipt['checks'] or receipt['case_failures'] or receipt['complete']):
        raise GateError('device_receipt_invalid')
    packages, checks, failed = receipt['system_packages'], receipt['checks'], receipt['case_failures']
    if (not isinstance(packages, dict) or set(packages) != set(CANDIDATES) or
            any(packages[key] not in CANDIDATES[key] for key in CANDIDATES) or
            not isinstance(checks, dict) or not set(checks) <= check_names or
            any(type(value) is not bool for value in checks.values()) or
            not isinstance(failed, dict) or not set(failed) <= {'voice', 'location', 'camera', 'picker'}):
        raise GateError('device_receipt_invalid')
    for item in failed.values():
        if (not isinstance(item, dict) or set(item) != {'stage', 'failure'} or
                item['stage'] not in STAGES or item['failure'] not in FAILURES):
            raise GateError('device_receipt_invalid')
    if (receipt['schema'] != 1 or type(receipt['schema']) is not int or
            not re.fullmatch('[a-f0-9]{40}', str(receipt['source_sha'])) or
            not re.fullmatch('[1-9][0-9]*', str(receipt['run_id'])) or
            not re.fullmatch('[a-f0-9]{64}', str(receipt['apk_sha256'])) or
            receipt['product_trees'] != TREES or receipt['package'] != PACKAGE or
            type(receipt['version_code']) is not int or not 1 <= receipt['version_code'] <= 2100000000 or
            receipt['api_level'] != 36 or type(receipt['api_level']) is not int or
            receipt['stage'] not in STAGES or receipt['failure'] not in FAILURES | {None} or
            receipt['network_scope'] != NETWORK_SCOPE or receipt['target_marker'] != TARGET or
            type(receipt['cleanup']) is not bool or type(receipt['complete']) is not bool or
            receipt['complete'] != (checks_complete(checks) and not failed and receipt['failure'] is None and receipt['cleanup'])):
        raise GateError('device_receipt_invalid')


def seal(private, output, receipt, frames, encryptor=encrypt):
    validate_receipt(receipt)
    expected = {'MANIFEST.json'} | {f"frame-{index:02d}.{suffix}" for index in range(len(frames)) for suffix in ('png', 'xml', 'json')}
    if receipt['startup_diagnostics'] is not None and receipt['startup_diagnostics']['frameRetained']:
        expected |= STARTUP_FILES
    if ({path.name for path in private.iterdir()} != expected or
            any(path.is_symlink() or not path.is_file() for path in private.iterdir())):
        raise GateError('device_export_scope_invalid')
    output.mkdir(mode=0o700)
    try:
        archive = private.parent / 'device.zip'
        try:
            with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as zipped:
                for path in sorted(private.iterdir()):
                    zipped.write(path, path.name)
            archive.chmod(0o600)
            encrypted = encryptor(archive, output / 'device.cms', RECIPIENT)
        finally:
            archive.unlink(missing_ok=True)
        public = {**receipt, 'encrypted_evidence': encrypted, 'recipient_sha256': RECIPIENT_SHA256,
                  'frame_count': len(frames), 'result': 'COMPLETE' if receipt['complete'] else 'INCOMPLETE',
                  'plaintext_exported': False, 'apk_exported': False, 'live_authentication': False,
                  'physical_device_acceptance': False, 'phase23_accepted': False, 'scope': SCOPE}
        (output / 'PUBLIC_RECEIPT.json').write_text(json.dumps(public, indent=2) + '\n')
        if {p.name for p in output.iterdir()} != {'device.cms', 'PUBLIC_RECEIPT.json'}:
            raise GateError('device_export_scope_invalid')
    except BaseException:
        shutil.rmtree(output)
        raise


def voice_case(device, private, frames, packages, checks):
    global STAGE
    device.tap('app', packages, names=('DEVICE_VOICE',))
    device.app(packages, case=1)
    device.tap('app', packages, clazz='android.widget.EditText')
    # The only text input is this fixed synthetic literal, never a credential.
    device.adb('shell', 'input', 'text', 'DEVICE_TYPED_BASE')
    ime = device.adb('shell', 'dumpsys', 'input_method')
    if re.search(r'(?:mInputShown|mIsInputViewShown)=true', ime):
        device.back('keyboard', packages)
    device.app(packages, typedBaseKept=1)
    STAGE = 'voice_deny'
    device.tap('app', packages, names=('أكمل بحثك بالصوت',))
    capture(device, private, frames, packages, 'permission')
    device.permission(packages, False)
    device.app(packages, voicePermissionDenied=1)
    checks['voice_denied'] = not device.granted('android.permission.RECORD_AUDIO')
    if not checks['voice_denied']:
        raise Incomplete('permission_unproven')
    capture(device, private, frames, packages)
    STAGE = 'voice_grant'
    device.tap('app', packages, names=('أكمل بحثك بالصوت',))
    device.permission(packages, True)
    checks['voice_permission_granted'] = device.granted('android.permission.RECORD_AUDIO')
    if not checks['voice_permission_granted']:
        raise Incomplete('permission_unproven')
    device.wait('app', packages, lambda data: data['voiceReadyCount'] >= 1 and data['voicePhase'] == 2)
    checks['voice_retry_ready'] = True
    if not checks['voice_retry_ready']:
        raise Incomplete('voice_not_ready')
    STAGE = 'voice_cancel'
    device.tap('app', packages, names=('إلغاء',))
    data = device.app(packages, voicePhase=0, typedBaseKept=1, searchStarted=0,
                      voiceTranscriptChars=0, voicePreviewChars=0)[1]
    checks['voice_cancel'] = data['voiceReadyCount'] >= 1 and data['dioBlocked'] == 0
    if not checks['voice_cancel']:
        raise Incomplete('voice_cancel_unproven')
    capture(device, private, frames, packages)
    device.tap('app', packages, names=('DEVICE_HOME',))
    device.app(packages, case=0)


def location_case(device, private, frames, packages, checks):
    global STAGE
    device.tap('app', packages, names=('DEVICE_LOCATION',))
    device.wait('app', packages, lambda data: data['case'] == 2 and data['mapReady'] == 1, seconds=60)
    STAGE = 'location_deny'
    device.tap('app', packages, names=('موقعي الحالي',))
    capture(device, private, frames, packages, 'permission')
    device.permission(packages, False)
    device.app(packages, gpsError=1)
    checks['location_denied'] = not device.granted('android.permission.ACCESS_FINE_LOCATION')
    if not checks['location_denied']:
        raise Incomplete('permission_unproven')
    capture(device, private, frames, packages)
    STAGE = 'location_grant'
    device.tap('app', packages, names=('موقعي الحالي',))
    xml, _ = device.wait('permission', packages)
    fine = packages['permission'] + ':id/permission_location_accuracy_radio_fine'
    if any(node.get('resource-id') == fine for node in ET.fromstring(xml).iter('node')):
        device.tap('permission', packages, ids=(fine,))
    device.permission(packages, True)
    for _ in range(4):
        device.geo()
        time.sleep(.5)
    checks['location_permission_granted'] = device.granted('android.permission.ACCESS_FINE_LOCATION')
    if not checks['location_permission_granted']:
        raise Incomplete('permission_unproven')
    device.app(packages, mapReady=1, gpsError=0)
    STAGE = 'location_confirm'
    device.tap('app', packages, names=('تأكيد هذا الموقع',))
    data = device.app(packages, case=0, gpsConfirmations=1, gpsPhase=2, gpsMethod=1)[1]
    checks['location_retry_gps'] = abs(data['latE6'] - 15372900) <= 20 and abs(data['lonE6'] - 44205100) <= 20
    if not checks['location_retry_gps']:
        raise Incomplete('gps_unproven')
    capture(device, private, frames, packages)


def camera_case(device, private, frames, packages, checks):
    global STAGE
    device.tap('app', packages, names=('DEVICE_MEDIA',))
    device.app(packages, case=3)
    baseline = device.snapshot(packages)
    if any(baseline[key] for key in ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes')):
        raise Incomplete('media_unproven')
    STAGE = 'camera_cancel'
    device.scroll_to(packages, 'صورة حية / سيلفي *')
    device.wait('camera', packages)
    capture(device, private, frames, packages, 'camera')
    device.back('camera', packages)
    data = device.snapshot(packages)
    checks['camera_cancel'] = all(data[key] == 0 for key in ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes'))
    if not checks['camera_cancel']:
        raise Incomplete('media_unproven')
    capture(device, private, frames, packages)
    STAGE = 'camera_capture'
    device.scroll_to(packages, 'صورة حية / سيلفي *')
    device.wait('camera', packages)
    device.tap('camera', packages, ids=tuple(packages['camera'] + ':id/' + s for s in ('shutter_button', 'shutter')),
               names=('Shutter', 'Take photo', 'Capture', 'التقاط صورة'))
    device.tap('camera', packages, ids=tuple(packages['camera'] + ':id/' + s for s in ('done_button', 'btn_done', 'review_done')),
               names=('Done', 'OK', 'تم', 'موافق'))
    data = device.snapshot(packages)
    checks['camera_capture'] = data['mediaSelected'] == 1 and data['cameraFiles'] == 1 and data['pickerFiles'] == 0 and data['mediaDecodable'] == 1 and data['mediaBytes'] > 0
    if not checks['camera_capture']:
        raise Incomplete('media_unproven')
    capture(device, private, frames, packages)
    device.tap('app', packages, names=('DEVICE_HOME',))
    device.app(packages, case=0)


def picker_case(device, private, frames, packages, checks):
    global STAGE
    STAGE = 'picker_cancel'
    # A separate original screen instance makes DocumentsUI independent of
    # camera onboarding/provider availability. Home was verified first.
    device.app(packages, case=0)
    device.tap('app', packages, names=('DEVICE_MEDIA',))
    device.app(packages, case=3)
    data = device.snapshot(packages)
    if any(data[key] for key in ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes')):
        raise Incomplete('media_unproven')
    device.scroll_to(packages, 'صورة البطاقة الشخصية أو جواز السفر *')
    device.tap('app', packages, names=('اختيار من الملفات',))
    device.wait('picker', packages)
    capture(device, private, frames, packages, 'picker')
    device.back('picker', packages)
    cancelled = device.snapshot(packages)
    checks['picker_cancel'] = all(cancelled[key] == data[key] for key in ('mediaSelected', 'cameraFiles', 'pickerFiles', 'mediaBytes', 'mediaDecodable'))
    if not checks['picker_cancel']:
        raise Incomplete('media_unproven')
    capture(device, private, frames, packages)
    STAGE = 'picker_select'
    device.scroll_to(packages, 'صورة البطاقة الشخصية أو جواز السفر *', upward=True)
    device.tap('app', packages, names=('اختيار من الملفات',))
    xml, _ = device.wait('picker', packages)
    try:
        point = control(xml, 'picker', packages, names=('phase23-device.png',))
    except Incomplete as error:
        if str(error) != 'control_missing':
            raise
        device.tap('picker', packages, names=('Show roots', 'Show navigation drawer', 'إظهار الجذور', 'فتح قائمة التنقل'), ids=('android:id/home',))
        device.tap('picker', packages, names=('Downloads', 'التنزيلات'))
        device.tap('picker', packages, names=('phase23-device.png',))
    else:
        device.adb('shell', 'input', 'tap', *map(str, point))
    picker_return(device, packages)
    data = device.snapshot(packages)
    checks['picker_select'] = data['mediaSelected'] == 1 and data['cameraFiles'] == 0 and data['pickerFiles'] == 1 and data['mediaDecodable'] == 1 and data['mediaBytes'] > cancelled['mediaBytes']
    if not checks['picker_select']:
        raise Incomplete('media_unproven')
    capture(device, private, frames, packages)
    device.tap('app', packages, names=('DEVICE_HOME',))
    device.app(packages, case=0)
    STAGE = 'finish'
    capture(device, private, frames, packages)




def picker_return(device, packages):
    """Accept direct app return or exactly one observed picker confirmation."""
    until = min(device.deadline, time.monotonic() + 20)
    confirmed = False
    while time.monotonic() < until:
        events(device.log())
        xml = device.xml()
        try:
            _, data = surface(xml, 'app', packages)
            if data['case'] != 3:
                raise Incomplete('capture_changed')
            return
        except Incomplete as error:
            if str(error) not in {'unknown_surface', 'surface_unavailable'}:
                raise
        # Unknown overlays cannot be clicked, adopted, or captured.
        surface(xml, 'picker', packages)
        if not confirmed:
            try:
                point = control(xml, 'picker', packages,
                    names=('Open', 'Select', 'فتح', 'تحديد'),
                    ids=(packages['picker'] + ':id/action_menu_select',))
            except Incomplete as error:
                if str(error) != 'control_missing':
                    raise
            else:
                device.adb('shell', 'input', 'tap', *map(str, point))
                confirmed = True
        time.sleep(.25)
    raise Incomplete('surface_unavailable')


def recover_home(device, packages):
    """Return only from an observed, allowlisted synthetic provider surface."""
    for _ in range(3):
        xml = device.xml()
        for role in ('app', 'permission', 'camera', 'picker', 'keyboard'):
            try:
                _, data = surface(xml, role, packages)
            except Incomplete:
                continue
            if role == 'app':
                if data['case'] != 0:
                    device.tap('app', packages, names=('DEVICE_HOME',))
                device.app(packages, case=0)
                return
            device.back(role, packages)
            break
        else:
            raise Incomplete('unknown_surface')
    raise Incomplete('surface_unavailable')


def execute(device, private, frames, packages, checks, case_failures):
    global STAGE
    STAGE = 'launch'
    device.app(packages, case=0)
    capture(device, private, frames, packages)
    for name, procedure in (('voice', voice_case), ('location', location_case),
                            ('camera', camera_case), ('picker', picker_case)):
        try:
            procedure(device, private, frames, packages, checks)
        except Incomplete as error:
            if str(error) not in FAILURES:
                raise
            case_failures[name] = {'stage': STAGE, 'failure': str(error)}
            try:
                device.wait('app', packages, seconds=3)
                capture(device, private, frames, packages)
            except (Incomplete, GateError, subprocess.SubprocessError):
                pass  # Only previously verified frames may be sealed.
            # Incomplete provider availability must not erase other independent
            # device evidence. No invented result or synthetic provider override.
            recover_home(device, packages)
    STAGE = 'finish'
    capture(device, private, frames, packages)


def cleanup(serial):
    ok = True
    for args in (('shell', 'am', 'force-stop', PACKAGE), ('shell', 'pm', 'clear', PACKAGE),
                 ('shell', 'rm', '-f', SEED, '/sdcard/aqer-device-window.xml')):
        try:
            result = subprocess.run(['adb', '-s', serial, *args], capture_output=True, timeout=8, check=False)
            ok = ok and result.returncode == 0 and (args[1:3] != ('pm', 'clear') or result.stdout.strip() == b'Success')
        except (OSError, subprocess.SubprocessError):
            ok = False
    return ok


def collect(args, env=os.environ):
    global STAGE
    context(env)
    device = Device(args.serial, time.monotonic() + args.max_seconds)
    apk = Path(args.apk).absolute()
    output = ROOT / 'phase23-offline-device-sealed'
    if output.exists() or output.is_symlink():
        raise GateError('device_fresh_output_required')
    verify_archive(apk)
    bt = Path(env['ANDROID_HOME']) / 'build-tools/36.0.0'
    device.command([bt / 'apksigner', 'verify', apk])
    badging = device.command([bt / 'aapt', 'dump', 'badging', apk])
    version = verify_badging(badging)
    if any("name='android.permission." + name + "'" in badging for name in ('CAMERA', 'READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO')):
        raise GateError('device_unexpected_app_media_permission')
    if device.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or device.adb('shell', 'getprop', 'ro.build.version.sdk') != '36':
        raise GateError('device_api36_emulator_required')
    if device.adb('shell', 'pm', 'path', PACKAGE, check=False):
        raise GateError('device_fresh_install_required')
    size = re.findall(r'(?:Physical|Override) size: (\d+)x(\d+)', device.adb('shell', 'wm', 'size'))
    if not size or tuple(map(int, size[-1])) != SIZE:
        raise GateError('device_display_size_invalid')
    installed = set(re.findall(r'^package:([A-Za-z0-9_.]+)$', device.adb('shell', 'pm', 'list', 'packages', '-s'), re.M))
    controllers = installed & CANDIDATES['permission']
    if len(controllers) != 1:
        raise GateError('device_permission_controller_unknown')
    packages = {'permission': controllers.pop()}
    for role, intent in (('camera', ('-a', 'android.media.action.IMAGE_CAPTURE')),
                         ('picker', ('-a', 'android.intent.action.OPEN_DOCUMENT', '-c', 'android.intent.category.OPENABLE', '-t', 'image/*'))):
        packages[role] = resolved_package(device.adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', *intent), role, installed)
    ime = device.adb('shell', 'settings', 'get', 'secure', 'default_input_method').split('/', 1)[0]
    if ime not in CANDIDATES['keyboard'] or ime not in installed:
        raise GateError('device_keyboard_unknown')
    packages['keyboard'] = ime
    device.adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable')
    device.adb('shell', 'svc', 'wifi', 'enable')
    device.adb('shell', 'svc', 'data', 'enable')
    device.adb('shell', 'cmd', 'location', 'set-location-enabled', 'true', '--user', '0')
    device.geo()
    device.adb('install', '--no-streaming', str(apk), timeout=180)
    path = device.adb('shell', 'pm', 'path', PACKAGE)
    if not re.fullmatch(r'package:/data/app/[A-Za-z0-9_./=+~-]+/base\.apk', path):
        raise GateError('device_installed_path_invalid')
    if hashlib.sha256(device.adb('exec-out', 'cat', path[8:], binary=True, timeout=60)).hexdigest() != digest(apk):
        raise GateError('device_installed_identity_mismatch')
    with tempfile.TemporaryDirectory(prefix='phase23-device-', dir=env['RUNNER_TEMP']) as directory:
        private = Path(directory) / 'frames'
        private.mkdir(mode=0o700)
        seed = Path(directory) / 'phase23-device.png'
        seed.write_bytes(synthetic_png())
        device.adb('shell', 'mkdir', '-p', '/sdcard/Download')
        device.adb('push', str(seed), SEED)
        device.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', 'file://' + SEED)
        frames, checks, failure, case_failures = [], {}, None, {}
        startup = None
        STAGE = 'launch'
        try:
            device.adb('logcat', '-c')
            device.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/com.example.real_estate_mobile.MainActivity')
            execute(device, private, frames, packages, checks, case_failures)
        except (Incomplete, GateError, subprocess.SubprocessError, OSError, UnicodeError) as error:
            failure = str(error) if isinstance(error, Incomplete) and str(error) in FAILURES else ('deadline' if isinstance(error, subprocess.TimeoutExpired) or 'timeout' in str(error) else 'command_failed')
            if STAGE == 'launch' and not frames and not checks and not case_failures:
                # Reached only after fresh API36 emulator, compiled marker,
                # signer, package and installed APK digest have all been verified.
                startup = startup_diagnostics(device, private, packages, verified_install=True)
        finally:
            cleaned = cleanup(args.serial)
        if case_failures and failure is None:
            failure = next(iter(case_failures.values()))['failure']
        if not cleaned:
            failure = failure or 'cleanup_failed'
        receipt = {'schema': 1, 'source_sha': env['GITHUB_SHA'], 'run_id': env['GITHUB_RUN_ID'],
                   'product_trees': TREES, 'target_marker': TARGET, 'package': PACKAGE,
                   'version_code': version, 'apk_sha256': digest(apk), 'api_level': 36,
                   'network_scope': NETWORK_SCOPE, 'system_packages': packages,
                   'stage': STAGE, 'failure': failure, 'case_failures': case_failures, 'checks': checks, 'cleanup': cleaned,
                   'complete': failure is None and cleaned and checks_complete(checks),
                   'startup_diagnostics': startup}
        (private / 'MANIFEST.json').write_text(json.dumps({**receipt, 'frames': frames, 'scope': SCOPE}, ensure_ascii=False, indent=2) + '\n')
        seal(private, output, receipt, frames)
        if not receipt['complete']:
            raise Incomplete(failure or 'surface_unavailable')
    print('AQER_DEVICE_SYNTHETIC_PROVIDER_PATHS_SEALED')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--max-seconds', type=int, default=900)
    args = parser.parse_args()
    if not 600 <= args.max_seconds <= 900:
        raise GateError('device_duration_invalid')
    def alarm(_signum, _frame):
        raise Incomplete('deadline')
    signal.signal(signal.SIGALRM, alarm)
    signal.alarm(args.max_seconds + 90)  # bounded cleanup/encryption reserve
    try:
        collect(args)
    finally:
        signal.alarm(0)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Never print subprocess output, API content, XML, logcat, or credentials.
        reason = str(error) if isinstance(error, GateError) and re.fullmatch('[a-z0-9_]+', str(error)) else 'device_collection_failed'
        print(reason, file=sys.stderr)
        raise SystemExit(1) from None
