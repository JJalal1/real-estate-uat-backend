"""LOCAL C4 proposal. Import is inert; Root alone supplies the live probe.

One call advances one stage. Missing review is a harmless pause. Any exception
after a stage is reserved permanently holds that stage for Root reconciliation;
there is no replay, cleanup, API fallback, auth input, or C2 implementation here.
"""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import uuid
from ci_remote_evidence import normalize_c4_review, reject_duplicate_pairs

APP = 'com.aqer.yemen.uat'
AI_NOTICE = 'راجع التفاصيل والنص قبل تطبيقها على مسودتك.'
FALLBACK_NOTICE = 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.'
BRIEF = ('شقة للإيجار في صنعاء في الدور الثاني، رقم الشقة 7، '
         'ثلاث غرف نوم وحمامان، دون موقف سيارة، واجهة شمالية.')
APPLY = 'استخدام البيانات والمتابعة'
UNIT = 'موضع الشقة داخل الدور (اختياري)'
RENT = 'الإيجار الشهري بالريال اليمني *'
REVIEW_ALL = 'مراجعة وتعديل البيانات المكتملة والاختيارية'
BACK_GAPS = 'العودة إلى النواقص'
KEY = 'local_c4_executor'
EXPECTED = {'type': 'apartment', 'purpose': 'rent', 'governorate': 'صنعاء',
            'floor_number': '2', 'unit_number': '7', 'bedrooms': '3',
            'bathrooms': '2', 'has_parking': False, 'building_facade': 'north'}
AUTH = {'مرحبًا بعودتك', 'رقم واتساب', 'رمز التحقق', 'رمز التحقق عبر واتساب',
        'تأكيد والدخول', 'إرسال رمز واتساب', 'تسجيل الدخول أو إنشاء حساب'}


class C4Blocked(RuntimeError):
    """Fixed diagnostics only, without arbitrary UI or exception values."""


def need(ok, code):
    if not ok:
        raise C4Blocked(code)


def names(row):
    return {s.strip() for key in ('text', 'description', 'hint')
            for s in str(row.get(key, '')).splitlines() if s.strip()}


def digits(value):
    return str(value).translate(str.maketrans('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
                                             (''.join(str(value) for value in range(10)) * 2))).strip()


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def save(probe):
    probe.save()


def identity(probe):
    report = probe.report
    key, tag, title = report.get('fixture_key'), report.get('fixture_tag'), probe.title
    try:
        valid = str(uuid.UUID(key)) == key
    except (ValueError, TypeError, AttributeError):
        valid = False
    need(valid and isinstance(tag, str) and re.fullmatch(r'AQER-C1-[a-f0-9]{12}', tag)
         and isinstance(title, str) and title.count(tag) == 1,
         'c4_original_fixture_identity_required')
    need(report.get('held_after_c1_restore_for_root_review') is True and
         any(r.get('id') == 'C1-force-stop-restore' and r.get('status') == 'PASS'
             for r in report.get('cases', [])), 'c4_actual_c1_restore_required')
    return key, tag, title


def safe_rows(probe):
    need(probe.authenticated is True and getattr(probe, 'recorder', None) is None,
         'c4_authenticated_unrecorded_context_required')
    rows = probe.nodes()
    need(not any(names(row) & AUTH for row in rows), 'c4_auth_context_refused')
    return rows


def scene(rows):
    # Only called after the auth/private-context guard; no auth witness is hashed.
    return digest([{k: row.get(k) for k in ('path', 'witness', 'text', 'description',
                   'hint', 'bounds', 'enabled', 'visible', 'editable', 'clickable', 'class')}
                   for row in rows])


def ai_scene(probe):
    ai_context(probe)  # Privacy check precedes any synthetic UI witness digest.
    return scene(safe_rows(probe))


