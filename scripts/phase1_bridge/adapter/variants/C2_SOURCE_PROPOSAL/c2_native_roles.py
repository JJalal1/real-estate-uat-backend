"""LOCAL-ONLY integration proposal; never imported by the active controller.

No file/environment reads, network client, app-storage access, CLI or execution
on import. The parent must review/integrate this after C1, retaining its v5 input
fixes. Credentials arrive only as the already validated in-memory object.
"""
import base64
import re
import time
from ci_remote_evidence import fresh_remote_review

APP = 'com.aqer.yemen.uat'
KNOWN_ROLES = frozenset({'broker', 'support', 'regular'})
ROLE_NAV = {
    'broker': frozenset({'عملي', 'العملاء', 'حسابي'}),
    'support': frozenset({'لوحة الدعم', 'الوارد', 'مهامي', 'حسابي'}),
    'regular': frozenset({'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'}),
}
GUEST_HOME_ANCHORS = frozenset({'ابحث عن عقار أو منطقة…', 'ماذا تبحث عنه؟'})
GUEST_HOME_NAV = frozenset({'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'})

AUTH_LABELS = frozenset({'مرحبًا بعودتك', 'رقم واتساب', 'رمز التحقق',
                         'رمز التحقق عبر واتساب', 'تأكيد والدخول', 'إرسال رمز واتساب'})
ACTION_LABELS = frozenset({'استلام', 'استلام الطلب', 'متابعة التحقيق'})
CARD_CONTROLS = {
    'استلام': frozenset({'استلام', 'بعد الاستلام', 'فتح'}),
    'استلام الطلب': frozenset({'استلام الطلب', 'عرض التفاصيل'}),
    'متابعة التحقيق': frozenset({'متابعة التحقيق'}),
}


class RouteBlocked(RuntimeError):
    """Only fixed, source-defined diagnostic labels."""


def need(condition, code):
    if not condition:
        raise RouteBlocked(code)


def row_labels(row):
    return {line.strip() for key in ('text', 'description', 'hint')
            for line in str(row.get(key, '')).splitlines() if line.strip()}


class KnownRoleMemory:
    """Retains only three known actors and OTP in memory; repr has no values."""
    def __init__(self, validated_access):
        need(isinstance(validated_access, dict), 'validated_role_memory_required')
        otp, phones = validated_access.get('otp'), validated_access.get('phones')
        need(isinstance(otp, str) and re.fullmatch('[0-9]{6}', otp) is not None and
             isinstance(phones, dict), 'validated_role_memory_required')
        selected = {}
        for role in KNOWN_ROLES:
            if role in phones:
                value = phones[role]
                need(isinstance(value, str) and
                     re.fullmatch(r'\+?[0-9]{7,20}', value) is not None,
                     'known_role_phone_format_invalid')
                selected[role] = value
        need('broker' in selected, 'known_broker_memory_required')
        canonical = [('+' + value[2:] if value.startswith('00') else value).lstrip('+')
                     for value in selected.values()]
        need(len(set(canonical)) == len(canonical), 'known_role_alias_collision')
        self.__otp, self.__phones = otp, selected

    def __repr__(self):
        return '<KnownRoleMemory redacted>'

    def available(self, role):
        return isinstance(role, str) and role in KNOWN_ROLES and role in self.__phones

    def resolve(self, role):
        need(self.available(role), 'known_role_not_available')
        return self.__phones[role], self.__otp

    def add_redactions_to(self, target):
        target.add(self.__otp)
        for phone in self.__phones.values():
            canonical = '+' + phone[2:] if phone.startswith('00') else phone
            target.update({phone, phone.lstrip('+'), canonical, canonical.lstrip('+')})

    def clear(self):
        self.__phones.clear()
        self.__otp = ''


def install_known_roles(probe, validated_access):
    """Call before the parent discards validated_access; no file/env re-read."""
    memory = KnownRoleMemory(validated_access)
    memory.add_redactions_to(probe.private_values)
    probe._known_role_memory = memory
    probe.active_native_role = None
    # Installation itself proves no UI state. Initial login needs the explicit
    # guest recovery check, just like recovery after an uncertain operation.
    probe.native_auth_uncertain = True


