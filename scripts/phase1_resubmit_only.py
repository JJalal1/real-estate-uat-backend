#!/usr/bin/env python3
"""Exercise only edit and resend on one returned UAT listing in Android."""

import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, build_opener
import uuid

from PIL import Image

from phase1_native_account_readiness import API, SECRET_NAME, validate_access
from phase1_native_fixture_api import FixtureApi, FixtureError, NoRedirect, summary
from prepare_phase1_native_account import PRIVATE, guard
from probe_phase1_native_account import APP, AUTH_LABELS, Blocked, NativeAccount, labels

sys.path.insert(0, str(Path(__file__).resolve().parent / 'phase1_bridge' / 'runtime'))
from owned_vm import OwnedApi36Vm, VmBlocked


class ProofBlocked(RuntimeError):
    pass


def need(value, reason):
    if not value:
        raise ProofBlocked(reason)


def safe_reason(error):
    if isinstance(error, (ProofBlocked, Blocked, FixtureError, VmBlocked)):
        code = str(error)
        if re.fullmatch(r'[a-z][a-z0-9_]{2,100}', code):
            return code
    return type(error).__name__


def api(session, method, path, expected=200, body=None):
    code, result, _ = session._call(method, path, body, token=session._active_token)
    need(code == expected, f'api_{method.lower()}_expected_{expected}_got_{code}')
    return result


def login_support(session, phone, otp):
    api(session, 'POST', '/auth/whatsapp/start', body={'phone': phone, 'intent': 'login'})
    code, response, _ = session._call('POST', '/auth/whatsapp/verify', {'phone': phone, 'code': otp})
    token = response.get('data', {}).get('token')
    if isinstance(token, str) and token:
        session._active_token = token
    need(code == 200 and session._active_token, 'support_login_failed')
    user = api(session, 'GET', '/auth/me')['data']['user']
    need(type(user.get('id')) is int and user['id'] > 0 and user['id'] != 28 and
         'support_agent' in user.get('roles', []) and 'listings.moderate' in user.get('permissions', []) and
         user.get('is_platform_owner') is False, 'known_support_actor_required')


def create_fixture(session, title, run_id, receipt):
    image = io.BytesIO()
    Image.new('RGB', (512, 512), '#176b6c').save(image, format='JPEG', quality=85)
    fields = {
        'title': title, 'description': 'بيانات اصطناعية لاختبار تصحيح إعلان وإعادة إرساله',
        'purpose': 'rent', 'type': 'apartment', 'listing_input_version': '9',
        'price': '50000', 'monthly_rent': '50000', 'currency': 'YER',
        'bedrooms': '3', 'bathrooms': '2',
        'has_parking': '0', 'building_facade': 'north', 'floor_number': '2',
        'unit_number': 'RS' + run_id[-6:], 'building_reference': 'اختبار ' + run_id,
        'address': 'المحافظة: صنعاء - المدينة: صنعاء - المديرية: مديرية الثورة - الحي: حارة الميثاق',
        'latitude': '15.3694', 'longitude': '44.1910', 'contact_phone': '770000028',
    }
    boundary = 'aqer-' + uuid.uuid4().hex
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
             for name, value in fields.items()]
    parts.extend([
        f'--{boundary}\r\nContent-Disposition: form-data; name="images[]"; filename="fixture.jpg"\r\n'
        'Content-Type: image/jpeg\r\n\r\n'.encode(),
        image.getvalue(), f'\r\n--{boundary}--\r\n'.encode(),
    ])
    req = Request(API + '/properties', data=b''.join(parts), method='POST', headers={
        'Accept': 'application/json', 'Authorization': 'Bearer ' + session._active_token,
        'Content-Type': 'multipart/form-data; boundary=' + boundary,
    })
    try:
        with build_opener(NoRedirect()).open(req, timeout=60) as response:
            receipt['create_http'] = response.status
            raw = response.read(2_000_001)
    except HTTPError as error:
        receipt['create_http'] = error.code
        raw = error.read(2_000_001)
    need(len(raw) <= 2_000_000, 'fixture_response_size_bound')
    data = json.loads(raw)
    if receipt['create_http'] != 201:
        receipt['create_validation_fields'] = [key for key in data.get('errors', {})
                                               if re.fullmatch(r'[a-zA-Z0-9_.]+', key)]
        raise ProofBlocked('fixture_creation_not_confirmed')
    result = data['data']
    need(type(result.get('id')) is int and result['id'] > 0 and result.get('title') == title,
         'fixture_create_identity_not_confirmed')
    return result['id']