def frame(probe, name):
    need(isinstance(name, str) and re.fullmatch(r'C1-[a-z0-9-]+\.png', name),
         'c4_review_frame_name_invalid')
    rows = [r for r in probe.report.get('frames', []) if r.get('file') == name]
    need(len(rows) == 1 and rows[0].get('authenticated_editor_only') is True,
         'c4_actual_recorded_frame_required')
    path = Path(probe.out) / name
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 32*1024*1024,
         'c4_actual_frame_file_required')
    data = path.read_bytes()
    actual = hashlib.sha256(data).hexdigest()
    need(data.startswith(b'\x89PNG\r\n\x1a\n') and actual == rows[0].get('sha256'),
         'c4_actual_frame_digest_mismatch')
    return actual


def video(probe, name):
    need(name == 'C1-c4-restored-facts.webm', 'c4_restore_clip_name_required')
    rows = [r for r in probe.report.get('videos', []) if r.get('file') == name]
    need(len(rows) == 1, 'c4_actual_restore_clip_required')
    row = rows[0]
    need(row.get('capture') == 'official_emulator_console_host_webm' and
         row.get('authentication_frames') is False and
         type(row.get('duration_s')) in (int, float) and 0 < row['duration_s'] <= 125,
         'c4_actual_validated_host_clip_required')
    path = Path(probe.out) / name
    need(path.is_file() and not path.is_symlink() and 1024 <= path.stat().st_size <= 64*1024*1024,
         'c4_actual_restore_clip_file_required')
    data = path.read_bytes()
    actual = hashlib.sha256(data).hexdigest()
    need(data[:4] == b'\x1a\x45\xdf\xa3' and actual == row.get('sha256'),
         'c4_actual_restore_clip_digest_mismatch')
    return {'file': name, 'sha256': actual, 'duration_s': row['duration_s']}


def review(probe, state, filename, cursor, frames):
    path = Path(probe.out) / filename
    if not path.exists():
        return None
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16384
         and path.stat().st_mode & 0o077 == 0, 'c4_private_root_review_file_required')
    try:
        data = normalize_c4_review(json.loads(path.read_text(), object_pairs_hook=reject_duplicate_pairs),
            expected_cursor=cursor, expected_frames=frames, actual_video=state.get('restore_video'))
    except (ValueError, UnicodeError):
        raise C4Blocked('c4_root_review_json_invalid') from None
    need(isinstance(data, dict) and data.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW'
         and data.get('phase') == 'C4' and data.get('case') == 'C4-native-saved-draft'
         and data.get('cursor') == cursor and data.get('fixture_key') == state['fixture_key']
         and data.get('fixture_tag') == state['fixture_tag'] and data.get('title') == state['title']
         and data.get('privacy_checked') is True and data.get('manual_review_completed') is True,
         'c4_actual_same_fixture_case_review_required')
    need(isinstance(frames, dict) and frames and data.get('frames') == frames,
         'c4_review_must_bind_exact_actual_frames')
    for name, wanted in frames.items():
        need(frame(probe, name) == wanted, 'c4_review_frame_changed')
    return data


def ensure_session(probe):
    if probe.adapter is None:
        probe.start_session()


def close_session(probe):
    if probe.adapter is not None:
        probe.stop_session('C4_segment_complete_root_visual_boundary')


def ai_context(probe):
    need(probe.authenticated is True and not getattr(probe, '_host_stop_unconfirmed', False),
         'c4_safe_ai_capture_context_required')
    rows = probe._capture_full_rows()
    need(not probe._capture_rows_private(rows), 'c4_private_ai_capture_refused')
    visible = [r for r in rows if r.get('visible')]
    labels = set().union(*(names(r) for r in visible)) if visible else set()
    sheet_labels = {AI_NOTICE, 'عنوان الإعلان', 'نص الإعلان', 'راجع ما سيتغير',
                    'نوع العقار', 'الغرض', 'المحافظة', 'غرف النوم', 'الحمامات',
                    'الدور', 'موضع الوحدة', 'موقف السيارة', 'واجهة البناء'}
    need((APPLY in labels and bool(labels & sheet_labels)) or
         ('جهّز إعلانك بسرعة' in labels and 'صف العقار' in labels),
         'c4_actual_prepare_sheet_required')
    return visible