def _visible_names(rows):
    return set().union(*(row_labels(row) for row in rows)) if rows else set()


def _visible_app_names(rows):
    return _visible_names([row for row in rows if row.get('package') == APP
                           and row.get('visible') is True])


def _safe_role_failure(error):
    # Never relay arbitrary controller exceptions, phone values or API bodies.
    safe = {'fresh_guest_account_gate_required', 'post_auth_account_not_observed',
            'expected_native_role_not_observed', 'native_guest_logout_state_not_observed',
            'native_guest_marketplace_not_observed', 'retained_broker_home_not_observed',
            'support_queue_before_logout_required', 'support_shell_before_logout_required'}
    return str(error) if isinstance(error, RouteBlocked) and str(error) in safe \
        else 'controller_operation_blocked'


def confirm_explicit_guest_recovery(probe, *, parent_cancelled_pending_native_work):
    """Parent must first stop/relaunch pending native work and show guest Account.

    This only verifies the current native guest gate and clears the UI-actor
    uncertainty latch. It neither clears app storage nor proves server logout.
    """
    need(parent_cancelled_pending_native_work is True,
         'explicit_native_work_recovery_required')
    need(probe.recorder is None and not probe.authenticated,
         'fresh_guest_recovery_required')
    for _ in range(2):
        names = _visible_names(probe.nodes())
        need('تسجيل الدخول أو إنشاء حساب' in names and 'تسجيل الخروج' not in names and
             not (names & AUTH_LABELS) and
             not (names & {'عملي', 'العملاء', 'لوحة الدعم', 'الوارد', 'مهامي'}),
             'fresh_guest_recovery_required')
    probe.active_native_role = None
    probe.native_auth_uncertain = False
    receipt = {'guest_gate_observed': True, 'ui_actor_uncertainty_cleared': True,
               'parent_cancelled_pending_native_work': True,
               'server_token_revocation_verified': False,
               'authentication_captures': False, 'auth_hashes_recorded': False}
    probe.report.setdefault('native_guest_recovery', []).append(receipt)
    probe.save()
    return receipt


