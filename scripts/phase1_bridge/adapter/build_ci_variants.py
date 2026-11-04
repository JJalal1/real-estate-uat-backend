"""Build remote-UTC plus observed guest-Home logout variants from pinned sources.

This is a source preparation command, not a runner. It never accesses a device,
credentials, API or current aqer files. Original executor files stay untouched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


PINS = {
    'ROOT_C4_EXECUTOR/phase_extensions.py': 'ae28e3fe2f5cb331cdfd40a8c7bc926ca783f91a69359c5b170770cd4f0ad333',
    'ROOT_C2_EXECUTOR_V2/phase_extensions.py': '27a567dbb175140c50a0de705385e56ea5ab4817714d165f06b94cfb8d2159b8',
    'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py': '612d92003702e39cc071815bb4b0ace564eaaeed679bc44cb693defec1e3d79f',
    'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py': '6ad2d841bddb9458752ebd4a79414a7c8c7f4f5d6cab43ac74d7b6c97d8eac44',
    'C2_SOURCE_PROPOSAL/c2_native_roles.py': '789a790fa1bbced95653cf0ecf66190420b814caf15c73189f5b783c5efc183c',
    'promoted_cleanup.py': '4a7752b29cc8b1417e5d82ab94c9113e3687b6b6e37ba995847e387f5d262f67',
}
CAPTURE_PIN = '2ec10b2659ea3f073c47d02c1800cd49b35b58e51ce8430517af74a1ecadcafa'
PREVIOUS_ROLES_PIN = 'cfec7b46f3d37b68c6432893435cd37c970b6713561c644ca6adbc562d635b6c'


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError('exact_variant_patch_precondition_failed')
    return text.replace(before, after, 1)


def transform(name, text):
    if name in {'ROOT_C4_EXECUTOR/phase_extensions.py', 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py'}:
        alphabet = ''.join(str(value) for value in range(10)) * 2
        text = replace_once(text, repr(alphabet),
                            "(''.join(str(value) for value in range(10)) * 2)")
    if name == 'ROOT_C4_EXECUTOR/phase_extensions.py':
        text = replace_once(text, 'import uuid\n',
                            'import uuid\nfrom ci_remote_evidence import normalize_c4_review, reject_duplicate_pairs\n')
        text = replace_once(text, '        data = json.loads(path.read_text())',
            "        data = normalize_c4_review(json.loads(path.read_text(), object_pairs_hook=reject_duplicate_pairs),\n"
            "            expected_cursor=cursor, expected_frames=frames, actual_video=state.get('restore_video'))")
        text = replace_once(text, "state['helper_or_recorder_release_unconfirmed'] = True",
                            "state['admission_or_recorder_stop_unconfirmed'] = True")
        text = replace_once(text, "data.get('copy_has_only_explicit_brief_facts') is True",
                            "data.get('copy_has_only_supplied_facts') is True")
        text = replace_once(text, "    selected = data.get('selected_fields')",
            "    existing = data.get('verified_existing_draft_copy_facts')\n"
            "    need(type(existing) is dict and set(existing) <= {'address','governorate','district','street','city'}\n"
            "         and all(type(v) is str and 0 < len(v) <= 240 for v in existing.values()),\n"
            "         'c4_verified_existing_copy_facts_required')\n"
            "    selected = data.get('selected_fields')")
        text = replace_once(text, "    probe.set('صف العقار', BRIEF)\n    probe.tap('جهّز الإعلان')",
            "    probe.set('صف العقار', BRIEF)\n"
            "    probe.require_value('صف العقار', BRIEF)\n"
            "    state['prepared_brief_scene'] = ai_scene(probe)\n"
            "    # End before the network request. Request/response and actual proposal\n"
            "    # capture receive a separate original120s grant, without refreshing this one.\n"
            "    return finish(probe, state, 'REQUEST')\n\n\n"
            "def prepared_brief_context(probe, state):\n"
            "    ensure_session(probe)\n"
            "    observed = ai_scene(probe)\n"
            "    need(observed == state.get('prepared_brief_scene'), 'c4_prepared_brief_scene_changed')\n"
            "    probe.require_value('صف العقار', BRIEF)\n"
            "    return observed\n\n\n"
            "def request_prepared(probe, state):\n"
            "    reserve(probe, state, 'prepare_request')\n"
            "    prepared_brief_context(probe, state)\n"
            "    probe.tap('جهّز الإعلان')")
        text = replace_once(text,
            "            return prepare(probe, state)\n        if cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:",
            "            return prepare(probe, state)\n        if cursor == 'REQUEST':\n"
            "            return request_prepared(probe, state)\n"
            "        if cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:")
        text = replace_once(text, '    # End before the network request. Request/response and actual proposal\n    # capture receive a separate original120s grant, without refreshing this one.', '    # End before the network request; each subsequent segment uses its own\n    # fresh signed authority without refreshing an existing grant.')
        text = replace_once(text, '    probe.wait(APPLY, seconds=120)\n    # Notice must be observed literally on the real native sheet.', "    probe.wait(APPLY, seconds=120)\n    # Preserve the actual response before any scrolling. This diagnostic is\n    # neither an AI-source assertion nor a visual acceptance decision.\n    state['response_ready_frames'] = ai_capture(probe, 'C1-c4-response-ready')\n    state['response_ready_scene'] = ai_scene(probe)\n    return finish(probe, state, 'RESPONSE_READY')\n\n\ndef seek_ai_notice(probe, state):\n    # Short overlapping physical swipes avoid skipping the small notice with\n    # full flings. Inspect the literal fallback too; never relabel it as AI.\n    directions = ('backward',) * 4 + ('forward',) * 8\n    diagnostic = {'observations': 0, 'short_scrolls_completed': 0,\n                  'ai_notice_seen': False, 'literal_fallback_seen': False}\n    state['notice_seek'] = diagnostic\n    for index in range(len(directions) + 1):\n        rows = [row for row in safe_rows(probe) if row.get('visible') is True]\n        diagnostic['observations'] += 1\n        diagnostic['ai_notice_seen'] = any(AI_NOTICE in names(row) for row in rows)\n        diagnostic['literal_fallback_seen'] = any(FALLBACK_NOTICE in names(row) for row in rows)\n        save(probe)\n        need(not diagnostic['literal_fallback_seen'], 'c4_literal_fallback_observed_no_ai_acceptance')\n        if diagnostic['ai_notice_seen']:\n            return\n        if index < len(directions):\n            probe.scroll(directions[index], short=True)\n            diagnostic['short_scrolls_completed'] += 1\n            save(probe)\n    need(False, 'c4_actual_ai_notice_not_observed_after_bounded_short_seek')\n\n\ndef collect_response(probe, state):\n    reserve(probe, state, 'collect_response')\n    ensure_session(probe)\n    need(ai_scene(probe) == state.get('response_ready_scene'), 'c4_response_ready_scene_changed')\n    # Notice must be observed literally on the real native sheet.")
        text = replace_once(text, '    probe.seek(AI_NOTICE)', '    seek_ai_notice(probe, state)')
        text = replace_once(text, "        if cursor == 'REQUEST':\n            return request_prepared(probe, state)\n", "        if cursor == 'REQUEST':\n            return request_prepared(probe, state)\n        if cursor == 'RESPONSE_READY':\n            return collect_response(probe, state)\n")
    elif name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, 'import time\n', 'import time\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text,
            "            type(review.get('reviewed_monotonic')) in (int, float) and\n"
            "            0 <= time.monotonic() - review['reviewed_monotonic'] <= 120)",
            '            fresh_remote_review(review))')
        text = replace_once(text,
            "                 type(record.get('reviewed_monotonic')) in (int, float) and\n"
            "                 0 <= time.monotonic() - record['reviewed_monotonic'] <= 120,",
            '                 fresh_remote_review(record),')
    elif name == 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py':
        text = replace_once(text, 'import uuid\n', 'import uuid\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text, '*, native_role, auth_uncertain, now=None):',
                            '*, native_role, auth_uncertain, now_utc=None):')
        text = replace_once(text,
            "    observed = review.get('reviewed_monotonic')\n"
            '    now = time.monotonic() if now is None else now\n'
            '    need(type(observed) in (int, float) and 0 <= now - observed <= 120,\n',
            '    need(fresh_remote_review(review, now_utc=now_utc),\n')
    elif name == 'C2_SOURCE_PROPOSAL/c2_native_roles.py':
        text = replace_once(text, 'import time\n', 'import time\nfrom ci_remote_evidence import fresh_remote_review\n')
        # V2 does not call the unbuilt atomic scoped-card function, but keeping
        # its unused selector on the same UTC schema avoids a legacy time path.
        text = replace_once(text,
            "    reviewed_at = visual_review.get('reviewed_monotonic')\n"
            '    need(type(reviewed_at) in (int, float) and\n'
            '         0 <= time.monotonic() - reviewed_at <= 120,\n',
            '    need(fresh_remote_review(visual_review),\n')
        # AuthController clears the account scope; AppShell resets index0 to
        # GuestMarketplace. Regular/guest share footer labels, so the footer
        # alone cannot prove this actual Home transition.
        text = replace_once(text, "\nAUTH_LABELS = frozenset(",
            "\nGUEST_HOME_ANCHORS = frozenset({'ابحث عن عقار أو منطقة…', 'ماذا تبحث عنه؟'})\n"
            "GUEST_HOME_NAV = frozenset({'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'})\n"
            "\nAUTH_LABELS = frozenset(")
        text = replace_once(text, '\ndef _safe_role_failure(error):',
            "\ndef _visible_app_names(rows):\n"
            "    return _visible_names([row for row in rows if row.get('package') == APP\n"
            "                           and row.get('visible') is True])\n\n"
            "\ndef _safe_role_failure(error):")
        text = replace_once(text,
            "'expected_native_role_not_observed', 'native_guest_logout_state_not_observed'}",
            "'expected_native_role_not_observed', 'native_guest_logout_state_not_observed',\n"
            "            'native_guest_marketplace_not_observed'}")
        text = replace_once(text,
            "        probe.wait('تسجيل الدخول أو إنشاء حساب', seconds=90)\n"
            "        names = _visible_names(probe.nodes())\n",
            "        deadline = time.monotonic() + 90\n"
            "        while time.monotonic() < deadline:\n"
            "            names = _visible_app_names(probe.nodes())\n"
            "            if (GUEST_HOME_NAV <= names and names & GUEST_HOME_ANCHORS\n"
            "                    and 'تسجيل الخروج' not in names and not names & AUTH_LABELS\n"
            "                    and not names & {'عملي', 'العملاء', 'لوحة الدعم', 'الوارد', 'مهامي'}):\n"
            "                break\n"
            "            time.sleep(.7)\n"
            "        else:\n"
            "            raise RouteBlocked('native_guest_marketplace_not_observed')\n"
            "        # Exactly one post-logout Account tap, after actual Home.\n"
            "        probe.tap('حسابي', seek=False)\n"
            "        probe.wait('تسجيل الدخول أو إنشاء حساب', seconds=45)\n"
            "        names = _visible_app_names(probe.nodes())\n")
        text = replace_once(text,
            "receipt.update(status='PASS_WITHIN_LOGOUT_UI_SCOPE', guest_gate_observed=True)",
            "receipt.update(status='PASS_WITHIN_LOGOUT_UI_SCOPE', guest_gate_observed=True,\n"
            "                       guest_marketplace_home_observed=True, post_logout_account_tap_delivered=True)")
    elif name == 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py':
        text = replace_once(text, 'import tempfile\n', 'import tempfile\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text, "BASE = Path('/workspace/scratch/e1739659bfa7/native-fixture')",
                            'BASE = Path(__file__).resolve().parents[1]')
        text = replace_once(text, "'frame_sha256', 'reviewed_monotonic', 'root_witness'",
                            "'frame_sha256', 'review_completed_utc', 'root_witness'")
        text = replace_once(text, '\n\nclass Hold(RuntimeError):',
            "\nC1_KEYS = C1_KEYS | {'review_completed_utc'}\n"
            "C4_KEYS = C4_KEYS | {'review_completed_utc'}\n\n\nclass Hold(RuntimeError):")
        text = replace_once(text,
            "    need(isinstance(data, dict) and set(data) <= allowed and\n",
            "    need(fresh_remote_review(data), 'root_review_utc_expired')\n"
            "    need(isinstance(data, dict) and set(data) <= allowed and\n")
        text = replace_once(text, "            receipt['helper_released_at_boundary'] = True",
            "            receipt['oneshot_admission_closed_at_boundary'] = True\n"
            "            receipt['persistent_helper_release_claimed'] = False\n"
            "            receipt['oneshot_admission'] = probe.admission_metrics")
        text = text.replace('_root_extension_dispatch_v2_helper_failed', '_root_extension_dispatch_v2_admission_failed')
        text = replace_once(text, 'previous_helper_release_failure_requires_root_review',
                            'previous_admission_close_failure_requires_root_review')
        text = replace_once(text, 'HELD_HELPER_RELEASE_UNCONFIRMED', 'HELD_ADMISSION_CLOSE_UNCONFIRMED')
        text = replace_once(text, 'reconciles this helper lease;', 'disposes this uncertain runtime;')
        text = replace_once(text, "        need(phase in ('C4', 'C2'), 'extension_phase_refused')",
            "        need(phase in ('C4', 'C2'), 'extension_phase_refused')\n"
            "        need(probe.require_phase_scope(phase) is True, 'active_root_phase_grant_required')")
    if name != 'promoted_cleanup.py' and 'reviewed_monotonic' in text:
        raise RuntimeError('legacy_review_clock_remains')
    return text


def build(source_root, capture_source, destination):
    source_root, capture_source, destination = map(Path, (source_root, capture_source, destination))
    if destination.exists():
        raise RuntimeError('fresh_variant_destination_required')
    outputs, originals = {}, {}
    for name, wanted in PINS.items():
        path = source_root / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('pinned_variant_source_unavailable')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != wanted:
            raise RuntimeError('pinned_variant_source_mismatch')
        originals[name] = data
        outputs[name] = transform(name, data.decode()).encode()
    capture = capture_source.read_bytes()
    if capture_source.is_symlink() or hashlib.sha256(capture).hexdigest() != CAPTURE_PIN:
        raise RuntimeError('pinned_capture_source_mismatch')
    outputs['runtime/host_console_capture.py'] = capture
    outputs['ci_remote_evidence.py'] = Path(__file__).with_name('ci_remote_evidence.py').read_bytes()
    destination.mkdir(mode=0o700, parents=True)
    manifest = {}
    for name, data in outputs.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                          'original_sha256': PINS.get(name, CAPTURE_PIN if name.startswith('runtime/') else None)}
        if name in {'ROOT_C4_EXECUTOR/phase_extensions.py', 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py'}:
            manifest[name]['delta'] = 'equivalent_generated_digit_translation_alphabet'
        if name == 'ROOT_C4_EXECUTOR/phase_extensions.py':
            manifest[name]['delta'] += '; separate_exact_brief_REQUEST_checkpoint_before_AI_request; copy_grounded_in_message_and_verified_same_draft_facts; actual_response_snapshot_boundary_before_bounded_short_notice_seek'
        if name == 'C2_SOURCE_PROPOSAL/c2_native_roles.py':
            manifest[name]['previous_utc_variant_sha256'] = PREVIOUS_ROLES_PIN
            manifest[name]['delta'] = 'one_logout_observed_guest_home_then_one_account_guest_gate'
    # Check the inputs again so this preparation cannot quietly alter originals.
    for name, data in originals.items():
        if (source_root / name).read_bytes() != data:
            raise RuntimeError('original_variant_source_changed')
    (destination / 'VARIANT_MANIFEST.json').write_text(json.dumps({
        'scope': 'Offline remote-UTC plus guest-Home logout variant; no native acceptance',
        'source_files_unchanged': True, 'manifest': manifest}, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', required=True)
    parser.add_argument('--capture-source', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source_root, args.capture_source, args.output), indent=2))
