#!/usr/bin/env python3
"""One reviewed Run78 fixture recovery; import is offline and never executes.

Credentials come only from the existing Actions secret and remain in RAM. The
original per-row baseline is reconstructed only after both aggregate hashes
match the verified historical report. No arbitrary fixture or destination input.
"""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / 'scripts/phase1_bridge/adapter'
sys.path.insert(0, str(ADAPTER))
sys.path.insert(0, str(ROOT / 'scripts/phase1_bridge/controller'))
from bounded_api import DeadlineTransport
from phase1_native_account_readiness import validate_access, SECRET_NAME


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


c2 = _load('_run78_cleanup_c2', ADAPTER / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
helper = c2.cleanup_module
KEY = '3e98c04c-8675-4856-8406-f8c164f2b86f'
TAG = 'AQER-C1-0d148f1402cc'
PROPERTY_ID = 97
EXACT_TITLE = 'اختبار استعادة المسودة ' + TAG
EXACT_DRAFT_REVISION = 24
BRANCH = 'refs/heads/work/phase1-run78-cleanup-20261105'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
HELPER_SHA256 = 'ec54c936f226b9c3cb5a27e914eced199ff6ee5a59b91a8dcfc14997a40f2a9b'
EXPECTED_BASELINE = {
    'properties': {'count': 25, 'sha256': '0abc8495cae3cdcabe4f9d00c4e732e7c1e63140175646008e8fe9ded1995cd6'},
    'drafts': {'count': 7, 'sha256': '8f10dc0a80fae8813d68c4b88d36e279a25353bd40071cd198c786deb96c5051'},
}
# Root-reviewed facts from the verified decrypted original run, not a new
# bootstrap claim. The historical full report remains private.
PROVENANCE = {
    'ci_run_id': '41980997096',
    'source_commit': 'b955b6a7abe7af19f35263c2164e87bd7b43febf',
    'full_report_sha256': '36f7c01febb2abee4314dbda47ab8eb1eefc5294dd3edf5cf46f9b416e00565d',
    'original_bootstrap_status': 'PASS', 'original_bootstrap_http': 200,
    'original_fixture_created': True, 'original_bootstrap_only_title_label': True,
    'original_actor_id': 28, 'original_account_type': 'broker',
    'original_vm_exit_code': 0, 'original_owned_process_group_absent': True,
    'original_vm_ended_utc': '2026-11-05T07:04:00.034156+00:00',
}


class CleanupRefused(RuntimeError):
    pass


def need(condition, code):
    if not condition:
        raise CleanupRefused(code) from None


def summary(snapshot):
    return {kind: {'count': len(rows), 'sha256': helper.digest(rows)}
            for kind, rows in snapshot.items()}


def read_snapshot(api):
    snapshot, originals = {}, {}
    for kind, route in (('properties', '/properties/mine/list'), ('drafts', '/listing-editor-drafts')):
        digests, rows = {}, {}
        for page in range(1, 21):
            code, body = api('GET', route + '?per_page=50&page=' + str(page))
            data = body.get('data')
            need(code == 200 and type(data) is list and len(data) <= 50, 'snapshot_read_unconfirmed')
            for row in data:
                need(type(row) is dict, 'snapshot_row_invalid')
                if kind == 'properties':
                    need(helper.positive_id(row.get('id')), 'snapshot_identity_invalid')
                    identity, projection = str(row['id']), helper.property_projection(row)
                else:
                    need(helper.canonical_uuid(row.get('key')), 'snapshot_identity_invalid')
                    identity, projection = row['key'], helper.draft_projection(row)
                need(identity not in rows, 'snapshot_duplicate_identity')
                rows[identity], digests[identity] = row, helper.digest(projection)
            last = body.get('meta', {}).get('last_page', 1)
            need(type(last) is int and page <= last <= 20, 'snapshot_pagination_invalid')
            if page == last:
                break
        snapshot[kind], originals[kind] = digests, rows
    return snapshot, originals


def reconstruct_baseline(snapshot, rows):
    """No baseline is adopted until the historical aggregate equality holds."""
    need(str(PROPERTY_ID) in snapshot['properties'] and KEY in snapshot['drafts'],
         'exact_fixture_pair_must_still_exist')
    draft, owned = rows['drafts'][KEY], rows['properties'][str(PROPERTY_ID)]
    title = draft.get('payload', {}).get('fields', {}).get('title')
    need(draft.get('key') == KEY and type(draft.get('property_id')) is int and
         draft['property_id'] == PROPERTY_ID and owned.get('id') == PROPERTY_ID and
         title == EXACT_TITLE and owned.get('title') == EXACT_TITLE and
         type(draft.get('revision')) is int and draft['revision'] == EXACT_DRAFT_REVISION,
         'exact_original_pair_identity_required')
    baseline = copy.deepcopy(snapshot)
    del baseline['properties'][str(PROPERTY_ID)]
    del baseline['drafts'][KEY]
    need(summary(baseline) == EXPECTED_BASELINE, 'historical_baseline_aggregate_mismatch')
    return baseline


def cleanup_authenticated(api, receipt):
    receipt['stage'] = 'baseline_reconstruction'
    snapshot, rows = read_snapshot(api)
    baseline = reconstruct_baseline(snapshot, rows)
    receipt.update(baseline_reconstructed_from_verified_aggregate=True,
                   baseline_before=summary(baseline), current_fixture_pair_observed=True)
    # These bootstrap facts are explicitly inherited from PROVENANCE; no new
    # record, title, photo, submission or financial term is ever created here.
    state = {'actor_id': PROVENANCE['original_actor_id'], 'key': KEY, 'tag': TAG,
        'creation_request_sent': PROVENANCE['original_bootstrap_http'] == 200,
        'created_confirmed': PROVENANCE['original_fixture_created'],
        'bootstrap_only_title_label': PROVENANCE['original_bootstrap_only_title_label'],
        'baseline': baseline}
    cleaner = helper.PromotedFixtureCleanup(api, state)
    receipt['stage'] = 'exact_pair_pin'
    receipt['pin'] = cleaner.pin_candidate(native_writers_stopped=True)
    need(receipt['pin'].get('status') == 'READY' and receipt['pin'].get('property_id') == PROPERTY_ID,
         'exact_pair_pin_not_ready')
    receipt['stage'] = 'property_then_draft_cleanup'
    receipt['cleanup'] = cleaner.cleanup(native_writers_stopped=True)
    need(receipt['cleanup'].get('status') == 'PASS', 'fixture_cleanup_not_confirmed')
    receipt['stage'] = 'final_baseline_readback'
    after, _ = read_snapshot(api)
    need(after == baseline and summary(after) == EXPECTED_BASELINE, 'historical_baseline_not_restored')
    receipt['baseline_after'] = summary(after)
    return True


def run_cleanup(access, request, *, source_commit):
    receipt = {'scope':'one reviewed Run78 fixture cleanup via normal broker API',
        'status':'BLOCKED','stage':'normal_broker_session','source_commit':source_commit,
        'fixture_key':KEY,'fixture_tag':TAG,'property_id':PROPERTY_ID,'actor_id':28,
        'historical_provenance':copy.deepcopy(PROVENANCE),
        'baseline_reconstructed_from_verified_aggregate':False,
        'native_acceptance_claimed':False,'phase1_accepted':False,
        'credentials_persisted':False,'automatic_retry_allowed':False,
        'started_utc':datetime.now(timezone.utc).isoformat()}
    memory = c2.roles.KnownRoleMemory(access)
    private_values = set()
    memory.add_redactions_to(private_values)
    session = c2.NormalOwnerSession(request, memory, private_values)
    try:
        session.run(lambda api: cleanup_authenticated(api, receipt))
        receipt.update(status='PASS',stage='complete')
    except Exception:
        # Helper receipts already contain fixed condition codes. Never emit an
        # arbitrary exception, request/response body, token, phone or trace.
        receipt['reason'] = 'normal_session_or_exact_fixture_cleanup_unconfirmed'
    finally:
        receipt.update(logout_http_200=session.logout_200, revoked_token_me_http_401=session.me_401,
                       ended_utc=datetime.now(timezone.utc).isoformat())
        memory.clear()
    encoded = json.dumps(receipt, ensure_ascii=False, sort_keys=True)
    need(not any(value and value in encoded for value in private_values), 'receipt_private_value_refused')
    private_values.clear()
    return receipt


def bounded_request():
    started = time.monotonic()
    work = DeadlineTransport(deadline_getter=lambda:started+300)
    revoke = DeadlineTransport(deadline_getter=lambda:started+420)
    revoking = False
    deletes = set()
    def request(method, path, body=None, token=None):
        nonlocal revoking
        if method == 'POST' and path == '/auth/logout': revoking = True
        if revoking:
            need((method,path) in {('POST','/auth/logout'),('GET','/auth/me')}, 'revocation_only_after_work')
            return revoke(method,path,body,token)
        if method == 'DELETE':
            need(path in {'/properties/97','/listing-editor-drafts/'+KEY} and path not in deletes,
                 'exact_delete_once_only')
            deletes.add(path)  # Reserve before transport; unknown outcomes cannot retry.
        elif method == 'POST':
            need(path in {'/auth/whatsapp/start','/auth/whatsapp/verify'}, 'only_normal_login_post_allowed')
        else:
            need(method == 'GET' and (path in {'/auth/me','/properties/97','/listing-editor-drafts/'+KEY} or
                 re.fullmatch(r'/(?:properties/mine/list|listing-editor-drafts)\?per_page=50&page=(?:[1-9]|1[0-9]|20)',path) or
                 re.fullmatch(r'/property-media/[1-9][0-9]{0,18}',path)), 'fixed_cleanup_read_routes_only')
        return work(method,path,body,token)
    return request


def context_valid(env):
    return (env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
        env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and env.get('GITHUB_RUN_ATTEMPT') == '1' and
        re.fullmatch('[a-f0-9]{40}',env.get('GITHUB_SHA','')) is not None and env.get('UAT_API_BASE_URL') == API)


def main():
    raw = os.environ.pop(SECRET_NAME, None)
    try:
        need(context_valid(os.environ), 'fixed_cleanup_ci_context_required')
        helper_path = ADAPTER / 'variants/promoted_cleanup.py'
        need(hashlib.sha256(helper_path.read_bytes()).hexdigest() == HELPER_SHA256, 'reviewed_cleanup_helper_required')
        access = validate_access(raw)
        raw = None
        receipt = run_cleanup(access, bounded_request(), source_commit=os.environ['GITHUB_SHA'])
        access.clear()
    except Exception:
        receipt = {'status':'BLOCKED','reason':'cleanup_context_or_channel_unconfirmed',
                   'credentials_persisted':False,'automatic_retry_allowed':False,'phase1_accepted':False}
    finally:
        raw = None
    out = ROOT / 'phase1-run78-cleanup'
    out.mkdir(mode=0o700, exist_ok=True)
    path = out / 'receipt.json'
    with path.open('x', encoding='utf-8') as stream:
        json.dump(receipt,stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    path.chmod(0o600)
    print('RUN78_EXACT_FIXTURE_CLEANUP_' + receipt['status'])
    return 0 if receipt['status'] == 'PASS' else 2


if __name__ == '__main__':
    raise SystemExit(main())
