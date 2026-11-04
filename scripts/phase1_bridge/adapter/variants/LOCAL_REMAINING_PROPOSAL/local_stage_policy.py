"""Offline-tested LOCAL continuation policy; no I/O, API or device operations.

The exclusive native controller supplies actual observations. These guards never
infer a card or invent a successful observation. Root must view the real frame
before supplying a manual review. No ordinary boolean/device-event count alone
accepts a native journey.
"""
import copy
import hashlib
import json
import re
import time
import uuid
from ci_remote_evidence import fresh_remote_review

APP = 'com.aqer.yemen.uat'
AI_NOTICE = 'راجع التفاصيل والنص قبل تطبيقها على مسودتك.'
FALLBACK_NOTICE = 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.'
AUTH_LABELS = frozenset({'مرحبًا بعودتك', 'رقم واتساب', 'رمز التحقق',
                         'رمز التحقق عبر واتساب', 'تأكيد والدخول', 'إرسال رمز واتساب'})
ACTION_SPEC = {
    'c4_apply': ('broker', 'استخدام البيانات والمتابعة'),
    'broker_submit': ('broker', 'إرسال للمراجعة'),
    'support_claim': ('support', 'استلام'),
    'support_open': ('support', 'متابعة التحقيق'),
}
BRIEF = ('شقة للإيجار في صنعاء في الدور الثاني، رقم الشقة 7، '
         'ثلاث غرف نوم وحمامان، دون موقف سيارة، واجهة شمالية.')


class RemainingBlocked(RuntimeError):
    """Fixed diagnostic labels only."""


def need(ok, code):
    if not ok:
        raise RemainingBlocked(code)


def sha(value):
    return isinstance(value, str) and re.fullmatch('[a-f0-9]{64}', value) is not None


def canonical_digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def digits(value):
    return str(value).translate(str.maketrans('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
                                             (''.join(str(value) for value in range(10)) * 2))).strip()


def tagged(title, tag):
    return isinstance(title, str) and re.search(
        r'(?<![A-Za-z0-9-])' + re.escape(tag) + r'(?![A-Za-z0-9-])', title) is not None


def names(row):
    return {line.strip() for key in ('text', 'description', 'hint')
            for line in str(row.get(key, '')).splitlines() if line.strip()}


def _rect(row):
    rect = row.get('bounds')
    need(isinstance(rect, list) and len(rect) == 4 and
         all(type(n) is int for n in rect) and
         rect[2] - rect[0] > 8 and rect[3] - rect[1] > 8,
         'actual_node_bounds_required')
    return rect


def _contains(outer, inner):
    return outer[0] <= inner[0] < inner[2] <= outer[2] and \
           outer[1] <= inner[1] < inner[3] <= outer[3]


