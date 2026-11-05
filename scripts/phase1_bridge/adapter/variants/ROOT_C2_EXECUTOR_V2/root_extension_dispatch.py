"""OFFLINE wrapper proposal for the existing phase-only extension operation.

Do not install implicitly. Import is inert; Root may later select this module as
the controller's phase_extensions. All failures are held locally so the current
supervisor does not enter automatic cleanup merely because an extension raises.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
from ci_remote_evidence import fresh_remote_review


BASE = Path(__file__).resolve().parents[1]
SOURCES = {'C4': BASE / 'ROOT_C4_EXECUTOR/phase_extensions.py',
           'C2': BASE / 'ROOT_C2_EXECUTOR_V2/phase_extensions.py'}
KEY = 'local_c2_executor'
C1_FILE = 'C2_V2_ROOT_C1_REVIEW.json'
C4_FILE = 'C2_V2_ROOT_C4_REVIEW.json'
STAGE_FILE = 'C2_V2_ROOT_STAGE_REVIEW.json'
JSON_LIMIT = 16384
C1_KEYS = frozenset({'kind', 'phase', 'privacy_checked', 'manual_review_completed', 'c1_accepted',
    'fixture_key', 'fixture_tag', 'native_title', 'restored_frame_sha256',
    'monthly_rent_still_blank'})
C4_KEYS = frozenset({'kind', 'phase', 'privacy_checked', 'manual_review_completed', 'c4_accepted',
    'fixture_key', 'fixture_tag', 'restored_title', 'monthly_rent_still_blank',
    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',
    'restored_frame_sha256'})
STAGE_KEYS = frozenset({'executor_cursor', 'actual_frame_file', 'kind', 'context', 'privacy_checked',
    'manual_review_completed', 'fixture_key', 'fixture_tag', 'exact_fixture_title',
    'frame_sha256', 'review_completed_utc', 'root_witness', 'title_path',
    'title_witness', 'button_path', 'button_witness', 'card_path', 'card_witness',
    'same_exact_tagged_item_and_button_visually_verified',
    'card_boundary_not_exposed_manual_click_only',
    'same_serialized_fixture_dialog_chain_reviewed',
    'preceding_exact_fixture_frame_sha256', 'monthly_rent_filled_natively',
    'existing_platform_fallback_sai_reviewed', 'custom_terms_accepted',
    'same_title_photo_location_reviewed', 'own_draft_card_visually_reviewed',
    'no_edit_action_on_exact_pending_card', 'exact_tagged_card_status',
    'own_card_status_visually_verified', 'published',
    'normal_support_claim_observed', 'own_task_owner_observed',
    'exact_own_case_title_observed', 'native_return_confirmed',
    'publication_or_rejection_executed', 'exact_reason', 'broker_photo_absent',
    'all_regular_tabs_checked', 'old_fixture_data_visible',
    'old_support_workspace_visible', 'evidence_kind', 'editor_chain',
    'same_serialized_editor_chain_reviewed', 'original_fixture_receipt_reviewed',
    'bound_c4_title_frame', 'photo_visually_unchanged', 'actual_safe_spec_photo_reviewed',
    'semantic_preview', 'policy_was_visually_reviewed', 'safe_surface_frames',
    'regular_cycle', 'nonimage_role_witness', 'same_serialized_support_case_chain_reviewed',
    'serialized_case_binding', 'fixture_title_visible_in_action_frame',
    'return_queue_transition', 'return_queue_transition_reviewed',
    'exact_outcome_deferred_to_broker_reason'})

C1_KEYS = C1_KEYS | {'review_completed_utc'}
C4_KEYS = C4_KEYS | {'review_completed_utc'}


class Hold(RuntimeError):
    """Fixed local diagnostics; never use arbitrary exception text."""


def need(ok, code):
    if not ok:
        raise Hold(code)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'review_duplicate_json_key')
        result[key] = value
    return result


def _version(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def _read(probe, filename, allowed):
    """Read only one fixed non-symlink0600 bounded Root review, no secret path."""
    need(filename in {C1_FILE, C4_FILE, STAGE_FILE}, 'review_filename_not_allowlisted')
    need(type(probe.private_values) is set, 'parent_redaction_set_required')
    path = Path(probe.out) / filename
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        raise Hold('actual_root_review_file_missing') from None
    except OSError:
        raise Hold('actual_root_review_file_unavailable') from None
    try:
        before = os.fstat(descriptor)
        need(stat.S_ISREG(before.st_mode) and stat.S_IMODE(before.st_mode) == 0o600 and
             before.st_uid == os.geteuid() and before.st_nlink == 1 and
             1 <= before.st_size <= JSON_LIMIT, 'bounded_owned_mode0600_review_required')
        raw = os.read(descriptor, JSON_LIMIT + 1)
        after = os.fstat(descriptor)
        need(len(raw) <= JSON_LIMIT and _version(before) == _version(after) and
             len(raw) == before.st_size, 'root_review_changed_while_reading')
    finally:
        os.close(descriptor)
    try:
        text = raw.decode('utf-8')
        need(not any(value and value in text for value in probe.private_values),
             'private_value_in_root_review_refused')
        data = json.loads(text, object_pairs_hook=_pairs)
    except (ValueError, UnicodeError, RecursionError):
        raise Hold('root_review_json_invalid') from None
    need(fresh_remote_review(data), 'root_review_utc_expired')
    need(isinstance(data, dict) and set(data) <= allowed and
         data.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW', 'root_review_schema_refused')
    try:
        need(_version(path.lstat()) == _version(before), 'root_review_replaced_after_read')
    except OSError:
        raise Hold('root_review_replaced_after_read') from None
    return data, (path, _version(before))


def _consume(version):
    path, expected = version
    try:
        need(_version(path.lstat()) == expected, 'root_review_replaced_before_consumption')
        path.unlink()
    except OSError:
        raise Hold('root_review_consumption_not_confirmed') from None


def _load(probe, phase):
    modules = getattr(probe, '_root_extension_dispatch_v2_modules', None)
    if modules is None:
        modules = {}
        probe._root_extension_dispatch_v2_modules = modules
    if phase not in modules:
        path = SOURCES[phase]
        need(path.is_absolute() and path.is_file() and not path.is_symlink(),
             'reviewed_extension_source_unavailable')
        spec = importlib.util.spec_from_file_location('_root_dispatch_' + phase.lower(), path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        modules[phase] = module
    return modules[phase]


def _bind_frame(probe, filename, wanted):
    # Only the already recorded safe restored-title images are read here.
    need(filename in {'C1-restored-title.png', 'C1-c4-restored-final-title.png'},
         'accepted_review_frame_not_allowlisted')
    receipts = [row for row in probe.report.get('frames', []) if row.get('file') == filename]
    need(len(receipts) == 1 and receipts[0].get('authenticated_editor_only') is True and
         receipts[0].get('sha256') == wanted, 'accepted_review_recorded_frame_mismatch')
    path = Path(probe.out) / filename
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 32 * 1024 * 1024,
         'accepted_review_safe_frame_unavailable')
    data = path.read_bytes()
    need(data.startswith(b'\x89PNG\r\n\x1a\n') and hashlib.sha256(data).hexdigest() == wanted,
         'accepted_review_actual_frame_mismatch')


def _configure(probe, module):
    need(not hasattr(probe, '_root_c2_executor'), 'existing_v1_executor_requires_root_reconciliation')
    c1, _ = _read(probe, C1_FILE, C1_KEYS)
    c4, _ = _read(probe, C4_FILE, C4_KEYS)
    need(set(c1) == C1_KEYS and set(c4) == C4_KEYS and
         c1.get('phase') == 'C1' and c4.get('phase') == 'C4', 'accepted_review_phase_mismatch')
    need(c1.get('manual_review_completed') is True and c1.get('c1_accepted') is True and
         c4.get('manual_review_completed') is True and c4.get('c4_accepted') is True and
         c1.get('privacy_checked') is True and c4.get('privacy_checked') is True and
         c1.get('monthly_rent_still_blank') is True and c4.get('monthly_rent_still_blank') is True and
         c4.get('property_id') is None and c4.get('same_unpromoted_uuid_verified') is True and
         type(c4.get('restored_editor_step')) is int and c4['restored_editor_step'] == 0,
         'actual_c1_c4_accepted_review_schema_required')
    state = getattr(getattr(probe, 'fixture_api', None), 'state', None)
    need(isinstance(state, dict) and state.get('actor_id') == 28 and
         state.get('key') == probe.report.get('fixture_key') and
         state.get('tag') == probe.report.get('fixture_tag') and
         c1.get('fixture_key') == state.get('key') == c4.get('fixture_key') and
         c1.get('fixture_tag') == state.get('tag') == c4.get('fixture_tag') and
         c1.get('native_title') == probe.title == c4.get('restored_title'),
         'original_bootstrap_state_and_reviews_required')
    actual = probe.report.get('local_c4_executor', {})
    need(isinstance(actual, dict) and actual.get('accepted') is True and
         actual.get('cursor') == 'C4_SAVED_RESTORED_HOLD_FOR_C2' and
         actual.get('inflight') is None and actual.get('uncertain') is not True and
         type(actual.get('held_same_draft_editor_step')) is int and
         actual['held_same_draft_editor_step'] == 0 and
         (actual.get('fixture_key'), actual.get('fixture_tag'), actual.get('title')) ==
         (state['key'], state['tag'], probe.title), 'actual_reviewed_c4_completion_required')
    _bind_frame(probe, 'C1-restored-title.png', c1.get('restored_frame_sha256'))
    need(actual.get('restore_frames', {}).get('C1-c4-restored-final-title.png') ==
         c4.get('restored_frame_sha256'), 'actual_c4_final_step0_frame_required')
    _bind_frame(probe, 'C1-c4-restored-final-title.png', c4.get('restored_frame_sha256'))
    access = getattr(probe, 'access', None)
    need(isinstance(access, dict) and isinstance(access.get('phones'), dict) and
         {'broker', 'support', 'regular'} <= set(access['phones']),
         'all_three_validated_roles_must_already_be_in_parent_memory')
    need(callable(getattr(probe.fixture_api, '_call', None)), 'normal_parent_api_adapter_required')
    # No callback runs during configuration. These only reference parent memory.
    return module.configure_c2(probe, state, c1, c4,
        role_loader=lambda: probe.access,
        request=lambda method, path, body, token:
            probe.fixture_api._call(method, path, body=body, token=token))


def _capture_rows(probe, module, executor, stage):
    need(probe.authenticated is True and getattr(probe, 'recorder', None) is None and
         not getattr(probe, '_host_stop_unconfirmed', False), 'CAPTURE_HELD_UNSAFE_SESSION')
    role = ('regular' if stage.startswith('regular_') else module.TARGETS[stage][0]
            if stage in module.TARGETS else 'support'
            if stage in {'review_claimed', 'review_case', 'review_returned'} else 'broker')
    need(getattr(probe, 'active_native_role', None) == role and
         getattr(probe, 'native_auth_uncertain', True) is False,
         'CAPTURE_HELD_KNOWN_NATIVE_ROLE_REQUIRED')
    rows = probe._capture_full_rows()
    # Preserve the parent's FULL tree privacy predicate before any frame/hash or
    # node binding is exported. Contact controls below viewport also block.
    need(not probe._capture_rows_private(rows), 'CAPTURE_HELD_PRIVATE_CONTEXT')
    visible = [row for row in rows if row.get('visible') and row.get('enabled')]
    names = module._names(visible)
    if stage == 'regular_isolation':
        raise Hold('NO_ACCOUNT_CAPTURE_USE_PRIOR_SAFE_REGULAR_FRAMES')
    if stage.startswith('regular_'):
        need({'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'} <= names and
             not (names & {'لوحة الدعم', 'الوارد', 'مهامي', 'مسوداتي'}),
             'CAPTURE_HELD_REGULAR_NAVBAR_NOT_OBSERVED')
        title_text, action_text = None, None
    elif stage == 'review_photo_before_save':
        need('صور الإعلان (1/12)' in names and 'مكتمل' in names,
             'CAPTURE_HELD_SAFE_SPEC_PHOTO_NOT_OBSERVED')
        title_text, action_text = None, None
    elif stage == 'review_returned':
        need(executor.return_queue_transition is not None and executor._return_queue_observed(),
             'CAPTURE_HELD_RETURN_QUEUE_TRANSITION_NOT_OBSERVED')
        title_text, action_text = 'تحقيق الإعلانات', None
        need(title_text in names, 'CAPTURE_HELD_RETURN_QUEUE_ANCHOR_NOT_OBSERVED')
    elif stage in module.TARGETS:
        _, action_text, anchor = module.TARGETS[stage]
        title_text = (executor.title if anchor == 'fixture' else
                      'تحقق نشر إعلان: ' + executor.title if anchor == 'task' else anchor)
        need(title_text in names and action_text in names,
             'CAPTURE_HELD_EXACT_TITLE_AND_ACTION_NOT_OBSERVED')
    else:
        title_text, action_text = executor.title, None
        need(title_text in names, 'CAPTURE_HELD_EXACT_FIXTURE_TITLE_NOT_OBSERVED')
    indexed = {row.get('path'): row for row in visible}
    need(len(indexed) == len(visible) and '0' in indexed and
         module.policy.sha(indexed['0'].get('witness')), 'CAPTURE_HELD_FRESH_ROOT_REQUIRED')
    def binding(row):
        need(module.policy.sha(row.get('witness')), 'CAPTURE_HELD_FRESH_NODE_REQUIRED')
        return {key: row.get(key) for key in
                ('path', 'witness', 'bounds', 'clickable', 'class')}
    # Exact candidates only. No arbitrary UI text or inferred card ancestor.
    bindings = {'root': binding(indexed['0']),
        'title_candidates': [binding(row) for row in visible
                             if title_text is not None and title_text in module.policy.names(row)],
        'button_candidates': [binding(row) for row in visible
                              if action_text is not None and action_text in module.policy.names(row)]}
    if stage == 'review_photo_before_save':
        bindings['serialized_identity_binding'] = {
            'fixture_key': executor.key, 'fixture_tag': executor.tag,
            'editor_chain': executor.editor_chain,
            'prior_c4_tagged_title_frame': {'file': 'C1-c4-restored-final-title.png',
                                           'sha256': executor.c4['restored_frame_sha256']},
            'fixture_title_visible_in_this_spec_frame': False}
    if stage == 'return_open':
        need(executor._case_header() == executor.case_header_binding,
             'CAPTURE_HELD_REVIEWED_CASE_HEADER_CHANGED')
        bindings['serialized_case_binding'] = executor._case_binding()
        bindings['fixture_title_visible_in_action_frame'] = False
    elif stage == 'review_returned':
        bindings['return_queue_transition'] = executor.return_queue_transition
    return bindings


def _safe_capture(probe, module, executor, stage):
    before = _capture_rows(probe, module, executor, stage)
    number = len(probe.report.get('c2_v2_safe_frames', [])) + 1
    filename = 'C2-' + stage + '-' + str(number) + '.png'
    destination = Path(probe.out) / filename
    need(not destination.exists(), 'CAPTURE_HELD_DESTINATION_EXISTS')
    with tempfile.TemporaryDirectory(prefix='c2-safe-png-', dir=probe._host_capture_root()) as directory:
        folder = Path(directory)
        probe._console('screenshot', folder)
        files = list(folder.iterdir())
        need(len(files) == 1 and files[0].is_file() and not files[0].is_symlink() and
             files[0].suffix.lower() == '.png' and files[0].stat().st_size <= 32 * 1024 * 1024,
             'CAPTURE_HELD_HOST_PNG_NOT_UNIQUE')
        data = files[0].read_bytes()
        dimensions = probe._validate_png(data)
        after = _capture_rows(probe, module, executor, stage)
        need(before == after, 'CAPTURE_HELD_SCENE_CHANGED')
        # No frame is exported until both full-tree privacy checks pass.
        with destination.open('xb') as stream:
            os.chmod(destination, 0o600)
            stream.write(data)
    receipt = {'file': filename, 'sha256': hashlib.sha256(data).hexdigest(),
        'stage': stage, 'cursor': executor.cursor, 'bytes': len(data),
        'width': dimensions[0], 'height': dimensions[1], 'node_bindings': after,
        'capture': 'official_emulator_console_host_png',
        'privacy_before_and_after': True, 'review_created': False,
        'compiled_scoped_card_guard_proved': False}
    if stage in {'regular_marketplace', 'regular_messages', 'regular_listing_gate'}:
        receipt['regular_cycle'] = executor.regular_cycle
    probe.report.setdefault('c2_v2_safe_frames', []).append(receipt)
    probe.report.setdefault('frames', []).append({key: receipt[key] for key in
        ('file', 'sha256', 'bytes', 'width', 'height', 'capture')})
    probe._root_c2_v2_last_capture = receipt
    return receipt


def _pending_capture(probe, module, executor, stage):
    cache = getattr(probe, '_root_c2_v2_pending_frames', None)
    if cache is None:
        cache = {}
        probe._root_c2_v2_pending_frames = cache
    existing = cache.get(stage)
    current = _capture_rows(probe, module, executor, stage)
    if existing is not None and existing['node_bindings'] == current:
        path = Path(probe.out) / existing['file']
        need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 32 * 1024 * 1024 and
             hashlib.sha256(path.read_bytes()).hexdigest() == existing['sha256'],
             'CAPTURE_HELD_RECORDED_FRAME_CHANGED')
        return existing
    cache[stage] = _safe_capture(probe, module, executor, stage)
    raise Hold('actual_c2_safe_frame_captured_root_review_pending')


def _regular_bundle(probe, executor):
    stages = {'regular_marketplace', 'regular_messages', 'regular_listing_gate'}
    need(set(executor.regular_frames) == stages and executor.regular_cycle > 0,
         'all_three_same_regular_cycle_safe_frames_required')
    for stage, frame in executor.regular_frames.items():
        receipts = [row for row in probe.report.get('c2_v2_safe_frames', [])
                    if row.get('file') == frame.get('file')]
        need(len(receipts) == 1 and receipts[0].get('stage') == stage and
             receipts[0].get('privacy_before_and_after') is True and
             receipts[0].get('regular_cycle') == frame.get('regular_cycle') == executor.regular_cycle and
             receipts[0].get('sha256') == frame.get('sha256'),
             'actual_regular_safe_frame_receipt_mismatch')
        path = Path(probe.out) / frame['file']
        need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 32 * 1024 * 1024,
             'actual_regular_safe_frame_file_required')
        data = path.read_bytes()
        need(data.startswith(b'\x89PNG\r\n\x1a\n') and
             hashlib.sha256(data).hexdigest() == frame['sha256'],
             'actual_regular_safe_frame_changed')


def _c2(probe, module):
    executor = getattr(probe, '_root_c2_executor_v2', None)
    if executor is None:
        return _configure(probe, module)  # First call configures only; no stage work.
    need(not executor.failed and not executor.inflight, 'c2_uncertain_stage_no_replay')
    if executor.cursor < len(module.STAGES):
        stage = module.STAGES[executor.cursor]
        # C4 deliberately releases its helper at the final Root review boundary.
        # Relaunch after force-stop belongs to the normal login stage itself;
        # no helper/session may be started around an API or writer-stop stage.
        no_helper = {'load_roles', 'pin_promotion', 'cleanup',
                     'stop_writers_for_pin', 'stop_writers_for_cleanup',
                     'broker_login_for_submit', 'broker_login_for_reason',
                     'support_login', 'regular_login'}
        if stage not in no_helper:
            need(getattr(probe, 'recorder', None) is None, 'c2_recorder_must_already_be_stopped')
            if getattr(probe, 'adapter', None) is None:
                probe.start_session()
        if stage in module.TARGETS or stage in module.REVIEW_STAGES:
            if stage == 'regular_isolation':
                _regular_bundle(probe, executor)
                capture = None  # Account has semantic evidence only; no image/hash.
            else:
                capture = _pending_capture(probe, module, executor, stage)
            record, version = _read(probe, STAGE_FILE, STAGE_KEYS)
            need(type(record.get('executor_cursor')) is int and
                 record['executor_cursor'] == executor.cursor and record.get('context') == stage,
                 'root_review_current_cursor_required')
            if stage == 'regular_isolation':
                need('actual_frame_file' not in record and 'frame_sha256' not in record and
                     record.get('safe_surface_frames') == executor.regular_frames and
                     type(record.get('regular_cycle')) is int and
                     record['regular_cycle'] == executor.regular_cycle,
                     'root_regular_review_must_bind_three_prior_frames_not_account')
            else:
                need(record.get('actual_frame_file') == capture['file'] and
                     record.get('frame_sha256') == capture['sha256'],
                     'root_review_must_bind_actual_captured_c2_frame')
            module.supply_review(probe, record)  # Pure memory; no input/API.
            _consume(version)  # Consume BEFORE any possible input; never resurrect.
    result = module.run_phase(probe, 'C2')
    if result.get('completed') in {'regular_marketplace', 'regular_messages', 'regular_listing_gate'}:
        try:
            frame = _safe_capture(probe, module, executor, result['completed'])
            executor.register_regular_frame(result['completed'], frame)
        except Hold as error:
            result['regular_surface_capture_held'] = str(error)
        except Exception:
            result['regular_surface_capture_held'] = 'CAPTURE_HELD_OPERATION_FAILED'
    return result


def _publish(probe, receipt):
    receipt = dict(receipt, phase1_accepted=False,
                   dispatcher_version=2,
                   report_persisted=True,
                   supervisor_command_done_is_not_acceptance=True,
                   implicit_cleanup_requested=False)
    try:
        probe.report[KEY] = receipt
        probe.save()
    except Exception:
        receipt['status'] = 'HELD_REPORT_SAVE_FAILED'
        receipt['report_persisted'] = False
        probe._root_extension_dispatch_v2_save_failed = True
        try:
            probe.report[KEY] = receipt
        except Exception:
            pass
    # The supervisor discards return values. Emit only this fixed safe receipt.
    try:
        print(json.dumps({KEY: receipt}, ensure_ascii=False), flush=True)
    except Exception:
        pass
    return receipt


def run_phase(probe, phase='C2'):
    """Existing extension operation only; no new RPC or credentials in files."""
    receipt = {'requested_phase': phase if phase in ('C4', 'C2') else 'REFUSED',
               'status': 'HELD_FOR_ROOT', 'scope': 'LOCAL phase dispatcher proposal'}
    executing = False
    try:
        need(phase in ('C4', 'C2'), 'extension_phase_refused')
        need(probe.require_phase_scope(phase) is True, 'active_root_phase_grant_required')
        need(not getattr(probe, '_root_extension_dispatch_v2_save_failed', False),
             'previous_report_save_failure_requires_root_review')
        need(not getattr(probe, '_root_extension_dispatch_v2_admission_failed', False),
             'previous_admission_close_failure_requires_root_review')
        latched = getattr(probe, '_root_extension_dispatch_v2_latched', set())
        need(phase not in latched, 'extension_uncertainty_no_replay')
        module = _load(probe, phase)
        if phase == 'C2':
            # _c2 performs only local preflight before module.run_phase. Its
            # executor owns reservation/latching of attempted native/API work.
            result = _c2(probe, module)
            receipt.update({key: result[key] for key in
                ('status', 'cursor', 'next_stage', 'completed', 'pending', 'failed',
                 'known_promoted_property_id', 'automatic_replay_allowed') if key in result})
        else:
            executing = True
            module.run_phase(probe, 'C4')
            actual = probe.report.get('local_c4_executor', {})
            receipt.update(status='C4_RETURNED_HELD_FOR_ROOT',
                           c4_cursor=actual.get('cursor'), c4_accepted=actual.get('accepted') is True)
    except Hold as error:
        receipt.update(status='HELD_LOCAL_REVIEW_REQUIRED', reason=str(error))
    except Exception:
        receipt.update(status='HELD_EXTENSION_ERROR', reason='extension_operation_held_locally')
        if executing:
            latched = set(getattr(probe, '_root_extension_dispatch_v2_latched', set()))
            latched.add(phase)
            probe._root_extension_dispatch_v2_latched = latched
    executor = getattr(probe, '_root_c2_executor_v2', None)
    if executor is not None:
        try:
            summary = executor._receipt('DISPATCH_SUMMARY')
            receipt.update(cursor=executor.cursor, next_stage=summary.get('next_stage'),
                           uncertain=bool(executor.failed or executor.inflight))
            if getattr(executor, 'regular_frames', None):
                receipt.update(safe_regular_surface_frames=executor.regular_frames,
                               current_account_image_captured=False,
                               regular_evidence_scope='three prior safe tabs plus nonimage role/logout witness')
        except Exception:
            receipt.update(status='HELD_EXECUTOR_SUMMARY_UNAVAILABLE')
    capture = getattr(probe, '_root_c2_v2_last_capture', None)
    if capture is not None:
        try:
            receipt['latest_safe_frame'] = {'file': capture['file'], 'sha256': capture['sha256'],
                                           'stage': capture['stage']}
        except Exception:
            receipt.update(status='HELD_CAPTURE_SUMMARY_UNAVAILABLE')
    if phase == 'C2' and getattr(probe, 'recorder', None) is None and getattr(probe, 'adapter', None) is not None:
        try:
            probe.stop_session('C2_segment_root_review_boundary')
            receipt['oneshot_admission_closed_at_boundary'] = True
            receipt['persistent_helper_release_claimed'] = False
            receipt['oneshot_admission'] = probe.admission_metrics
        except Exception:
            # Keep the cursor/executor intact and block later calls until Root
            # disposes this uncertain runtime; never retry a native action.
            receipt.update(status='HELD_ADMISSION_CLOSE_UNCONFIRMED')
            probe._root_extension_dispatch_v2_admission_failed = True
    return _publish(probe, receipt)