def ai_capture(probe, name):
    """Separate narrow AI-sheet extension of the existing host PNG protocol.

    The current controller is untouched. Existing full-tree privacy checks,
    official host console and PNG validation are reused before and after capture.
    No auth, account profile, rent/contact view or guest screencap is allowed.
    """
    return _host_png(probe, name, ai_context, 'actual_listing_prepare_sheet_privacy_checked')


def spec_copy_context(probe):
    need(probe.authenticated is True and not getattr(probe, '_host_stop_unconfirmed', False),
         'c4_safe_restored_copy_capture_context_required')
    rows = probe._capture_full_rows()
    need(not probe._capture_rows_private(rows), 'c4_private_restored_copy_capture_refused')
    visible = [r for r in rows if r.get('visible')]
    labels = set().union(*(names(r) for r in visible)) if visible else set()
    need('وصف العقار' in labels and
         bool({'إضافة عقار', 'تعديل الإعلان'} & labels) and
         ('التالي' in labels or BACK_GAPS in labels),
         'c4_actual_restored_spec_copy_editor_required')


def _host_png(probe, name, guard, context):
    need(re.fullmatch(r'C1-c4-[a-z0-9-]+', name) is not None,
         'c4_safe_capture_name_required')
    need(getattr(probe, 'recorder', None) is None, 'c4_ai_capture_without_recording_required')
    guard(probe)
    destination = Path(probe.out) / (name + '.png')
    need(not destination.exists(), 'c4_capture_name_already_exists')
    with tempfile.TemporaryDirectory(prefix='c4-png-', dir=probe._host_capture_root()) as directory:
        folder = Path(directory)
        probe._console('screenshot', folder)
        files = list(folder.iterdir())
        need(len(files) == 1 and not files[0].is_symlink() and files[0].is_file()
             and files[0].suffix.lower() == '.png', 'c4_host_png_output_not_unique')
        data = files[0].read_bytes()
        dims = probe._validate_png(data)
        guard(probe)
        destination.write_bytes(data)
        destination.chmod(0o600)
    probe.report['frames'].append({'file': destination.name, 'bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(), 'width': dims[0], 'height': dims[1],
        'authenticated_editor_only': True, 'capture': 'official_emulator_console_host_png',
        'context': context})
    save(probe)
    return {destination.name: frame(probe, destination.name)}


def capture(probe, name):
    probe.safe_capture(name)
    return {name + '.png': frame(probe, name + '.png')}


def blank_rent(probe):
    row = probe.field(RENT)
    # The ordinary rent field has source-known hint '0'; that is not entered
    # content. Native getText must itself be empty. Entered zero still blocks.
    value = row.get('text')
    need(isinstance(value, str) and value.strip() == '',
         'c4_monthly_rent_must_be_actually_blank')


def copy_digest(probe, label):
    row = probe.field(label)
    value = row.get('text')
    need(isinstance(value, str) and value.strip() and value.strip() != label,
         'c4_actual_native_copy_readback_required')
    return hashlib.sha256(value.strip().encode()).hexdigest()


def selected_review(data):
    need(data.get('actual_ai_notice') == AI_NOTICE and
         data.get('literal_fallback_notice_visible') is False and
         data.get('all_selected_fields_and_copy_reviewed') is True and
         data.get('copy_has_only_supplied_facts') is True,
         'c4_actual_ai_all_proposals_copy_review_required')
    existing = data.get('verified_existing_draft_copy_facts')
    need(type(existing) is dict and set(existing) <= {'address','governorate','district','street','city'}
         and all(type(v) is str and 0 < len(v) <= 240 for v in existing.values()),
         'c4_verified_existing_copy_facts_required')
    selected = data.get('selected_fields')
    need(isinstance(selected, dict) and {'floor_number', 'unit_number'} <= selected.keys(),
         'c4_explicit_floor_and_unit_proposals_required')
    for field, value in selected.items():
        need(field in EXPECTED, 'c4_unsupported_selected_field_refused')
        wanted = EXPECTED[field]
        if field in {'floor_number', 'unit_number', 'bedrooms', 'bathrooms'}:
            need(digits(value) == wanted, 'c4_selected_proposal_fact_mismatch')
        else:
            need(type(value) is type(wanted) and value == wanted,
                 'c4_selected_proposal_fact_mismatch')