def read_listing(session, property_id, titles):
    path = f'/properties/{property_id}?_phase1={uuid.uuid4().hex}'
    data = api(session, 'GET', path)['data']
    need(data.get('id') == property_id and data.get('title') in titles and data.get('is_owner') is True
         and data.get('advertiser', {}).get('id') == 28, 'exact_owned_fixture_required')
    return data


def listing_fact(data):
    return {key: data.get(key) for key in ('id', 'title', 'status', 'review_status',
                                         'submitted_at', 'last_review_reason')}


def await_listing(session, property_id, titles, predicate, failure):
    until = time.monotonic() + 85
    while time.monotonic() < until:
        row = read_listing(session, property_id, titles)
        if predicate(row):
            return row
        time.sleep(1.5)
    raise ProofBlocked(failure)


def list_rows(session, path):
    for page in range(1, 21):
        result = api(session, 'GET', f'{path}?per_page=50&page={page}&_phase1={uuid.uuid4().hex}')
        yield from result['data']
        if page == result.get('meta', {}).get('last_page', 1):
            return
    raise ProofBlocked('listing_page_limit')


def recover_fixture_id(session, baseline, titles):
    found = [r['id'] for r in list_rows(session, '/properties/mine/list')
             if r.get('title') in titles and str(r.get('id')) not in baseline['properties']]
    need(len(found) <= 1, 'ambiguous_fixture_cleanup_refused')
    return found[0] if found else None


def return_fixture(support, property_id, reason):
    prefix = f'/admin/listing-review/listings/{property_id}'
    data = api(support, 'POST', prefix + '/start', body={})['data']
    need(data.get('id') == property_id and data.get('review_status') == 'under_review',
         'exact_fixture_claim_unconfirmed')
    data = api(support, 'POST', prefix + '/return', body={'reason': reason})['data']
    need(data.get('id') == property_id and data.get('review_status') == 'returned_for_correction'
         and data.get('last_review_reason') == reason, 'exact_fixture_return_unconfirmed')


def clean_fixture(broker, support, baseline, property_id, titles, receipt):
    if property_id is None:
        property_id = recover_fixture_id(broker, baseline, titles)
    if property_id is not None:
        need(str(property_id) not in baseline['properties'], 'protected_property_cleanup_refused')
        current = read_listing(broker, property_id, titles)
        if current['review_status'] in {'submitted', 'under_review'}:
            return_fixture(support, property_id, 'تنظيف إعلان الاختبار ' + titles[0])
            current = read_listing(broker, property_id, titles)
        need(current['review_status'] in {'draft', 'returned_for_correction'}, 'unsafe_fixture_cleanup_state')
        media_ids = [img['id'] for img in current.get('images', [])]
        drafts = [d['key'] for d in list_rows(broker, '/listing-editor-drafts')
                  if d['key'] not in baseline['drafts'] and (
                      d.get('property_id') == property_id or (
                          d.get('property_id') is None and isinstance(d.get('payload'), dict)
                          and d['payload'].get('title') in titles))]
        for key in drafts:
            uuid.UUID(key)
        api(broker, 'DELETE', f'/properties/{property_id}')
        api(broker, 'GET', f'/properties/{property_id}?_phase1={uuid.uuid4().hex}', expected=404)
        for key in drafts:
            path = '/listing-editor-drafts/' + key
            code, _, _ = broker._call('GET', path, token=broker._active_token)
            if code == 200:
                api(broker, 'DELETE', path)
            api(broker, 'GET', path + '?_phase1=' + uuid.uuid4().hex, expected=404)
        for image_id in media_ids:
            need(type(image_id) is int and image_id > 0, 'invalid_known_media_id')
            api(broker, 'GET', f'/property-media/{image_id}', expected=404)
        receipt.update(property_id=property_id, delete_http=200, property_readback_http=404,
                       linked_drafts_removed=len(drafts), media_routes_404=len(media_ids))
    after = broker._snapshot()
    receipt['baseline_after'] = summary(after)
    need(after == baseline, 'protected_baseline_changed')
    receipt.update(status='PASS', protected_baseline_restored=True)


