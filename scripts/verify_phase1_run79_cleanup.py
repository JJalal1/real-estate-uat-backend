#!/usr/bin/env python3
"""Read-only normal-API verification of Run79 cleanup; no listing mutations."""
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

spec = importlib.util.spec_from_file_location('_run79_verification_c2', ADAPTER/'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
c2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c2)
helper = c2.cleanup_module
KEY = '04fd2b30-db88-4f59-a5d7-49891d49a4fc'
TAG = 'AQER-C1-b84b562e0098'
PROPERTY_ID = 98
BRANCH = 'refs/heads/work/phase1-run79-cleanup-20261105'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
HELPER_SHA256 = 'ec54c936f226b9c3cb5a27e914eced199ff6ee5a59b91a8dcfc14997a40f2a9b'
EXPECTED_BASELINE = {
    'properties': {'count':25,'sha256':'0abc8495cae3cdcabe4f9d00c4e732e7c1e63140175646008e8fe9ded1995cd6'},
    'drafts': {'count':7,'sha256':'8f10dc0a80fae8813d68c4b88d36e279a25353bd40071cd198c786deb96c5051'},
}
PROVENANCE = {
    'ci_run_id':'41986698109','source_commit':'3bc44e5ac991fb3647e7b33da1ee8917fe1e6e9c',
    'full_report_sha256':'7f3b3583dbbb2e125276938510ed6f7af1697a1fea1537f616cd01d2f0ead86f',
    'original_bootstrap_status':'PASS','original_actor_id':28,
    'original_vm_exit_code':0,'original_owned_process_group_absent':True,
    'original_vm_ended_utc':'2026-11-05T07:45:37.262234+00:00',
}


class VerificationRefused(RuntimeError): pass


def need(condition, code):
    if not condition: raise VerificationRefused(code) from None


def read_baseline(api):
    result = {}
    for kind, route in (('properties','/properties/mine/list'),('drafts','/listing-editor-drafts')):
        rows = {}
        for page in range(1,21):
            code, body = api('GET',route+'?per_page=50&page='+str(page))
            data = body.get('data')
            need(code == 200 and type(data) is list and len(data) <= 50, 'baseline_read_unconfirmed')
            for row in data:
                need(type(row) is dict,'baseline_row_invalid')
                if kind == 'properties':
                    need(helper.positive_id(row.get('id')),'baseline_identity_invalid')
                    identity, projection = str(row['id']), helper.property_projection(row)
                else:
                    need(helper.canonical_uuid(row.get('key')),'baseline_identity_invalid')
                    identity, projection = row['key'], helper.draft_projection(row)
                need(identity not in rows,'baseline_duplicate_identity')
                rows[identity] = helper.digest(projection)
            last = body.get('meta',{}).get('last_page',1)
            need(type(last) is int and page <= last <= 20,'baseline_pagination_invalid')
            if page == last: break
        result[kind] = {'count':len(rows),'sha256':helper.digest(rows)}
    return result


def verify_authenticated(api, receipt):
    receipt['stage'] = 'exact_fixture_absence'
    code, _ = api('GET','/properties/98')
    receipt['property_readback_http'] = code
    need(code == 404,'exact_property_absence_unconfirmed')
    code, _ = api('GET','/listing-editor-drafts/'+KEY)
    receipt['draft_readback_http'] = code
    need(code == 404,'exact_draft_absence_unconfirmed')
    receipt['stage'] = 'historical_baseline_readback'
    receipt['baseline_after'] = read_baseline(api)
    need(receipt['baseline_after'] == EXPECTED_BASELINE,'historical_baseline_mismatch')
    receipt['known_fixture_absent'] = receipt['protected_baseline_restored'] = True
    return True


def run_verification(access, request, *, source_commit):
    receipt = {'scope':'Run79 exact absence and original baseline through normal broker API',
        'status':'BLOCKED','stage':'normal_broker_session','source_commit':source_commit,
        'historical_provenance':dict(PROVENANCE),'fixture_key':KEY,'fixture_tag':TAG,
        'property_id':PROPERTY_ID,'actor_id':28,'listing_mutations_requested':False,
        'credentials_persisted':False,'automatic_retry_allowed':False,
        'native_acceptance_claimed':False,'phase1_accepted':False,
        'started_utc':datetime.now(timezone.utc).isoformat()}
    memory = c2.roles.KnownRoleMemory(access)
    private_values = set()
    memory.add_redactions_to(private_values)
    session = c2.NormalOwnerSession(request,memory,private_values)
    try:
        session.run(lambda api:verify_authenticated(api,receipt))
        receipt.update(status='PASS',stage='complete')
    except Exception:
        receipt['reason'] = 'normal_session_or_cleanup_verification_unconfirmed'
    finally:
        receipt.update(logout_http_200=session.logout_200,revoked_token_me_http_401=session.me_401,
                       ended_utc=datetime.now(timezone.utc).isoformat())
        memory.clear()
    encoded = json.dumps(receipt,ensure_ascii=False,sort_keys=True)
    need(not any(value and value in encoded for value in private_values),'receipt_private_value_refused')
    private_values.clear()
    return receipt


def bounded_request():
    started = time.monotonic()
    work = DeadlineTransport(deadline_getter=lambda:started+180)
    revoke = DeadlineTransport(deadline_getter=lambda:started+240)
    revoking = False
    def request(method,path,body=None,token=None):
        nonlocal revoking
        if method == 'POST' and path == '/auth/logout': revoking=True
        if revoking:
            need((method,path) in {('POST','/auth/logout'),('GET','/auth/me')},'revocation_only_after_work')
            return revoke(method,path,body,token)
        need((method == 'POST' and path in {'/auth/whatsapp/start','/auth/whatsapp/verify'}) or
             (method == 'GET' and (path in {'/auth/me','/properties/98','/listing-editor-drafts/'+KEY} or
              re.fullmatch(r'/(?:properties/mine/list|listing-editor-drafts)\?per_page=50&page=(?:[1-9]|1[0-9]|20)',path))),
             'only_fixed_verification_and_normal_auth_routes_allowed')
        return work(method,path,body,token)
    return request


def context_valid(env):
    return (env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
        env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and env.get('GITHUB_RUN_ATTEMPT') == '1' and
        re.fullmatch('[a-f0-9]{40}',env.get('GITHUB_SHA','')) is not None and env.get('UAT_API_BASE_URL') == API)


def main():
    raw = os.environ.pop(SECRET_NAME,None)
    try:
        need(context_valid(os.environ),'fixed_verification_ci_context_required')
        need(hashlib.sha256((ADAPTER/'variants/promoted_cleanup.py').read_bytes()).hexdigest() == HELPER_SHA256,
             'reviewed_projection_source_required')
        access = validate_access(raw)
        raw = None
        receipt = run_verification(access,bounded_request(),source_commit=os.environ['GITHUB_SHA'])
        access.clear()
    except Exception:
        receipt = {'status':'BLOCKED','reason':'verification_context_or_channel_unconfirmed',
            'credentials_persisted':False,'listing_mutations_requested':False,'phase1_accepted':False}
    finally: raw = None
    out = ROOT/'phase1-run79-cleanup'
    out.mkdir(mode=0o700,exist_ok=True)
    path = out/'receipt.json'
    with path.open('x',encoding='utf-8') as stream:
        json.dump(receipt,stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    path.chmod(0o600)
    print('RUN79_CLEANUP_VERIFICATION_'+receipt['status'])
    return 0 if receipt['status'] == 'PASS' else 2


if __name__ == '__main__': raise SystemExit(main())