def reserve(probe, state, stage):
    need(state.get('inflight') is None and state.get('uncertain') is not True,
         'c4_uncertain_action_requires_root_reconciliation_no_replay')
    state['inflight'] = stage
    save(probe)  # Durable reservation precedes every stage with UI/lifecycle input.


def finish(probe, state, cursor):
    close_session(probe)
    state['cursor'], state['inflight'] = cursor, None
    state.pop('held_error', None)
    save(probe)
    return {'phase': 'C4', 'cursor': cursor, 'held_for_root': True,
            'c4_accepted': state.get('accepted', False), 'c2_executed': False}


def prepare(probe, state):
    reserve(probe, state, 'prepare_request')
    ensure_session(probe)
    safe_rows(probe)
    probe.require_value('عنوان الإعلان *', state['title'])
    probe.tap('جهّز الإعلان بالصوت أو المساعد')
    probe.wait('صف العقار')
    probe.set('صف العقار', BRIEF)
    probe.require_value('صف العقار', BRIEF)
    state['prepared_brief_scene'] = ai_scene(probe)
    # End before the network request; each subsequent segment uses its own
    # fresh signed authority without refreshing an existing grant.
    return finish(probe, state, 'REQUEST')


def prepared_brief_context(probe, state):
    ensure_session(probe)
    observed = ai_scene(probe)
    need(observed == state.get('prepared_brief_scene'), 'c4_prepared_brief_scene_changed')
    probe.require_value('صف العقار', BRIEF)
    return observed


def request_prepared(probe, state):
    reserve(probe, state, 'prepare_request')
    prepared_brief_context(probe, state)
    probe.tap('جهّز الإعلان')
    probe.wait(APPLY, seconds=120)
    # Preserve the actual response before any scrolling. This diagnostic is
    # neither an AI-source assertion nor a visual acceptance decision.
    state['response_ready_frames'] = ai_capture(probe, 'C1-c4-response-ready')
    state['response_ready_scene'] = ai_scene(probe)
    return finish(probe, state, 'RESPONSE_READY')


def seek_ai_notice(probe, state):
    # Short overlapping physical swipes avoid skipping the small notice with
    # full flings. Inspect the literal fallback too; never relabel it as AI.
    directions = ('backward',) * 4 + ('forward',) * 8
    diagnostic = {'observations': 0, 'short_scrolls_completed': 0,
                  'ai_notice_seen': False, 'literal_fallback_seen': False}
    state['notice_seek'] = diagnostic
    for index in range(len(directions) + 1):
        rows = [row for row in safe_rows(probe) if row.get('visible') is True]
        diagnostic['observations'] += 1
        diagnostic['ai_notice_seen'] = any(AI_NOTICE in names(row) for row in rows)
        diagnostic['literal_fallback_seen'] = any(FALLBACK_NOTICE in names(row) for row in rows)
        save(probe)
        need(not diagnostic['literal_fallback_seen'], 'c4_literal_fallback_observed_no_ai_acceptance')
        if diagnostic['ai_notice_seen']:
            return
        if index < len(directions):
            probe.scroll(directions[index], short=True)
            diagnostic['short_scrolls_completed'] += 1
            save(probe)
    need(False, 'c4_actual_ai_notice_not_observed_after_bounded_short_seek')


