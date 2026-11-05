"""LOCAL segmented C2 executor. Import/configuration does no device or API work.

Only the exclusive parent calls run_phase. One call advances ONE named stage;
missing Root evidence pauses before input. Once input/auth/API work starts, any
uncertain result latches the executor and is never replayed. This source and its
offline tests are not native acceptance evidence. No C4 implementation lives here.
"""
from __future__ import annotations

import copy
import base64
import importlib.util
import json
from pathlib import Path
import re
import time
from ci_remote_evidence import fresh_remote_review


HERE = Path(__file__).resolve().parent


def _module(name, relative):
    spec = importlib.util.spec_from_file_location(name, HERE.parent / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Private imports avoid changing the existing policy module or its allowlist.
policy = _module('_root_c2_policy', 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py')
roles = _module('_root_c2_roles', 'C2_SOURCE_PROPOSAL/c2_native_roles.py')
cleanup_module = _module('_root_c2_cleanup', 'promoted_cleanup.py')


class C2Blocked(RuntimeError):
    """Fixed diagnostics only; arbitrary transport/controller text is redacted."""


def need(ok, code):
    if not ok:
        raise C2Blocked(code)


PREPARE_REFUSAL_REASONS = frozenset({
    'root_review_not_validated', 'preparation_exception_unclassified',
    'known_normal_native_actor_required', 'auth_context_forbids_c2_review',
    'safe_specs_full_tree_privacy_required', 'safe_specs_auth_surface_refused',
    'actual_specification_step_required',
    'safe_photo_plus_serialized_identity_and_nonimage_policy_review_required',
    'native_promotion_card_review_required', 'native_submission_review_required',
    'native_support_claim_review_required', 'native_exact_review_case_required',
    'native_return_review_required', 'broker_exact_reason_not_observed',
    'regular_prior_frames_nonimage_review_required', 'regular_cache_isolation_review_required',
    'fresh_normal_regular_logout_control_required', 'only_existing_platform_fallback_sai_allowed',
    'actual_sai_zero_text_required_hint_is_not_value', 'sai_actual_review_required',
    'exact_synthetic_reason_readback_required'})


# Fixed UI contexts. The dialog title is an explicit anchor only after the
# preceding exact-fixture action was delivered in this same serialized chain.
TARGETS = {
    'submit_open': ('broker', 'إرسال للمراجعة', 'fixture'),
    'submit_continue': ('broker', 'متابعة', 'إرسال الإعلان للمراجعة؟'),
    'submit_confirm': ('broker', 'تأكيد السعي والمتابعة', 'تحديد السعي قبل إرسال الإعلان'),
    'support_claim': ('support', 'استلام', 'task'),
    'support_open': ('support', 'متابعة التحقيق', 'fixture'),
    'return_open': ('support', 'إرجاع للتصحيح', 'تحقيق الإعلان'),
    'return_confirm': ('support', 'تأكيد', 'إرجاع الإعلان للتصحيح'),
}
policy.ACTION_SPEC.update({name: (value[0], value[1]) for name, value in TARGETS.items()})


def _names(rows):
    return set().union(*(policy.names(row) for row in rows)) if rows else set()


def _valid_review(review, stage, key, tag, title):
    return (isinstance(review, dict) and
            review.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW' and
            review.get('context') == stage and review.get('privacy_checked') is True and
            review.get('manual_review_completed') is True and
            review.get('fixture_key') == key and review.get('fixture_tag') == tag and
            review.get('exact_fixture_title') == title and policy.sha(review.get('frame_sha256')) and
            fresh_remote_review(review))


def _reviewed_dialog_node(rows, stage, anchor, record, preceding_frame):
    """Bind a modal's own actual title/button to the exact-case prior frame.

    Modal routes can hide the listing title from accessibility. No card ancestry
    is inferred: Root attests the serialized case chain and both actual frames.
    """
    need(record.get('same_serialized_fixture_dialog_chain_reviewed') is True and
         policy.sha(preceding_frame) and
         record.get('preceding_exact_fixture_frame_sha256') == preceding_frame and
         record.get('same_exact_tagged_item_and_button_visually_verified') is True,
         'actual_fixture_dialog_chain_review_required')
    return _reviewed_anchor_action_node(rows, stage, anchor, record)


def _reviewed_anchor_action_node(rows, stage, anchor, record):
    """Revalidate one actual visible anchor/action pair, without fixture claims."""
    eligible = [row for row in rows if row.get('package') == roles.APP and
                row.get('visible') and row.get('enabled')]
    indexed = {row.get('path'): row for row in eligible}
    need(len(indexed) == len(eligible) and '0' in indexed and
         not (_names(eligible) & roles.AUTH_LABELS), 'fresh_safe_dialog_tree_required')
    need(all(isinstance(path, str) and re.fullmatch(r'0(?:\.[0-9]{1,4}){0,40}', path) and
             policy.sha(row.get('witness')) for path, row in indexed.items()),
         'fresh_dialog_identity_required')
    root, title, action = indexed['0'], indexed.get(record.get('title_path')), indexed.get(record.get('button_path'))
    need(root.get('witness') == record.get('root_witness') and title is not None and
         title.get('witness') == record.get('title_witness') and anchor in policy.names(title),
         'actual_dialog_title_changed')
    need(action is not None and action.get('witness') == record.get('button_witness') and
         TARGETS[stage][1] in policy.names(action) and
         (action.get('clickable') or action.get('class') == 'android.widget.Button'),
         'actual_dialog_action_changed')
    matching = [row for row in eligible if anchor in policy.names(row)]
    leaves = [row for row in matching if not any(other['path'].startswith(row['path'] + '.')
                                               for other in matching)]
    need(len(leaves) == 1 and leaves[0]['path'] == title['path'], 'dialog_title_not_unique')
    screen = policy._rect(root)
    need(policy._contains(screen, policy._rect(title)) and
         policy._contains(screen, policy._rect(action)), 'dialog_target_outside_screen')
    return copy.deepcopy(action)


class NormalOwnerSession:
    """Normal WhatsApp API login, broker28 pin, finally logout and me401.

    request(method, relative_path, body, token) is supplied by the parent and
    preserves its normal same-UAT-origin/default-TLS transport. No network or
    credential loader is built in. Tokens exist only in memory and are redacted.
    """
    def __init__(self, request, memory, private_values):
        need(callable(request), 'normal_api_adapter_required')
        self._request, self._memory, self._redactions = request, memory, private_values
        self._token = None
        self.used = False
        self.logout_200 = self.me_401 = False

    def __repr__(self):
        return '<NormalOwnerSession redacted>'

    def _call(self, method, path, body=None):
        try:
            response = self._request(method, path, body, self._token)
        except Exception:
            raise C2Blocked('normal_api_transport_uncertain') from None
        need(isinstance(response, tuple) and len(response) in (2, 3), 'normal_api_response_shape')
        code, value = response[:2]
        need(type(code) is int and isinstance(value, dict), 'normal_api_response_shape')
        return code, value

    def run(self, work):
        need(not self.used, 'normal_api_session_already_consumed')
        self.used = True
        completed = False
        try:
            phone, otp = self._memory.resolve('broker')
            code, _ = self._call('POST', '/auth/whatsapp/start', {'phone': phone, 'intent': 'login'})
            need(code == 200, 'normal_api_login_start_failed')
            code, value = self._call('POST', '/auth/whatsapp/verify', {'phone': phone, 'code': otp})
            del phone, otp
            token = value.get('data', {}).get('token')
            if isinstance(token, str) and token:
                self._token = token
                self._redactions.add(token)
            need(code == 200 and self._token, 'normal_api_login_verify_failed')
            code, value = self._call('GET', '/auth/me')
            user = value.get('data', {}).get('user', {})
            need(code == 200 and user.get('id') == 28 and user.get('account_type') == 'broker',
                 'normal_broker_28_required')
            result = work(lambda method, path: self._call(method, path))
            completed = True
        except Exception:
            raise C2Blocked('normal_api_work_or_auth_uncertain') from None
        finally:
            if self._token is not None:
                # Try BOTH logout and its readback, even if one call fails.
                try:
                    code, _ = self._call('POST', '/auth/logout', {})
                    self.logout_200 = code == 200
                except Exception:
                    pass
                try:
                    code, _ = self._call('GET', '/auth/me')
                    self.me_401 = code == 401
                except Exception:
                    pass
                self._token = None
        need(completed and self.logout_200 and self.me_401, 'normal_api_logout_revocation_not_confirmed')
        return result


PIN_DIAGNOSTIC_REASONS = frozenset({
    'native_writers_not_stopped', 'candidate_already_pinned_or_attempted',
    'expected_normal_actor_required', 'api_adapter_shape', 'api_response_shape',
    'original_draft_read_required', 'original_draft_identity_required', 'original_draft_shape_required',
    'new_promoted_property_required', 'pinned_property_substitution_refused',
    'protected_snapshot_read_required', 'protected_snapshot_row_shape', 'property_identity_shape',
    'draft_identity_shape', 'protected_snapshot_identity_shape', 'protected_snapshot_page_bound',
    'preexisting_state_changed', 'unknown_extra_or_missing_state', 'draft_changed_during_preflight',
    'new_property_read_required', 'new_property_ownership_required', 'new_property_tag_mismatch',
    'new_property_not_deletable', 'property_changed_during_preflight', 'new_property_images_shape',
    'transport_or_runtime_C2Blocked', 'transport_or_runtime_ControllerRefused',
    'transport_or_runtime_AdmissionError', 'transport_or_runtime_TimeoutError',
    'transport_or_runtime_ConnectionError', 'transport_or_runtime_OSError',
    'transport_or_runtime_RuntimeError', 'transport_or_runtime_ValueError',
    'transport_or_runtime_TypeError', 'transport_or_runtime_KeyError',
})


def pin_candidate_diagnostic(receipt):
    """Persist only fixed pin outcomes before session wrapping hides the cause."""
    receipt = receipt if type(receipt) is dict else {}
    status, reason = receipt.get('status'), receipt.get('reason')
    return {'status': status if type(status) is str and status in {'READY', 'BLOCKED'} else 'UNOBSERVED',
            'reason': reason if type(reason) is str and reason in PIN_DIAGNOSTIC_REASONS else
                      'NONE' if status == 'READY' else 'UNOBSERVED'}


STAGES = (
    'load_roles', 'open_rent', 'complete_rent', 'navigate_previous_to_specs',
    'review_photo_before_save', 'return_next_step3', 'back_gaps_to_completion', 'full_save',
    'review_promotion', 'broker_logout_for_pin', 'stop_writers_for_pin', 'pin_promotion',
    'broker_login_for_submit', 'open_my_listings', 'submit_open', 'submit_continue',
    'submit_sai_setup', 'submit_confirm', 'review_submitted', 'broker_logout',
    'support_login', 'support_inbox', 'support_claim', 'review_claimed', 'support_open',
    'review_case', 'return_open', 'fill_return_reason', 'return_confirm',
    'review_returned', 'support_logout', 'broker_login_for_reason', 'open_reason',
    'review_broker_reason', 'broker_logout_after_reason', 'regular_login',
    'regular_marketplace', 'regular_messages', 'regular_listing_gate',
    'regular_return_account', 'regular_isolation', 'regular_logout',
    'stop_writers_for_cleanup', 'cleanup',
)
REVIEW_STAGES = frozenset({'review_photo_before_save', 'review_promotion', 'review_submitted',
                          'review_claimed', 'review_case', 'review_returned',
                          'review_broker_reason', 'regular_isolation'})


class C2Executor:
    def __init__(self, probe, original_state, c1_review, c4_review, *,
                 role_loader=None, request=None, monthly_rent='50000', entry_review=None):
        # Validation is source-only and reads only parent-provided objects.
        state = copy.deepcopy(original_state)
        policy.RemainingLocalFence(state, c1_review)
        title = c1_review['native_title']
        if entry_review is not None:
            # C2 may start from this run's actual C1 restoration. Historical C4
            # acceptance belongs to Root's separate report, never this fixture.
            need(c4_review is None and isinstance(entry_review, dict) and
                 set(entry_review) == {'kind', 'phase', 'privacy_checked', 'manual_review_completed',
                    'fixture_key', 'fixture_tag', 'restored_title', 'monthly_rent_still_blank',
                    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',
                    'restored_frame_sha256', 'restored_photo_frame_sha256', 'entry_mode',
                    'current_fixture_visually_verified', 'review_completed_utc'} and
                 entry_review.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW' and
                 entry_review.get('phase') == 'C2' and entry_review.get('privacy_checked') is True and
                 entry_review.get('manual_review_completed') is True and
                 entry_review.get('current_fixture_visually_verified') is True and
                 entry_review.get('entry_mode') == 'standard_editor' and
                 entry_review.get('fixture_key') == state['key'] and
                 entry_review.get('fixture_tag') == state['tag'] and
                 entry_review.get('restored_title') == title and
                 entry_review.get('monthly_rent_still_blank') is True and
                 entry_review.get('property_id') is None and
                 entry_review.get('same_unpromoted_uuid_verified') is True and
                 type(entry_review.get('restored_editor_step')) is int and
                 entry_review['restored_editor_step'] == 0 and
                 entry_review.get('restored_frame_sha256') == c1_review['restored_frame_sha256'] and
                 policy.sha(entry_review.get('restored_photo_frame_sha256')) and
                 fresh_remote_review(entry_review), 'actual_current_c1_fixture_entry_review_required')
            self.entry_mode = 'standard_editor'
            self.fixture_title_frame = {'file': 'C1-restored-title.png',
                                        'sha256': entry_review['restored_frame_sha256']}
        else:
            need(isinstance(c4_review, dict) and c4_review.get('manual_review_completed') is True and
             c4_review.get('c4_accepted') is True and
             c4_review.get('fixture_key') == state['key'] and
             c4_review.get('fixture_tag') == state['tag'] and
             c4_review.get('restored_title') == title and
             c4_review.get('monthly_rent_still_blank') is True and
             c4_review.get('property_id') is None and
             c4_review.get('same_unpromoted_uuid_verified') is True and
             type(c4_review.get('restored_editor_step')) is int and
             c4_review['restored_editor_step'] == 0 and
             policy.sha(c4_review.get('restored_frame_sha256')),
                 'actual_c4_same_unpromoted_restored_review_required')
            self.entry_mode = 'completed_review'
            self.fixture_title_frame = {'file': 'C1-c4-restored-final-title.png',
                                        'sha256': c4_review['restored_frame_sha256']}
        need(monthly_rent == '50000',
             'synthetic_monthly_rent_shape')
        self.probe, self.state, self.c1 = probe, state, copy.deepcopy(c1_review)
        self.c4 = copy.deepcopy(c4_review)
        self.entry_review = copy.deepcopy(entry_review)
        self.key, self.tag, self.title = state['key'], state['tag'], title
        self.reason = 'تصحيح اختبار اصطناعي فقط ' + self.tag
        self.monthly_rent, self.role_loader, self.request = monthly_rent, role_loader, request
        self.cursor = 0
        self.failed = self.inflight = False
        self.preparation_attempt = 0
        self.pending_preparation = None
        self.reviews = {}
        self.delivered_frames = {}
        self.property_id = None
        self.cleanup_helper = None
        self.last_receipt = None
        self.regular_surfaces = set()
        self.editor_chain = 'C2-V2:' + self.key
        self.rent_sai_readback = self.rent_sai_recheck = None
        self.contact_policy_prefixes = None
        # UAT listing contact only; never changes the account/OTP identity.
        self.fixture_contact = '770000028'
        self.probe.private_values.add(self.fixture_contact)
        self.regular_cycle = 0
        self.regular_frames = {}
        self.regular_account_witness = self.regular_logout_receipt = None
        self.case_review_frame = None
        self.case_header_binding = None
        self.return_confirmation_frame = None
        self.return_queue_transition = None

    def __repr__(self):
        return '<C2Executor LOCAL segmented; no acceptance>'

    def review(self, record):
        need(isinstance(record, dict) and record.get('context') in STAGES,
             'c2_review_context_required')
        raw = json.dumps(record, ensure_ascii=False)
        need(not any(value and value in raw for value in self.probe.private_values),
             'private_value_in_c2_review_refused')
        self.reviews[record['context']] = copy.deepcopy(record)

    def _guest(self):
        p = self.probe
        need(not p.authenticated and getattr(p, 'active_native_role', None) is None and
             getattr(p, 'native_auth_uncertain', True) is False and p.recorder is None,
             'normal_native_guest_required')

    def _actor(self, role):
        p = self.probe
        need(p.authenticated is True and getattr(p, 'active_native_role', None) == role and
             getattr(p, 'native_auth_uncertain', True) is False and p.recorder is None,
             'known_normal_native_actor_required')

    def _fresh_review(self, stage):
        record = self.reviews.get(stage)
        if stage == 'regular_isolation':
            need(isinstance(record, dict) and record.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW' and
                 record.get('context') == stage and record.get('privacy_checked') is True and
                 record.get('manual_review_completed') is True and
                 record.get('fixture_key') == self.key and record.get('fixture_tag') == self.tag and
                 record.get('exact_fixture_title') == self.title and
                 'actual_frame_file' not in record and 'frame_sha256' not in record and
                 fresh_remote_review(record),
                 'regular_prior_frames_nonimage_review_required')
            return record
        if not _valid_review(record, stage, self.key, self.tag, self.title):
            return None
        return record

    def _prepare(self, stage):
        # No input/auth/API work here. Invalid evidence stays pending.
        if stage in TARGETS or stage in REVIEW_STAGES:
            record = self._fresh_review(stage)
            if record is None:
                return None
            if stage in TARGETS:
                role, _, anchor = TARGETS[stage]
                self._actor(role)
                expected = (self.title if anchor == 'fixture' else
                            'تحقق نشر إعلان: ' + self.title if anchor == 'task' else anchor)
                rows = self.probe.nodes()
                try:
                    if stage == 'return_open':
                        need(record.get('same_serialized_support_case_chain_reviewed') is True and
                             record.get('serialized_case_binding') == self._case_binding() and
                             record.get('fixture_title_visible_in_action_frame') is False and
                             record.get('title_path') == self.case_header_binding['path'] and
                             record.get('title_witness') == self.case_header_binding['witness'],
                             'actual_separate_case_title_and_return_action_review_required')
                        node = _reviewed_anchor_action_node(rows, stage, anchor, record)
                    elif anchor in ('fixture', 'task'):
                        node = policy.reviewed_action_node(rows, stage, expected, self.tag, record,
                            native_role=role, auth_uncertain=False)
                    else:
                        predecessor = 'return_open' if stage == 'return_confirm' else 'submit_open'
                        node = _reviewed_dialog_node(rows, stage, anchor, record,
                                                   self.delivered_frames.get(predecessor))
                except (policy.RemainingBlocked, C2Blocked):
                    return None
                if stage == 'submit_confirm':
                    self._fallback(rows)
                    need(record.get('existing_platform_fallback_sai_reviewed') is True and
                         record.get('custom_terms_accepted') is False, 'sai_actual_review_required')
                if stage == 'return_confirm':
                    need(self.reason in _names(rows), 'exact_synthetic_reason_readback_required')
                return (record, node)
            self._review_observation(stage, record)
            return record
        return True

    def _case_header(self):
        self._actor('support')
        rows = [row for row in self.probe.nodes() if row.get('package') == roles.APP and
                row.get('visible') and row.get('enabled') and 'تحقيق الإعلان' in policy.names(row)]
        leaves = [row for row in rows if not any(other['path'].startswith(row['path'] + '.')
                                                for other in rows)]
        need(len(leaves) == 1 and policy.sha(leaves[0].get('witness')),
             'unique_same_support_case_header_required')
        return {key: leaves[0][key] for key in ('path', 'witness', 'bounds')}

    def _case_binding(self):
        need(type(self.case_review_frame) is dict and
             set(self.case_review_frame) == {'file', 'sha256'} and
             policy.sha(self.case_review_frame['sha256']) and
             type(self.case_header_binding) is dict and
             policy.sha(self.delivered_frames.get('support_open')),
             'actual_reviewed_case_identity_required')
        return {'kind': 'SERIALIZED_SUPPORT_CASE_IDENTITY', 'fixture_key': self.key,
                'fixture_tag': self.tag, 'exact_fixture_title': self.title,
                'property_id': self.property_id,
                'case_title_review_frame': copy.deepcopy(self.case_review_frame),
                'case_header_binding': copy.deepcopy(self.case_header_binding),
                'case_open_frame_sha256': self.delivered_frames['support_open'],
                'title_to_action_transition_scope': 'SOURCE_SCOPED_SCROLL_WITH_SAME_CASE_HEADER'}

    def _return_queue_observed(self):
        self._actor('support')
        names = _names(self.probe.nodes())
        return ({'تحقيق الإعلانات', 'طلبات التحقيق'} <= names and
                bool(names & {'لا توجد طلبات معلقة', 'بانتظار الاستلام', 'تم الاستلام - قيد التحقيق'}) and
                not names & (roles.AUTH_LABELS | {'جارٍ تحميل طلبات التحقيق...', 'إرجاع الإعلان للتصحيح'}) and
                not any(self.tag in name for name in names))

    def _wait_return_queue(self):
        # The source pops the case only after the awaited return request succeeds.
        # The default queue excludes returned cases; do not require their title there.
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if self._return_queue_observed():
                self.return_queue_transition = {
                    'kind': 'RETURN_QUEUE_TRANSITION_PENDING_BROKER_REASON',
                    'serialized_case_binding': self._case_binding(),
                    'return_confirmation_frame': copy.deepcopy(self.return_confirmation_frame),
                    'exact_reason': self.reason, 'investigation_queue_observed': True,
                    'exact_fixture_absent_from_visible_queue': True,
                    'return_dialog_closed': True, 'exact_returned_state_proved': False}
                return
            time.sleep(.4)
        need(False, 'source_confirmed_return_queue_not_observed')

    def _logout(self):
        result = roles.native_logout_role(self.probe)
        need(result.get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE', 'native_logout_uncertain')
        if result.get('role') == 'regular':
            self.regular_logout_receipt = copy.deepcopy(result)

    def _login(self, role):
        self._guest()
        if self.probe.adapter is None:
            self.probe.startup()  # Relaunch after force-stop; login rechecks guest UI.
        result = roles.native_login_role(self.probe, role)
        need(result.get('status') == 'PASS_WITHIN_AUTH_UI_SCOPE', 'native_role_login_uncertain')
        if role == 'regular':
            self.regular_cycle += 1

    def _stop_writers(self):
        self._guest()
        if self.probe.adapter is not None:
            self.probe.stop_session('C2_normal_UI_logout_before_serialized_API')
        self.probe.adb('shell', 'am', 'force-stop', roles.APP)

    def _api(self, work):
        self._guest()
        need(self.probe.adapter is None, 'native_writers_must_stop_before_api')
        session = NormalOwnerSession(self.request, self.probe._known_role_memory,
                                     self.probe.private_values)
        def checked_work(api):
            def checked_api(method, path):
                code, body = api(method, path)
                if method == 'GET' and path == '/listing-editor-drafts/' + self.key and code == 200:
                    need(body.get('data', {}).get('payload', {}).get('fields', {}).get('title') == self.title,
                         'exact_original_native_title_required')
                return code, body
            return work(checked_api)
        try:
            return session.run(checked_work)
        finally:
            self.probe.report.setdefault('c2_normal_api_sessions', []).append({
                'normal_broker_28_required': True, 'logout_http_200': session.logout_200,
                'revoked_token_me_http_401': session.me_401, 'token_persisted': False,
                'native_ui_logout_is_not_server_token_revocation_proof': True})

    def _fallback(self, rows):
        names = _names(rows)
        need('قبول' not in names and 'رفض' not in names and
             any(text.startswith('اختيار 0% يفعّل السعي الثابت ') for text in names),
             'only_existing_platform_fallback_sai_allowed')
        need(policy.digits(self.probe.field('نسبة السعي %').get('text', '')) == '0',
             'actual_sai_zero_text_required_hint_is_not_value')

    def _nonimage_previous_control(self):
        """Settle the source footer before one input; keep all node data in memory."""
        need(self.cursor == STAGES.index('navigate_previous_to_specs') and self.inflight and
             not self.failed and self.rent_sai_readback is not None,
             'previous_reserved_editor_stage_required')
        p, deadline, observations = self.probe, time.monotonic() + 15, 0
        def bounded(row):
            b = row.get('bounds')
            return (isinstance(b, list) and len(b) == 4 and
                    all(type(v) is int for v in b) and b[0] < b[2] and b[1] < b[3])
        while time.monotonic() < deadline:
            self._actor('broker')
            rows = p.nodes()
            need(not _names(rows) & roles.AUTH_LABELS, 'previous_auth_surface_refused')
            visible = [r for r in rows if r.get('package') == roles.APP and r.get('visible') is True]
            named = {r['path']: r for r in visible if 'السابق' in policy.names(r)}
            exact = [r for r in named.values() if policy.names(r) == {'السابق'}]
            enabled = [r for r in exact if r.get('enabled') is True]
            direct = {r['path']: r for r in enabled if r.get('clickable') or
                      r.get('class') == 'android.widget.Button'}
            observations += 1
            diagnostic = {'observations': observations, 'visible_label_paths': len(named),
                          'enabled_exact_label_paths': len(enabled),
                          'direct_control_paths': len(direct), 'ancestor_control_paths': 0,
                          'state': 'absent' if not named else 'disabled_or_nonactionable',
                          'hashes_recorded': False}
            p.report['c2_v2_previous_control_readiness'] = diagnostic
            if len(direct) > 1 or (not direct and len(named) > 1):
                diagnostic['state'] = 'ambiguous'
                raise C2Blocked('nonimage_exact_normal_control_required')
            row = next(iter(direct.values()), None)
            if row is None and len(enabled) == 1:
                leaf = enabled[0]
                # Like Probe.tap, use the nearest actual clickable ancestor.
                # A disabled/button ancestor is a boundary, never skipped to
                # reach a wider clickable container.
                ancestors = [r for r in visible if leaf['path'].startswith(r['path'] + '.') and
                             (r.get('clickable') or r.get('class') == 'android.widget.Button')]
                if ancestors:
                    parent = max(ancestors, key=lambda r: len(r['path'].split('.')))
                    diagnostic['ancestor_control_paths'] = 1
                    if (parent.get('enabled') is True and parent.get('clickable') and
                        not parent.get('editable') and not parent.get('scrollable') and
                        '.' in parent['path'] and policy.names(parent) <= {'السابق'} and
                        bounded(parent) and bounded(leaf) and
                        parent['bounds'][0] <= leaf['bounds'][0] < leaf['bounds'][2] <= parent['bounds'][2] and
                        parent['bounds'][1] <= leaf['bounds'][1] < leaf['bounds'][3] <= parent['bounds'][3]):
                        row = parent
            names = _names(visible)
            footer = (({'خيارات المسودة', 'إرسال للمراجعة', 'السابق'} <= names and
                       'العودة إلى النواقص' not in names) if self.entry_mode == 'standard_editor' else
                      self.entry_mode == 'completed_review' and 'العودة إلى النواقص' in names)
            if row is not None and footer and bounded(row) and not row.get('editable') and not row.get('scrollable'):
                diagnostic['state'] = 'direct_ready' if direct else 'ancestor_ready'
                return row
            if not footer:
                diagnostic['state'] = 'editor_footer_pending'
            time.sleep(max(0, min(.25, deadline - time.monotonic())))
        raise C2Blocked('nonimage_previous_control_not_ready')

    def _nonimage_input(self, kind, label, value=None):
        """Existing normal receiver, synthetic allowlist, no persisted hashes.

        The stale-node witness is used only in memory for the ordinary receiver.
        This avoids inherited act()'s authenticated hash ledger on contact views;
        native and driver authentication state are never changed.
        """
        controls = {('set', 'الإيجار الشهري بالريال اليمني *'): 'rent',
                    ('click', 'نسبة مئوية %'): 'sai_mode', ('set', 'نسبة السعي %'): 'sai_rate',
                    ('set', 'رقم الاتصال *'): 'fixture_contact', ('click', 'معاينة'): 'validation_preview',
                    ('click', 'السابق'): 'previous', ('click', 'العودة إلى النواقص'): 'back_gaps',
                    ('click', 'خيارات المسودة'): 'draft_options', ('click', 'حفظ مسودة'): 'save_draft'}
        self._diagnostic_operation = {'control': controls.get((kind, label), 'unrecognized'),
                                      'substage': 'actor_check'}
        self._actor('broker')
        p = self.probe
        self._diagnostic_operation['substage'] = 'field_lookup'
        if kind == 'set':
            need((label, value) in {('الإيجار الشهري بالريال اليمني *', self.monthly_rent),
                                   ('نسبة السعي %', '0'), ('رقم الاتصال *', self.fixture_contact)},
                 'nonimage_synthetic_set_allowlist')
            if label == 'رقم الاتصال *':
                need(self.entry_mode == 'standard_editor' and self.contact_policy_prefixes is not None and
                     '77' in self.contact_policy_prefixes, 'observed_listing_contact_policy_required')
            row = self._nonimage_field(label)
        else:
            need(kind == 'click' and label in {'نسبة مئوية %', 'السابق', 'العودة إلى النواقص',
                                              'خيارات المسودة', 'حفظ مسودة', 'معاينة'},
                 'nonimage_click_allowlist')
            if label == 'السابق':
                row = self._nonimage_previous_control()
            else:
                matches = [row for row in p.matching(p.nodes(), label)
                           if row.get('visible') and row.get('enabled') and
                           (row.get('clickable') or row.get('class') == 'android.widget.Button')]
                need(len({row.get('path') for row in matches}) == 1,
                     'nonimage_exact_normal_control_required')
                row = matches[0]
        extra = {'node_path': row['path'], 'node_witness': row['witness']}
        explicit = getattr(p, 'explicit_pointer_mode', False)
        op = 'account-pointer-click' if kind == 'click' and explicit else 'account-' + kind
        if kind == 'set':
            extra['value_b64'] = base64.b64encode(value.encode()).decode()
            if explicit:
                extra['input_mode'] = 'explicit_pointer'
        self._diagnostic_operation['substage'] = 'instrument'
        result = p.instrument(op, **extra)
        self._diagnostic_operation['substage'] = 'delivery_check'
        need(result.get('account_action_delivered') == 'true' and
             (kind != 'set' or result.get('set_text_delivered') == 'true'),
             'nonimage_native_input_not_confirmed')
        if kind == 'set':
            self._diagnostic_operation['substage'] = 'dismiss_ime'
            p.adb('shell', 'input', 'keyevent', '4')
        self._diagnostic_operation['substage'] = 'completed'
        p.report['c2_v2_nonimage_input_operations_delivered'] = (
            p.report.get('c2_v2_nonimage_input_operations_delivered', 0) + 1)
        if label == 'رقم الاتصال *':
            return  # Contact deliveries retain only the count, never field metadata.
        p.report.setdefault('c2_v2_nonimage_input_delivery', []).append({
            'kind': kind, 'allowlisted_control': label, 'hashes_recorded': False,
            **{key: result[key] for key in ('native_pointer_used', 'native_pointer_events',
                'semantic_action_used', 'account_action_delivered', 'set_text_delivered') if key in result}})

    def _nonimage_field(self, label):
        """Seek only fixed step4 fields without inherited act() hash receipts."""
        need(label in {'الإيجار الشهري بالريال اليمني *', 'نسبة السعي %',
                       'رقم الاتصال *', 'رقم اتصال آخر (اختياري)'}, 'nonimage_field_allowlist')
        self._actor('broker')
        p = self.probe
        directions = (('backward', 'forward') if label in
                      {'الإيجار الشهري بالريال اليمني *', 'نسبة السعي %'} else ('forward', 'backward'))
        for direction in directions:
            for attempt in range(13):
                rows = p.nodes()
                need(not _names(rows) & roles.AUTH_LABELS, 'contact_auth_surface_refused')
                if p.matching(rows, label):
                    row = p.field(label, seek=False)
                    need(row.get('package') == roles.APP and row.get('visible') is True and
                         row.get('enabled') is True and row.get('editable') is True and
                         isinstance(row.get('text'), str), 'actual_nonimage_field_required')
                    return row
                if attempt == 12:
                    break
                scrolls = [row for row in rows if row.get('package') == roles.APP and
                           row.get('visible') is True and row.get('enabled') is True and row.get('scrollable')]
                need(bool(scrolls), 'nonimage_scroll_container_required')
                row = max(scrolls, key=lambda r: (r['bounds'][2]-r['bounds'][0]) *
                                                  (r['bounds'][3]-r['bounds'][1]))
                result = p.instrument('account-scroll', node_path=row['path'],
                                      node_witness=row['witness'], direction=direction)
                need(result.get('account_action_delivered') == 'true' and
                     ((result.get('native_pointer_used') == 'true' and
                       result.get('semantic_action_used') != 'true' and result.get('native_pointer_events') == '14') or
                      (result.get('semantic_action_used') == 'true' and result.get('native_pointer_used') != 'true')),
                     'nonimage_scroll_delivery_required')
                p.report['c2_v2_nonimage_input_operations_delivered'] = (
                    p.report.get('c2_v2_nonimage_input_operations_delivered', 0) + 1)
        raise C2Blocked('actual_nonimage_field_not_found')

    @staticmethod
    def _normalize_contact(value):
        # Exact ListingContactPolicy.normalize; no values leave this call chain.
        value = value.strip().translate(str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789'))
        value = re.sub(r'[\s()\-]', '', value)
        return value[4:] if value.startswith('+967') else value[5:] if value.startswith('00967') else value

    def _complete_fixture_contact(self):
        self._actor('broker')
        self._diagnostic_operation = {'control': 'fixture_contact', 'substage': 'contact_policy_observation'}
        need(self.entry_mode == 'standard_editor' and self.state['actor_id'] == 28 and
             self.contact_policy_prefixes is None, 'fixed_contact_fixture_scope_required')
        original = self._normalize_contact(self._nonimage_field('رقم الاتصال *')['text'])
        alternate = self._normalize_contact(self._nonimage_field('رقم اتصال آخر (اختياري)')['text'])
        # Invalid shape guarantees _preview returns with validation before any
        # sheet, save, submit or API call; do not infer the loaded prefix policy.
        need(re.fullmatch(r'7[0-9]{8}', original) is None and not alternate,
             'actual_invalid_default_contact_and_empty_alternate_required')
        self._rent_editor_surface()
        self._nonimage_input('click', 'خيارات المسودة')
        self._nonimage_input('click', 'معاينة')
        self._diagnostic_operation = {'control': 'fixture_contact', 'substage': 'contact_policy_observation'}
        deadline = time.monotonic() + 15
        prefixes = None
        while time.monotonic() < deadline:
            rows = self.probe.nodes()
            names = _names(rows)
            need(not names & roles.AUTH_LABELS, 'contact_auth_surface_refused')
            need('معاينة قبل الإرسال' not in names, 'validation_only_preview_required')
            if not {'خيارات المسودة', 'إرسال للمراجعة', 'السابق'} <= names:
                time.sleep(.25)
                continue  # Read-only settling while the popup closes.
            self._rent_editor_surface(rows)
            messages = {match.group(1) for name in names if (match := re.fullmatch(
                r'أدخل رقم جوال يمني من 9 أرقام يبدأ بـ (7[0-9](?:، 7[0-9]){0,9})\.', name))}
            need(len(messages) <= 1, 'unique_loaded_contact_policy_required')
            if messages:
                values = next(iter(messages)).split('، ')
                need(len(set(values)) == len(values) and '77' in values,
                     'fixture_contact_prefix_not_in_loaded_policy')
                prefixes = frozenset(values)
                break
            time.sleep(.25)
        need(prefixes is not None, 'actual_contact_policy_validation_message_required')
        self.contact_policy_prefixes = prefixes
        self._nonimage_input('set', 'رقم الاتصال *', self.fixture_contact)

    def _contact_readback(self):
        self._actor('broker')
        self._diagnostic_operation = {'control': 'fixture_contact', 'substage': 'contact_readback'}
        need(self.entry_mode == 'standard_editor' and isinstance(self.contact_policy_prefixes, frozenset) and
             '77' in self.contact_policy_prefixes, 'observed_listing_contact_policy_required')
        actual = self._nonimage_field('رقم الاتصال *')['text']
        normalized = self._normalize_contact(actual)
        alternate = self._normalize_contact(self._nonimage_field('رقم اتصال آخر (اختياري)')['text'])
        proof = {'native_contact_readback_matches_fixture': actual == self.fixture_contact,
                 'contact_policy_valid': bool(re.fullmatch(r'7[0-9]{8}', normalized)) and
                     normalized[:2] in self.contact_policy_prefixes,
                 'optional_contact_empty': not alternate, 'contact_policy_observed_in_ui': True}
        need(all(proof.values()), 'actual_valid_fixture_contact_required')
        return proof

    def _rent_sai_preview(self):
        self._actor('broker')
        p = self.probe
        contact = self._contact_readback() if self.entry_mode == 'standard_editor' else {}
        self._diagnostic_operation = {'control': 'rent_sai', 'substage': 'preview'}
        rent = policy.digits(self._nonimage_field('الإيجار الشهري بالريال اليمني *').get('text', ''))
        rate = policy.digits(self._nonimage_field('نسبة السعي %').get('text', ''))
        rows = p.nodes()  # Ephemeral only; no tree/root/node hashes or raw text retained.
        names = _names(rows)
        # The real /add-property route is a dismissible CustomTransitionPage.
        # Flutter's Arabic modal barrier is labelled "رفض" and has onTap, but
        # no button/text-field semantics. It is not a business rejection button.
        # Never classify a combined parent label or an actionable Button as this
        # barrier; the declared editor anchors below must also remain present.
        dismissals = [row for row in rows if 'رفض' in policy.names(row)]
        route_dismissal_only = all(
            policy.names(row) == {'رفض'} and row.get('class') == 'android.view.View' and
            row.get('editable') is False and row.get('package') == roles.APP and
            row.get('visible') is True for row in dismissals)
        custom_sai_sheet_absent = not bool(names & {
            'تحديد السعي قبل إرسال الإعلان', 'إرسال الإعلان للمراجعة؟',
            'العودة بدون إرسال', 'تأكيد السعي والمتابعة'})
        def shape(value, expected):
            # Fixed categories only; these observations never broaden acceptance.
            if value == expected:
                return 'EXPECTED'
            if not value:
                return 'EMPTY'
            if re.fullmatch(r'0[.٫]0{1,2}', value):
                return 'ZERO_DECIMAL'
            if (re.fullmatch(r'[1-9][0-9]{0,2}(?:[,٬][0-9]{3})+', value) and
                    value.replace(',', '').replace('٬', '') == expected):
                return 'GROUPED_EXPECTED'
            return 'OTHER'
        p.report['c2_v2_rent_sai_readback_diagnostic'] = {
            'stage': STAGES[self.cursor], 'fixture_key': self.key,
            'fixture_tag': self.tag, 'editor_chain': self.editor_chain,
            'rent_matches_expected': rent == self.monthly_rent,
            'sai_rate_is_zero': rate == '0',
            'auth_surface_absent': not bool(names & roles.AUTH_LABELS),
            'accept_reject_absent': not bool(names & {'قبول', 'رفض'}),
            'route_dismissal_only': route_dismissal_only,
            'custom_sai_sheet_absent': custom_sai_sheet_absent,
            'rent_shape': shape(rent, self.monthly_rent), 'rate_shape': shape(rate, '0')}
        need(rent == self.monthly_rent and rate == '0' and
             not (names & (roles.AUTH_LABELS | {'قبول'})) and
             route_dismissal_only and custom_sai_sheet_absent,
             'actual_synthetic_rent_and_sai_zero_text_required')
        self._rent_editor_surface(rows)
        notices = [text for text in names if re.fullmatch(
            r'اختيار 0% يفعّل السعي الثابت [0-9]+% تلقائيًا\.', text)]
        need(len(notices) == 1, 'actual_source_shaped_platform_fallback_notice_required')
        percentage = int(re.search(r'الثابت ([0-9]+)%', notices[0]).group(1))
        need(0 < percentage <= 100, 'loaded_positive_platform_fallback_percent_required')
        return {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'fixture_key': self.key,
                'fixture_tag': self.tag, 'editor_chain': self.editor_chain,
                'rent_text': rent, 'sai_rate_text': rate, 'fallback_notice': notices[0],
                'recording_stopped': True, 'custom_terms_visible': False,
                'policy_was_visually_reviewed': False,
                'persisted_policy_configuration_proved': False, **contact}

    def _safe_specs(self):
        self._actor('broker')
        rows = self.probe._capture_full_rows()
        need(not self.probe._capture_rows_private(rows), 'safe_specs_full_tree_privacy_required')
        names = _names(rows)
        need(not names & roles.AUTH_LABELS, 'safe_specs_auth_surface_refused')
        visible = _names([row for row in rows if row.get('package') == roles.APP and
                          row.get('visible') is True and row.get('enabled') is True])
        # Seeking the photo moves the section heading above the viewport. The
        # same source step remains identified by its photo and real footer.
        photo_step = ({'3/4', 'صور الإعلان (1/12)', 'مكتمل', 'إضافة صور', 'السابق', 'التالي'} <= visible and
            ((self.entry_mode == 'standard_editor' and 'العودة إلى النواقص' not in visible) or
             (self.entry_mode == 'completed_review' and 'العودة إلى النواقص' in visible)))
        need('المواصفات' in names or photo_step, 'actual_specification_step_required')

    def _rent_editor_surface(self, rows=None):
        """Observe the declared real editor mode; never change it implicitly."""
        self._actor('broker')
        names = _names(self.probe.nodes() if rows is None else rows)
        need(not names & roles.AUTH_LABELS, 'rent_editor_auth_surface_refused')
        if self.entry_mode == 'standard_editor':
            need({'خيارات المسودة', 'إرسال للمراجعة', 'السابق'} <= names and
                 'العودة إلى النواقص' not in names,
                 'actual_standard_editor_step4_required')
        else:
            need(self.entry_mode == 'completed_review' and 'العودة إلى النواقص' in names,
                 'actual_completed_review_editor_required')
        return True

    def register_regular_frame(self, stage, receipt):
        allowed = {'regular_marketplace', 'regular_messages', 'regular_listing_gate'}
        need(stage in allowed and stage.removeprefix('regular_') in self.regular_surfaces and
             receipt.get('stage') == stage and receipt.get('privacy_before_and_after') is True and
             receipt.get('regular_cycle') == self.regular_cycle and self.regular_cycle > 0 and
             policy.sha(receipt.get('sha256')) and isinstance(receipt.get('file'), str),
             'actual_same_regular_cycle_safe_frame_required')
        self.regular_frames[stage] = {key: receipt[key] for key in
                                      ('file', 'sha256', 'regular_cycle')}

    def _regular_account_semantics(self):
        self._actor('regular')
        names = _names(self.probe.nodes())
        need('تسجيل الخروج' in names and 'تسجيل الدخول أو إنشاء حساب' not in names and
             not (names & roles.AUTH_LABELS) and self.regular_cycle > 0,
             'fresh_normal_regular_logout_control_required')
        return {'regular_cycle': self.regular_cycle, 'normal_regular_role_witness': True,
                'logout_control_observed': True, 'guest_gate_absent': True,
                'auth_labels_absent': True, 'no_account_frame_or_hash_recorded': True}

    def _review_observation(self, stage, record):
        p = self.probe
        names = _names(p.nodes())
        need(not (names & roles.AUTH_LABELS), 'auth_context_forbids_c2_review')
        if stage == 'review_photo_before_save':
            self._safe_specs()
            title_key = ('bound_fixture_title_frame' if self.entry_mode == 'standard_editor'
                         else 'bound_c4_title_frame')
            other_title_key = ('bound_c4_title_frame' if self.entry_mode == 'standard_editor'
                               else 'bound_fixture_title_frame')
            need('صور الإعلان (1/12)' in names and 'مكتمل' in names and
                 record.get('evidence_kind') == 'SAFE_SPEC_PHOTO_PLUS_NONIMAGE_POLICY_AND_SERIALIZED_IDENTITY' and
                 record.get('same_serialized_editor_chain_reviewed') is True and
                 record.get('editor_chain') == self.editor_chain and
                 record.get('original_fixture_receipt_reviewed') is True and
                 record.get(title_key) == self.fixture_title_frame and other_title_key not in record and
                 record.get('photo_visually_unchanged') is True and
                 record.get('actual_safe_spec_photo_reviewed') is True and
                 record.get('semantic_preview') == self.rent_sai_readback and
                 self.rent_sai_readback is not None and
                 record.get('policy_was_visually_reviewed') is False,
                 'safe_photo_plus_serialized_identity_and_nonimage_policy_review_required')
        elif stage == 'review_promotion':
            need('عقاراتي' in names and self.title in names and
                 record.get('own_draft_card_visually_reviewed') is True,
                 'native_promotion_card_review_required')
        elif stage == 'review_submitted':
            need(self.title in names and names & {'بانتظار المراجعة', 'تحت المراجعة'} and
                 record.get('exact_tagged_card_status') in ('بانتظار المراجعة', 'تحت المراجعة') and
                 record.get('own_card_status_visually_verified') is True and
                 record.get('no_edit_action_on_exact_pending_card') is True and
                 record.get('published') is False, 'native_submission_review_required')
        elif stage == 'review_claimed':
            need(record.get('normal_support_claim_observed') is True and
                 record.get('own_task_owner_observed') is True and self.title in names,
                 'native_support_claim_review_required')
        elif stage == 'review_case':
            need(self.title in names and 'تحقيق الإعلان' in names and
                 record.get('exact_own_case_title_observed') is True,
                 'native_exact_review_case_required')
        elif stage == 'review_returned':
            need(self.return_queue_transition is not None and self._return_queue_observed() and
                 record.get('return_queue_transition') == self.return_queue_transition and
                 record.get('return_queue_transition_reviewed') is True and
                 record.get('exact_outcome_deferred_to_broker_reason') is True and
                 record.get('native_return_confirmed') is False and
                 record.get('publication_or_rejection_executed') is False and
                 record.get('exact_reason') == self.reason, 'native_return_review_required')
        elif stage == 'review_broker_reason':
            self._actor('broker')
            need(self.title in names and self.reason in names and
                 'ملاحظة فريق المراجعة' in names and 'إعادة الإرسال' in names,
                 'broker_exact_reason_not_observed')
        elif stage == 'regular_isolation':
            self._actor('regular')
            need('تسجيل الخروج' in names and self.title not in names and self.tag not in names and
                 self.reason not in names and not (names & {'مسوداتي', 'لوحة الدعم', 'الوارد', 'مهامي'}) and
                 record.get('broker_photo_absent') is True and
                 record.get('all_regular_tabs_checked') is True and
                 record.get('old_fixture_data_visible') is False and
                 record.get('old_support_workspace_visible') is False and
                 record.get('evidence_kind') == 'SAFE_SURFACE_FRAMES_PLUS_NONIMAGE_ROLE_WITNESS' and
                 record.get('safe_surface_frames') == self.regular_frames and
                 set(self.regular_frames) == {'regular_marketplace', 'regular_messages', 'regular_listing_gate'} and
                 type(record.get('regular_cycle')) is int and
                 record['regular_cycle'] == self.regular_cycle and
                 record.get('nonimage_role_witness') == self.regular_account_witness ==
                    self._regular_account_semantics() and
                 self.regular_surfaces == {'marketplace', 'messages', 'listing_gate'},
                 'regular_cache_isolation_review_required')

    def _list_observation(self, role):
        self._actor(role)
        rows = [row for row in self.probe.nodes() if row.get('package') == roles.APP
                and row.get('visible') is True and row.get('enabled') is True]
        names = _names(rows)
        need(not names & roles.AUTH_LABELS, 'listing_readiness_auth_surface_refused')
        return rows, names

    def _wait_loaded_list(self, surface, *, deadline=None):
        """Observe source-owned data markers before an already planned seek."""
        scopes = {
            'my_listings': ('broker', {'open_my_listings', 'open_reason', 'submit_confirm'}),
            'support_inbox': ('support', {'support_inbox'}),
            'support_queue': ('support', {'support_claim'}),
        }
        need(surface in scopes, 'known_list_readiness_surface_required')
        role, stages = scopes[surface]
        need(self.inflight and not self.failed and STAGES[self.cursor] in stages,
             'reserved_list_readiness_stage_required')
        deadline = time.monotonic() + 45 if deadline is None else deadline
        while time.monotonic() < deadline:
            _, names = self._list_observation(role)
            if surface == 'my_listings':
                ready = ('عقاراتي' in names and bool(names & {'ملخص إعلاناتك', 'إضافة عقار'})
                         and not names & {'إرسال الإعلان للمراجعة؟', 'تحديد السعي قبل إرسال الإعلان'})
            elif surface == 'support_inbox':
                ready = ({'الوارد', 'تحقيق إعلانات'} <= names and
                         bool(names & {'استلام', 'بعد الاستلام', 'فتح', 'تفاصيل القرار'}) and
                         'جارٍ تحميل طلبات الدعم…' not in names)
            else:
                ready = ({'تحقيق الإعلانات', 'طلبات التحقيق'} <= names and
                         bool(names & {'بانتظار الاستلام', 'تم الاستلام - قيد التحقيق'}) and
                         'جارٍ تحميل طلبات التحقيق...' not in names)
            if ready:
                return
            time.sleep(.4)
        need(False, 'source_loaded_list_not_observed')

    def _wait_submitted_listing(self):
        """Wait after the sole confirmation; reveal the refreshed exact card.

        Flutter closes the SAI sheet before submit/reload completes. The second
        bounded seek is allowed only if a previously observed title disappears
        on the still-loaded list. Root still reviews the actual card and status.
        """
        need(self.inflight and not self.failed and STAGES[self.cursor] == 'submit_confirm',
             'reserved_submit_readiness_stage_required')
        deadline = time.monotonic() + 120
        self._wait_loaded_list('my_listings', deadline=deadline)
        seeks = 1
        self.probe.seek(self.title, attempts=12)
        while time.monotonic() < deadline:
            rows, names = self._list_observation('broker')
            need('عقاراتي' in names, 'known_listing_surface_required')
            dialogs = bool(names & {'إرسال الإعلان للمراجعة؟', 'تحديد السعي قبل إرسال الإعلان'})
            titles = [row for row in rows if self.title in policy.names(row)
                      and isinstance(row.get('path'), str)]
            leaves = [row for row in titles if not any(
                other['path'].startswith(row['path'] + '.') for other in titles)]
            if not titles and names & {'ملخص إعلاناتك', 'إضافة عقار'} and not dialogs:
                need(seeks < 2, 'listing_title_lost_after_bounded_recovery')
                seeks += 1  # Consume before input; never replay an uncertain seek.
                self.probe.seek(self.title, attempts=12)
                continue
            if len(leaves) == 1 and not dialogs and names & {'بانتظار المراجعة', 'تحت المراجعة'}:
                return
            time.sleep(.4)
        need(False, 'exact_submitted_listing_not_ready')

    @staticmethod
    def _fields_below_title(rows, title, required):
        bounds = title.get('bounds')
        need(isinstance(bounds, list) and len(bounds) == 4 and
             all(type(value) is int for value in bounds), 'actual_listing_title_bounds_required')
        # Readiness only: a previous card's action above this title cannot stop
        # scrolling. Root's separate exact-card action binding stays authoritative.
        def below(row):
            box = row.get('bounds')
            return (isinstance(box, list) and len(box) == 4 and
                    all(type(value) is int for value in box) and box[1] >= bounds[1])
        return all(any(label in policy.names(row) and below(row) for row in rows)
                   for label in required)

    def _reveal_own_listing_fields(self):
        """Reveal the existing own-card evidence without clicking its actions."""
        stage = STAGES[self.cursor]
        need(self.inflight and not self.failed and stage in {'open_my_listings', 'open_reason'},
             'reserved_own_listing_reveal_stage_required')
        required = ({'إرسال للمراجعة'} if stage == 'open_my_listings' else
                    {self.reason, 'ملاحظة فريق المراجعة', 'إعادة الإرسال'})
        deadline = time.monotonic() + 30
        for attempt in range(7):
            rows, names = self._list_observation('broker')
            titles = [row for row in rows if self.title in policy.names(row)
                      and isinstance(row.get('path'), str)]
            leaves = [row for row in titles if not any(
                other['path'].startswith(row['path'] + '.') for other in titles)]
            need('عقاراتي' in names and len(leaves) == 1,
                 'same_exact_listing_title_required_during_reveal')
            need(not names & {'إرسال الإعلان للمراجعة؟', 'تحديد السعي قبل إرسال الإعلان'},
                 'own_listing_reveal_dialog_refused')
            if self._fields_below_title(rows, leaves[0], required):
                return
            need(attempt < 6 and time.monotonic() < deadline, 'own_listing_fields_not_revealed')
            self.probe.scroll('forward', short=True)

    def _reveal_support_card_fields(self):
        """Keep the exact task/queue title visible while revealing its control."""
        stage = STAGES[self.cursor]
        need(self.inflight and not self.failed and stage in {'support_inbox', 'support_claim'},
             'reserved_support_card_reveal_stage_required')
        title = 'تحقق نشر إعلان: ' + self.title if stage == 'support_inbox' else self.title
        required = ({'استلام'} if stage == 'support_inbox' else
                    {'تم الاستلام - قيد التحقيق', 'متابعة التحقيق'})
        anchors = ({'الوارد', 'تحقيق إعلانات'} if stage == 'support_inbox' else
                   {'تحقيق الإعلانات', 'طلبات التحقيق'})
        deadline = time.monotonic() + 30
        for attempt in range(7):
            rows, names = self._list_observation('support')
            titles = [row for row in rows if title in policy.names(row)
                      and isinstance(row.get('path'), str)]
            leaves = [row for row in titles if not any(
                other['path'].startswith(row['path'] + '.') for other in titles)]
            need(anchors <= names and len(leaves) == 1,
                 'same_exact_support_card_title_required_during_reveal')
            if self._fields_below_title(rows, leaves[0], required):
                return
            need(attempt < 6 and time.monotonic() < deadline, 'support_card_control_not_revealed')
            self.probe.scroll('forward', short=True)

    def _regular_absence(self, surface):
        self._actor('regular')
        names = _names(self.probe.nodes())
        need(self.title not in names and self.reason not in names and
             not any(self.tag in name for name in names) and
             not (names & {'مسوداتي', 'لوحة الدعم', 'الوارد', 'مهامي', 'متابعة التحقيق'}),
             'previous_actor_cache_visible_to_regular')
        if surface == 'listing_gate':
            need(bool(names & {'توثيق نوع الحساب مطلوب', 'أكمل الاسم الرباعي أولاً'}),
                 'normal_regular_listing_eligibility_gate_required')
        self.regular_surfaces.add(surface)

    def _execute(self, stage, prepared):
        p = self.probe
        if stage == 'load_roles':
            if not isinstance(getattr(p, '_known_role_memory', None), roles.KnownRoleMemory):
                need(callable(self.role_loader), 'already_validated_role_memory_loader_required')
                validated = self.role_loader()  # Contract: memory only; no file/env/session reads.
                roles.install_known_roles(p, validated)
                del validated
            need(all(p._known_role_memory.available(role) for role in roles.KNOWN_ROLES),
                 'all_three_known_roles_required')
            policy.adopt_reviewed_c1_broker_tracking(p, self.state, self.c1)
        elif stage == 'open_rent':
            self._actor('broker')
            p.require_value('عنوان الإعلان *', self.title)
            for label in ('تم تحديد موقع العقار على الخريطة', 'المواصفات', 'الإيجار الشهري بالريال اليمني *'):
                p.tap('التالي'); p.wait(label)
            field = p.field('الإيجار الشهري بالريال اليمني *')
            need(isinstance(field.get('text'), str) and not field['text'].strip(),
                 'same_blank_rent_editor_required')
            self._rent_editor_surface()
        elif stage == 'complete_rent':
            self._actor('broker')
            self._nonimage_input('set', 'الإيجار الشهري بالريال اليمني *', self.monthly_rent)
            self._nonimage_input('click', 'نسبة مئوية %')
            self._nonimage_input('set', 'نسبة السعي %', '0')
            if self.entry_mode == 'standard_editor':
                self._complete_fixture_contact()
            self._diagnostic_operation = {'control': 'rent_sai', 'substage': 'preview'}
            self.rent_sai_readback = self._rent_sai_preview()
            p.report['c2_v2_nonimage_rent_sai_preview'] = copy.deepcopy(self.rent_sai_readback)
        elif stage == 'navigate_previous_to_specs':
            self._actor('broker')
            need(self.rent_sai_readback is not None, 'actual_nonimage_preview_required_before_specs')
            self._nonimage_input('click', 'السابق'); p.wait('المواصفات')
            self._safe_specs(); p.seek('صور الإعلان (1/12)'); p.wait('مكتمل')
        elif stage == 'return_next_step3':
            self._safe_specs(); p.tap('التالي'); p.wait('الإيجار الشهري بالريال اليمني *')
            self.rent_sai_recheck = self._rent_sai_preview()
            need(self.rent_sai_recheck == self.rent_sai_readback,
                 'rent_sai_changed_after_safe_photo_review')
            self._rent_editor_surface()
            p.report['c2_v2_nonimage_rent_sai_recheck'] = copy.deepcopy(self.rent_sai_recheck)
        elif stage == 'back_gaps_to_completion':
            need(self.rent_sai_recheck == self.rent_sai_readback is not None,
                 'same_actual_rent_sai_recheck_required')
            need(self._rent_sai_preview() == self.rent_sai_readback,
                 'rent_sai_changed_immediately_before_completion')
            if self.entry_mode == 'standard_editor':
                # Standard step4 already exposes the normal explicit save menu.
                # No completion-mode transition or synthetic click is claimed.
                self._rent_editor_surface()
                p.report['c2_v2_completion_transition'] = {
                    'entry_mode': self.entry_mode, 'native_input_delivered': False,
                    'outcome': 'not_required_standard_editor_save_surface_observed'}
            else:
                self._nonimage_input('click', 'العودة إلى النواقص'); p.wait('خيارات المسودة')
        elif stage == 'review_case':
            # Root first accepts the exact case title at the top. The return
            # control is below evidence/history; reveal it without clicking.
            self.case_review_frame = {'file': prepared['actual_frame_file'],
                                      'sha256': prepared['frame_sha256']}
            self.case_header_binding = self._case_header()
            self._case_binding()
            self._actor('support')
            p.seek('إرجاع للتصحيح')
            need(self._case_header() == self.case_header_binding and
                 {'تحقيق الإعلان', 'إرجاع للتصحيح'} <= _names(p.nodes()),
                 'same_case_return_action_not_observed')
        elif stage in REVIEW_STAGES:
            pass  # Fresh evidence was checked before reservation; no input here.
        elif stage == 'full_save':
            self._actor('broker')
            need(self.rent_sai_recheck == self.rent_sai_readback is not None,
                 'same_actual_preview_required_before_explicit_save')
            if self.entry_mode == 'standard_editor':
                need(all(self.rent_sai_readback.get(key) is value for key, value in
                         self._contact_readback().items()), 'reviewed_contact_changed_before_explicit_save')
            self._nonimage_input('click', 'خيارات المسودة')
            self._nonimage_input('click', 'حفظ مسودة'); p.wait('عقاراتي', seconds=120)
        elif stage in ('broker_logout_for_pin', 'broker_logout', 'support_logout',
                       'broker_logout_after_reason', 'regular_logout'):
            self._logout()
        elif stage in ('stop_writers_for_pin', 'stop_writers_for_cleanup'):
            self._stop_writers()
        elif stage == 'pin_promotion':
            def pin(api):
                helper = cleanup_module.PromotedFixtureCleanup(api, self.state)
                result = helper.pin_candidate(native_writers_stopped=True)
                p.report['c2_pin_promotion_diagnostic'] = pin_candidate_diagnostic(result)
                p.save()
                need(result.get('status') == 'READY', 'strict_original_promoted_pair_pin_failed')
                return result
            self.property_id = self._api(pin)['property_id']
        elif stage in ('broker_login_for_submit', 'broker_login_for_reason'):
            self._login('broker')
        elif stage == 'support_login':
            self._login('support')
        elif stage == 'regular_login':
            self._login('regular')
        elif stage == 'regular_marketplace':
            self._actor('regular'); p.tap('العقارات', seek=False)
            self._regular_absence('marketplace')
        elif stage == 'regular_messages':
            self._actor('regular'); p.tap('الرسائل', seek=False)
            self._regular_absence('messages')
        elif stage == 'regular_listing_gate':
            self._actor('regular'); p.tap('إعلاناتي', seek=False)
            self._regular_absence('listing_gate')
        elif stage == 'regular_return_account':
            self._actor('regular')
            # Count-only Account navigation: native actor/session stays unchanged.
            authenticated = p.authenticated
            p.authenticated = False
            try:
                p.tap('حسابي', seek=False)
                p.wait_account_logout_control(seconds=60)
            finally:
                p.authenticated = authenticated
            self.regular_account_witness = self._regular_account_semantics()
            p.report['c2_v2_regular_nonimage_role_witness'] = copy.deepcopy(self.regular_account_witness)
        elif stage in ('open_my_listings', 'open_reason'):
            self._actor('broker'); p.tap('حسابي'); p.tap('عقاراتي')
            self._wait_loaded_list('my_listings'); p.seek(self.title)
            self._reveal_own_listing_fields()
        elif stage == 'support_inbox':
            self._actor('support'); p.tap('الوارد')
            self._wait_loaded_list('support_inbox'); p.seek('تحقق نشر إعلان: ' + self.title)
            self._reveal_support_card_fields()
        elif stage in TARGETS:
            record, node = prepared
            if stage == 'submit_confirm':
                self._fallback(p.nodes())
                need(record.get('existing_platform_fallback_sai_reviewed') is True and
                     record.get('custom_terms_accepted') is False, 'sai_actual_review_required')
            if stage == 'return_confirm':
                need(self.reason in _names(p.nodes()), 'exact_synthetic_reason_readback_required')
            # Existing receiver rechecks node witness; this is a manual reviewed
            # input, NOT proof of the separate unbuilt final-root card extension.
            p.act('click', node)
            self.delivered_frames[stage] = record['frame_sha256']
            if stage == 'submit_confirm':
                self._wait_submitted_listing()
            elif stage == 'support_claim':
                # Inbox claim normally opens the investigation queue after reload.
                p.wait('تحقيق الإعلانات', seconds=45)
                self._wait_loaded_list('support_queue')
                p.seek(self.title)
                p.wait('تم الاستلام - قيد التحقيق', seconds=45)
                self._reveal_support_card_fields()
            elif stage == 'support_open':
                p.wait('تحقيق الإعلان', seconds=45)
                p.wait(self.title, seconds=45)
            elif stage == 'return_confirm':
                self.return_confirmation_frame = {'file': record['actual_frame_file'],
                                                  'sha256': record['frame_sha256']}
                self._wait_return_queue()
        elif stage == 'submit_sai_setup':
            self._actor('broker'); p.wait('تحديد السعي قبل إرسال الإعلان')
            p.tap('نسبة مئوية %'); p.set('نسبة السعي %', '0'); self._fallback(p.nodes())
        elif stage == 'fill_return_reason':
            self._actor('support'); p.wait('إرجاع الإعلان للتصحيح')
            p.set('اكتب للمعلن تحديداً ما الذي يجب تعديله.', self.reason)
            need(self.reason in _names(p.nodes()), 'exact_synthetic_reason_readback_required')
        elif stage == 'cleanup':
            def clean(api):
                # Final pin is intentionally AFTER all native edits/return.
                # Keep the SAME helper for pin and the sole cleanup attempt.
                self.cleanup_helper = cleanup_module.PromotedFixtureCleanup(api, self.state)
                pin = self.cleanup_helper.pin_candidate(native_writers_stopped=True)
                p.report['c2_cleanup_pin_diagnostic'] = pin_candidate_diagnostic(pin)
                p.save()
                need(pin.get('status') == 'READY' and pin.get('property_id') == self.property_id,
                     'final_known_property_pin_failed')
                receipt = self.cleanup_helper.cleanup(native_writers_stopped=True)
                self.last_receipt = receipt
                p.report['c2_promoted_cleanup'] = copy.deepcopy(receipt)
                p.save()
                need(receipt.get('status') == 'PASS', 'promoted_cleanup_not_confirmed')
                return receipt
            self.last_receipt = self._api(clean)
            p.report['c2_promoted_cleanup'] = copy.deepcopy(self.last_receipt)
            p.fixture_possible = False
            p.auth_attempted = False
        else:
            raise C2Blocked('c2_stage_not_implemented')

    def advance(self):
        need(not self.failed and not self.inflight, 'c2_uncertain_stage_no_replay')
        if self.cursor == len(STAGES):
            return self._receipt('COLLECTED_PENDING_ROOT_ACCEPTANCE')
        stage = STAGES[self.cursor]
        self.pending_preparation = None
        self.preparation_attempt = getattr(self, 'preparation_attempt', 0) + 1
        try:
            prepared = self._prepare(stage)
        except Exception as error:
            # Only exact source-owned constants leave this preparation boundary.
            reason = 'preparation_exception_unclassified'
            if type(error) is C2Blocked:
                for known in PREPARE_REFUSAL_REASONS:
                    if error.args == (known,):
                        reason = known
                        break
            return self._preparation_pending(stage, reason)
        if prepared is None:
            return self._preparation_pending(stage, 'root_review_not_validated')
        # Reserve BEFORE the first possible input/auth/API call. No retry on
        # transport errors, failed postconditions, save failure or timeout.
        self.inflight = True
        self._diagnostic_operation = {'control': 'stage', 'substage': 'execute'}
        try:
            self._execute(stage, prepared)
            self.cursor += 1
            self.inflight = False
            receipt = self._receipt('STAGE_COMPLETED', completed=stage)
            self.probe.report.setdefault('c2_segmented_execution', []).append(receipt)
            self.probe.save()
            return receipt
        except Exception as error:
            self.failed = True
            self.inflight = False
            # Fixed categories and own code locations only. Never exception
            # messages/args, frame locals, raw UI values or contact-view hashes.
            diagnostic = dict(self._diagnostic_operation)
            diagnostic['stage'] = stage
            kind = type(error).__name__
            diagnostic['exception_type'] = kind if kind in {
                'C2Blocked', 'Blocked', 'AdmissionError', 'BridgeRefused',
                'TimeoutError', 'OSError', 'ValueError', 'KeyError', 'TypeError'} else 'OtherException'
            frames, trace = [], error.__traceback__
            while trace is not None:
                code = trace.tb_frame.f_code
                if code.co_filename == __file__:
                    frames.append({'file': 'ROOT_C2_EXECUTOR_V2/phase_extensions.py',
                                   'function': code.co_name, 'line': trace.tb_lineno})
                trace = trace.tb_next
            diagnostic['source_frames'] = frames[-8:]
            self.probe.report['c2_v2_stage_failure'] = diagnostic
            receipt = self._receipt('BLOCKED_NO_REPLAY', failed=stage)
            self.probe.report.setdefault('c2_segmented_execution', []).append(receipt)
            self.probe.save()
            raise C2Blocked('c2_stage_uncertain_root_readback_required') from None

    def _preparation_pending(self, stage, reason):
        need(not self.failed and not self.inflight and reason in PREPARE_REFUSAL_REASONS,
             'pre_input_pending_proof_required')
        self.pending_preparation = {
            'attempt': self.preparation_attempt, 'stage': stage, 'cursor': self.cursor,
            'preparation_only': stage in REVIEW_STAGES,
            'execution_called': False, 'reservation_created': False,
            'failed': False, 'inflight': False, 'reason': reason}
        return self._receipt('PENDING_ROOT_REVIEW', pending=stage,
                             pending_preparation=copy.deepcopy(self.pending_preparation))

    def _receipt(self, status, **facts):
        return {'status': status, 'scope': 'LOCAL native C2 segmented executor',
                'cursor': self.cursor, 'next_stage': STAGES[self.cursor] if self.cursor < len(STAGES) else None,
                'phase1_accepted': False, 'automatic_replay_allowed': False,
                'executor_version': 2, 'editor_entry_mode': getattr(self, 'entry_mode', None),
                'regular_native_logout_confirmed': bool(self.regular_logout_receipt and
                    self.regular_logout_receipt.get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE'),
                'known_promoted_property_id': self.property_id,
                'manual_reviewed_input_only': True, 'compiled_scoped_card_guard_proved': False,
                'immutable_audit_sai_review_support_history_may_remain': True,
                'cloud_object_erasure_independently_verified': False, **facts}


def configure_c2(probe, original_state, c1_review, c4_review, **callbacks):
    need(not hasattr(probe, '_root_c2_executor_v2'), 'existing_c2_executor_protected')
    executor = C2Executor(probe, original_state, c1_review, c4_review, **callbacks)
    probe._root_c2_executor_v2 = executor
    return executor._receipt('CONFIGURED_NO_DEVICE_OR_API_WORK')


def supply_review(probe, record):
    need(hasattr(probe, '_root_c2_executor_v2'), 'c2_configuration_required')
    probe._root_c2_executor_v2.review(record)
    return {'review_stored_in_memory': True, 'phase1_accepted': False}


def run_phase(probe, phase='C2'):
    need(phase == 'C2', 'this_local_extension_exposes_only_c2')
    need(hasattr(probe, '_root_c2_executor_v2'), 'c2_configuration_required')
    return probe._root_c2_executor_v2.advance()
