"""Strict remote Root-evidence codecs; no signatures or approvals are created.

Use only on the review payload already decrypted by the signed-command owner.
The original executor still validates the actual files, scene and attestations.
"""
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
import re

UTC = re.compile(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z')
SHA = re.compile(r'[a-f0-9]{64}\Z')
FRAME = re.compile(r'C1-[a-z0-9-]+\.png\Z')
DURATION = re.compile(r'(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,3})?\Z')
ROOT_KIND = 'ROOT_ACTUAL_FRAME_REVIEW'
C4_BASE = frozenset({'kind', 'phase', 'case', 'cursor', 'fixture_key', 'fixture_tag',
    'title', 'privacy_checked', 'manual_review_completed', 'frames', 'review_completed_utc'})
C4_EXTRA = {
    'C1_REVIEW': frozenset({'c1_accepted', 'monthly_rent_still_blank',
        'same_tagged_fixture_visually_verified', 'original_UUID_bound_by_existing_fixture_receipt'}),
    'AI_REVIEW': frozenset({'actual_ai_notice', 'literal_fallback_notice_visible',
        'all_selected_fields_and_copy_reviewed', 'copy_has_only_supplied_facts',
        'all_proposal_cards_visible_in_reviewed_frames', 'selected_fields',
        'verified_existing_draft_copy_facts'}),
    'APPLY_REVIEW': frozenset({'same_exact_tagged_title_and_apply_visually_verified',
        'approved_proposal_frames'}),
    'RESTORE_REVIEW': frozenset({'same_exact_saved_draft_visually_verified',
        'photo_visually_unchanged', 'applied_floor_unit_and_copy_visually_verified',
        'actual_restore_clip_reviewed', 'monthly_rent_still_blank', 'video'}),
}


class RemoteEvidenceError(RuntimeError):
    """Fixed diagnostics only; do not format review values or file contents."""


def need(ok, code):
    if not ok:
        raise RemoteEvidenceError(code) from None


def utc_now():
    return datetime.now(timezone.utc)


def parse_utc(value):
    need(type(value) is str and UTC.fullmatch(value) is not None, 'review_utc_format_invalid')
    try:
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        raise RemoteEvidenceError('review_utc_value_invalid') from None


def fresh_remote_review(record, *, now_utc=None):
    """Real Root UTC age, never a substituted runner monotonic timestamp.

    Signature/issued-time/expiry/context binding remains the owner grant's job.
    Every actual input must independently recheck that active signed grant.
    """
    if type(record) is not dict or 'reviewed_monotonic' in record:
        return False
    current = utc_now() if now_utc is None else now_utc
    if not (type(current) is datetime and current.tzinfo is not None
            and current.utcoffset() == timedelta(0)):
        return False
    try:
        reviewed = parse_utc(record.get('review_completed_utc'))
    except RemoteEvidenceError:
        return False
    age = (current - reviewed).total_seconds()
    return -5 <= age <= 120


def reject_duplicate_pairs(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'remote_review_duplicate_key')
        result[key] = value
    return result


def frame_map(entries):
    """Decode sorted filename/value records without filename-shaped JSON keys."""
    need(type(entries) is list and 0 < len(entries) <= 32, 'frame_list_required')
    names, result = [], {}
    for entry in entries:
        need(type(entry) is dict and set(entry) == {'file', 'sha256'}, 'frame_entry_schema_invalid')
        name, digest = entry['file'], entry['sha256']
        need(type(name) is str and FRAME.fullmatch(name) is not None
             and type(digest) is str and SHA.fullmatch(digest) is not None,
             'frame_entry_value_invalid')
        need(name not in result, 'frame_entry_duplicate')
        names.append(name)
        result[name] = digest
    need(names == sorted(names), 'frame_entries_not_canonical_order')
    return result


def frames_wire(frames):
    need(type(frames) is dict and frames, 'held_frame_map_required')
    result = [{'file': name, 'sha256': digest} for name, digest in sorted(frames.items())]
    frame_map(result)
    return result


def video_wire(actual):
    """Faithfully encode an existing validated float/int duration as a string."""
    need(type(actual) is dict and set(actual) == {'file', 'sha256', 'duration_s'},
         'held_video_tuple_required')
    need(type(actual['duration_s']) in (int, float), 'held_video_duration_invalid')
    value = str(actual['duration_s'])
    need(DURATION.fullmatch(value) is not None, 'held_video_duration_precision_invalid')
    return {'file': actual['file'], 'sha256': actual['sha256'], 'duration_s_decimal': value}


def video_tuple(wire, actual):
    need(type(wire) is dict and set(wire) == {'file', 'sha256', 'duration_s_decimal'},
         'video_wire_schema_invalid')
    need(type(actual) is dict and set(actual) == {'file', 'sha256', 'duration_s'},
         'held_video_tuple_required')
    need(wire['file'] == actual['file'] == 'C1-c4-restored-facts.webm'
         and type(wire['sha256']) is str and SHA.fullmatch(wire['sha256']) is not None
         and wire['sha256'] == actual['sha256'], 'video_identity_mismatch')
    text = wire['duration_s_decimal']
    need(type(text) is str and DURATION.fullmatch(text) is not None
         and type(actual['duration_s']) in (int, float), 'video_duration_schema_invalid')
    try:
        duration, observed = Decimal(text), Decimal(str(actual['duration_s']))
    except InvalidOperation:
        raise RemoteEvidenceError('video_duration_invalid') from None
    need(duration.is_finite() and observed.is_finite() and 0 < duration <= 125
         and duration == observed, 'video_duration_mismatch')
    # This conversion restores the already observed local tuple value. It does
    # not round, extend a clip, transcode media, or invent a measured duration.
    return {'file': wire['file'], 'sha256': wire['sha256'], 'duration_s': actual['duration_s']}


def normalize_c4_review(record, *, expected_cursor, expected_frames, actual_video=None):
    need(type(record) is dict and expected_cursor in C4_EXTRA,
         'c4_remote_review_context_invalid')
    need(set(record) == C4_BASE | C4_EXTRA[expected_cursor], 'c4_remote_review_keys_invalid')
    need(record.get('kind') == ROOT_KIND and record.get('phase') == 'C4'
         and record.get('case') == 'C4-native-saved-draft'
         and record.get('cursor') == expected_cursor and fresh_remote_review(record),
         'c4_remote_review_stale_or_context_invalid')
    need(type(record.get('privacy_checked')) is bool
         and type(record.get('manual_review_completed')) is bool, 'c4_review_flag_type_invalid')
    result = copy.deepcopy(record)
    result['frames'] = frame_map(record['frames'])
    need(type(expected_frames) is dict and result['frames'] == expected_frames,
         'c4_current_frame_binding_mismatch')
    if expected_cursor == 'AI_REVIEW':
        existing = record['verified_existing_draft_copy_facts']
        need(type(existing) is dict and set(existing) <= {'address','governorate','district','street','city'}
             and all(type(v) is str and 0 < len(v) <= 240 for v in existing.values()),
             'c4_verified_existing_copy_facts_invalid')
    if expected_cursor == 'APPLY_REVIEW':
        result['approved_proposal_frames'] = frame_map(record['approved_proposal_frames'])
    if expected_cursor == 'RESTORE_REVIEW':
        result['video'] = video_tuple(record['video'], actual_video)
    return result