def app_rows(probe):
    return [row for row in probe.nodes() if row.get('package') == APP and row.get('visible') is True]


def names(rows):
    return set().union(*(labels(row) for row in rows))


def overlap(first, second):
    return max(first[0], second[0]) < min(first[2], second[2]) and max(first[1], second[1]) < min(first[3], second[3])


def leaves(rows):
    return [row for row in rows if not any(other['path'].startswith(row['path'] + '.') for other in rows)]


def unique_control(rows, label, *, clickable):
    matched = [row for row in rows if label in labels(row) and row.get('enabled')]
    direct = [row for row in matched if row.get('clickable') or row['class'] == 'android.widget.Button']
    if not clickable:
        direct = matched
    elif not direct:
        direct = [row for row in rows if row.get('clickable') and row.get('enabled')
                  and any(item['path'].startswith(row['path'] + '.') for item in matched)]
    candidates = leaves(direct)
    need(len({tuple(row['bounds']) for row in candidates}) <= 1, 'ambiguous_native_control_bounds')
    return candidates[0] if candidates else None


def stable_tap(probe, select):
    # Reattaching the input helper changed the account node's pointer witness
    # before dispatch in run 42153305550. Use two fresh matching observations
    # and one ordinary Android shell tap, with a separate UI/API postcondition.
    previous = None
    until = time.monotonic() + 12
    while time.monotonic() < until:
        rows = app_rows(probe)
        need(probe.authenticated and not names(rows) & AUTH_LABELS, 'authenticated_input_surface_required')
        target = select(rows)
        box = tuple(target['bounds']) if target is not None else None
        if box is not None and box == previous:
            left, top, right, bottom = box
            need(0 <= left < right <= 540 and 0 <= top < bottom <= 960
                 and right - left > 8 and bottom - top > 8, 'safe_native_pointer_bounds_required')
            probe.adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
            return
        previous = box
        time.sleep(.3)
    raise ProofBlocked('stable_exact_native_control_not_observed')


def tap(probe, label, *, seek=False):
    if seek:
        probe.seek(label, attempts=5)
    stable_tap(probe, lambda rows: unique_control(rows, label, clickable=True))


def card_control(rows, title, other_titles, control, *, reason=None):
    if 'عقاراتي' not in names(rows):
        return None
    anchor = unique_control(rows, title, clickable=False)
    if anchor is None:
        return None
    start = anchor['bounds'][1]
    end = min((row['bounds'][1] for row in rows
               if row['bounds'][1] > start and labels(row) & other_titles), default=960)
    if reason is not None:
        marker = unique_control(rows, reason, clickable=False)
        if marker is None or not start <= marker['bounds'][1] < end:
            return None
        start = marker['bounds'][1]
        end = min(end, marker['bounds'][3] + 155)
    else:
        end = min(end, start + 270)
    scoped = [row for row in rows if start <= row['bounds'][1] < end]
    target = unique_control(scoped, control, clickable=reason is not None)
    if target is not None and reason is not None and any(
            overlap(row['bounds'], target['bounds']) for row in rows
            if 'إضافة عقار' in labels(row) and row.get('clickable')):
        return None
    return target


def reveal_card_control(probe, title, select):
    probe.seek(title, attempts=6)
    for attempt in range(7):
        rows = app_rows(probe)
        need('عقاراتي' in names(rows) and unique_control(rows, title, clickable=False),
             'same_fixture_card_required_during_reveal')
        if select(rows) is not None:
            return
        if attempt < 6:
            probe.scroll('forward', short=True)
    raise ProofBlocked('fixture_card_action_not_visible')


def frame(probe, name, required):
    def safe():
        rows = probe.nodes()
        observed = names(rows)
        need(probe.authenticated and not observed.intersection(AUTH_LABELS) and required <= observed,
             'private_or_unmatched_frame_refused')
        visible = '\n'.join(observed)
        need(not any(value and value in visible for value in probe.private_values), 'private_frame_refused')
    safe()
    png = probe.adb('exec-out', 'screencap', '-p', binary=True)
    with Image.open(io.BytesIO(png)) as image:
        need(image.format == 'PNG' and image.size == (540, 960), 'native_png_dimensions_invalid')
        image.verify()
    safe()
    file = name + '.png'
    (probe.out / file).write_bytes(png)
    probe.report['frames'].append({'file': file, 'sha256': hashlib.sha256(png).hexdigest(),
                                   'bytes': len(png), 'capture': 'android_api36_adb_screencap'})
    probe.save()