def reviewed_action_node(rows, context, expected_title, original_tag, review,
                         *, native_role, auth_uncertain, now_utc=None):
    """Return ONE explicitly reviewed fresh node; never search for a global label.

    Root may approve a visually associated card/button when Flutter exposes no
    usable card ancestor. That is a manual click, not automatic structural proof.
    If a card path is supplied, both title and button must be its descendants.
    The parent must perform exactly one ordinary self-targeted input operation
    using the returned node; no automatic retry or label-based fallback.
    """
    need(context in ACTION_SPEC, 'remaining_action_not_allowlisted')
    role, label = ACTION_SPEC[context]
    need(native_role == role and auth_uncertain is False,
         'known_normal_native_actor_required')
    need(isinstance(original_tag, str) and
         re.fullmatch(r'AQER-C[124]-[a-f0-9]{12}', original_tag) and
         tagged(expected_title, original_tag), 'known_tagged_fixture_required')
    need(isinstance(review, dict) and
         review.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW' and
         review.get('context') == context and review.get('privacy_checked') is True and
         review.get('same_exact_tagged_item_and_button_visually_verified') is True and
         sha(review.get('frame_sha256')), 'actual_manual_frame_review_required')
    need(fresh_remote_review(review, now_utc=now_utc),
         'actual_manual_frame_review_expired')
    visible = [row for row in rows if row.get('package') == APP and
               row.get('visible') and row.get('enabled')]
    eligible = {row.get('path'): row for row in visible}
    need(len(eligible) == len(visible), 'duplicate_fresh_node_path')
    need('0' in eligible, 'fresh_app_root_required')
    need(not any(names(row) & AUTH_LABELS for row in eligible.values()),
         'auth_context_forbids_remaining_action')
    for path, row in eligible.items():
        need(isinstance(path, str) and re.fullmatch(r'0(?:\.[0-9]{1,4}){0,40}', path) and
             sha(row.get('witness')), 'fresh_node_identity_required')
    root = eligible['0']
    need(root['witness'] == review.get('root_witness'), 'reviewed_root_changed')
    title = eligible.get(review.get('title_path'))
    action = eligible.get(review.get('button_path'))
    need(title is not None and title.get('witness') == review.get('title_witness') and
         expected_title in names(title), 'reviewed_fixture_title_changed')
    # Matching parent/child semantics may repeat the same title; independent
    # visible leaf matches represent ambiguous cards and are refused.
    matching = [row for row in eligible.values() if expected_title in names(row)]
    leaves = [row for row in matching if not any(other['path'].startswith(row['path'] + '.')
                                               for other in matching)]
    need(len(leaves) == 1 and leaves[0]['path'] == title['path'],
         'reviewed_fixture_title_not_unique')
    need(action is not None and action.get('witness') == review.get('button_witness') and
         label in names(action) and
         (action.get('clickable') or action.get('class') == 'android.widget.Button'),
         'reviewed_exact_button_changed')
    screen, tb, ab = _rect(root), _rect(title), _rect(action)
    need(_contains(screen, tb) and _contains(screen, ab), 'reviewed_target_outside_screen')
    card_path = review.get('card_path')
    if card_path is not None:
        card = eligible.get(card_path)
        need(card is not None and card_path != '0' and
             card.get('witness') == review.get('card_witness') and
             title['path'].startswith(card_path + '.') and
             action['path'].startswith(card_path + '.') and not card.get('scrollable'),
             'reviewed_card_boundary_changed')
        cb = _rect(card)
        need(_contains(screen, cb) and _contains(cb, tb) and _contains(cb, ab),
             'reviewed_card_bounds_changed')
    else:
        need(review.get('card_boundary_not_exposed_manual_click_only') is True,
             'actual_card_review_or_explicit_manual_click_required')
    return copy.deepcopy(action)