def native_login_role(probe, role):
    """RPC input is a known role enum only; input values remain internal.

    Uses the existing controller's actual native tap/set/nodes operations. It
    never captures a frame/video, reads app storage or uses an API auth shortcut.
    Returns only public role/status flags and an operation count.
    """
    memory = getattr(probe, '_known_role_memory', None)
    need(isinstance(memory, KnownRoleMemory) and memory.available(role),
         'known_role_not_available')
    need(probe.recorder is None, 'recording_must_stop_before_auth')
    need(not probe.authenticated and getattr(probe, 'active_native_role', None) is None,
         'previous_native_actor_must_logout_first')
    need(getattr(probe, 'native_auth_uncertain', True) is False,
         'uncertain_native_auth_requires_explicit_recovery')
    receipt = {'role': role, 'status': 'BLOCKED', 'normal_whatsapp_ui': True,
               'authentication_captures': False, 'auth_hashes_recorded': False,
               'server_actor_id_verified_by_this_chunk': False,
               'native_journey_accepted': False}
    start_count = probe.report.get('auth_input_operations_delivered', 0)
    # The parent act() logs hashes only when authenticated=True. Keep it False
    # until the complete post-auth role witness AND logout control are observed.
    probe.authenticated = False
    probe.native_auth_uncertain = True
    try:
        probe.tap('حسابي', seek=False)
        rows = probe.nodes()
        need(not (_visible_names(rows) & AUTH_LABELS), 'fresh_guest_account_gate_required')
        need(bool(probe.matching(rows, 'تسجيل الدخول أو إنشاء حساب')) and
             not probe.matching(rows, 'تسجيل الخروج'), 'fresh_guest_account_gate_required')
        probe.tap('تسجيل الدخول أو إنشاء حساب', seek=False)
        probe.wait('مرحبًا بعودتك')
        phone, otp = memory.resolve(role)
        probe.set('رقم واتساب', phone)
        probe.auth_attempted = True
        probe.report['native_auth_attempted'] = True
        probe.tap('إرسال رمز واتساب', seek=False)
        probe.wait('تأكيد والدخول', seconds=60)
        probe.set('رمز التحقق', otp)
        del phone, otp
        probe.tap('تأكيد والدخول', seek=False)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            rows = probe.nodes()
            names = _visible_names(rows)
            if ROLE_NAV[role] <= names and not (names & AUTH_LABELS):
                # Regular and guest share navigation. Logout is indispensable
                # post-auth evidence; navigation alone cannot prove login.
                probe.tap('حسابي', seek=False)
                probe.wait('تسجيل الخروج', seconds=60)
                names = _visible_names(probe.nodes())
                need('تسجيل الخروج' in names and
                     'تسجيل الدخول أو إنشاء حساب' not in names and
                     not (names & AUTH_LABELS), 'post_auth_account_not_observed')
                probe.authenticated = True
                probe.active_native_role = role
                probe.native_auth_uncertain = False
                probe.report['native_auth_executed'] = True
                receipt.update(status='PASS_WITHIN_AUTH_UI_SCOPE',
                               role_navigation_observed=True,
                               post_auth_logout_control_observed=True)
                break
            time.sleep(.7)
        else:
            raise RouteBlocked('expected_native_role_not_observed')
    except Exception as error:
        receipt['reason'] = _safe_role_failure(error)
        # Keep count-only handling after uncertain authentication. A parent must
        # explicitly recover/logout before attempting another actor.
        probe.authenticated = False
        probe.active_native_role = None
        probe.native_auth_uncertain = True
    receipt['auth_input_operations_delivered'] = max(
        0, probe.report.get('auth_input_operations_delivered', 0) - start_count)
    probe.report.setdefault('native_role_auth', []).append(receipt)
    probe.save()
    return receipt


def native_logout_role(probe):
    """Normal native UI only. Guest UI is not server-token-revocation proof."""
    need(probe.recorder is None, 'recording_must_stop_before_auth')
    role = getattr(probe, 'active_native_role', None)
    need(role in KNOWN_ROLES and probe.authenticated, 'known_native_actor_required')
    # Logout navigation and account text also remain count-only, with no hashes.
    probe.authenticated = False
    probe.native_auth_uncertain = True
    receipt = {'role': role, 'status': 'BLOCKED', 'normal_native_ui': True,
               'authentication_captures': False, 'auth_hashes_recorded': False,
               'server_token_revocation_verified': False}
    try:
        if role == 'broker':
            # MyListings is a standalone route without the Account footer.
            # Relaunch its already retained session, as in C1 logout; never
            # reset storage, guess Back navigation, or enter credentials.
            if probe.adapter is not None:
                probe.stop_session('C2_broker_logout_retained_home')
            probe.adb('shell', 'am', 'force-stop', APP)
            probe.startup()
            names = _visible_app_names(probe.nodes())
            need(ROLE_NAV['broker'] <= names and not names & AUTH_LABELS
                 and 'تسجيل الدخول أو إنشاء حساب' not in names,
                 'retained_broker_home_not_observed')
            receipt['retained_broker_home_observed'] = True
        elif role == 'support':
            names = _visible_app_names(probe.nodes())
            if not ROLE_NAV['support'] <= names:
                # The task opens this queue with context.push; its standard
                # AppBar Back is Arabic Material's observed named control.
                need({'تحقيق الإعلانات', 'طلبات التحقيق', 'رجوع'} <= names
                     and not names & AUTH_LABELS,
                     'support_queue_before_logout_required')
                probe.tap('رجوع', seek=False)
                probe.wait('لوحة الدعم', seconds=15)
                names = _visible_app_names(probe.nodes())
            need(ROLE_NAV['support'] <= names and not names & AUTH_LABELS
                 and 'تسجيل الدخول أو إنشاء حساب' not in names,
                 'support_shell_before_logout_required')
            receipt['support_shell_before_logout_observed'] = True
        probe.tap('حسابي', seek=False)
        probe.tap('تسجيل الخروج')
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            names = _visible_app_names(probe.nodes())
            if (GUEST_HOME_NAV <= names and names & GUEST_HOME_ANCHORS
                    and 'تسجيل الخروج' not in names and not names & AUTH_LABELS
                    and not names & {'عملي', 'العملاء', 'لوحة الدعم', 'الوارد', 'مهامي'}):
                break
            time.sleep(.7)
        else:
            raise RouteBlocked('native_guest_marketplace_not_observed')
        # Exactly one post-logout Account tap, after actual Home.
        probe.tap('حسابي', seek=False)
        probe.wait('تسجيل الدخول أو إنشاء حساب', seconds=45)
        names = _visible_app_names(probe.nodes())
        need('تسجيل الدخول أو إنشاء حساب' in names and
             'تسجيل الخروج' not in names and not (names & AUTH_LABELS),
             'native_guest_logout_state_not_observed')
        probe.active_native_role = None
        probe.native_auth_uncertain = False
        receipt.update(status='PASS_WITHIN_LOGOUT_UI_SCOPE', guest_gate_observed=True,
                       guest_marketplace_home_observed=True, post_logout_account_tap_delivered=True)
    except Exception as error:
        receipt['reason'] = _safe_role_failure(error)
    probe.report.setdefault('native_role_logout', []).append(receipt)
    probe.save()
    return receipt