def use_fallback_and_confirm(probe):
    probe.wait('تحديد السعي قبل إرسال الإعلان')
    rate_label = 'نسبة السعي %'
    if not probe.has(rate_label):
        tap(probe, 'نسبة مئوية %')
        probe.wait(rate_label)
    if probe.field(rate_label, seek=False).get('text', '').strip() not in {'0', '٠'}:
        probe.set(rate_label, '0')
    until = time.monotonic() + 12
    while time.monotonic() < until:
        rows = app_rows(probe)
        observed = names(rows)
        rejects = [row for row in rows if 'رفض' in labels(row)]
        need(not observed.intersection(AUTH_LABELS | {'قبول'}) and len(rejects) <= 1 and
             all(labels(row) == {'رفض'} and row.get('class') == 'android.view.View' and
                 row.get('editable') is False for row in rejects), 'custom_sai_decision_refused')
        notices = [s for s in observed if re.fullmatch(r'اختيار 0% يفعّل السعي الثابت [0-9]+% تلقائيًا\.', s)]
        field = probe.field(rate_label, seek=False)
        if len(notices) == 1 and field.get('text', '').strip() in {'0', '٠'} and \
                {'تحديد السعي قبل إرسال الإعلان', 'تأكيد السعي والمتابعة', 'العودة بدون إرسال'} <= observed:
            tap(probe, 'تأكيد السعي والمتابعة')
            return
        time.sleep(.5)
    raise ProofBlocked('zero_platform_sai_confirmation_not_ready')


def prepare_android(probe):
    temp = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    recipe = temp / 'aqer-resubmit-build.sh'
    need(recipe.is_file() and not recipe.is_symlink(), 'reviewed_build_recipe_required')
    android = temp / 'aqer-native-account-android'
    homes = {'ANDROID_USER_HOME': str(android), 'ANDROID_EMULATOR_HOME': str(android),
             'ANDROID_AVD_HOME': str(android / 'avd')}
    allowed = {'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL', 'TZ', 'CI',
               'TMPDIR', 'TEMP', 'TMP', 'JAVA_HOME', 'FLUTTER_ROOT', 'PUB_CACHE', 'ANDROID_HOME',
               'ANDROID_SDK_ROOT', 'GRADLE_USER_HOME', 'RUNNER_TEMP', 'GITHUB_ACTIONS',
               'GITHUB_REPOSITORY', 'GITHUB_REF', 'GITHUB_EVENT_NAME', 'GITHUB_SHA',
               'GITHUB_RUN_ID', 'GITHUB_RUN_NUMBER', 'GITHUB_RUN_ATTEMPT', 'SOURCE_COMMIT',
               'AQER_PHASE1_NATIVE_ACCOUNT', 'AQER_PHASE1_RESUBMIT_ONLY', 'UAT_API_BASE_URL',
               'QT_QPA_PLATFORM', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'HTTP_PROXY', 'HTTPS_PROXY',
               'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy'}
    build_env = {key: value for key, value in os.environ.items() if key in allowed}
    build_env.update(homes, AQER_ALLOW_DEBUG_RELEASE_SIGNING='true', AQER_PHASE1_RELEASE_UI_TEST='true')
    result = subprocess.run(['bash', str(recipe)], env=build_env, timeout=18 * 60)
    need(result.returncode == 0, 'verified_android_preparation_failed')
    os.environ.update(homes)
    probe.env.update(homes)
    return OwnedApi36Vm(build_env)