class RemainingLocalFence:
    """Serial C4-before-C2 policy for the SAME C1 fixture, without side effects."""
    def __init__(self, original_state, c1_review):
        state, proof = copy.deepcopy(original_state), copy.deepcopy(c1_review)
        try:
            key = state['key']
            canonical = str(uuid.UUID(key))
        except (KeyError, ValueError, TypeError, AttributeError):
            raise RemainingBlocked('original_c1_fixture_required') from None
        need(canonical == key and state.get('actor_id') == 28 and
             state.get('creation_request_sent') is True and state.get('created_confirmed') is True,
             'original_c1_fixture_required')
        baseline, tag = state.get('baseline'), state.get('tag')
        need(isinstance(baseline, dict) and set(baseline) == {'properties', 'drafts'} and
             isinstance(baseline['properties'], dict) and isinstance(baseline['drafts'], dict) and
             len(baseline['properties']) == 25 and len(baseline['drafts']) == 7 and
             key not in baseline['drafts'], 'original_protected_baseline_required')
        need(all(isinstance(identity, str) and identity and sha(value)
                 for rows in baseline.values() for identity, value in rows.items()),
             'original_protected_baseline_digest_shape')
        need(isinstance(tag, str) and re.fullmatch(r'AQER-C1-[a-f0-9]{12}', tag),
             'original_c1_tag_required')
        need(proof.get('manual_review_completed') is True and proof.get('c1_accepted') is True and
             proof.get('fixture_key') == key and proof.get('fixture_tag') == tag and
             tagged(proof.get('native_title'), tag) and sha(proof.get('restored_frame_sha256')) and
             proof.get('monthly_rent_still_blank') is True,
             'actual_c1_restored_review_required')
        self.__state, self.__key, self.__tag = state, key, tag
        self.__baseline_digest = canonical_digest(baseline)
        self.__title = proof['native_title']
        self.__stage = 'C1_REVIEWED'
        self.__pending = None
        self.__return_reason = None

    @property
    def stage(self):
        return self.__stage

    @property
    def title(self):
        return self.__title

    @property
    def fixture_key(self):
        return self.__key

    def reserve_c4_request(self, *, native_role, auth_uncertain):
        need(self.__stage == 'C1_REVIEWED' and self.__pending is None,
             'c4_request_order_or_repeat_refused')
        need(native_role == 'broker' and auth_uncertain is False,
             'known_normal_broker_required')
        self.__pending = 'c4_request'
        return BRIEF

    def accept_c4_review(self, review):
        need(self.__stage == 'C1_REVIEWED' and self.__pending == 'c4_request',
             'c4_review_order_refused')
        need(review.get('actual_ai_notice') == AI_NOTICE and
             review.get('literal_fallback_notice_visible') is False,
             'c4_requires_actual_ai_notice')
        need(review.get('manual_all_fields_and_copy_reviewed') is True and
             sha(review.get('frame_sha256')) and
             review.get('title_readback') == self.__title and
             review.get('title_tag_edited_natively') is True,
             'c4_actual_review_and_unique_title_required')
        selected = review.get('selected_fields')
        need(isinstance(selected, dict) and digits(selected.get('floor_number')) == '2' and
             digits(selected.get('unit_number')) == '7', 'c4_explicit_floor_unit_required')
        expected = {'type': 'apartment', 'purpose': 'rent', 'floor_number': '2',
                    'unit_number': '7', 'bedrooms': '3', 'bathrooms': '2',
                    'governorate': 'صنعاء', 'has_parking': False, 'building_facade': 'north'}
        for field, value in selected.items():
            need(field in expected, 'c4_unsupported_selected_field')
            if field in {'floor_number', 'unit_number', 'bedrooms', 'bathrooms'}:
                need(digits(value) == expected[field], 'c4_selected_fact_mismatch')
            else:
                need(type(value) is type(expected[field]) and value == expected[field],
                     'c4_selected_fact_mismatch')
        need(review.get('monthly_rent_still_blank') is True,
             'c4_must_keep_account_checkpoint_scope')
        self.__stage, self.__pending = 'C4_REVIEWED', None
        return {'source_evidence': 'ai inferred from exact live UI notice/source mapping',
                'raw_response_source_field_observed': False,
                'provider_grounding_api04_is_separate': True, 'ready_for_reviewed_apply': True}

    def action_spec(self, context):
        expected = {'c4_apply': 'C4_REVIEWED', 'broker_submit': 'C2_PROMOTED',
                    'support_claim': 'C2_SUBMITTED', 'support_open': 'C2_CLAIMED'}
        need(context in expected and self.__stage == expected[context] and self.__pending is None,
             'remaining_action_order_or_repeat_refused')
        title = ('تحقق نشر إعلان: ' + self.__title
                 if context == 'support_claim' else self.__title)
        return {'context': context, 'expected_title': title, 'tag': self.__tag,
                'required_role': ACTION_SPEC[context][0], 'label': ACTION_SPEC[context][1]}

    def reserve_action(self, context):
        spec = self.action_spec(context)
        self.__pending = context  # Consumed before delivery; no automatic retry.
        return spec

    def confirm_c4_saved_restored(self, proof):
        need(self.__stage == 'C4_REVIEWED' and self.__pending == 'c4_apply',
             'c4_apply_save_restore_order_refused')
        need(all(proof.get(key) is True for key in
                 ('native_apply_delivered', 'explicit_native_save_delivered',
                  'force_stop_without_reset', 'photo_visually_unchanged',
                  'location_restored', 'monthly_rent_still_blank', 'manual_review_completed')) and
             proof.get('restored_title') == self.__title and
             digits(proof.get('restored_floor')) == '2' and
             digits(proof.get('restored_unit')) == '7' and sha(proof.get('restored_frame_sha256')),
             'actual_c4_apply_save_restore_proof_required')
        self.__stage, self.__pending = 'C4_SAVED_RESTORED', None

    def confirm_c2_promotion(self, proof):
        need(self.__stage == 'C4_SAVED_RESTORED' and self.__pending is None,
             'c2_promotion_must_follow_c4_restore')
        need(proof.get('title') == self.__title and proof.get('same_fixture_key') == self.__key and
             proof.get('native_full_save_delivered') is True and
             proof.get('my_listings_page_observed') is True and
             proof.get('monthly_rent_filled_natively') is True and
             proof.get('existing_platform_fallback_sai_reviewed') is True and
             proof.get('custom_terms_accepted') is False and
             proof.get('own_draft_card_visually_reviewed') is True and sha(proof.get('frame_sha256')),
             'actual_c2_promotion_proof_required')
        self.__stage = 'C2_PROMOTED'

    def confirm_c2_step(self, step, proof):
        sequence = {
            'submitted': ('C2_PROMOTED', 'broker_submit', 'C2_SUBMITTED'),
            'claimed': ('C2_SUBMITTED', 'support_claim', 'C2_CLAIMED'),
            'case_opened': ('C2_CLAIMED', 'support_open', 'C2_CASE_OPEN'),
            'returned': ('C2_CASE_OPEN', None, 'C2_RETURNED'),
            'broker_reason': ('C2_RETURNED', None, 'C2_REASON_OBSERVED'),
            'regular_isolation': ('C2_REASON_OBSERVED', None, 'C2_ISOLATED'),
        }
        need(step in sequence, 'remaining_step_not_allowlisted')
        before, pending, after = sequence[step]
        need(self.__stage == before and self.__pending == pending,
             'remaining_step_order_refused')
        need(proof.get('manual_review_completed') is True and sha(proof.get('frame_sha256')) and
             proof.get('fixture_key') == self.__key and proof.get('exact_tag') == self.__tag,
             'actual_known_fixture_step_proof_required')
        if step == 'submitted':
            need(proof.get('native_submission_observed') is True and
                 proof.get('custom_terms_accepted') is False and
                 proof.get('published') is False, 'native_submission_scope_invalid')
        elif step == 'claimed':
            need(proof.get('normal_support_claim_observed') is True and
                 proof.get('own_task_owner_observed') is True, 'native_claim_not_observed')
        elif step == 'case_opened':
            need(proof.get('exact_own_case_title_observed') is True,
                 'known_review_case_not_observed')
        elif step == 'returned':
            need(proof.get('native_return_confirmed') is True and
                 proof.get('publication_or_rejection_executed') is False and
                 tagged(proof.get('reason'), self.__tag), 'known_native_return_not_observed')
            self.__return_reason = proof['reason']
        elif step == 'broker_reason':
            need(proof.get('normal_broker_authenticated') is True and
                 proof.get('exact_return_reason_visible') is True and
                 proof.get('observed_reason') == self.__return_reason,
                 'broker_return_reason_not_observed')
        else:
            need(proof.get('normal_regular_authenticated') is True and
                 proof.get('logout_control_observed') is True and
                 proof.get('listing_eligibility_gate_observed') is True and
                 proof.get('listing_eligibility_gate_title') in
                    ('توثيق نوع الحساب مطلوب', 'أكمل الاسم الرباعي أولاً') and
                 proof.get('old_fixture_data_visible') is False and
                 proof.get('old_support_workspace_visible') is False,
                 'normal_regular_isolation_not_observed')
        self.__stage, self.__pending = after, None

    def confirm_cleanup(self, receipt, *, all_native_writers_stopped, native_ui_logged_out,
                        api_logout_200, api_me_401):
        need(self.__stage == 'C2_ISOLATED' and self.__pending is None,
             'cleanup_acceptance_order_refused')
        need(all_native_writers_stopped is True and native_ui_logged_out is True and
             api_logout_200 is True and api_me_401 is True and
             receipt.get('status') == 'PASS' and receipt.get('fixture_key') == self.__key and
             receipt.get('fixture_tag') == self.__tag and
             receipt.get('baseline_sha256') == self.__baseline_digest and
             receipt.get('known_application_rows_removed') is True and
             receipt.get('protected_baseline_restored') is True and
             receipt.get('known_property_media_routes_404') is True,
             'known_fixture_cleanup_not_complete')
        self.__stage = 'C2_C4_COLLECTED_AND_REVIEWED'
        return {'c2_c4_collected_and_reviewed': True, 'phase1_accepted': False,
                'cloud_objects_independently_erased': False,
                'immutable_history_may_remain': True,
                'native_ui_logout_is_not_independent_server_token_revocation_proof': True}