def _bounds(row):
    value = row.get('bounds')
    need(isinstance(value, list) and len(value) == 4 and
         all(type(n) is int for n in value), 'card_bounds_invalid')
    a, b, c, d = value
    need(c - a > 8 and d - b > 8, 'card_bounds_invalid')
    return value


def _contains(outer, inner):
    return outer[0] <= inner[0] < inner[2] <= outer[2] and \
           outer[1] <= inner[1] < inner[3] <= outer[3]


def select_exact_card_scope(rows, expected_title, tag, action_label, *, visual_review):
    """No inferred ancestor selection: a fresh actual visual card review is required.

    The parent supplies the one observed card, exact title and button paths after
    viewing the actual frame. This function must never climb to a shared wrapper.
    Java then rechecks the entire chosen scope in the actual input call.
    """
    need(action_label in ACTION_LABELS, 'card_action_not_allowlisted')
    need(isinstance(tag, str) and re.fullmatch(r'AQER-C[124]-[a-f0-9]{12}', tag),
         'original_fixture_tag_required')
    need(isinstance(expected_title, str) and 4 <= len(expected_title) <= 240 and
         re.search(r'(?<![A-Za-z0-9-])' + re.escape(tag) + r'(?![A-Za-z0-9-])',
                   expected_title) is not None, 'exact_tagged_title_required')
    eligible = [row for row in rows if row.get('package') == APP and
                row.get('visible') and row.get('enabled')]
    by_path = {}
    for row in eligible:
        path, witness = row.get('path'), row.get('witness')
        need(isinstance(path, str) and re.fullmatch(r'0(?:\.[0-9]{1,4}){0,40}', path) and
             isinstance(witness, str) and re.fullmatch('[a-f0-9]{64}', witness),
             'card_fresh_node_identity_invalid')
        need(path not in by_path, 'card_duplicate_node_path')
        by_path[path] = row
    need('0' in by_path, 'card_root_bounds_required')
    screen = _bounds(by_path['0'])
    need(isinstance(visual_review, dict) and
         visual_review.get('kind') == 'fresh_visual_exact_tagged_card_and_button' and
         visual_review.get('single_visual_card') is True and
         isinstance(visual_review.get('frame_sha256'), str) and
         re.fullmatch('[a-f0-9]{64}', visual_review['frame_sha256']) and
         visual_review.get('root_witness') == by_path['0']['witness'],
         'fresh_visual_card_review_required')
    need(fresh_remote_review(visual_review),
         'fresh_visual_card_review_required')
    titles = [row for row in eligible if expected_title in row_labels(row)]
    # A merged semantic parent repeating its child's title is not another card.
    leaves = [row for row in titles if not any(
        other['path'].startswith(row['path'] + '.') for other in titles)]
    need(len(leaves) == 1, 'exact_tagged_card_title_not_unique')
    title = leaves[0]
    need(visual_review.get('title_path') == title['path'] and
         visual_review.get('title_witness') == title['witness'],
         'reviewed_title_changed')
    title_bounds = _bounds(title)
    need(_contains(screen, title_bounds), 'tagged_title_outside_screen')
    card = by_path.get(visual_review.get('card_path'))
    need(card is not None and card['path'] != '0' and
         visual_review.get('card_witness') == card['witness'] and
         title['path'].startswith(card['path'] + '.') and not card.get('scrollable'),
         'reviewed_single_card_boundary_required')
    card_bounds = _bounds(card)
    need(_contains(screen, card_bounds) and _contains(card_bounds, title_bounds),
         'reviewed_card_bounds_invalid')
    width, height = card_bounds[2] - card_bounds[0], card_bounds[3] - card_bounds[1]
    sw, sh = screen[2] - screen[0], screen[3] - screen[1]
    need(height * 100 < sh * 85 and width * height * 100 < sw * sh * 90,
         'reviewed_single_card_boundary_required')
    descendants = [row for row in eligible if row['path'].startswith(card['path'] + '.')]
    need(not any(row.get('scrollable') for row in descendants),
         'reviewed_single_card_boundary_required')
    controls = [row for row in descendants if row.get('clickable') or
                row.get('class') == 'android.widget.Button']
    limit = 1 if action_label == 'متابعة التحقيق' else 2
    need(1 <= len(controls) <= limit and all(
        row_labels(row) & CARD_CONTROLS[action_label] for row in controls),
        'reviewed_single_card_controls_invalid')
    actions = [row for row in controls if action_label in row_labels(row)]
    need(len(actions) == 1, 'exact_tagged_card_action_not_unique')
    action = actions[0]
    need(visual_review.get('button_path') == action['path'] and
         visual_review.get('button_witness') == action['witness'] and
         _contains(card_bounds, _bounds(action)), 'reviewed_card_button_changed')
    return {'node_path': action['path'], 'node_witness': action['witness'],
            'card_path': card['path'], 'card_witness': card['witness'],
            'title_path': title['path'], 'title_witness': title['witness'],
            'visual_review_ack': 'fresh_visual_exact_tagged_card_and_button',
            'visual_frame_sha256': visual_review['frame_sha256'],
            'reviewed_root_witness': by_path['0']['witness'],
            'title_b64': base64.b64encode(expected_title.encode()).decode(),
            'tag_b64': base64.b64encode(tag.encode()).decode(),
            'action_b64': base64.b64encode(action_label.encode()).decode()}


def scoped_support_card_click(probe, expected_title, original_tag, action_label, *, visual_review):
    """No global tap fallback, no automatic retry, no acceptance from delivery."""
    need(probe.authenticated and getattr(probe, 'active_native_role', None) == 'support',
         'normal_support_actor_required')
    need(probe.explicit_pointer_mode is True, 'explicit_pointer_mode_required')
    scope = select_exact_card_scope(probe.nodes(), expected_title, original_tag,
                                    action_label, visual_review=visual_review)
    result = probe.instrument('account-card-pointer-click', **scope)
    need(result.get('card_scope_verified') == 'true' and
         result.get('native_pointer_used') == 'true' and
         result.get('native_pointer_events') == '2' and
         result.get('account_action_delivered') == 'true',
         'scoped_card_pointer_not_delivered')
    receipt = {'action': action_label, 'scoped_card_guard_verified': True,
               'native_pointer_events': 2, 'delivery_observed': True,
               'postcondition_review_required': True, 'claim_state_accepted': False}
    # Paths/title/witness hashes stay only in process memory, not the receipt.
    probe.report.setdefault('native_scoped_support_actions', []).append(receipt)
    probe.save()
    return receipt
