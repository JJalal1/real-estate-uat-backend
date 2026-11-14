#!/usr/bin/env python3
"""Finite ordinary-app media/review journey against a disposable local Laravel DB.

No live UAT credentials or data. Private pixels are permitted only after independent
source, APK, local server, fixture and emulator egress checks. Product code, routes,
authentication, media picker and review decisions are unchanged. An unavailable UI
control stops the journey; already observed checkpoints remain encrypted evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

from phase23_preflight import GateError
from phase23_local_media_guard import guard, TREES
from prepare_phase1_close import encrypt
from run_phase23_offline_device import focused_activity
from run_phase23_offline_visual import Device as BaseDevice, bounds, digest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.aqer.yemen.uat'
ACTIVITY = PACKAGE + '/com.example.real_estate_mobile.MainActivity'
API = 'http://10.0.2.2:8000/api'
HOST = 'http://127.0.0.1:8000'
API_ORIGIN = 'http://10.0.2.2:8000'
DATABASE = 'phase23_local_media_ci'
MARKER = 'AQER_LOCAL_MEDIA_FIXTURE_V1'
RECIPIENT = ROOT / 'scripts/phase23_recipient.pem'
RECIPIENT_SHA256 = 'b53bdbc6d97e75db5a95207e198ebbd9900af017690585e26ccb79c599008070'
REVIEW_RECIPIENT = ROOT / 'scripts/phase23_owner_delivery_recipient.pem'
REVIEW_RECIPIENT_SHA256 = '4bdf43f77b92183d2902c1c4742116ff8c8a24310e0e86a2b190c8f42bfd810e'
ACTORS = ('advertiser', 'support', 'researcher')
PHONES = dict(zip(ACTORS, ('+967700230101', '+967700230102', '+967700230103')))
PICKERS = {'com.google.android.documentsui', 'com.android.documentsui'}
MEDIA_NAMES = {'A-exterior.png', 'B-interior.png', 'C-replacement.jpg', 'X-brand-logo.png'}
KEYBOARDS = {'com.google.android.inputmethod.latin', 'com.android.inputmethod.latin'}
PERMISSIONS = {'com.google.android.permissioncontroller', 'com.android.permissioncontroller'}
STARTUP_SYSTEM_PACKAGES = {'android', 'com.android.systemui', 'com.android.launcher3',
                           'com.google.android.apps.nexuslauncher'}
SIZE = (1080, 1920)
MAX_CHECKPOINTS = 40
MAX_INPUTS = 350
STARTUP_XML_RETRIES = 40
BIDI_FORMAT = dict.fromkeys(map(ord, '\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069'))
REASON = 'P23 logo is not a property photograph. Replace it with the house image.'
SCOPE = ('Ordinary main.dart debug app and unchanged Laravel/PostgreSQL controllers on '
         'disposable loopback fixtures only; actual Android picker/auth/media/review UI; '
         'not live UAT, owner APK, physical handset or full phase acceptance')


class Incomplete(GateError):
    """Fixed diagnostics; no UI, credentials or arbitrary exception text in stdout."""


def validate_fixture(value, env):
    if not isinstance(value, dict) or value.get('schema') != 1 or value.get('marker') != MARKER:
        raise GateError('local_media_fixture_identity_invalid')
    if (value.get('api') != API or value.get('database') != DATABASE or value.get('app_env') != 'local' or
            value.get('product_trees') != TREES or
            value.get('origin') != API_ORIGIN or value.get('run_id') != env.get('GITHUB_RUN_ID') or
            value.get('source_sha') != env.get('GITHUB_SHA') or
            not re.fullmatch(r'[0-9a-f]{32,64}', str(value.get('nonce', ''))) or
            value.get('identity_path') != '/phase23-local-identity-' + value['nonce'] + '.json'):
        raise GateError('local_media_fixture_scope_invalid')
    actors = value.get('actors')
    if not isinstance(actors, dict) or set(actors) != set(ACTORS):
        raise GateError('local_media_actors_invalid')
    ids = []
    for name in ACTORS:
        actor = actors[name]
        if (not isinstance(actor, dict) or set(actor) != {'id', 'phone', 'email'} or
                type(actor['id']) is not int or actor['id'] <= 0 or actor['phone'] != PHONES[name] or
                not re.fullmatch(r'[a-z0-9_.+-]+@[a-z0-9.-]+\.test', actor['email'])):
            raise GateError('local_media_actors_invalid')
        ids.append(actor['id'])
    if len(set(ids)) != 3 or type(value.get('listing_id')) is not int or value['listing_id'] <= 0:
        raise GateError('local_media_listing_identity_invalid')
    for key in ('title', 'updated_title'):
        if not isinstance(value.get(key), str) or not re.fullmatch(r'P23 [A-Za-z0-9 ]{3,80}', value[key]):
            raise GateError('local_media_title_invalid')
    if value['title'] == value['updated_title']:
        raise GateError('local_media_distinct_titles_required')
    files = value.get('files')
    if (not isinstance(files, list) or len(files) != 4 or not all(isinstance(x,dict) for x in files) or
            sorted(x.get('kind', '') for x in files) != ['bad', 'good', 'good', 'good']):
        raise GateError('local_media_files_invalid')
    names = set()
    for item in files:
        if (item.get('name') not in MEDIA_NAMES or
                not re.fullmatch(r'[0-9a-f]{64}', item.get('sha256', '')) or
                not Path(item.get('path', '')).is_absolute() or item['name'] in names):
            raise GateError('local_media_files_invalid')
        names.add(item['name'])
    return value


def verify_build(apk, receipt, fixture):
    required = {'marker':'AQER_LOCAL_MEDIA_BUILD_V1','schema':1,'target': 'lib/main.dart', 'mode': 'debug', 'environment': 'local',
                'flavor':'uat','run_id':fixture['run_id'],'database':DATABASE,'share_base':API_ORIGIN,
                'compiled_local_endpoint':True,'provider_overrides':False,
                'api': API, 'package': PACKAGE, 'source_sha': fixture['source_sha'],
                'product_trees': TREES, 'apk_sha256': digest(apk)}
    if any(receipt.get(k) != v for k, v in required.items()):
        raise GateError('local_media_build_receipt_invalid')
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(set(archive.namelist())):
            raise GateError('local_media_apk_invalid')
        name = 'assets/flutter_assets/kernel_blob.bin'
        if name not in archive.namelist() or API.encode() not in archive.read(name):
            raise GateError('local_media_compiled_api_missing')
    return required


def labels(node):
    # Android wraps explicit LTR phone/OTP/title semantics in bidi controls.
    # Match their visible text, retaining the original XML as private evidence.
    return {x.translate(BIDI_FORMAT).strip() for k in ('text', 'content-desc', 'hint', 'tooltip-text')
            for x in node.get(k, '').splitlines() if x.strip()}


def ui_nodes(xml, allowed_packages):
    if len(xml.encode()) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        raise Incomplete('local_media_xml_invalid')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise Incomplete('local_media_xml_invalid') from None
    if root.tag != 'hierarchy':
        raise Incomplete('local_media_xml_invalid')
    nodes = list(root.iter('node'))
    seen = {n.get('package') for n in nodes if n.get('package')}
    if not seen or not seen <= set(allowed_packages):
        raise Incomplete('local_media_foreign_surface')
    return root, nodes


def transient_startup_xml(xml):
    """Readiness-only: never accepts a tree for input or pixel collection."""
    if len(xml.encode()) > 2_000_000 or '<!DOCTYPE' in xml or '<!ENTITY' in xml:
        return False
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        # A dump warning/prefix is acquisition failure, never an accepted tree.
        # The caller additionally requires exact app focus, isolation and budgets.
        return True
    if root.tag != 'hierarchy':
        return False
    nodes = list(root.iter('node'))
    if not nodes:
        return True
    packages = {node.get('package') for node in nodes if node.get('package')}
    # Some fresh AVDs report an Android launch overlay in the first dump
    # even after MainActivity resumes. Discard it and observe again. Only
    # the normal target/permission allowlist can authorize a tap or frame.
    return bool(packages & STARTUP_SYSTEM_PACKAGES) and packages <= (
        STARTUP_SYSTEM_PACKAGES | {PACKAGE} | KEYBOARDS | PERMISSIONS)


def xml_failure_shape(xml):
    """Fixed categories only; raw text never enters the public receipt."""
    if len(xml.encode()) > 2_000_000: return 'oversized'
    if '<!DOCTYPE' in xml or '<!ENTITY' in xml: return 'forbidden_declaration'
    if not xml.strip(): return 'empty'
    try: root = ET.fromstring(xml)
    except ET.ParseError:
        return 'malformed_xml' if xml.lstrip().startswith(('<?xml','<hierarchy')) else 'non_xml_output'
    if root.tag != 'hierarchy': return 'wrong_root'
    if not list(root.iter('node')): return 'empty_hierarchy'
    return 'foreign_surface'


def select_shell_tab(nodes, label, size):
    if label not in {'حسابي', 'الوارد'}:
        raise GateError('local_media_shell_tab_invalid')
    # AppNavigationBar puts physical touch on the excluded GestureDetector.
    # Android exposes the outer tab as a Button without a semantic click action.
    matches = []
    for node in nodes:
        if (node.get('package') != PACKAGE or label not in labels(node) or
                node.get('class') != 'android.widget.Button' or node.get('enabled') != 'true' or
                node.get('visible-to-user', 'true') != 'true' or
                node.get('selected') not in {'true', 'false'}):
            continue
        try:
            left, top, right, bottom = bounds(node.get('bounds'), size)
        except GateError:
            continue
        if (top >= size[1]*.75 and bottom <= size[1]*.98 and
                right-left <= size[0]*.35 and bottom-top <= size[1]*.16):
            matches.append((left, top, right, bottom))
    if len(matches) != 1:
        raise Incomplete('local_media_control_missing' if not matches else 'local_media_control_ambiguous')
    return matches[0]


def select_overflow(nodes, label, listing_title, size):
    def app_button(node):
        return (node.get('package') == PACKAGE and node.get('class') == 'android.widget.Button'
                and node.get('clickable') == 'true' and node.get('enabled') == 'true'
                and node.get('visible-to-user', 'true') == 'true')

    if listing_title is not None:
        cards = [n for n in nodes if n.get('package') == PACKAGE and listing_title in labels(n)
                 and any(app_button(c) for c in n if c is not n)]
        if len(cards) != 1:
            raise Incomplete('local_media_control_missing' if not cards else 'local_media_control_ambiguous')
        buttons = [n for n in cards[0].iter('node') if app_button(n)]
    else:
        if not any(n.get('package') == PACKAGE and 'تعديل الإعلان' in labels(n) for n in nodes):
            raise Incomplete('local_media_control_missing')
        buttons = [n for n in nodes if app_button(n) and bounds(n.get('bounds'), size)[1] >= size[1]*.84]

    floating_add = [bounds(n.get('bounds'), size) for n in nodes
                    if listing_title is not None and app_button(n) and 'إضافة عقار' in labels(n)]

    def visible(box):
        return not any(box[0] < right and left < box[2] and box[1] < bottom and top < box[3]
                       for left, top, right, bottom in floating_add)

    named = [bounds(n.get('bounds'), size) for n in buttons if label in labels(n)]
    if named:
        if len(named) != 1:
            raise Incomplete('local_media_control_ambiguous')
        if not visible(named[0]):
            raise Incomplete('local_media_control_missing')
        return named[0]

    # On the API36 dump a Flutter popup can be an unnamed button. Only the
    # small RTL sibling of an observed primary action can stand for this menu.
    primary = [bounds(n.get('bounds'), size) for n in buttons if labels(n) & {
        'إرسال للمراجعة', 'إعادة الإرسال', 'عرض', 'إقرار السعي', 'ما زال متوفرًا', 'معاينة الإعلان'}]
    matches = set()
    for node in buttons:
        if labels(node):
            continue
        left, top, right, bottom = bounds(node.get('bounds'), size)
        if not (80 <= right-left <= 150 and 80 <= bottom-top <= 150):
            continue
        if (visible((left, top, right, bottom)) and
                any(0 <= p[0]-right <= 40 and abs(p[1]-top) <= 35 and abs(p[3]-bottom) <= 35 for p in primary)):
            matches.add((left, top, right, bottom))
    if len(matches) != 1:
        raise Incomplete('local_media_control_missing' if not matches else 'local_media_control_ambiguous')
    return matches.pop()


def select_control(xml, label, packages, size=SIZE, ordinal=None, editable=False,
                   shell_tab=False, listing_title=None):
    root, nodes = ui_nodes(xml, packages)
    if shell_tab:
        return select_shell_tab(nodes, label, size)
    if label == 'خيارات البطاقة' and listing_title is not None:
        return select_overflow(nodes, label, listing_title, size)
    parents = {child: node for node in root.iter() for child in node}
    matches = {}
    for node in nodes:
        if label not in labels(node) or node.get('visible-to-user', 'true') != 'true':
            continue
        action = node
        if editable:
            if action.get('class') != 'android.widget.EditText':
                continue
        else:
            while action is not None and action.get('clickable') != 'true':
                action = parents.get(action)
        if action is None or action.get('enabled') != 'true' or action.get('visible-to-user', 'true') != 'true':
            continue
        try:
            box = bounds(action.get('bounds'), size)
        except GateError:
            continue
        matches[box] = action
    boxes = sorted(matches, key=lambda b: (b[1], -b[0]))
    if not boxes:
        if label == 'خيارات المسودة':
            return select_overflow(nodes, label, listing_title, size)
        raise Incomplete('local_media_control_missing')
    if ordinal is None:
        if len(boxes) != 1:
            raise Incomplete('local_media_control_ambiguous')
        return boxes[0]
    if type(ordinal) is not int or ordinal < 0 or ordinal >= len(boxes):
        raise Incomplete('local_media_control_ordinal_missing')
    return boxes[ordinal]


def select_review_control(xml, image_number, packages, size=SIZE):
    """Bind the repeated review button to its visible, numbered image card."""
    if type(image_number) is not int or image_number not in (1, 2):
        raise Incomplete('local_media_review_card_invalid')
    root, nodes = ui_nodes(xml, packages)
    headers = []
    for node in nodes:
        if node.get('visible-to-user', 'true') != 'true':
            continue
        for label in labels(node):
            match = re.fullmatch(r'الصورة ([1-9][0-9]*) — .+', label)
            if match:
                try: box = bounds(node.get('bounds'), size)
                except GateError: continue
                headers.append((int(match[1]), box))
    selected = {box for number, box in headers if number == image_number}
    if not selected:
        raise Incomplete('local_media_review_card_missing')
    if len(selected) != 1:
        raise Incomplete('local_media_review_card_ambiguous')
    header = selected.pop()
    lower = min((box[1] for number, box in headers if box[1] > header[1]), default=size[1])
    matches = set()
    for index in range(6):
        try: box = select_control(xml, 'تسجيل المراجعة البشرية', packages, size, ordinal=index)
        except Incomplete as error:
            if str(error) in {'local_media_control_missing', 'local_media_control_ordinal_missing'}: break
            raise
        if box[1] >= header[3] and box[3] <= lower:
            matches.add(box)
    if not matches:
        raise Incomplete('local_media_review_card_missing')
    if len(matches) != 1:
        raise Incomplete('local_media_review_card_ambiguous')
    return matches.pop()


def picker_item(xml, name, package):
    if name not in MEDIA_NAMES or package not in PICKERS:
        raise GateError('local_media_picker_item_invalid')
    root, nodes = ui_nodes(xml, {package, PACKAGE} | KEYBOARDS)
    parents = {child: node for node in root.iter() for child in node}
    pattern = re.compile(re.escape(name) + r'(?:, [^\r\n]{1,100})?')
    hits = set()
    for node in nodes:
        if (node.get('package') != package or node.get('enabled') != 'true'
                or not any(pattern.fullmatch(text) for text in labels(node))):
            continue
        child = node
        ancestor = parents.get(node)
        while ancestor is not None and ancestor.get('resource-id') != package+':id/dir_list':
            child = ancestor
            ancestor = parents.get(ancestor)
        if ancestor is None or child.get('package') != package:
            continue
        left, top, right, bottom = bounds(child.get('bounds'), SIZE)
        if 80 <= right-left <= 970 and 60 <= bottom-top <= 400:
            hits.add(((left+right)//2, top+(bottom-top)*3//4))
    if len(hits) != 1:
        raise Incomplete('local_media_control_missing' if not hits else 'local_media_control_ambiguous')
    return hits.pop()


def media_drag_targets(xml, packages):
    """Two fully visible cards, derived from their own menu/remove controls."""
    _, nodes = ui_nodes(xml, packages)
    viewports = []
    for node in nodes:
        if node.get('scrollable') == 'true' and node.get('enabled') == 'true':
            try: box = bounds(node.get('bounds'), SIZE)
            except GateError: continue
            if box[2]-box[0] > box[3]-box[1]: viewports.append(box)
    if len(viewports) != 1:
        raise Incomplete('local_media_drag_viewport_ambiguous')
    viewport = viewports[0]
    points, card_widths = [], []
    for index in (0, 1):
        menu = select_control(xml, 'خيارات الصورة', packages, ordinal=index)
        remove = select_control(xml, 'إزالة الصورة', packages, ordinal=index)
        if abs(menu[1]-remove[1]) > 8 or min(menu[3]-menu[1], remove[3]-remove[1]) < 20:
            raise Incomplete('local_media_drag_card_unbound')
        point = ((menu[0]+menu[2]+remove[0]+remove[2])//4,
                 max(menu[3], remove[3]) + min(menu[3]-menu[1], remove[3]-remove[1])//3)
        if not (viewport[0] <= min(menu[0],remove[0]) and max(menu[2],remove[2]) <= viewport[2]
                and viewport[1] < point[1] < viewport[3]):
            raise Incomplete('local_media_drag_card_clipped')
        points.append(point)
        card_widths.append(max(menu[2],remove[2])-min(menu[0],remove[0]))
    if abs(card_widths[0]-card_widths[1]) > 8:
        raise Incomplete('local_media_drag_card_clipped')
    if points[0][0] <= points[1][0] or abs(points[0][1]-points[1][1]) > 8:
        raise Incomplete('local_media_drag_card_order_unproved')
    return tuple(points)


def validate_snapshot(value, fixture):
    if (not isinstance(value, dict) or value.get('marker') != MARKER or
            value.get('nonce') != fixture['nonce'] or value.get('app_env') != 'local' or
            value.get('database') != DATABASE or value.get('api_origin') != API_ORIGIN or
            value.get('user_count') != 3 or value.get('property_count') != 1):
        raise GateError('local_media_database_scope_changed')
    listing = value.get('listing', {})
    if listing.get('id') != fixture['listing_id'] or listing.get('title') not in (fixture['title'], fixture['updated_title']):
        raise GateError('local_media_snapshot_listing_invalid')
    images = listing.get('images')
    if not isinstance(images, list) or len(images) > 4:
        raise GateError('local_media_snapshot_images_invalid')
    ids = []
    for image in images:
        if (type(image.get('id')) is not int or image['id'] <= 0 or
                type(image.get('sort_order')) is not int or image['sort_order'] < 0 or
                type(image.get('is_primary')) is not bool or
                not re.fullmatch(r'[0-9a-f]{64}', image.get('sha256', '')) or
                image.get('relevance_status') not in {'pending', 'unreviewed', 'relevant', 'uncertain', 'unrelated'}):
            raise GateError('local_media_snapshot_images_invalid')
        ids.append(image['id'])
    if len(ids) != len(set(ids)):
        raise GateError('local_media_snapshot_duplicate_images')
    reviews = listing.get('reviews')
    if not isinstance(reviews,list) or len(reviews)>60:
        raise GateError('local_media_snapshot_reviews_invalid')
    review_ids = []
    for review in reviews:
        if (not isinstance(review,dict) or type(review.get('id')) is not int or review['id'] <= 0
                or review.get('actor_user_id') not in {x['id'] for x in fixture['actors'].values()}
                or not isinstance(review.get('action'),str)
                or review.get('metadata') is not None and not isinstance(review.get('metadata'),dict)):
            raise GateError('local_media_snapshot_reviews_invalid')
        review_ids.append(review['id'])
    if len(review_ids) != len(set(review_ids)):
        raise GateError('local_media_snapshot_reviews_invalid')
    return value


def media_identity(snapshot):
    return [(x['id'], x['sort_order'], x['is_primary'], x['sha256']) for x in snapshot['listing']['images']]


def assert_transition(name, before, after, fixture):
    validate_snapshot(before, fixture)
    validate_snapshot(after, fixture)
    a, b = before['listing'], after['listing']
    ai, bi = a['images'], b['images']
    aset, bset = {x['id'] for x in ai}, {x['id'] for x in bi}
    files = {x['name']:x['sha256'] for x in fixture['files']}
    old_reviews = {x['id'] for x in a.get('reviews', [])}
    fresh_reviews = [x for x in b.get('reviews', []) if x['id'] not in old_reviews]
    def reviewed(action, actor):
        return any(x.get('action') == action and x.get('actor_user_id') == fixture['actors'][actor]['id']
                   for x in fresh_reviews)
    ok = False
    if name == 'media_added':
        ok = len(ai) == 0 and [x['sha256'] for x in bi] == [files[n] for n in ('A-exterior.png','B-interior.png','X-brand-logo.png')]
    elif name == 'media_reordered':
        ok = (len(ai) == 3 and [x['id'] for x in bi] == [ai[1]['id'], ai[0]['id'], ai[2]['id']]
              and {x['id']:x['sha256'] for x in ai} == {x['id']:x['sha256'] for x in bi})
    elif name == 'media_primary':
        ok = aset == bset and len(bi) == 3 and ai[0]['id'] != bi[0]['id'] and bi[0]['is_primary'] and sum(x['is_primary'] for x in bi) == 1
    elif name == 'media_removed':
        ok = len(ai) == 3 and [x['id'] for x in bi] == [ai[1]['id'], ai[2]['id']]
    elif name == 'media_reopened':
        ok = len(bi) == 2 and media_identity(before) == media_identity(after)
    elif name in ('submitted', 'resubmitted'):
        ok = (len(bi) == 2 and a['review_status'] != 'submitted' and b['review_status'] == 'submitted'
              and reviewed('submitted','advertiser'))
    elif name == 'bad_rejected':
        ok = (len(ai) == len(bi) == 2 and aset == bset and a['review_status'] == 'submitted'
              and b['review_status'] == 'under_review' and bi[0]['id'] == ai[0]['id']
              and bi[0]['relevance_status'] == 'relevant' and bi[1]['id'] == ai[1]['id']
              and bi[1]['relevance_status'] == 'unrelated' and bi[1]['sha256'] == files['X-brand-logo.png']
              and any(x.get('action') == 'media_relevance_review'
                      and x.get('actor_user_id') == fixture['actors']['support']['id']
                      and x.get('metadata',{}).get('image_id') == bi[1]['id']
                      and x.get('metadata',{}).get('decision') == 'unrelated' for x in fresh_reviews))
    elif name == 'returned':
        ok = (a['review_status'] == 'under_review' and b['review_status'] == 'returned_for_correction'
              and b.get('last_review_reason') == REASON and reviewed('returned_for_correction','support'))
    elif name == 'replaced':
        ok = (len(ai) == len(bi) == 2 and ai[1]['relevance_status'] == 'unrelated'
              and bi[0]['id'] == ai[0]['id'] and ai[1]['id'] not in bset and bi[1]['id'] not in aset
              and bi[1]['sha256'] == files['C-replacement.jpg'])
    elif name in ('approved', 'reapproved'):
        ok = (a['review_status'] == 'submitted' and b['status'] == 'published' and b['review_status'] == 'approved'
              and len(bi) == 2 and all(x['relevance_status'] == 'relevant' for x in bi) and reviewed('approved','support'))
    elif name == 'public_old':
        ok = after.get('public_title') == fixture['title'] and after.get('native_title_seen') == fixture['title']
    elif name == 'pending_edit':
        ok = (a['title'] == fixture['title'] and a['status'] == 'published'
              and b['title'] == fixture['updated_title'] and b['status'] != 'published' and
              b['review_status'] == 'submitted' and after.get('public_status') == 404)
    elif name == 'public_new':
        ok = after.get('public_title') == fixture['updated_title'] and after.get('native_title_seen') == fixture['updated_title'] and before.get('public_title') == fixture['title']
    if not ok:
        raise Incomplete('local_media_transition_unproved_' + name)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise GateError('local_media_redirect_refused')


def local_json(path, allow_not_found=False):
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', path) or '..' in path:
        raise GateError('local_media_local_path_invalid')
    # Disable inherited HTTP proxy for this loopback-only disposable service.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(HOST + path, timeout=15) as response:
            if response.status != 200 or response.geturl() != HOST + path:
                raise GateError('local_media_local_response_invalid')
            raw = response.read(2_000_001)
            if len(raw) > 2_000_000:
                raise GateError('local_media_local_response_too_large')
            return json.loads(raw)
    except urllib.error.HTTPError as error:
        if allow_not_found and error.code==404:
            return {'local_http_status':404}
        raise Incomplete('local_media_local_response_unavailable') from None
    except (ValueError, urllib.error.URLError):
        raise Incomplete('local_media_local_response_unavailable') from None


class Journey:
    def __init__(self, device, fixture, fixture_path, private):
        self.d, self.f, self.fixture_path, self.private = device, fixture, fixture_path, private
        self.records, self.inputs, self.stage = [], 0, 'startup'
        self.picker = None
        self.callsite, self.failure_context, self.failure_xml = 'startup', None, None
        self.startup_retries, self.startup_started = 0, None

    def isolation(self):
        identity = local_json(self.f['identity_path'])
        if any(identity.get(key) != self.f[key] for key in
               ('schema','marker','nonce','app_env','api','origin','database','source_sha','run_id','product_trees')):
            raise GateError('local_media_server_identity_changed')
        rules = self.d.adb('shell', 'iptables', '-S', 'OUTPUT').splitlines()
        expected = {'-P OUTPUT DROP', '-A OUTPUT -o lo -j ACCEPT',
                    '-A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT',
                    '-A OUTPUT -d 10.0.2.2/32 -p tcp -m tcp --dport 8000 -j ACCEPT'}
        if set(rules) != expected or self.d.adb('shell', 'ip6tables', '-S', 'OUTPUT').splitlines() != ['-P OUTPUT DROP']:
            raise GateError('local_media_emulator_egress_not_isolated')

    def inspect(self):
        self.isolation()
        raw = self.d.command(['php', ROOT / 'scripts/phase23_local_backend_fixture.php', 'inspect', self.fixture_path], timeout=30)
        return validate_snapshot(json.loads(raw), self.f)

    def read_xml(self, allowed, site):
        self.callsite = site
        self.failure_context, self.failure_xml = None, None
        self.isolation()
        xml = self.d.xml()
        try:
            ui_nodes(xml, allowed)
        except Incomplete:
            self.failure_xml = xml
            self.failure_context = {'stage':self.stage,'callsite':site,'shape':xml_failure_shape(xml),
                'xml_bytes':len(xml.encode()),'xml_sha256':hashlib.sha256(xml.encode()).hexdigest(),
                'inputs':self.inputs,'startup_retries':self.startup_retries,
                'startup_elapsed_seconds':round(time.monotonic()-self.startup_started,3) if self.startup_started is not None else None}
            raise
        self.failure_context, self.failure_xml = None, None
        return xml

    def xml(self, picker=False, site='ordinary_read'):
        allowed = {PACKAGE} | KEYBOARDS | ({self.picker} if picker and self.picker else set())
        return self.read_xml(allowed, site)

    def persist_startup_failure(self):
        """Keep the original failing read, separately from the later diagnostic frame."""
        context = dict(self.failure_context or {'stage':self.stage,'callsite':self.callsite,
            'inputs':self.inputs,'startup_retries':self.startup_retries})
        if context['stage'] not in {'startup','initial'} or self.failure_xml is None:
            return context
        try:
            self.isolation()
            if focused_activity(self.d.adb('shell','dumpsys','activity','activities'),{}) != 'target':
                context['raw_xml_retained'] = False
                return context
            raw = self.failure_xml.encode()
            private_context = {**context,'raw_xml':raw[:2_000_000].decode('utf-8',errors='replace'),
                               'raw_xml_truncated':len(raw)>2_000_000,'delivery_export_allowed':False}
            (self.private/'STARTUP_FAILURE.json').write_text(json.dumps(private_context,ensure_ascii=False,indent=2)+'\n')
            context['raw_xml_retained'] = True
        except (GateError,OSError,ValueError,subprocess.SubprocessError):
            context['raw_xml_retained'] = False
        return context

    def names(self, xml):
        return set().union(*(labels(n) for n in ET.fromstring(xml).iter('node')))

    def wait(self, label, seconds=35, picker=False, site='ordinary_read'):
        deadline = min(self.d.deadline, time.monotonic() + seconds)
        while time.monotonic() < deadline:
            xml = self.xml(picker, site=site)
            if label in self.names(xml):
                return xml
            time.sleep(.5)
        raise Incomplete('local_media_expected_label_unobserved')

    def startup(self, capture_initial=False):
        continued, denied = False, 0
        self.startup_retries, self.startup_started = 0, time.monotonic()
        deadline = min(self.d.deadline, self.startup_started+120)
        while time.monotonic() < deadline:
            self.stage = 'startup'
            try:
                xml = self.read_xml({PACKAGE}|KEYBOARDS|PERMISSIONS,'startup_observe')
                _, nodes = ui_nodes(xml,{PACKAGE}|KEYBOARDS|PERMISSIONS)
                if any(n.get('package') in PERMISSIONS for n in nodes):
                    candidates = [n for n in nodes if n.get('package') in PERMISSIONS and
                                  n.get('resource-id') == n.get('package')+':id/permission_deny_button' and
                                  n.get('enabled') == 'true' and n.get('clickable') == 'true']
                    if len(candidates) != 1 or denied >= 2:
                        raise Incomplete('local_media_startup_permission_unbound')
                    box = bounds(candidates[0].get('bounds'), SIZE)
                    fresh = self.read_xml({PACKAGE}|KEYBOARDS|PERMISSIONS,'startup_permission_revalidate')
                    _, fresh_nodes = ui_nodes(fresh,{PACKAGE}|KEYBOARDS|PERMISSIONS)
                    same = [n for n in fresh_nodes if n.attrib == candidates[0].attrib]
                    if len(same) != 1:
                        raise Incomplete('local_media_control_moved')
                    self.input(); self.d.adb('shell','input','tap',str((box[0]+box[2])//2),str((box[1]+box[3])//2))
                    denied += 1; continue
                names = self.names(xml)
                intro = {'عقارات في منطقتك','تحديد موقعي','اختيار المحافظة يدويًا','المتابعة الآن'}
                if not continued and intro <= names:
                    self.tap('المتابعة الآن',site='startup_intro'); continued = True
                elif {'ماذا تبحث عنه؟','حسابي'} <= names and not names & intro:
                    select_control(self.xml(site='startup_home_revalidate'),'حسابي',{PACKAGE}|KEYBOARDS,shell_tab=True)
                    return self.checkpoint('initial') if capture_initial else None
            except Incomplete:
                # Every startup read participates, including action revalidation and
                # the first checkpoint. A failed read discards its old candidate.
                # Keep the strict normal input and screenshot checks.
                if (self.failure_xml is None or self.startup_retries >= STARTUP_XML_RETRIES
                        or not transient_startup_xml(self.failure_xml)): raise
                if focused_activity(self.d.adb('shell','dumpsys','activity','activities'), {}) != 'target':
                    raise Incomplete('local_media_startup_foreground_unproved')
                self.isolation()
                self.startup_retries += 1
                time.sleep(.5)
                continue
            time.sleep(.5)
        raise Incomplete('local_media_startup_unobserved')

    def input(self):
        self.inputs += 1
        if self.inputs > MAX_INPUTS:
            raise Incomplete('local_media_input_budget_exceeded')

    def tap(self, label, ordinal=None, picker=False, seek=0, site='tap', shell_tab=False, listing_title=None):
        packages = {PACKAGE} | KEYBOARDS | ({self.picker} if picker else set())
        for attempt in range(seek + 1):
            xml = self.xml(picker,site=site+'_candidate')
            try:
                box = select_control(xml, label, packages, ordinal=ordinal, shell_tab=shell_tab, listing_title=listing_title)
                break
            except Incomplete as error:
                if str(error) != 'local_media_control_missing' or attempt == seek:
                    raise
                self.scroll()
        fresh = self.xml(picker,site=site+'_revalidate')
        other = select_control(fresh, label, packages, ordinal=ordinal, shell_tab=shell_tab, listing_title=listing_title)
        if other != box:
            raise Incomplete('local_media_control_moved')
        self.input()
        self.d.adb('shell', 'input', 'tap', str((box[0]+box[2])//2), str((box[1]+box[3])//2))
        time.sleep(.6)

    def scroll(self, horizontal=False, reverse=False):
        xml = self.xml(site='scroll_viewport')
        _, nodes = ui_nodes(xml, {PACKAGE} | KEYBOARDS)
        owned_listings = not horizontal and 'عقاراتي' in self.names(xml)
        boxes = []
        for node in nodes:
            if node.get('scrollable') == 'true' and node.get('enabled') == 'true':
                try:
                    box = bounds(node.get('bounds'), SIZE)
                except GateError:
                    continue
                if owned_listings and (node.get('package') != PACKAGE or
                        node.get('class') != 'android.widget.ScrollView' or box[2]-box[0] < SIZE[0]*.9):
                    continue  # Ignore nested filters and the card's swipeable image.
                if (box[2]-box[0] > box[3]-box[1]) == horizontal:
                    boxes.append(box)
        if len(boxes) != 1:
            raise Incomplete('local_media_scroll_viewport_ambiguous')
        l,t,r,b = boxes[0]
        coords = ((l+(r-l)*4//5,(t+b)//2,l+(r-l)//5,(t+b)//2) if horizontal else
                  ((l+r)//2,t+(b-t)*4//5,(l+r)//2,t+(b-t)//5))
        if reverse:
            coords = coords[2:] + coords[:2]
        self.input(); self.d.adb('shell', 'input', 'swipe', *map(str, coords), '450'); time.sleep(.4)

    def text(self, label, value, seek=0, prefix=''):
        if not re.fullmatch(r'[A-Za-z0-9 .+_-]{1,160}', value):
            raise GateError('local_media_ascii_fixture_input_required')
        if prefix and (prefix != '+967' or label != 'رقم واتساب' or value not in PHONES.values()):
            raise GateError('local_media_phone_prefix_invalid')
        for attempt in range(seek+1):
            xml = self.xml()
            try:
                box = select_control(xml, label, {PACKAGE} | KEYBOARDS, editable=True)
                break
            except Incomplete as error:
                if str(error) != 'local_media_control_missing' or attempt == seek: raise
                self.scroll()
        fresh = self.xml(site='text_field_revalidate')
        if select_control(fresh,label,{PACKAGE}|KEYBOARDS,editable=True) != box:
            raise Incomplete('local_media_control_moved')
        if prefix:
            _, fields = ui_nodes(fresh, {PACKAGE}|KEYBOARDS)
            if not any(n.get('class') == 'android.widget.EditText' and prefix in labels(n)
                       and n.get('bounds') == f'[{box[0]},{box[1]}][{box[2]},{box[3]}]' for n in fields):
                raise Incomplete('local_media_phone_prefix_unobserved')
        self.input(); self.d.adb('shell', 'input', 'tap', str((box[0]+box[2])//2), str((box[1]+box[3])//2))
        if prefix:
            # The ordinary phone field already includes +967. Enter only the
            # synthetic subscriber digits, keeping the app's country prefix.
            self.d.adb('shell', 'input', 'keyevent', 'KEYCODE_MOVE_END')
        else:
            self.d.adb('shell', 'input', 'keycombination', 'KEYCODE_CTRL_LEFT', 'KEYCODE_A')
            self.d.adb('shell', 'input', 'keyevent', 'KEYCODE_DEL')
        self.d.adb('shell', 'input', 'text', value.removeprefix(prefix).replace(' ', '%s'))
        time.sleep(.3)
        entered = self.xml(site='text_field_verify')
        if not any(n.get('class') == 'android.widget.EditText' and value in labels(n) for n in ET.fromstring(entered).iter('node')):
            raise Incomplete('local_media_text_input_unproved')
        self.d.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK'); time.sleep(.3)

    def checkpoint(self, name, before=None, extra=None):
        self.stage = name
        if len(self.records) >= MAX_CHECKPOINTS:
            raise Incomplete('local_media_checkpoint_budget_exceeded')
        deadline = min(self.d.deadline,time.monotonic()+45)
        while True:
            snapshot = self.inspect()
            if extra: snapshot.update(extra)
            if before is None: break
            try:
                assert_transition(name,before,snapshot,self.f)
                break
            except Incomplete:
                if time.monotonic() >= deadline: break
                time.sleep(.5)
        xml = self.xml(site='checkpoint_before_capture')
        png = self.d.adb('exec-out', 'screencap', '-p', binary=True)
        if png[:8] != b'\x89PNG\r\n\x1a\n' or len(png)<24 or struct.unpack('>II',png[16:24]) != SIZE:
            raise Incomplete('local_media_png_invalid')
        # Reprove isolation after capture before writing any private evidence.
        self.isolation(); self.xml(site='checkpoint_after_capture')
        stem = f'{len(self.records):02d}-{name}'
        (self.private/(stem+'.png')).write_bytes(png)
        (self.private/(stem+'.xml')).write_text(xml)
        record = {'stage': name, 'snapshot': snapshot, 'source_sha': self.f['source_sha'],
                  'nonce': self.f['nonce'], 'inputs': self.inputs,
                  'png_sha256': hashlib.sha256(png).hexdigest(), 'xml_sha256': hashlib.sha256(xml.encode()).hexdigest()}
        (self.private/(stem+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
        self.records.append({'stage':name,'file':stem,'inputs':self.inputs})
        if before is not None:
            assert_transition(name, before, snapshot, self.f)
        return snapshot

    def login(self, alias):
        self.stage = 'login_' + alias
        self.shell()
        self.tap('حسابي', shell_tab=True, site='account_tab'); self.tap('تسجيل الدخول أو إنشاء حساب', seek=2, site='login_entry')
        self.wait('رقم واتساب'); self.text('رقم واتساب', self.f['actors'][alias]['phone'], prefix='+967')
        self.tap('إرسال رمز واتساب')
        xml = self.wait('تأكيد والدخول')
        codes = [m[1] for text in self.names(xml) if (m:=re.fullmatch(r'رمز بيئة الاختبار المحلية: ([0-9]{6})',text))]
        if len(codes)!=1:
            raise Incomplete('local_media_local_otp_unobserved')
        self.text('رمز التحقق', codes[0]); self.tap('تأكيد والدخول')
        self.wait('حسابي'); self.checkpoint('authenticated_' + alias)

    def logout(self):
        self.shell()
        self.tap('حسابي', shell_tab=True, site='account_tab'); self.tap('تسجيل الخروج', seek=5)
        xml=self.xml()
        if 'هل تريد تسجيل الخروج؟' in self.names(xml):
            self.tap('تسجيل الخروج')
        self.wait('تسجيل الدخول أو إنشاء حساب')

    def shell(self):
        for _ in range(7):
            xml=self.xml()
            if 'لديك تعديلات غير محفوظة' in self.names(xml):
                raise Incomplete('local_media_unsaved_navigation_refused')
            try:
                select_control(xml,'حسابي',{PACKAGE}|KEYBOARDS,shell_tab=True)
                return
            except Incomplete as error:
                if str(error) not in {'local_media_control_missing','local_media_control_ambiguous'}:
                    raise
            self.input(); self.d.adb('shell','input','keyevent','KEYCODE_BACK'); time.sleep(.4)
        raise Incomplete('local_media_shell_unobserved')

    def editor(self, label='إكمال الإعلان'):
        self.stage = 'open_listing_editor'
        self.shell()
        self.tap('حسابي', shell_tab=True, site='account_tab')
        self.tap('عقاراتي', seek=5, site='owned_listings')
        visible = self.wait(self.f['title'])
        if label not in self.names(visible):
            self.tap('خيارات البطاقة', seek=5, site='listing_actions_menu', listing_title=self.f['title'])
            self.wait(label, site='listing_menu_action_observe')
        self.tap(label, site='edit_listing')
        deadline = min(self.d.deadline,time.monotonic()+35)
        while time.monotonic() < deadline:
            names = self.names(self.xml(site='editor_ready_observe'))
            if 'تعديل الإعلان' in names and names & {'التالي','إضافة صور','معاينة الإعلان','إرسال للمراجعة'}:
                return
            time.sleep(.5)
        raise Incomplete('local_media_editor_unobserved')

    def photos(self):
        self.stage = 'open_photo_step'
        for _ in range(4):
            names = self.names(self.xml())
            if names & {'المواصفات','3/4','إضافة صور'}:
                for attempt in range(8):
                    names = self.names(self.xml())
                    if 'إضافة صور' in names: return
                    self.scroll()
                raise Incomplete('local_media_photo_step_unobserved')
            self.tap('التالي', site='next_editor_step')
        raise Incomplete('local_media_photo_step_unobserved')

    def gallery(self):
        # The add button can appear at the lower edge before its gallery does.
        for attempt in range(5):
            try:
                media_drag_targets(self.xml(),{PACKAGE}|KEYBOARDS)
                return
            except Incomplete as error:
                if str(error) not in {'local_media_control_missing','local_media_control_ordinal_missing',
                    'local_media_drag_viewport_ambiguous','local_media_drag_card_clipped'} or attempt == 4: raise
                self.scroll()

    def reorder(self):
        self.stage = 'media_drag'
        xml = self.xml(); points = media_drag_targets(xml,{PACKAGE}|KEYBOARDS)
        if media_drag_targets(self.xml(),{PACKAGE}|KEYBOARDS) != points:
            raise Incomplete('local_media_control_moved')
        (sx,sy),(tx,ty) = points
        self.input()
        self.d.adb('shell','input','touchscreen','motionevent','DOWN',str(sx),str(sy))
        try:
            time.sleep(.75)
            for step in range(1,9):
                self.d.adb('shell','input','touchscreen','motionevent','MOVE',
                           str(sx+(tx-sx)*step//8),str(sy+(ty-sy)*step//8))
                time.sleep(.06)
        finally:
            self.d.adb('shell','input','touchscreen','motionevent','UP',str(tx),str(ty))
        time.sleep(.5)

    def pick(self, item, replacement=False):
        self.stage = 'pick_replacement_image' if replacement else 'pick_draft_image'
        if not replacement:
            self.tap('إضافة صور', seek=5, site='open_android_picker')
        # ACTION_OPEN_DOCUMENT package was resolved and allowlisted before app start.
        deadline = min(self.d.deadline, time.monotonic()+30)
        reached = set()
        while time.monotonic() < deadline:
            xml = self.xml(picker=True, site='picker_item_candidate')
            _, nodes = ui_nodes(xml, {self.picker, PACKAGE}|KEYBOARDS)
            if self.picker not in {node.get('package') for node in nodes}:
                time.sleep(.35); continue
            try:
                point = picker_item(xml, item['name'], self.picker)
            except Incomplete as error:
                if str(error) != 'local_media_control_missing': raise
                names = self.names(xml)
                for group in (('Downloads','التنزيلات','Download'),
                              ('Show roots','Show navigation drawer','إظهار الجذور','فتح قائمة التنقل')):
                    option = next((label for label in group if label in names), None)
                    if option is not None and group not in reached:
                        self.tap(option, picker=True, site='picker_open_downloads')
                        reached.add(group)
                        break
                time.sleep(.35)
                continue
            fresh = self.xml(picker=True, site='picker_item_revalidate')
            if picker_item(fresh, item['name'], self.picker) != point:
                raise Incomplete('local_media_control_moved')
            self.input()
            self.d.adb('shell','input','tap',*map(str,point))
            break
        else:
            raise Incomplete('local_media_picker_item_unobserved')

        deadline = min(self.d.deadline, time.monotonic()+30)
        confirmed = False
        while time.monotonic() < deadline:
            xml = self.xml(picker=True, site='picker_return_observe')
            _, nodes = ui_nodes(xml, {self.picker, PACKAGE}|KEYBOARDS)
            names = self.names(xml)
            if self.picker not in {node.get('package') for node in nodes}:
                if 'إضافة صور' in names:
                    return
            elif not confirmed:
                option = next((name for name in ('Open','فتح','Select','اختيار','تحديد') if name in names), None)
                if option is not None:
                    self.tap(option, picker=True, site='picker_confirm_selection')
                    confirmed = True
            time.sleep(.35)
        raise Incomplete('local_media_picker_return_unobserved')

    def final_actions(self):
        for _ in range(4):
            xml = self.xml()
            if 'العودة إلى النواقص' in self.names(xml):
                self.tap('العودة إلى النواقص'); continue
            try:
                select_control(xml, 'خيارات المسودة', {PACKAGE}|KEYBOARDS)
                return
            except Incomplete as error:
                if str(error) != 'local_media_control_missing': raise
            self.tap('التالي')
        raise Incomplete('local_media_final_actions_unobserved')

    def save(self):
        # Explicit persistence, not the recovery-only exit-save path.
        self.final_actions()
        self.tap('خيارات المسودة'); self.tap('حفظ مسودة')
        self.wait('عقاراتي',seconds=80); self.wait(self.f['title'])

    def submit(self, updated=False):
        self.final_actions()
        self.tap('خيارات المسودة'); self.tap('معاينة')
        self.wait('معاينة قبل الإرسال'); self.checkpoint('preview')
        self.tap('إرسال للمراجعة',seek=6)
        self.wait('إرسال الإعلان للمراجعة؟'); self.tap('حفظ وإرسال')
        self.wait('عقاراتي',seconds=80)
        self.wait(self.f['updated_title'] if updated else self.f['title'],seconds=80)

    def review_open(self):
        self.shell(); self.tap('الوارد', shell_tab=True, site='support_inbox_tab')
        self.tap('استلام',seek=6)
        # Support claim opens the actual ListingReviewCaseScreen automatically.
        self.wait('تم الاستلام - قيد التحقيق')

    def review_image(self, ordinal, decision):
        for attempt in range(9):
            try:
                box = select_review_control(self.xml(),ordinal+1,{PACKAGE}|KEYBOARDS)
                break
            except Incomplete as error:
                if str(error) != 'local_media_review_card_missing' or attempt == 8: raise
                self.scroll()
        if select_review_control(self.xml(),ordinal+1,{PACKAGE}|KEYBOARDS) != box:
            raise Incomplete('local_media_control_moved')
        self.input(); self.d.adb('shell','input','tap',str((box[0]+box[2])//2),str((box[1]+box[3])//2))
        self.wait('مراجعة صلة الصورة بالعقار')
        self.checkpoint('review_image_' + str(ordinal+1) + '_observed')
        names=self.names(self.xml())
        current=next((n for n in ('تحتاج توضيحًا','مرتبطة بالعقار','غير مرتبطة') if n in names),None)
        if current is None:
            raise Incomplete('local_media_relevance_selector_unobserved')
        self.tap(current)
        self.tap(decision)
        self.text('سبب المراجعة', REASON if decision=='غير مرتبطة' else 'P23 visible synthetic property photograph reviewed.')
        self.tap('حفظ المراجعة')
        deadline = min(self.d.deadline,time.monotonic()+35)
        while time.monotonic() < deadline:
            if 'مراجعة صلة الصورة بالعقار' not in self.names(self.xml()): return
            time.sleep(.5)
        raise Incomplete('local_media_review_dialog_not_closed')

    def approve(self):
        self.tap('قبول ونشر',seek=8); self.wait('اعتماد الإعلان ونشره')
        self.tap('اعتماد ونشر',seek=3)
        self.wait('الوارد',seconds=60)

    def public_view(self, title):
        self.d.adb('shell','am','start','-a','android.intent.action.VIEW','-d',f'realestate://app/properties/{self.f["listing_id"]}',PACKAGE)
        self.wait(title,seconds=60)
        response=local_json('/api/properties/'+str(self.f['listing_id']))
        item=response.get('data',{})
        if item.get('id')!=self.f['listing_id'] or item.get('title')!=title:
            raise Incomplete('local_media_public_response_unproved')
        return {'public_title':item['title'],'native_title_seen':title}

    def run(self, initial):
        if initial['listing']['images'] or initial['listing']['review_status']!='draft':
            raise GateError('local_media_empty_seed_draft_required')
        good=[x for x in self.f['files'] if x['kind']=='good']; bad=next(x for x in self.f['files'] if x['kind']=='bad')
        self.login('advertiser'); self.editor()
        self.checkpoint('listing_editor_opened')
        self.photos()
        self.checkpoint('draft_photo_step_opened')
        for item in (good[0],good[1],bad): self.pick(item)
        self.save(); added=self.checkpoint('media_added',initial)
        self.editor(); self.photos(); self.gallery(); self.reorder()
        self.save(); reordered=self.checkpoint('media_reordered',added)
        self.editor(); self.photos(); self.gallery(); self.tap('خيارات الصورة',ordinal=1)
        self.tap('جعلها الصورة الرئيسية'); self.save(); primary=self.checkpoint('media_primary',reordered)
        self.editor(); self.photos(); self.gallery(); self.tap('إزالة الصورة',ordinal=0)
        self.save(); removed=self.checkpoint('media_removed',primary)
        self.d.adb('shell','am','force-stop',PACKAGE); self.d.adb('shell','am','start','-n',ACTIVITY)
        self.wait('حسابي'); self.editor(); self.photos(); self.gallery(); reopened=self.checkpoint('media_reopened',removed)
        self.submit(); submitted=self.checkpoint('submitted',reopened)
        self.logout(); self.login('support'); self.review_open()
        self.review_image(0,'مرتبطة بالعقار'); self.review_image(1,'غير مرتبطة')
        rejected=self.checkpoint('bad_rejected',submitted)
        self.tap('إرجاع للتصحيح',seek=8); self.wait('إرجاع الإعلان للتصحيح')
        self.text('اكتب للمعلن تحديداً ما الذي يجب تعديله.',REASON); self.tap('تأكيد')
        returned=self.checkpoint('returned',rejected)
        self.logout(); self.login('advertiser'); self.editor('تصحيح الإعلان'); self.photos(); self.gallery()
        self.tap('خيارات الصورة',ordinal=1); self.tap('استبدال الصورة'); self.pick(good[2],replacement=True)
        self.save(); replaced=self.checkpoint('replaced',returned)
        self.editor('تصحيح الإعلان')
        self.submit(); resubmitted=self.checkpoint('resubmitted',replaced)
        self.logout(); self.login('support'); self.review_open()
        self.review_image(0,'مرتبطة بالعقار'); self.review_image(1,'مرتبطة بالعقار'); self.approve()
        approved=self.checkpoint('approved',resubmitted)
        self.logout(); self.login('researcher')
        public=self.checkpoint('public_old',approved,self.public_view(self.f['title']))
        self.d.adb('shell','input','keyevent','KEYCODE_BACK'); self.logout(); self.login('advertiser')
        self.editor('تعديل')
        if 'مراجعة وتعديل البيانات المكتملة والاختيارية' in self.names(self.xml()):
            self.tap('مراجعة وتعديل البيانات المكتملة والاختيارية')
        self.text('عنوان الإعلان *',self.f['updated_title'],seek=5)
        self.submit(updated=True)
        hidden=local_json('/api/properties/'+str(self.f['listing_id']),allow_not_found=True)
        pending=self.checkpoint('pending_edit',public,{'public_status':hidden.get('local_http_status')})
        self.logout(); self.login('support'); self.review_open()
        self.review_image(0,'مرتبطة بالعقار'); self.review_image(1,'مرتبطة بالعقار'); self.approve()
        self.checkpoint('reapproved',pending)
        self.logout(); self.login('researcher')
        self.checkpoint('public_new',public,self.public_view(self.f['updated_title']))
        self.d.adb('shell','input','keyevent','KEYCODE_BACK'); self.logout(); self.checkpoint('finished')


def seal(private, output, fixture, records, result, reason, failure_context=None):
    output.mkdir(mode=0o700)
    manifest={'schema':1,'scope':SCOPE,'source_sha':fixture['source_sha'],'run_id':fixture['run_id'],
              'product_trees':TREES,'result':result,'failure_reason':reason,'checkpoints':records,
              'local_only':True,'phase23_accepted':False,'failure_context':failure_context}
    (private/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
    archive=private.parent/'local-media-evidence.zip'
    try:
        with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as target:
            for path in sorted(private.iterdir()):
                if path.is_symlink() or not path.is_file() or path.suffix not in {'.json','.xml','.png'}:
                    raise GateError('local_media_export_inventory_invalid')
                target.write(path,path.name)
        recipient = REVIEW_RECIPIENT if os.environ.get('PHASE23_LOCAL_JOURNEY_RECIPIENT_SHA256') else RECIPIENT
        encrypted=encrypt(archive,output/'journey.cms',recipient)
    finally:
        archive.unlink(missing_ok=True)
    receipt={**manifest,'checkpoint_count':len(records),'checkpoints':[x['stage'] for x in records],
             'encrypted_evidence':encrypted,'recipient_sha256':RECIPIENT_SHA256,
             'plaintext_exported':False,'apk_exported':False}
    if recipient == REVIEW_RECIPIENT:
        receipt['journey_recipient_sha256'] = REVIEW_RECIPIENT_SHA256
    (output/'PUBLIC_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--apk',required=True,type=Path)
    parser.add_argument('--serial',default='emulator-5554'); parser.add_argument('--fixture',required=True,type=Path)
    parser.add_argument('--max-seconds',type=int,default=1800)
    args=parser.parse_args()
    guard(os.environ)
    if os.environ.get('PHASE23_LOCAL_MEDIA')!='true' or not 60<=args.max_seconds<=1800:
        raise GateError('local_media_explicit_context_required')
    if any(os.environ.get(k) for k in ('AQER_PHASE1_TEST_ACCESS_JSON','AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION',
        'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64','AQER_UAT_KEYSTORE_BASE64','SUPABASE_SERVICE_ROLE_KEY','DATABASE_URL')):
        raise GateError('local_media_live_credentials_refused')
    if digest(RECIPIENT)!=RECIPIENT_SHA256 or RECIPIENT.is_symlink():
        raise GateError('local_media_recipient_invalid')
    if os.environ.get('PHASE23_LOCAL_JOURNEY_RECIPIENT_SHA256') is not None and (
        os.environ['PHASE23_LOCAL_JOURNEY_RECIPIENT_SHA256'] != REVIEW_RECIPIENT_SHA256 or
        REVIEW_RECIPIENT.is_symlink() or not REVIEW_RECIPIENT.is_file() or
        digest(REVIEW_RECIPIENT) != REVIEW_RECIPIENT_SHA256):
        raise GateError('local_media_journey_recipient_invalid')
    fixture=validate_fixture(json.loads(args.fixture.read_text()),os.environ)
    verify_build(args.apk,json.loads((args.fixture.parent/'BUILD_RECEIPT.json').read_text()),fixture)
    d=BaseDevice(args.serial,time.monotonic()+args.max_seconds)
    if d.adb('shell','getprop','ro.build.version.sdk')!='36':
        raise GateError('local_media_api36_required')
    private=Path(tempfile.mkdtemp(prefix='phase23-local-journey-',dir=os.environ.get('RUNNER_TEMP')))
    journey=Journey(d,fixture,args.fixture,private)
    journey.isolation()
    d.adb('shell','am','force-stop',PACKAGE)
    d.adb('install','-r',str(args.apk),timeout=90)
    d.adb('shell','pm','clear',PACKAGE)
    d.adb('shell','mkdir','-p','/sdcard/Download')
    for item in fixture['files']:
        path=Path(item['path'])
        if path.is_symlink() or digest(path)!=item['sha256']:
            raise GateError('local_media_seed_image_changed')
        filename = '/sdcard/Download/'+item['name']
        d.adb('push',str(path),filename)
        d.adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file://'+filename)
    resolved=d.adb('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.OPEN_DOCUMENT','-c','android.intent.category.OPENABLE','-t','image/*')
    components=re.findall(r'^([A-Za-z0-9_.]+)/[A-Za-z0-9_.$]+$',resolved,re.M)
    if len(components)!=1 or components[0] not in PICKERS:
        raise GateError('local_media_picker_not_allowlisted')
    journey.picker=components[0]
    d.adb('shell','am','start','-W','-n',ACTIVITY,timeout=60)
    result,reason,failure_context='COMPLETE',None,None
    try:
        initial=journey.startup(capture_initial=True); journey.run(initial)
    except (Incomplete,GateError) as error:
        result='INCOMPLETE'
        reason=str(error) if re.fullmatch(r'local_media_[a-z_]{1,100}',str(error)) else 'local_media_guard_failure'
        failure_context=journey.persist_startup_failure()
        # Preserve diagnostics only while the independent local boundary still holds.
        try: journey.checkpoint('diagnostic')
        except (Incomplete,GateError): pass
    except (subprocess.SubprocessError,OSError,ValueError):
        result,reason='INCOMPLETE','local_media_executor_failure'
        failure_context=journey.persist_startup_failure()
    finally:
        try: d.adb('shell','am','force-stop',PACKAGE)
        except Exception: result,reason='INCOMPLETE','local_media_cleanup_unverified'
    seal(private,ROOT/'phase23-local-media-sealed',fixture,journey.records,result,reason,failure_context)
    shutil.rmtree(private)
    print(json.dumps({'result':result,'checkpoint_count':len(journey.records),'reason':reason,'phase23_accepted':False}))
    return 0 if result=='COMPLETE' else 2


if __name__=='__main__':
    try: sys_exit=main()
    except (GateError,ValueError,OSError,subprocess.SubprocessError,zipfile.BadZipFile) as error:
        print(json.dumps({'result':'GUARD_REFUSED','reason':str(error) if re.fullmatch('[a-z_]+',str(error)) else 'local_media_guard_failure'}))
        sys_exit=3
    raise SystemExit(sys_exit)