def adopt_reviewed_c1_broker_tracking(probe, original_state, c1_review):
    """Track an ALREADY normally authenticated/restored broker; does not log in.

    Use after loading the optional known-role input pool, which resets its role
    tracker. No footer-only identity inference, token/session read or API call.
    """
    RemainingLocalFence(original_state, c1_review)  # Same identity/review fence.
    need(probe.authenticated is True and probe.recorder is None,
         'reviewed_retained_broker_session_required')
    bootstrap = probe.report.get('api_bootstrap') or {}
    identity = bootstrap.get('identity') or {}
    need(bootstrap.get('status') == 'PASS' and bootstrap.get('fresh_session_cleaned') is True and
         identity.get('actor_id') == 28 and identity.get('account_type') == 'broker',
         'normal_broker_bootstrap_identity_pin_required')
    state = getattr(getattr(probe, 'fixture_api', None), 'state', None)
    need(isinstance(state, dict) and state.get('key') == original_state['key'] and
         state.get('tag') == original_state['tag'] and
         state.get('baseline') == original_state.get('baseline') and
         probe.title == c1_review['native_title'],
         'current_known_fixture_tracking_required')
    cases = {row['id']: row for row in probe.report.get('cases', [])}
    need(all(cases.get(key, {}).get('status') == 'PASS' for key in
             ('C1-auth', 'C1-photo-save', 'C1-force-stop-restore')),
         'actual_c1_native_steps_required')
    probe.active_native_role = 'broker'
    probe.native_auth_uncertain = False
    receipt = {'role_tracking_only': True, 'normal_broker_api_identity_pinned': True,
               'actual_c1_retained_session_reviewed': True,
               'footer_only_identity_assumption': False,
               'new_authentication_performed': False}
    probe.report['remaining_initial_broker_tracking'] = receipt
    probe.save()
    return receipt