def collect_response(probe, state):
    reserve(probe, state, 'collect_response')
    ensure_session(probe)
    need(ai_scene(probe) == state.get('response_ready_scene'), 'c4_response_ready_scene_changed')
    # Notice must be observed literally on the real native sheet. This does not
    # inspect a response source field or establish the provider used.
    seek_ai_notice(probe, state)
    rows = safe_rows(probe)
    need(any(AI_NOTICE in names(r) for r in rows) and
         not any(FALLBACK_NOTICE in names(r) for r in rows),
         'c4_actual_ai_notice_required_no_fallback')
    frames = ai_capture(probe, 'C1-c4-ai-notice')
    probe.seek('عنوان الإعلان')
    frames.update(ai_capture(probe, 'C1-c4-ai-title-copy'))
    probe.seek('نص الإعلان')
    frames.update(ai_capture(probe, 'C1-c4-ai-copy'))
    state['request_copy_sha256'] = copy_digest(probe, 'نص الإعلان')
    probe.seek('راجع ما سيتغير')
    frames.update(ai_capture(probe, 'C1-c4-ai-proposals-top'))
    # Capture bounded native scrolls; Root must review all cards. No card is
    # toggled, filled, or accepted by this scan.
    for index in range(3):
        probe.scroll('forward')
        frames.update(ai_capture(probe, 'C1-c4-ai-proposals-' + str(index + 1)))
    state['ai_frames'] = frames
    state['ai_scene'] = ai_scene(probe)
    state['source_evidence'] = 'inferred from exact live native notice/source mapping'
    state['raw_response_source_observed'] = False
    state['provider_evidence_from_AI04'] = False
    return finish(probe, state, 'AI_REVIEW')


def edit_title(probe, state, data):
    selected_review(data)
    need(data.get('all_proposal_cards_visible_in_reviewed_frames') is True,
         'c4_all_actual_cards_review_required')
    reserve(probe, state, 'edit_reviewed_title')
    ensure_session(probe)
    need(ai_scene(probe) == state['ai_scene'], 'c4_reviewed_ai_scene_changed')
    ai_context(probe)
    # Preserve the original same-draft synthetic title and exact unique tag.
    probe.set('عنوان الإعلان', state['title'])
    probe.require_value('عنوان الإعلان', state['title'])
    frames = ai_capture(probe, 'C1-c4-edited-title')
    state['reviewed_copy_sha256'] = copy_digest(probe, 'نص الإعلان')
    need(state['reviewed_copy_sha256'] == state['request_copy_sha256'],
         'c4_reviewed_proposal_copy_changed')
    # Reading copy can scroll the sheet; restore the reviewed title/apply view.
    probe.seek('عنوان الإعلان')
    frames.update(ai_capture(probe, 'C1-c4-edited-title-apply'))
    ai_context(probe)
    rows = safe_rows(probe)
    need(probe.matching(rows, APPLY), 'c4_copy_not_ready_after_title_edit')
    state['apply_frames'], state['apply_scene'] = frames, scene(rows)
    state['selected_fields'] = data['selected_fields']
    return finish(probe, state, 'APPLY_REVIEW')


def apply_reviewed(probe, state, data):
    need(data.get('same_exact_tagged_title_and_apply_visually_verified') is True and
         data.get('approved_proposal_frames') == state['ai_frames'],
         'c4_reviewed_actual_title_and_apply_required')
    reserve(probe, state, 'apply_once')
    ensure_session(probe)
    rows = safe_rows(probe)
    ai_context(probe)
    rows = safe_rows(probe)  # Fresh action lease after privacy check.
    need(scene(rows) == state['apply_scene'], 'c4_reviewed_apply_scene_changed')
    matches = [r for r in probe.matching(rows, APPLY)
               if r.get('clickable') or r.get('class') == 'android.widget.Button']
    need(len({r['path'] for r in matches}) == 1, 'c4_unique_reviewed_apply_button_required')
    probe.act('click', matches[0])  # Exactly one fresh, native self-targeted input.
    probe.wait('خيارات المسودة', seconds=60)
    blank_rent(probe)  # No capture or recording of completion/contact fields.
    state['native_apply_delivered'] = True
    state['monthly_rent_blank_after_apply'] = True
    return finish(probe, state, 'SAVE')


