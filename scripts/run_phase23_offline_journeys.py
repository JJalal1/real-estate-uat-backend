#!/usr/bin/env python3
"""Bounded synthetic Native recent-history persistence and actual role-shell journeys.

No live login, remote business writes, ordinary APK delivery or production claim.
Only reviewed synthetic screenshots, XML and numeric/enum proofs are encrypted.
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

from phase23_preflight import GateError
from phase23_visual_revision import TREES, guard
from prepare_phase1_close import encrypt
from run_phase23_offline_visual import Device, bounds, digest, verify_badging

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.aqer.yemen.uat'
ACTIVITY = PACKAGE + '/com.example.real_estate_mobile.MainActivity'
TARGET = 'AQER_OFFLINE_JOURNEYS_TARGET_V1'
FULL_TARGET = TARGET
TAIL_TARGET = 'AQER_OFFLINE_JOURNEYS_TAIL9_V1'
START_STAGE = 0
BANNER = 'SYNTHETIC OFFLINE'
NEXT = 'AQER_JOURNEY_NEXT'
FAILURE = 'AQER_JOURNEY_FAILURE'
COUNT = 16
DEFAULT_SIZE = (1080, 1920)
COMPACT_SIZE = (840, 1493)
FAVORITES_HELPER = 'اضغط على رمز القلب في أي عقار ليظهر هنا ويظل محفوظاً في حسابك.'
RECIPIENT = ROOT / 'scripts/phase23_recipient.pem'
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
SCOPE = ('Synthetic offline Native recent-store persistence and actual AppShell navigation only; '
         'one Android custom-scheme message VIEW intent; no HTTPS App Links, live authentication, '
         'backend authorization, production or owner APK acceptance; compact Favorites forced-scroll '
         'supplement requires human pixel review and does not infer glyph visibility from AX bounds')
FIELDS = {'event', 'stage', 'role', 'scope', 'recent_ids', 'file_exists', 'file_bytes',
          'restart_count', 'requests', 'failures'}
ROLES = [('regular', 'A')]*6 + [('regular', 'B'), ('guest', 'guest'), ('regular', 'A'),
                                  ('broker', 'verified'), ('broker', 'verified'),
                                  ('broker', 'pending'), ('broker', 'pending'), ('regular', 'A'), ('regular', 'A'), ('regular', 'A')]
RECENTS = [[], [9001], [9002, 9001], [9001, 9002], [9001, 9002], [9001, 9002], [], [],
           [9001, 9002], [], [], [], [], [9001, 9002], [9001, 9002], [9001, 9002]]
TITLES = {key: f'عقار اصطناعي للاختبار {key}' for key in (9001, 9002)}
BROKER_TABS = {'الرئيسية', 'عملي', 'العملاء', 'حسابي'}
REGULAR_TABS = {'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'}
REASONS = {'history_mismatch', 'file_persistence_mismatch', 'recent_ui_mismatch',
           'shell_ui_mismatch', 'workspace_anchor_missing', 'pending_gate_missing',
           'required_control_missing', 'message_link_ui_mismatch', 'favorites_supplement_missing',
           'ready_state_timeout'}
WAITABLE = {'offline_journey_expected_surface_missing', 'offline_journey_ready_missing',
            'offline_journey_next_state_invalid'}
STAGE = 'startup'


class CoverageIncomplete(GateError):
    def __init__(self, reason, stage):
        if reason not in REASONS or type(stage) is not int or not 0 <= stage < COUNT:
            raise GateError('offline_journey_partial_reason_invalid')
        self.reason, self.stage = reason, stage
        super().__init__(f'offline_journey_coverage_incomplete reason={reason} stage={stage:02d}')


class ReadyTimeout(CoverageIncomplete):
    def __init__(self, stage, last_ready_stage, wait_reason):
        if (type(last_ready_stage) is not int or not -1 <= last_ready_stage <= stage or
                wait_reason not in WAITABLE):
            raise GateError('offline_journey_timeout_diagnostic_invalid')
        super().__init__('ready_state_timeout', stage)
        self.last_ready_stage, self.wait_reason = last_ready_stage, wait_reason

    def __str__(self):
        return (super().__str__() + f' last_ready_stage={self.last_ready_stage}'
                + f' wait_reason={self.wait_reason}')


def marker(stage):
    if type(stage) is not int or not 0 <= stage < COUNT:
        raise GateError('offline_journey_stage_invalid')
    return f'AQER_JOURNEY_STAGE_{stage:02d}'


def context(env):
    global START_STAGE, TARGET
    guard(env)
    if env.get('PHASE23_OFFLINE_JOURNEYS') != 'true':
        raise GateError('explicit_offline_journey_context_required')
    if env.get('PHASE23_JOURNEYS_TAIL_ONLY', 'false') not in ('true', 'false'):
        raise GateError('offline_journey_execution_mode_invalid')
    START_STAGE = 9 if env.get('PHASE23_JOURNEYS_TAIL_ONLY') == 'true' else 0
    TARGET = TAIL_TARGET if START_STAGE == 9 else FULL_TARGET
    forbidden = ('AQER_PHASE1_TEST_ACCESS_JSON', 'AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION',
                 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', 'AQER_UAT_KEYSTORE_BASE64',
                 'AQER_RELEASE_STORE_PASSWORD', 'AQER_RELEASE_KEY_PASSWORD',
                 'AQER_UAT_KEYSTORE_PASSWORD', 'AQER_UAT_KEY_PASSWORD')
    if any(env.get(key) for key in forbidden):
        raise GateError('offline_journey_secret_environment_refused')
    if RECIPIENT.is_symlink() or digest(RECIPIENT) != RECIPIENT_SHA256:
        raise GateError('offline_journey_recipient_mismatch')


def verify_archive(apk):
    if apk.is_symlink() or not apk.is_file():
        raise GateError('offline_journey_apk_required')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        libraries = [name for name in names if name.endswith('/libapp.so')]
        if (len(names) != len(set(names)) or archive.testzip() is not None or
                libraries != ['lib/x86_64/libapp.so']):
            raise GateError('offline_journey_x86_64_target_required')
        compiled = archive.read(libraries[0])
        if TARGET.encode() not in compiled or BANNER.encode() not in compiled:
            raise GateError('offline_journey_compiled_marker_required')


def proof_events(log):
    if FAILURE in log:
        raise GateError('offline_journey_target_failure')
    result = []
    for line in log.splitlines():
        if 'AQER_JOURNEY ' not in line:
            continue
        try:
            value = json.loads(line.split('AQER_JOURNEY ', 1)[1])
        except (ValueError, TypeError):
            raise GateError('offline_journey_unknown_event') from None
        if not isinstance(value, dict) or value.get('event') != 'ready':
            raise GateError('offline_journey_target_failure')
        if (set(value) != FIELDS or type(value['stage']) is not int or not 0 <= value['stage'] < COUNT or
                value['role'] not in {'regular', 'broker', 'guest'} or
                value['scope'] not in {'A', 'B', 'guest', 'verified', 'pending'} or
                type(value['recent_ids']) is not list or len(value['recent_ids']) > 30 or
                any(type(number) is not int or number not in TITLES for number in value['recent_ids']) or
                type(value['file_exists']) is not bool or type(value['file_bytes']) is not int or
                not 0 <= value['file_bytes'] <= 1_000_000 or
                type(value['restart_count']) is not int or value['restart_count'] not in (0, 1) or
                type(value['requests']) is not int or not 0 <= value['requests'] <= 1000 or
                type(value['failures']) is not int or value['failures'] != 0):
            raise GateError('offline_journey_unknown_event')
        if result and value['stage'] < result[-1]['stage']:
            raise GateError('offline_journey_stage_regressed')
        if not result or value != result[-1]:
            result.append(value)
    return result


def labels(node):
    # Android wraps LTR semantics inside an Arabic app with directional format
    # marks. These are presentation controls, never part of a control identity.
    # Keep all actual text and the strict unique-node/bounds checks unchanged.
    formatting = dict.fromkeys(map(ord, '\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069'))
    return {part.translate(formatting).strip() for field in ('text', 'content-desc')
            for part in node.get(field, '').splitlines() if part.strip()}


def ui_guard(xml, stage, size, allow_busy=False):
    if len(xml.encode()) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        raise GateError('offline_journey_xml_invalid')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise GateError('offline_journey_xml_invalid') from None
    if root.tag != 'hierarchy':
        raise GateError('offline_journey_xml_invalid')
    nodes = list(root.iter('node'))
    if any(node.get('package') not in (None, '', PACKAGE) for node in nodes):
        raise GateError('offline_journey_foreign_surface')
    names = set().union(*(labels(node) for node in nodes)) if nodes else set()
    if any(FAILURE in name for name in names):
        raise GateError('offline_journey_target_failure')
    if not {TARGET, BANNER, marker(stage)} <= names:
        raise GateError('offline_journey_expected_surface_missing')
    if {name for name in names if name.startswith('AQER_JOURNEY_STAGE_')} != {marker(stage)}:
        raise GateError('offline_journey_stage_mismatch')
    controls = [node for node in nodes if NEXT in labels(node)]
    if len(controls) != 1:
        raise GateError('offline_journey_next_not_unique')
    next_node = controls[0]
    box = bounds(next_node.get('bounds'), size)
    if box[3] > size[1] * .3 or next_node.get('visible-to-user', 'true') != 'true':
        raise GateError('offline_journey_next_bounds_invalid')
    if next_node.get('enabled') not in ('false', 'true'):
        raise GateError('offline_journey_next_state_invalid')
    if not allow_busy and next_node.get('enabled') != ('false' if stage in (4, 13, 15) else 'true'):
        raise GateError('offline_journey_next_state_invalid')
    return nodes


def ready_for(xml, log, stage, size):
    nodes = ui_guard(xml, stage, size)
    events = proof_events(log)
    if not events or events[-1]['stage'] != stage:
        raise GateError('offline_journey_ready_missing')
    if list(dict.fromkeys(event['stage'] for event in events)) != list(range(START_STAGE, stage + 1)):
        raise GateError('offline_journey_sequence_incomplete')
    return nodes, events[-1]


def visible_nodes(nodes, text, size, footer=False):
    result = []
    for node in nodes:
        if text not in labels(node) or node.get('visible-to-user', 'true') != 'true':
            continue
        try:
            box = bounds(node.get('bounds'), size)
        except GateError:
            continue
        if footer and box[1] < size[1] * .75:
            continue
        result.append((node, box))
    return result


def footer_state(nodes, size):
    names = set()
    selected = set()
    for label in BROKER_TABS | REGULAR_TABS:
        matches = visible_nodes(nodes, label, size, footer=True)
        if len(matches) == 1:
            node, _box = matches[0]
            names.add(label)
            if node.get('selected') == 'true':
                selected.add(label)
    return names, selected


def assert_evidence(nodes, proof, stage, size, restart_proof=None, after_work=False, message_before=None, after_scroll=False):
    # Tail mode starts with a fresh AVD and never fabricates the already-proven
    # property visits. Every actor scope observed in this tail must be empty.
    expected_recents = [] if START_STAGE == 9 else RECENTS[stage]
    expected_restarts = 0 if START_STAGE == 9 or stage <= 4 else 1
    if ((proof['role'], proof['scope']) != ROLES[stage] or proof['recent_ids'] != expected_recents or
            proof['restart_count'] != expected_restarts or
            proof['file_exists'] != bool(expected_recents) or
            (bool(proof['file_bytes']) != bool(expected_recents))):
        raise CoverageIncomplete('history_mismatch', stage)
    if stage == 5 and (not restart_proof or proof['file_bytes'] != restart_proof['file_bytes'] or
                       proof['recent_ids'] != restart_proof['recent_ids']):
        raise CoverageIncomplete('file_persistence_mismatch', stage)
    if stage in (0, 4, 5, 6, 7, 8):
        if not visible_nodes(nodes, 'شوهد مؤخرًا', size):
            raise CoverageIncomplete('recent_ui_mismatch', stage)
        if not RECENTS[stage]:
            if (not visible_nodes(nodes, 'ما شاهدت عقارات بعد', size) or
                    any(visible_nodes(nodes, text, size) for text in TITLES.values())):
                raise CoverageIncomplete('recent_ui_mismatch', stage)
        else:
            positions = []
            for number in RECENTS[stage]:
                matches = visible_nodes(nodes, TITLES[number], size)
                if len(matches) != 1:
                    raise CoverageIncomplete('recent_ui_mismatch', stage)
                positions.append(matches[0][1][1])
            if positions != sorted(positions) or len(set(positions)) != len(positions):
                raise CoverageIncomplete('recent_ui_mismatch', stage)
    if stage in (1, 2, 3):
        number = 9002 if stage == 2 else 9001
        if not visible_nodes(nodes, TITLES[number], size):
            raise CoverageIncomplete('recent_ui_mismatch', stage)
    if 9 <= stage <= 13:
        names, selected = footer_state(nodes, size)
        expected = REGULAR_TABS if stage == 13 else BROKER_TABS
        selected_label = 'العقارات' if stage == 13 else ('عملي' if stage in (10, 12) or after_work else 'الرئيسية')
        if names != expected or selected != {selected_label}:
            raise CoverageIncomplete('shell_ui_mismatch', stage)
        if stage == 10 or (stage == 9 and after_work):
            if not all(visible_nodes(nodes, name, size) for name in ('لوحة الدلال', 'يحتاج إجراء منك')):
                raise CoverageIncomplete('workspace_anchor_missing', stage)
        if stage == 12 or (stage == 11 and after_work):
            if (not visible_nodes(nodes, 'أدوات الدلال بعد اعتماد التوثيق', size) or
                    visible_nodes(nodes, 'لوحة الدلال', size)):
                raise CoverageIncomplete('pending_gate_missing', stage)
    if stage == 14:
        if (not message_before or proof['requests'] <= message_before['requests'] or
                not all(visible_nodes(nodes, name, size) for name in
                        ('محادثة اصطناعية للاختبار', 'رسالة اصطناعية عبر رابط أندرويد'))):
            raise CoverageIncomplete('message_link_ui_mismatch', stage)
    if stage == 15:
        required = ('المفضلة', FAVORITES_HELPER) if after_scroll else ('المفضلة', 'لا توجد عقارات محفوظة', FAVORITES_HELPER)
        if size != COMPACT_SIZE or not all(visible_nodes(nodes, name, size) for name in required):
            raise CoverageIncomplete('favorites_supplement_missing', stage)


def input_point(xml, log, stage, size, label):
    nodes, _proof = ready_for(xml, log, stage, size)
    if label not in (NEXT, 'عملي') or (label == 'عملي' and stage not in (9, 11)):
        raise GateError('offline_journey_input_refused')
    if label == NEXT and stage in (4, 13, 15):
        raise GateError('offline_journey_input_refused')
    candidates = visible_nodes(nodes, label, size, footer=label == 'عملي')
    if len(candidates) != 1:
        raise CoverageIncomplete('required_control_missing', stage)
    node, (left, top, right, bottom) = candidates[0]
    if node.get('enabled') != 'true':
        raise CoverageIncomplete('required_control_missing', stage)
    if label == 'عملي':
        # The original reviewed AppNavigationBar exposes a semantic Button but
        # its excluded child GestureDetector owns the physical touch callback.
        # API36 consequently reports clickable=false. Permit only this exact
        # observed tight footer button and prove the resulting real page later;
        # this is not an accessibility-action or TalkBack acceptance claim.
        names, selected = footer_state(nodes, size)
        if (names != BROKER_TABS or selected != {'الرئيسية'} or
                node.get('class') != 'android.widget.Button' or
                node.get('selected') != 'false' or
                right-left > size[0]*.35 or bottom-top > size[1]*.16 or
                bottom > size[1]*.98):
            raise CoverageIncomplete('required_control_missing', stage)
    elif node.get('clickable') != 'true':
        raise CoverageIncomplete('required_control_missing', stage)
    return ((left + right)//2, (top + bottom)//2)


def supplement_scroll(xml, log, size):
    """One forced upward drag in the observed real product scrollable viewport.

    Merged AX text bounds do not prove individual glyph visibility. Always retain
    both images for human review, even when the helper is already in the XML.
    """
    if size != COMPACT_SIZE:
        raise GateError('offline_journey_supplement_size_invalid')
    nodes, _proof = ready_for(xml, log, 15, size)
    header_bottom = max(bounds(n.get('bounds'), size)[3] for n in nodes if NEXT in labels(n))
    wrappers = [node for node in nodes if 'AQER_JOURNEY_SCROLL' in labels(node)]
    if len(wrappers) != 1:
        raise CoverageIncomplete('favorites_supplement_missing', 15)
    wrapper = bounds(wrappers[0].get('bounds'), size)
    candidates = set()
    for node in nodes:
        if node.get('scrollable') != 'true' or node.get('enabled') != 'true' or node.get('visible-to-user', 'true') != 'true':
            continue
        box = bounds(node.get('bounds'), size)
        left, top, right, bottom = box
        if (top >= header_bottom and right-left >= size[0]*.5 and bottom-top >= size[1]*.15 and
                left >= wrapper[0] and top >= wrapper[1] and right <= wrapper[2] and bottom <= wrapper[3]):
            candidates.add(box)
    if not candidates:
        raise CoverageIncomplete('favorites_supplement_missing', 15)
    # Prefer the inner actual viewport when ListView and AppEmptyState nest.
    left, top, right, bottom = min(candidates, key=lambda b: ((b[2]-b[0])*(b[3]-b[1]), b))
    x, height = (left+right)//2, bottom-top
    return x, top+height*4//5, x, top+height//5


class JourneyDevice(Device):
    def wait_ready(self, stage, size, after_work=False):
        deadline = min(self.deadline, time.monotonic() + 35)
        last = None
        last_ready_stage, wait_reason = -1, 'offline_journey_ready_missing'
        while time.monotonic() < deadline:
            log = self.log()
            events = proof_events(log)
            last_ready_stage = events[-1]['stage'] if events else -1
            xml = self.xml()
            try:
                nodes, proof = ready_for(xml, log, stage, size)
                if after_work:
                    expected = ('لوحة الدلال', 'يحتاج إجراء منك') if stage == 9 else ('أدوات الدلال بعد اعتماد التوثيق',)
                    last = (xml, nodes, proof)
                    if not all(visible_nodes(nodes, label, size) for label in expected):
                        time.sleep(.25)
                        continue
                return xml, nodes, proof
            except GateError as error:
                # setState precedes the ready log, but accessibility may still
                # expose one busy frame with a disabled Next control.
                if str(error) not in WAITABLE:
                    raise
                wait_reason = str(error)
            time.sleep(.25)
        if last is not None:
            return last  # Safe diagnostic screenshot; acceptance check then fails.
        raise ReadyTimeout(stage, last_ready_stage, wait_reason)

    def restart_preserving_files(self):
        self.adb('shell', 'am', 'force-stop', PACKAGE)
        self.adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)

    def open_message_link(self):
        self.adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW',
                 '-d', 'realestate://app/messages/9010', '-p', PACKAGE)


def capture(device, private, frames, stage, size, restart_proof=None, after_work=False, message_before=None, after_scroll=False):
    xml, nodes, proof = device.wait_ready(stage, size, after_work)
    png = device.adb('exec-out', 'screencap', '-p', binary=True)
    if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', png[16:24]) != size:
        raise GateError('offline_journey_screenshot_invalid')
    after_xml, log = device.xml(), device.log()
    after_nodes, after_proof = ready_for(after_xml, log, stage, size)
    if after_proof != proof:
        raise GateError('offline_journey_capture_proof_changed')
    name = f'stage-{stage:02d}' + ('-after-work' if after_work else '-after-scroll' if after_scroll else '')
    row = {'frame': name, 'stage': stage, 'after_work': after_work, 'accepted': False,
           'after_scroll': after_scroll, 'display_size_px': list(size),
           'manual_pixel_review_required': stage == 15,
           'proof': proof, 'png_sha256': hashlib.sha256(png).hexdigest(),
           'xml_sha256': hashlib.sha256(xml.encode()).hexdigest()}
    (private/(name+'.png')).write_bytes(png)
    (private/(name+'.xml')).write_text(xml, encoding='utf-8')
    (private/(name+'.json')).write_text(json.dumps(row, ensure_ascii=False, indent=2)+'\n')
    frames.append(row)
    assert_evidence(nodes, proof, stage, size, restart_proof, after_work, message_before, after_scroll)
    assert_evidence(after_nodes, after_proof, stage, size, restart_proof, after_work, message_before, after_scroll)
    row['accepted'] = True
    (private/(name+'.json')).write_text(json.dumps(row, ensure_ascii=False, indent=2)+'\n')
    return after_xml, proof


def diagnostic_ui(xml):
    if len(xml.encode()) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        raise GateError('offline_journey_xml_invalid')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise GateError('offline_journey_xml_invalid') from None
    nodes = list(root.iter('node'))
    if root.tag != 'hierarchy' or not nodes or len(nodes) > 10000:
        raise GateError('offline_journey_xml_invalid')
    packages = {node.get('package') for node in nodes if node.get('package')}
    if packages != {PACKAGE}:
        raise GateError('offline_journey_foreign_surface')
    names = set().union(*(labels(node) for node in nodes))
    if any(FAILURE in name for name in names):
        raise GateError('offline_journey_target_failure')
    structure = [{key: node.get(key) for key in ('class', 'bounds', 'enabled', 'clickable', 'scrollable')}
                 for node in nodes]
    next_nodes = [node for node in nodes if NEXT in labels(node)]
    next_enabled = (next_nodes[0].get('enabled', 'missing') if len(next_nodes) == 1
                    else 'missing' if not next_nodes else 'ambiguous')
    if next_enabled not in ('true', 'false', 'missing', 'ambiguous'):
        next_enabled = 'missing'
    return names, {'has_target': TARGET in names, 'has_banner': BANNER in names,
                   'has_next': NEXT in names, 'node_count': len(nodes),
                   'next_enabled': next_enabled,
                   'observed_stages': [stage for stage in range(COUNT) if marker(stage) in names],
                   'structure_sha256': hashlib.sha256(json.dumps(structure, sort_keys=True).encode()).hexdigest()}


def diagnostic_activity(device):
    resumed = re.findall(r'(?:topResumedActivity|mResumedActivity)\s*[:=]\s*ActivityRecord\{[^}\n]*?\s('
                         + re.escape(PACKAGE) + r'/[A-Za-z0-9_.$]+)',
                         device.adb('shell', 'dumpsys', 'activity', 'activities'))
    if not resumed or set(resumed) != {ACTIVITY}:
        raise GateError('offline_journey_diagnostic_activity_unverified')


def timeout_diagnostic(device, private, failure, size, installed_apk_sha256=None):
    """Save only enum diagnostics, and pixels only for this exact synthetic target.

    This is not a passing checkpoint and never relaxes normal readiness/input
    checks. Unknown or foreign surfaces, target failures and network faults still
    stop without a new screenshot. Previous verified checkpoints are retained.
    """
    if not isinstance(failure, ReadyTimeout):
        raise GateError('offline_journey_timeout_diagnostic_invalid')
    diagnostic = {'stage': failure.stage, 'last_ready_stage': failure.last_ready_stage,
                  'wait_reason': failure.wait_reason, 'target_frame_verified': False,
                  'png_sha256': None, 'xml_sha256': None, 'display_size_px': list(size),
                  'capture_identity': None}
    xml, log = device.xml(), device.log()
    events = proof_events(log)
    names, structure = diagnostic_ui(xml)
    diagnostic.update(structure, ready_count=len(events))
    capture_identity = None
    try:
        ui_guard(xml, failure.stage, size, allow_busy=True)
    except GateError as error:
        if str(error) != 'offline_journey_expected_surface_missing':
            raise
        # Exact source + installed APK were already checked on a fresh isolated
        # AVD before launch. Reverify that identity and resumed activity here so
        # a missing accessibility header cannot suppress useful synthetic-only
        # diagnostics. This permission never applies to normal input/readiness.
        if installed_apk_sha256 is not None:
            if not re.fullmatch('[0-9a-f]{64}', installed_apk_sha256):
                raise GateError('offline_journey_diagnostic_apk_unverified')
            diagnostic_activity(device)
            installed = device.adb('shell', 'pm', 'path', PACKAGE)
            if not re.fullmatch(r'package:/data/app/[A-Za-z0-9_./=+~-]+/base\.apk', installed):
                raise GateError('offline_journey_installed_path_invalid')
            if hashlib.sha256(device.adb('exec-out', 'cat', installed[8:], binary=True, timeout=60)).hexdigest() != installed_apk_sha256:
                raise GateError('offline_journey_diagnostic_apk_unverified')
            capture_identity = 'fresh_synthetic_apk_activity'
    else:
        capture_identity = 'target_markers'
    if capture_identity is not None:
        png = device.adb('exec-out', 'screencap', '-p', binary=True)
        if (len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or
                struct.unpack('>II', png[16:24]) != size):
            raise GateError('offline_journey_screenshot_invalid')
        after = device.xml()
        diagnostic_ui(after)
        if capture_identity == 'target_markers':
            ui_guard(after, failure.stage, size, allow_busy=True)
        else:
            diagnostic_activity(device)
        proof_events(device.log())
        diagnostic.update(target_frame_verified=True, capture_identity=capture_identity,
                          png_sha256=hashlib.sha256(png).hexdigest(),
                          xml_sha256=hashlib.sha256(xml.encode()).hexdigest())
        (private/'DIAGNOSTIC.png').write_bytes(png)
        (private/'DIAGNOSTIC.xml').write_text(xml, encoding='utf-8')
    (private/'DIAGNOSTIC.json').write_text(json.dumps(diagnostic, indent=2)+'\n')
    return diagnostic


def export(private, output, identity, frames, restart_count, failure=None, encryptor=encrypt, diagnostic=None):
    allowed_identity = {'source_sha', 'run_id', 'product_trees', 'package', 'version_code', 'apk_sha256'}
    if (set(identity) != allowed_identity or identity['product_trees'] != TREES or
            identity['package'] != PACKAGE or not re.fullmatch('[a-f0-9]{40}', identity['source_sha']) or
            not re.fullmatch('[1-9][0-9]*', identity['run_id']) or
            type(identity['version_code']) is not int or not 1 <= identity['version_code'] <= 2100000000 or
            not re.fullmatch('[a-f0-9]{64}', identity['apk_sha256']) or
            type(restart_count) is not int or restart_count not in (0, 1)):
        raise GateError('offline_journey_public_identity_invalid')
    if failure is not None and not isinstance(failure, CoverageIncomplete):
        raise GateError('offline_journey_partial_failure_refused')
    names = [row['frame'] for row in frames]
    expected = [f'stage-{stage:02d}' + suffix for stage in range(START_STAGE, COUNT)
                for suffix in (('', '-after-work') if stage in (9, 11) else ('', '-after-scroll') if stage == 15 else ('',))]
    if ((not names and diagnostic is None) or names != expected[:len(names)] or len(names) != len(set(names)) or
            any(type(row.get('accepted')) is not bool or type(row.get('stage')) is not int or
                type(row.get('after_work')) is not bool or
                type(row.get('after_scroll')) is not bool or
                row.get('display_size_px') != list(COMPACT_SIZE if row['stage'] == 15 else DEFAULT_SIZE) or
                row['frame'] != f"stage-{row['stage']:02d}" + ('-after-work' if row['after_work'] else '-after-scroll' if row['after_scroll'] else '')
                for row in frames)):
        raise GateError('offline_journey_frame_sequence_invalid')
    if failure is None and (names != expected or not all(row['accepted'] for row in frames) or
                            restart_count != (0 if START_STAGE == 9 else 1)):
        raise GateError('offline_journey_complete_proof_missing')
    if diagnostic is None:
        if failure is not None and (failure.stage != frames[-1]['stage'] or
                                   any(not row['accepted'] for row in frames[:-1])):
            raise GateError('offline_journey_unverified_prior_frame')
    else:
        diagnostic_fields = {'stage', 'last_ready_stage', 'wait_reason', 'target_frame_verified',
                             'png_sha256', 'xml_sha256', 'display_size_px', 'capture_identity',
                             'has_target', 'has_banner', 'has_next', 'node_count',
                             'observed_stages', 'structure_sha256', 'ready_count', 'next_enabled'}
        next_stage = int(expected[len(names)].split('-')[1]) if len(names) < len(expected) else None
        if (not isinstance(failure, ReadyTimeout) or set(diagnostic) != diagnostic_fields or
                diagnostic['stage'] != failure.stage or failure.stage != next_stage or
                diagnostic['last_ready_stage'] != failure.last_ready_stage or
                diagnostic['wait_reason'] != failure.wait_reason or
                type(diagnostic['target_frame_verified']) is not bool or
                any(type(diagnostic[key]) is not bool for key in ('has_target', 'has_banner', 'has_next')) or
                diagnostic['next_enabled'] not in ('true', 'false', 'missing', 'ambiguous') or
                type(diagnostic['node_count']) is not int or not 1 <= diagnostic['node_count'] <= 10000 or
                type(diagnostic['ready_count']) is not int or not 0 <= diagnostic['ready_count'] <= 1000 or
                not re.fullmatch('[a-f0-9]{64}', str(diagnostic['structure_sha256'])) or
                type(diagnostic['observed_stages']) is not list or
                any(type(stage) is not int or not 0 <= stage < COUNT for stage in diagnostic['observed_stages']) or
                diagnostic['observed_stages'] != sorted(set(diagnostic['observed_stages'])) or
                diagnostic['capture_identity'] not in ({'target_markers', 'fresh_synthetic_apk_activity'}
                    if diagnostic['target_frame_verified'] else {None}) or
                diagnostic['display_size_px'] != list(COMPACT_SIZE if failure.stage == 15 else DEFAULT_SIZE) or
                not all(row['accepted'] for row in frames)):
            raise GateError('offline_journey_timeout_diagnostic_invalid')
        for suffix in ('png', 'xml'):
            value = diagnostic[suffix+'_sha256']
            if diagnostic['target_frame_verified']:
                if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value) or digest(private/('DIAGNOSTIC.'+suffix)) != value:
                    raise GateError('offline_journey_timeout_diagnostic_invalid')
            elif value is not None:
                raise GateError('offline_journey_timeout_diagnostic_invalid')
        if json.loads((private/'DIAGNOSTIC.json').read_text()) != diagnostic:
            raise GateError('offline_journey_timeout_diagnostic_invalid')
    completed = [row['stage'] for row in frames if row['accepted'] and not row['after_work'] and not row['after_scroll']]
    public = {'schema': 1, **identity, 'target_marker': TARGET,
              'display_sizes_px': [list(DEFAULT_SIZE)] + ([list(COMPACT_SIZE)] if any(row['stage'] == 15 for row in frames) else []),
              'api_level': 36, 'network_disabled': True, 'live_authentication': False,
              'start_stage': START_STAGE, 'execution_mode': 'tail9' if START_STAGE == 9 else 'full',
              'expected_stage_count': COUNT-START_STAGE, 'completed_stages': completed,
              'frame_count': len(frames), 'native_restart_count': restart_count,
              'message_custom_scheme_proven': 14 in completed,
              'https_app_links_proven': False,
              'compact_favorites_forced_scroll': any(row['stage'] == 15 and row['after_scroll'] for row in frames),
              'compact_favorites_manual_pixel_review_required': True,
              'result': 'INCOMPLETE' if failure else 'COMPLETE', 'coverage_complete': failure is None,
              'failure_reason': failure.reason if failure else None,
              'failure_stage': failure.stage if failure else None, 'phase23_accepted': False,
              'plaintext_exported': False, 'apk_exported': False,
              'physical_footer_touch_only': True, 'talkback_action_tested': False,
              'scope': ('Fresh synthetic role/link/helper tail9–15 only; accepted history stages0–8 '
                        'are referenced from a prior run and are neither replayed nor accepted by this run. '
                        'Actual AppShell physical touch, custom-scheme Android VIEW and compact helper pixels; '
                        'no live authentication, HTTPS App Links, TalkBack or full phase acceptance.'
                        if START_STAGE == 9 else SCOPE)}
    if START_STAGE == 9:
        public['prior_history_reference'] = {
            'run_id': '43538357580', 'source_sha': '91b24899f2961a3ecf39699fa7356444548962e1',
            'artifact_zip_sha256': '967911d4f6fd9a3ecb3088c1964f1fbfe069678d1f09ab3b2e51845c33b5fec6',
            'stages': list(range(9)), 'replayed': False, 'accepted_by_this_run': False}
    if diagnostic is not None:
        public['timeout_diagnostic'] = diagnostic
    (private/'MANIFEST.json').write_text(json.dumps({**public, 'frames': frames}, ensure_ascii=False, indent=2)+'\n')
    allowed = {'MANIFEST.json'} | {name+'.'+suffix for name in names for suffix in ('png', 'xml', 'json')}
    if diagnostic is not None:
        allowed.add('DIAGNOSTIC.json')
        if diagnostic['target_frame_verified']:
            allowed.update({'DIAGNOSTIC.png', 'DIAGNOSTIC.xml'})
    files = list(private.iterdir())
    if {path.name for path in files} != allowed or any(path.is_symlink() or not path.is_file() for path in files):
        raise GateError('offline_journey_export_scope_invalid')
    output.mkdir(mode=0o700)
    archive = private.parent/(private.name+'.zip')
    try:
        try:
            with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as bundle:
                for path in sorted(files): bundle.write(path, path.name)
            archive.chmod(0o600)
            encrypted = encryptor(archive, output/'checkpoints.cms', RECIPIENT)
        finally:
            archive.unlink(missing_ok=True)
        public.update(encrypted_evidence=encrypted, recipient_sha256=RECIPIENT_SHA256)
        (output/'PUBLIC_RECEIPT.json').write_text(json.dumps(public, indent=2)+'\n')
        return public
    except BaseException:
        shutil.rmtree(output)
        raise


def collect(args, env=os.environ):
    global STAGE
    STAGE = 'context'
    context(env)
    output = ROOT/'phase23-offline-journeys-sealed'
    if output.exists() or output.is_symlink(): raise GateError('offline_journey_fresh_output_required')
    device = JourneyDevice(args.serial, time.monotonic()+args.max_seconds)
    apk = Path(args.apk).absolute()
    STAGE = 'apk_identity'
    verify_archive(apk)
    tools = Path(env['ANDROID_HOME'])/'build-tools/36.0.0'
    device.command([tools/'apksigner', 'verify', apk])
    version = verify_badging(device.command([tools/'aapt', 'dump', 'badging', apk]))
    STAGE = 'emulator_preflight'
    if (device.adb('shell', 'getprop', 'ro.kernel.qemu') != '1' or
            device.adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
            device.adb('shell', 'pm', 'path', PACKAGE, check=False)):
        raise GateError('offline_journey_fresh_api36_emulator_required')
    device.offline()
    STAGE = 'install'
    device.adb('install', '--no-streaming', str(apk), timeout=180)
    installed = device.adb('shell', 'pm', 'path', PACKAGE)
    if not re.fullmatch(r'package:/data/app/[A-Za-z0-9_./=+~-]+/base\.apk', installed):
        raise GateError('offline_journey_installed_path_invalid')
    if hashlib.sha256(device.adb('exec-out', 'cat', installed[8:], binary=True, timeout=60)).hexdigest() != digest(apk):
        raise GateError('offline_journey_installed_hash_mismatch')
    sizes = re.findall(r'(?:Physical|Override) size: ([0-9]+)x([0-9]+)', device.adb('shell', 'wm', 'size'))
    if not sizes or tuple(map(int, sizes[-1])) != (1080, 1920):
        raise GateError('offline_journey_display_size_invalid')
    size = DEFAULT_SIZE
    identity = {'source_sha': env['GITHUB_SHA'], 'run_id': env['GITHUB_RUN_ID'], 'product_trees': TREES,
                'package': PACKAGE, 'version_code': version, 'apk_sha256': digest(apk)}
    with tempfile.TemporaryDirectory(prefix='phase23-offline-journeys-', dir=env['RUNNER_TEMP']) as directory:
        private = Path(directory)/'frames'; private.mkdir(mode=0o700)
        frames, restart_count, restart_proof, message_before = [], 0, None, None
        try:
            STAGE = 'capture'
            # Clear only before the first launch. The later restart preserves files.
            if device.adb('shell', 'pm', 'clear', PACKAGE) != 'Success':
                raise GateError('offline_journey_initial_clear_failed')
            device.adb('logcat', '-c')
            device.adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)
            for stage in range(START_STAGE, COUNT):
                _xml, proof = capture(device, private, frames, stage, size, restart_proof,
                                      message_before=message_before)
                if stage == 4:
                    restart_proof = proof
                    device.restart_preserving_files()
                    restart_count += 1
                    continue
                if stage == 13:
                    # Observe the same final regular-shell witness immediately
                    # before the sole fixed Android intent. No harness navigation.
                    ready_for(device.xml(), device.log(), stage, size)
                    message_before = proof
                    device.open_message_link()
                    continue
                if stage == 14:
                    device.adb('shell', 'wm', 'size', '840x1493')
                    observed = re.findall(r'(?:Physical|Override) size: ([0-9]+)x([0-9]+)', device.adb('shell', 'wm', 'size'))
                    if not observed or tuple(map(int, observed[-1])) != COMPACT_SIZE:
                        raise GateError('offline_journey_supplement_size_invalid')
                    size = COMPACT_SIZE
                    time.sleep(.6)
                    xml, _nodes, _proof = device.wait_ready(stage, size)
                    point = input_point(xml, device.log(), stage, size, NEXT)
                    device.adb('shell', 'input', 'tap', *map(str, point))
                    continue
                if stage == 15:
                    gesture = supplement_scroll(device.xml(), device.log(), size)
                    device.adb('shell', 'input', 'swipe', *map(str, gesture), '400')
                    time.sleep(.6)
                    capture(device, private, frames, stage, size, restart_proof, after_scroll=True)
                    continue
                if stage in (9, 11):
                    xml = device.xml()
                    point = input_point(xml, device.log(), stage, size, 'عملي')
                    device.adb('shell', 'input', 'tap', *map(str, point))
                    capture(device, private, frames, stage, size, restart_proof, after_work=True)
                if stage < COUNT-1:
                    xml = device.xml()
                    point = input_point(xml, device.log(), stage, size, NEXT)
                    device.adb('shell', 'input', 'tap', *map(str, point))
            device.offline(); proof_events(device.log())
            STAGE = 'seal'
            export(private, output, identity, frames, restart_count)
        except CoverageIncomplete as failure:
            device.offline(); proof_events(device.log())
            STAGE = 'seal_incomplete'
            diagnostic = timeout_diagnostic(device, private, failure, size,
                identity['apk_sha256']) if isinstance(failure, ReadyTimeout) else None
            export(private, output, identity, frames, restart_count, failure, diagnostic=diagnostic)
            raise
        finally:
            subprocess.run(['adb', '-s', args.serial, 'shell', 'am', 'force-stop', PACKAGE],
                           capture_output=True, timeout=5, check=False)
    print(f'AQER_OFFLINE_JOURNEYS_{COUNT-START_STAGE}_STAGES_SEALED mode={"tail9" if START_STAGE == 9 else "full"}')


def failure_message(error):
    return str(error) if isinstance(error, GateError) else f'offline_journey_failed stage={STAGE} exception={type(error).__name__}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--max-seconds', type=int, default=600)
    args = parser.parse_args()
    if not 30 <= args.max_seconds <= 600: raise GateError('offline_journey_duration_invalid')
    def timeout(_signum, _frame): raise GateError('offline_journey_timeout')
    signal.signal(signal.SIGALRM, timeout); signal.alarm(args.max_seconds)
    try: collect(args)
    finally: signal.alarm(0)


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(failure_message(error), file=sys.stderr)
        raise SystemExit(1) from None