def perform_one_reviewed_action(probe, fence, context, review):
    """Future exclusive-controller hook; this file never invokes it on import.

    The parent views the actual frame, supplies the review, and invokes this
    through its serialized controller. No label search, recorder or API is used.
    Node freshness is rechecked here and by the existing self-targeted helper.
    This manual-input path is not an atomic card-title/input transaction.
    """
    spec = fence.action_spec(context)
    need(probe.authenticated is True, 'normal_native_auth_required')
    row = reviewed_action_node(
        probe.nodes(), context, spec['expected_title'], spec['tag'], review,
        native_role=getattr(probe, 'active_native_role', None),
        auth_uncertain=getattr(probe, 'native_auth_uncertain', True))
    fence.reserve_action(context)
    try:
        probe.act('click', row)
    except Exception:
        # No arbitrary controller exception text, no replay after uncertainty.
        probe.report.setdefault('remaining_action_delivery', []).append(
            {'context': context, 'delivered': False, 'uncertain': True,
             'automatic_retry_allowed': False})
        probe.save()
        raise RemainingBlocked('reviewed_action_delivery_uncertain') from None
    receipt = {'context': context, 'delivered': True, 'manual_review_supplied': True,
               'automatic_retry_allowed': False, 'journey_accepted_by_delivery': False}
    probe.report.setdefault('remaining_action_delivery', []).append(receipt)
    probe.save()
    return receipt