def save_draft(probe, state):
    reserve(probe, state, 'explicit_account_draft_save_once')
    ensure_session(probe)
    safe_rows(probe)
    blank_rent(probe)
    probe.tap('خيارات المسودة')
    probe.tap('حفظ مسودة')
    probe.wait('حُفظت المسودة على حسابك. يمكنك إكمالها لاحقًا.', seconds=120)
    state['explicit_native_account_draft_save_delivered'] = True
    return finish(probe, state, 'REOPEN')


def reopen(probe, state):
    reserve(probe, state, 'force_stop_reopen_same_draft_once')
    close_session(probe)
    probe.adb('shell', 'am', 'force-stop', APP)
    probe.authenticated = False
    probe.startup()
    # Existing saved session only. No credential reads, login or storage reads.
    probe.authenticated_account_evidence(seconds=45)
    probe.authenticated = True
    probe.manual_entry(state['title'])
    probe.wait('خيارات المسودة')
    blank_rent(probe)
    state['force_stop_without_reset'] = True
    # The explicit save above persists completion_only=true. Its review link
    # can be below the viewport, so use the ordinary bounded seek in tap().
    # An unexpected restored mode holds; do not guess with global Previous.
    probe.tap(REVIEW_ALL)
    probe.require_value('عنوان الإعلان *', state['title'])
    frames = capture(probe, 'C1-c4-restored-title')
    probe.tap('التالي')
    probe.wait('تم تحديد موقع العقار على الخريطة')
    probe.require_value('المحافظة *', 'صنعاء')
    frames.update(capture(probe, 'C1-c4-restored-location'))
    probe.tap('التالي')
    probe.wait('المواصفات')
    probe.require_value('غرف النوم *', '3')
    probe.require_value('الحمامات *', '2')
    probe.require_value(UNIT, '7')
    probe.seek('الثاني')
    frames.update(capture(probe, 'C1-c4-restored-floor-unit'))
    # Start late: a short host clip covers specification/photo inspection, with
    # title/location already in frames. Long TCG reopening is never recorded.
    probe.record_start('C1-c4-restored-facts')
    try:
        probe.seek('لا يوجد')
        probe.seek('شمالية')
        probe.seek('صور الإعلان (1/12)')
        probe.wait('مكتمل', seconds=90)
        frames.update(capture(probe, 'C1-c4-restored-photo'))
        probe.record_stop(export=True)  # End at photo before scrolling to copy.
        state['restore_video'] = video(probe, 'C1-c4-restored-facts.webm')
        need(copy_digest(probe, 'وصف العقار') == state['reviewed_copy_sha256'],
             'c4_restored_copy_differs_from_reviewed_native_copy')
        frames.update(_host_png(probe, 'C1-c4-restored-copy', spec_copy_context,
                                'actual_restored_spec_copy_privacy_checked'))
        # Full completed-data review keeps normal Previous navigation. Return
        # to this same draft's basics so the subsequent C2 executor starts at 0.
        probe.tap('السابق')
        probe.wait('تم تحديد موقع العقار على الخريطة')
        probe.tap('السابق')
        probe.require_value('عنوان الإعلان *', state['title'])
        frames.update(capture(probe, 'C1-c4-restored-final-title'))
    except Exception:
        probe.record_stop(export=False)
        raise
    state['restore_frames'] = frames
    state['restored_fields_observed'] = True
    state['monthly_rent_blank_after_reopen'] = True
    state['held_same_draft_editor_step'] = 0
    return finish(probe, state, 'RESTORE_REVIEW')