def main():
    env = dict(os.environ)
    guard(env)
    need(env.get('AQER_PHASE1_RESUBMIT_ONLY') == 'true', 'resubmit_only_context_required')
    access = validate_access(env[SECRET_NAME])
    need('support' in access['phones'], 'known_support_credential_required')
    run_id = env['GITHUB_RUN_ID']
    title = 'اختبار التصحيح AQER-RS-' + run_id
    corrected = title + ' بعد التعديل'
    reason = 'صحح عنوان إعلان الاختبار AQER-RS-' + run_id
    broker = FixtureApi(access['phones']['broker'], access['otp'], run_id)
    support = FixtureApi(access['phones']['support'], access['otp'], run_id)
    probe = NativeAccount(PRIVATE, env)
    probe.private_values.update({access['phones']['support'], access['phones']['support'].lstrip('+')})
    vm = None
    receipt = {'scope': 'Android correction and resubmission only', 'status': 'BLOCKED',
               'baseline_source': 'd3eacc6986827862a0f129ad973a9a13842a9938', 'cleanup': {}}
    probe.report['scope'] = receipt['scope']
    probe.report['resubmit'] = receipt
    baseline = property_id = None
    stage = 'authorized_fixture_login'
    try:
        login_receipt = {}
        broker._login(login_receipt)
        receipt['broker_api_identity'] = login_receipt['identity']
        login_support(support, access['phones']['support'], access['otp'])
        baseline = broker._snapshot()
        receipt['baseline_before'] = summary(baseline)
        stage = 'create_fixture'
        property_id = create_fixture(broker, title, run_id, receipt)
        receipt['fixture_property_id'] = property_id
        need(str(property_id) not in baseline['properties'], 'new_fixture_required')
        row = read_listing(broker, property_id, {title})
        need(row.get('review_status') == 'draft' and len(row.get('images', [])) == 1, 'draft_fixture_invalid')
        stage = 'configure_fixture_platform_fallback'
        sai = api(broker, 'PUT', f'/properties/{property_id}/sai', body={
            'sai_payer': 'tenant', 'sai_amount_type': 'percentage', 'broker_sai_rate_percent': 0,
        })['data']['sai_management']
        need(sai.get('source_mode') == 'platform_fallback' and sai.get('requested_broker_rate_percent') == 0,
             'fixture_platform_fallback_unconfirmed')
        receipt['fixture_platform_fallback'] = True
        stage = 'initial_fixture_submit'
        submitted = api(broker, 'POST', f'/properties/{property_id}/submit', body={})['data']
        need(submitted.get('id') == property_id and submitted.get('review_status') == 'submitted',
             'initial_fixture_submit_unconfirmed')
        stage = 'claim_and_return_fixture'
        return_fixture(support, property_id, reason)
        before = read_listing(broker, property_id, {title})
        need(before.get('review_status') == 'returned_for_correction' and before.get('last_review_reason') == reason,
             'returned_fixture_required')
        receipt['before_edit'] = listing_fact(before)
        probe.save()
        print('RESUBMIT_FIXTURE_READY', flush=True)

        stage = 'verified_android_preparation'
        vm = prepare_android(probe)
        vm.start()
        vm.prepare_utc_clock(deadline=time.monotonic() + 90)
        probe.validate_and_install()
        probe.startup()

        stage = 'native_broker_login'
        probe.login()
        stage = 'open_broker_account'
        if not probe.has('عقاراتي'):
            tap(probe, 'حسابي')
        stage = 'open_my_listings'
        tap(probe, 'عقاراتي', seek=True)
        probe.wait('عقاراتي')
        probe.wait('إضافة عقار', seconds=85)
        other_titles = {row['title'] for row in list_rows(broker, '/properties/mine/list')
                        if row['id'] != property_id}
        stage = 'open_exact_correction_card'
        correction_menu = lambda rows: card_control(rows, title, other_titles, 'خيارات البطاقة', reason=reason)
        reveal_card_control(probe, title, correction_menu)
        stable_tap(probe, correction_menu)
        tap(probe, 'تصحيح الإعلان')
        probe.wait('تعديل الإعلان')
        stage = 'edit_exact_title'
        field = 'عنوان الإعلان *'
        probe.require_value(field, title)
        probe.set(field, corrected)
        probe.require_value(field, corrected)
        frame(probe, 'resubmit-edited-title', {'تعديل الإعلان', corrected})
        stage = 'save_correction'
        for step in range(1, 4):
            if probe.has('خيارات المسودة'):
                break
            tap(probe, 'التالي')
            probe.wait(f'{step + 1}/4', seconds=20)
        tap(probe, 'خيارات المسودة')
        tap(probe, 'حفظ مسودة')
        edited = await_listing(broker, property_id, {title, corrected}, lambda row: row['title'] == corrected,
                               'native_edit_not_persisted')
        receipt['after_edit'] = listing_fact(edited)
        need(edited.get('review_status') == 'returned_for_correction' and edited.get('last_review_reason') == reason,
             'edited_fixture_lost_return_state_or_reason')
        probe.wait('عقاراتي', seconds=85)
        probe.wait('إضافة عقار', seconds=85)
        stage = 'open_resend_confirmation'
        resend = lambda rows: card_control(rows, corrected, other_titles, 'إعادة الإرسال', reason=reason)
        reveal_card_control(probe, corrected, resend)
        frame(probe, 'resubmit-corrected-returned', {corrected, reason, 'إعادة الإرسال'})
        stable_tap(probe, resend)
        probe.wait('إعادة إرسال الإعلان؟')
        tap(probe, 'متابعة')
        stage = 'confirm_resend_platform_fallback'
        use_fallback_and_confirm(probe)
        stage = 'read_server_resubmission'
        after = await_listing(broker, property_id, {corrected},
                              lambda row: row.get('review_status') == 'submitted' and row.get('status') == 'pending',
                              'native_resubmission_not_persisted')
        need(after.get('last_review_reason') is None and after.get('can_edit') is False,
             'submitted_state_incomplete')
        receipt['after_resend'] = listing_fact(after)
        receipt['owner_readback_http'] = 200
        history = api(support, 'GET', f'/admin/listing-review/listings/{property_id}')['data']
        transitions = [row for row in history['review_history']
                       if row.get('action') == 'submitted' and row.get('from') == 'returned_for_correction'
                       and row.get('to') == 'submitted']
        need(history.get('id') == property_id and history.get('review_status') == 'submitted' and
             history.get('submitted_at') and len(transitions) == 1, 'actual_resubmission_history_missing')
        receipt['server_transition'] = {'from': 'returned_for_correction', 'to': 'submitted', 'http': 200,
                                        'submitted_at': history['submitted_at'],
                                        'review_history_id': transitions[0]['id']}
        stage = 'capture_pending_review'
        probe.wait('عقاراتي', seconds=85)
        probe.wait('إضافة عقار', seconds=85)
        reveal_card_control(probe, corrected,
                            lambda rows: card_control(rows, corrected, other_titles, 'بانتظار المراجعة'))
        frame(probe, 'resubmit-pending-review', {corrected, 'بانتظار المراجعة'})
        receipt['status'] = 'PASS'
        probe.report['submission_executed'] = True
    except Exception as error:
        receipt.update(failed_stage=stage, reason=safe_reason(error))
    finally:
        cleanup = receipt['cleanup']
        try:
            if probe.auth_attempted:
                probe.native_logout()
                cleanup['native_logout'] = probe.report.get('session_logged_out') is True
        except Exception:
            cleanup['native_logout'] = False
        cleanup['vm'] = vm.close(deadline=time.monotonic() + 45) if vm is not None else {'created': False}
        try:
            if baseline is not None:
                clean_fixture(broker, support, baseline, property_id, {title, corrected}, cleanup)
            else:
                cleanup['status'] = 'NO_FIXTURE_REQUESTED'
        except Exception as error:
            cleanup.update(status='BLOCKED', reason=safe_reason(error))
        for role, session in [('broker', broker), ('support', support)]:
            evidence = {}
            session._logout(evidence)
            cleanup[role + '_api_session'] = evidence
            session.clear_credentials()
        probe.save()
    passed = receipt['status'] == 'PASS' and cleanup.get('status') == 'PASS' and cleanup.get('native_logout') is True \
        and cleanup['vm'].get('owned_process_group_absence_observed') is True \
        and all(cleanup[role + '_api_session'].get('fresh_session_cleaned') is True for role in ('broker', 'support'))
    print(json.dumps({'status': 'PASS' if passed else 'BLOCKED', 'stage': receipt.get('failed_stage'),
                      'reason': receipt.get('reason'), 'cleanup': cleanup.get('status')}, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('RESUBMIT_PREFLIGHT_BLOCKED')
        sys.exit(1)
