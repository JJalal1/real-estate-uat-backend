#!/usr/bin/env python3
"""Capture fourteen synthetic, offline native fixtures; export ciphertext only.

This is a separate target collector. It neither authenticates nor starts the
ordinary application. Its screenshots establish fixture rendering only, never
live authorization, provider delivery, or hardware/permission acceptance.
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

from phase23_preflight import GateError, TREES, guard
from prepare_phase1_close import encrypt

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.aqer.yemen.uat'
TARGET = 'AQER_OFFLINE_VISUAL_TARGET_V1'
BANNER = 'SYNTHETIC OFFLINE'
NEXT = 'AQER_VISUAL_NEXT'
FAILURE = 'AQER_VISUAL_FAILURE'
COUNT = 14
STAGE = 'startup'
RECIPIENT = ROOT / 'scripts/phase23_recipient.pem'
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
SCOPE = ('Synthetic offline fixture rendering on API36 only; no live account, '
         'authorization, provider, hardware, permission, or ordinary-app acceptance')
READY_FIELDS = {'event', 'case', 'state', 'role', 'surface', 'dark', 'textScale', 'requests', 'failures'}
# These are controlled harness metadata, not arbitrary app logs or UI labels.
CASES = (
    ('favorites', 'regular', 'populated', False, 1),
    ('favorites', 'regular', 'empty', True, 1),
    ('favorites', 'regular', 'error', False, 1),
    ('favorites', 'regular', 'loading', True, 1),
    ('availability', 'broker', 'populated', True, 2.4),
    ('customers', 'broker', 'populated', False, 2.4),
    ('messages', 'regular', 'populated', True, 1),
    ('messages', 'regular', 'empty', False, 2.4),
    ('support', 'support', 'populated', True, 1),
    ('support', 'support', 'empty', False, 1),
    ('support', 'support', 'error', True, 2.4),
    ('support', 'support', 'loading', False, 1),
    ('notifications', 'regular', 'populated', True, 2.4),
    ('reports', 'support', 'populated', False, 2.4),
)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def context(env):
    guard(env)
    if (env.get('PHASE23_OFFLINE_VISUAL') != 'true' or
            env.get('SOURCE_COMMIT') != env.get('GITHUB_SHA') or
            not re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_ID', ''))):
        raise GateError('explicit_offline_visual_context_required')
    forbidden = ('AQER_PHASE1_TEST_ACCESS_JSON', 'AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION',
                 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', 'AQER_UAT_KEYSTORE_BASE64',
                 'AQER_UAT_KEYSTORE_PASSWORD', 'AQER_UAT_KEY_PASSWORD',
                 'AQER_RELEASE_STORE_PASSWORD', 'AQER_RELEASE_KEY_PASSWORD')
    if any(env.get(key) for key in forbidden):
        raise GateError('offline_visual_auth_or_secret_environment_refused')
    subprocess.run(['git', '-C', str(ROOT), 'diff', '--exit-code', 'HEAD', '--',
                    'mobile_app', 'backend-api-runtime'], check=True,
                   capture_output=True, timeout=20)
    if (RECIPIENT.is_symlink() or not RECIPIENT.is_file() or
            digest(RECIPIENT) != RECIPIENT_SHA256):
        raise GateError('offline_visual_recipient_mismatch')


def marker(case):
    if type(case) is not int or not 0 <= case < COUNT:
        raise GateError('offline_visual_case_invalid')
    return f'AQER_VISUAL_CASE_{case:02d}'


def ready_events(log):
    """Fail closed on any malformed, failed or unknown harness event."""
    events = []
    if FAILURE in log:
        raise GateError('offline_visual_target_failure')
    for line in log.splitlines():
        if 'AQER_VISUAL ' not in line:
            continue
        raw = line.split('AQER_VISUAL ', 1)[1]
        try:
            value = json.loads(raw)
        except (ValueError, TypeError):
            raise GateError('offline_visual_unknown_log_event') from None
        if not isinstance(value, dict) or value.get('event') != 'ready':
            raise GateError('offline_visual_target_failure')
        if (set(value) != READY_FIELDS or type(value['case']) is not int or
                not 0 <= value['case'] < COUNT or
                type(value['dark']) is not bool or
                type(value['textScale']) not in (int, float) or
                (value['surface'], value['role'], value['state'], value['dark'], value['textScale'])
                != CASES[value['case']] or
                type(value['requests']) is not int or not 1 <= value['requests'] <= 1000 or
                type(value['failures']) is not int or value['failures'] != 0):
            raise GateError('offline_visual_unknown_log_event')
        if events and value['case'] < events[-1]['case']:
            raise GateError('offline_visual_case_order_invalid')
        if not events or value != events[-1]:
            events.append(value)
    return events


def bounds(value, size):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', value or '')
    if not match:
        raise GateError('offline_visual_bounds_invalid')
    left, top, right, bottom = map(int, match.groups())
    if not (0 <= left < right <= size[0] and 0 <= top < bottom <= size[1]):
        raise GateError('offline_visual_bounds_invalid')
    return (left, top, right, bottom)


def ui_state(xml, case, size):
    """Require an observed synthetic target before capturing or choosing input."""
    if len(xml.encode('utf-8')) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        raise GateError('offline_visual_xml_invalid')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise GateError('offline_visual_xml_invalid') from None
    if root.tag != 'hierarchy':
        raise GateError('offline_visual_xml_invalid')
    nodes, names, next_nodes = list(root.iter('node')), set(), []
    for node in nodes:
        if node.get('package') not in (None, '', PACKAGE):
            raise GateError('offline_visual_foreign_surface')
        values = {part.strip() for field in ('text', 'content-desc')
                  for part in node.get(field, '').splitlines() if part.strip()}
        names.update(values)
        if NEXT in values:
            next_nodes.append(node)
    if any(FAILURE in name for name in names):
        raise GateError('offline_visual_target_failure')
    if not {TARGET, BANNER, marker(case)} <= names:
        raise GateError('offline_visual_expected_surface_missing')
    if {name for name in names if name.startswith('AQER_VISUAL_CASE_')} != {marker(case)}:
        raise GateError('offline_visual_case_mismatch')
    if len(next_nodes) != 1:
        raise GateError('offline_visual_next_not_unique')
    node = next_nodes[0]
    if case == COUNT - 1:
        if node.get('enabled') != 'false':
            raise GateError('offline_visual_final_next_not_disabled')
        return None
    if (node.get('enabled') != 'true' or node.get('clickable') != 'true' or
            node.get('visible-to-user', 'true') != 'true'):
        raise GateError('offline_visual_next_not_actionable')
    left, top, right, bottom = bounds(node.get('bounds'), size)
    return ((left + right) // 2, (top + bottom) // 2)


def verified_frame(xml, log, case, size):
    tap = ui_state(xml, case, size)
    events = ready_events(log)
    if not events or events[-1]['case'] != case:
        raise GateError('offline_visual_ready_not_observed')
    # The fixed journey must have reached every prior case, with no jump/wrap.
    if list(dict.fromkeys(event['case'] for event in events)) != list(range(case + 1)):
        raise GateError('offline_visual_case_order_invalid')
    return tap, events[-1]


def verify_archive(apk):
    if apk.is_symlink() or not apk.is_file():
        raise GateError('offline_visual_apk_missing')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise GateError('offline_visual_apk_invalid')
        libs = [name for name in names if name.endswith('/libapp.so')]
        if 'lib/x86_64/libapp.so' not in libs or any(
                TARGET.encode() not in archive.read(name) or BANNER.encode() not in archive.read(name)
                for name in libs):
            raise GateError('offline_visual_compiled_target_required')


def verify_badging(value):
    if (re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", value, re.M)
            == []):
        raise GateError('offline_visual_apk_identity_invalid')
    packages = re.findall(r"^package: name='([^']+)' versionCode='([0-9]+)'", value, re.M)
    if (len(packages) != 1 or packages[0][0] != PACKAGE or
            re.findall(r"^targetSdkVersion:'([0-9]+)'$", value, re.M) != ['36'] or
            re.findall(r"^sdkVersion:'([0-9]+)'$", value, re.M) != ['23'] or
            'application-debuggable' in value):
        raise GateError('offline_visual_apk_identity_invalid')
    return int(packages[0][1])


class Device:
    def __init__(self, serial, deadline):
        if not re.fullmatch(r'emulator-[0-9]{4,5}', serial):
            raise GateError('offline_visual_emulator_serial_required')
        self.serial, self.deadline = serial, deadline

    def command(self, argv, binary=False, check=True, timeout=20):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise GateError('offline_visual_timeout')
        result = subprocess.run([str(arg) for arg in argv], check=check,
                                capture_output=True, timeout=min(timeout, remaining))
        return result.stdout if binary else result.stdout.decode('utf-8', errors='strict').strip()

    def adb(self, *args, **kwargs):
        return self.command(['adb', '-s', self.serial, *args], **kwargs)

    def xml(self):
        path = '/sdcard/aqer-offline-visual-window.xml'
        self.adb('shell', 'rm', '-f', path)
        self.adb('shell', 'uiautomator', 'dump', '--compressed', path)
        return self.adb('exec-out', 'cat', path)

    def log(self):
        return self.adb('logcat', '-d', '-v', 'brief')

    def wait_frame(self, case, size):
        waitable = {'offline_visual_expected_surface_missing', 'offline_visual_ready_not_observed'}
        while time.monotonic() < self.deadline:
            log = self.log()
            ready_events(log)  # Failures must not be retried as loading states.
            xml = self.xml()
            try:
                tap, event = verified_frame(xml, log, case, size)
                return xml, tap, event
            except GateError as error:
                if str(error) not in waitable:
                    raise
            time.sleep(.25)
        raise GateError('offline_visual_timeout')

    def offline(self):
        self.adb('shell', 'svc', 'wifi', 'disable')
        self.adb('shell', 'svc', 'data', 'disable')
        self.adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
        for _ in range(15):
            state = [self.adb('shell', 'settings', 'get', 'global', name)
                     for name in ('airplane_mode_on', 'wifi_on', 'mobile_data')]
            connection = self.adb('shell', 'dumpsys', 'connectivity')
            if state == ['1', '0', '0'] and re.search(r'Active default network:\s*none\b', connection):
                return
            time.sleep(.25)
        raise GateError('offline_visual_network_not_disabled')


def safe_receipt(receipt):
    expected = {'schema', 'source_sha', 'product_trees', 'run_id', 'package',
                'version_code', 'target_marker', 'apk_sha256', 'api_level',
                'network_disabled', 'live_authentication', 'display_size_px'}
    if (set(receipt) != expected or receipt['schema'] != 1 or
            not re.fullmatch('[a-f0-9]{40}', str(receipt['source_sha'])) or
            receipt['product_trees'] != TREES or
            not re.fullmatch('[1-9][0-9]*', str(receipt['run_id'])) or
            receipt['package'] != PACKAGE or type(receipt['version_code']) is not int or
            not 1 <= receipt['version_code'] <= 2100000000 or
            receipt['target_marker'] != TARGET or
            not re.fullmatch('[a-f0-9]{64}', str(receipt['apk_sha256'])) or
            receipt['api_level'] != 36 or type(receipt['display_size_px']) is not list or
            any(type(value) is not int for value in receipt['display_size_px']) or
            receipt['display_size_px'] not in ([1080, 1920], [840, 1493]) or
            receipt['network_disabled'] is not True or
            receipt['live_authentication'] is not False):
        raise GateError('offline_visual_public_receipt_invalid')


def seal(private, output, receipt, encryptor=encrypt):
    """The export directory is exclusive and contains no plaintext or APK."""
    safe_receipt(receipt)
    files = sorted(private.iterdir())
    allowed = {'MANIFEST.json'} | {f'case-{case:02d}.{suffix}'
              for case in range(COUNT) for suffix in ('png', 'xml', 'json')}
    if {path.name for path in files} != allowed or any(
            path.is_symlink() or not path.is_file() for path in files):
        raise GateError('offline_visual_private_export_scope_invalid')
    output.mkdir(mode=0o700)
    try:
        archive = private.parent / (private.name + '.zip')
        try:
            with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as target:
                for path in files:
                    target.write(path, path.name)
            archive.chmod(0o600)
            encrypted = encryptor(archive, output / 'visual.cms', RECIPIENT)
        finally:
            archive.unlink(missing_ok=True)
        public = {**receipt, 'encrypted_evidence': encrypted,
                  'recipient_sha256': RECIPIENT_SHA256,
                  'frame_count': COUNT, 'plaintext_exported': False,
                  'apk_exported': False, 'phase23_accepted': False, 'scope': SCOPE}
        (output / 'PUBLIC_RECEIPT.json').write_text(json.dumps(public, indent=2) + '\n')
        if {path.name for path in output.iterdir()} != {'visual.cms', 'PUBLIC_RECEIPT.json'}:
            raise GateError('offline_visual_public_export_scope_invalid')
        return public
    except BaseException:
        shutil.rmtree(output)
        raise


def collect(args, env=os.environ):
    global STAGE
    STAGE = 'context'
    context(env)
    deadline = time.monotonic() + args.max_seconds
    device = Device(args.serial, deadline)
    apk = Path(args.apk).absolute()
    output = ROOT / 'phase23-offline-visual-sealed'
    if output.exists() or output.is_symlink():
        raise GateError('offline_visual_fresh_output_required')
    STAGE = 'apk_archive'
    verify_archive(apk)
    STAGE = 'apk_tools'
    bt = Path(env['ANDROID_HOME']) / 'build-tools/36.0.0'
    device.command([bt / 'apksigner', 'verify', apk])
    version = verify_badging(device.command([bt / 'aapt', 'dump', 'badging', apk]))
    STAGE = 'emulator_preflight'
    if (device.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
            device.adb('shell', 'getprop', 'ro.build.version.sdk') != '36'):
        raise GateError('offline_visual_api36_emulator_required')
    if device.adb('shell', 'pm', 'path', PACKAGE, check=False):
        raise GateError('offline_visual_fresh_emulator_required')
    device.offline()
    STAGE = 'install_identity'
    device.adb('install', '--no-streaming', str(apk), timeout=180)
    installed = device.adb('shell', 'pm', 'path', PACKAGE)
    if not re.fullmatch(r'package:/data/app/[A-Za-z0-9_./=+~-]+/base\.apk', installed):
        raise GateError('offline_visual_installed_path_invalid')
    if hashlib.sha256(device.adb('exec-out', 'cat', installed[8:], binary=True, timeout=60)).hexdigest() != digest(apk):
        raise GateError('offline_visual_installed_target_mismatch')
    raw_size = device.adb('shell', 'wm', 'size')
    sizes = re.findall(r'(?:Physical|Override) size: (\d+)x(\d+)', raw_size)
    if not sizes:
        raise GateError('offline_visual_display_size_invalid')
    size = tuple(map(int, sizes[-1]))
    if size not in ((1080, 1920), (840, 1493)):
        raise GateError('offline_visual_display_size_invalid')
    # TemporaryDirectory removes every plaintext file even on failure.
    with tempfile.TemporaryDirectory(prefix='phase23-offline-visual-', dir=env['RUNNER_TEMP']) as directory:
        private = Path(directory) / 'frames'
        private.mkdir(mode=0o700)
        try:
            STAGE = 'capture'
            device.adb('shell', 'am', 'force-stop', PACKAGE)
            if device.adb('shell', 'pm', 'clear', PACKAGE) != 'Success':
                raise GateError('offline_visual_clear_failed')
            device.adb('logcat', '-c')
            device.adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/com.example.real_estate_mobile.MainActivity')
            frames = []
            for case in range(COUNT):
                xml, tap, event = device.wait_frame(case, size)
                png = device.adb('exec-out', 'screencap', '-p', binary=True)
                if (len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or
                        struct.unpack('>II', png[16:24]) != size):
                    raise GateError('offline_visual_screenshot_invalid')
                after_xml, after_log = device.xml(), device.log()
                after_tap, after_event = verified_frame(after_xml, after_log, case, size)
                if tap != after_tap or event != after_event:
                    raise GateError('offline_visual_capture_state_changed')
                prefix = private / f'case-{case:02d}'
                prefix.with_suffix('.png').write_bytes(png)
                prefix.with_suffix('.xml').write_text(xml, encoding='utf-8')
                record = {**event, 'case_marker': marker(case), 'synthetic_offline': True,
                          'png_sha256': hashlib.sha256(png).hexdigest(),
                          'xml_sha256': hashlib.sha256(xml.encode()).hexdigest()}
                prefix.with_suffix('.json').write_text(json.dumps(record, indent=2) + '\n')
                frames.append(record)
                if tap is not None:
                    # Coordinates derive exclusively from the fresh XML above.
                    device.adb('shell', 'input', 'tap', str(tap[0]), str(tap[1]))
            device.offline()
            ready_events(device.log())
            receipt = {'schema': 1, 'source_sha': env['GITHUB_SHA'], 'product_trees': TREES,
                       'run_id': env['GITHUB_RUN_ID'], 'package': PACKAGE, 'version_code': version,
                       'target_marker': TARGET, 'apk_sha256': digest(apk), 'api_level': 36,
                       'display_size_px': list(size),
                       'network_disabled': True, 'live_authentication': False}
            (private / 'MANIFEST.json').write_text(json.dumps({**receipt, 'frames': frames, 'scope': SCOPE}, indent=2) + '\n')
            STAGE = 'seal'
            seal(private, output, receipt)
        finally:
            # A bounded cleanup uses no UI input and never prints device output.
            subprocess.run(['adb', '-s', args.serial, 'shell', 'am', 'force-stop', PACKAGE],
                           capture_output=True, timeout=5, check=False)
    print('AQER_OFFLINE_VISUAL_SEALED_14_SYNTHETIC_FRAMES')


def failure_message(error):
    return (str(error) if isinstance(error, GateError) else
            f'offline_visual_collection_failed stage={STAGE} exception={type(error).__name__}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--max-seconds', type=int, default=300)
    args = parser.parse_args()
    if not 30 <= args.max_seconds <= 300:
        raise GateError('offline_visual_duration_invalid')
    def timed_out(_signum, _frame):
        raise GateError('offline_visual_timeout')
    signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(args.max_seconds)
    try:
        collect(args)
    finally:
        signal.alarm(0)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(failure_message(error), file=sys.stderr)
        raise SystemExit(1) from None