def _run_phase(probe, phase):
    """Root calls repeatedly with C4, reviewing each returned cursor separately."""
    need(phase == 'C4', 'c4_executor_exposes_C4_only')
    key, tag, title = identity(probe)
    state = probe.report.setdefault(KEY, {'schema': 1, 'cursor': 'C1_REVIEW',
        'fixture_key': key, 'fixture_tag': tag, 'title': title,
        'accepted': False, 'inflight': None, 'uncertain': False})
    need((state['fixture_key'], state['fixture_tag'], state['title']) == (key, tag, title),
         'c4_fixture_changed_no_continuation')
    need(state.get('inflight') is None and state.get('uncertain') is not True,
         'c4_uncertain_action_requires_root_reconciliation_no_replay')
    cursor = state['cursor']
    try:
        if cursor == 'C1_REVIEW':
            frames = {name: frame(probe, name) for name in
                      ('C1-restored-title.png', 'C1-restored-complete-photo.png')}
            data = review(probe, state, 'C4_ROOT_C1_REVIEW.json', cursor, frames)
            if data is None:
                save(probe)
                return {'phase': 'C4', 'cursor': cursor, 'held_for_root': True}
            need(data.get('c1_accepted') is True and data.get('monthly_rent_still_blank') is True
                 and data.get('same_tagged_fixture_visually_verified') is True
                 and data.get('original_UUID_bound_by_existing_fixture_receipt') is True,
                 'c4_actual_c1_visual_acceptance_required')
            return prepare(probe, state)
        if cursor == 'REQUEST':
            return request_prepared(probe, state)
        if cursor == 'RESPONSE_READY':
            return collect_response(probe, state)
        if cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:
            group = {'AI_REVIEW': 'ai_frames', 'APPLY_REVIEW': 'apply_frames',
                     'RESTORE_REVIEW': 'restore_frames'}[cursor]
            filename = 'C4_ROOT_' + cursor + '.json'
            data = review(probe, state, filename, cursor, state[group])
            if data is None:
                return {'phase': 'C4', 'cursor': cursor, 'held_for_root': True}
            if cursor == 'AI_REVIEW':
                return edit_title(probe, state, data)
            if cursor == 'APPLY_REVIEW':
                return apply_reviewed(probe, state, data)
            need(data.get('same_exact_saved_draft_visually_verified') is True and
                 data.get('photo_visually_unchanged') is True and
                 data.get('applied_floor_unit_and_copy_visually_verified') is True and
                 data.get('actual_restore_clip_reviewed') is True and
                 data.get('video') == state['restore_video'] and
                 data.get('monthly_rent_still_blank') is True,
                 'c4_actual_restored_fields_image_and_copy_review_required')
            need(video(probe, state['restore_video']['file']) == state['restore_video'],
                 'c4_reviewed_restore_clip_changed')
            state['accepted'] = True
            return finish(probe, state, 'C4_SAVED_RESTORED_HOLD_FOR_C2')
        if cursor == 'SAVE':
            return save_draft(probe, state)
        if cursor == 'REOPEN':
            return reopen(probe, state)
        need(cursor == 'C4_SAVED_RESTORED_HOLD_FOR_C2', 'c4_unknown_cursor_refused')
        return {'phase': 'C4', 'cursor': cursor, 'held_for_root': True,
                'c4_accepted': True, 'c2_executed': False}
    except Exception:
        if state.get('inflight') is not None:
            state['uncertain'] = True
            state['failed_stage'] = state['inflight']
            save(probe)
            # Leave the app and known fixture intact for Root; never replay or
            # fall through to API fixture edits, cleanup, submission, or auth.
            try:
                if getattr(probe, 'recorder', None) is not None:
                    probe.record_stop(export=False)
                close_session(probe)
            except Exception:
                state['admission_or_recorder_stop_unconfirmed'] = True
                save(probe)
        raise


def run_phase(probe, phase):
    """Hold errors locally so the supervisor does not enter cleanup implicitly.

    Root must inspect report[KEY] after every delivered extension command. The
    supervisor's COMMAND_DONE means the segment returned, not C4 acceptance.
    """
    need(phase == 'C4', 'c4_executor_exposes_C4_only')
    try:
        return _run_phase(probe, phase)
    except Exception as error:
        state = probe.report.get(KEY)
        reason = str(error) if isinstance(error, C4Blocked) else 'c4_native_segment_failed'
        if isinstance(state, dict):
            state['held_error'] = reason
            save(probe)
        return {'phase': 'C4', 'cursor': state.get('cursor') if isinstance(state, dict) else None,
                'held_for_root': True, 'blocked': True, 'reason': reason,
                'c4_accepted': False, 'c2_executed': False}
