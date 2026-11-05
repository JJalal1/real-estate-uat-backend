#!/usr/bin/env python3
"""One reviewed Run85 fixture recovery; import is offline and never executes.

Credentials come only from the existing Actions secret and remain in RAM. The
original API baseline is pinned before normal support return and owner deletion;
pre-existing filtered-out drafts are never read or changed. No arbitrary fixture or destination input.
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


c2 = _load('_run85_cleanup_c2', ADAPTER / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
helper = c2.cleanup_module
KEY = '262ff83f-ab7f-49bc-bee1-a1d76010d808'
TAG = 'AQER-C1-5d4e4b2aac00'
PROPERTY_ID = 101
EXACT_TITLE = 'اختبار استعادة المسودة ' + TAG
EXACT_DRAFT_REVISION = 24
BRANCH = 'refs/heads/work/phase1-run85-cleanup-20261105'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
HELPER_SHA256 = 'ec54c936f226b9c3cb5a27e914eced199ff6ee5a59b91a8dcfc14997a40f2a9b'
EXPECTED_BASELINE = {
    'properties': {'count': 25, 'sha256': '0abc8495cae3cdcabe4f9d00c4e732e7c1e63140175646008e8fe9ded1995cd6'},
    'drafts': {'count': 7, 'sha256': '8f10dc0a80fae8813d68c4b88d36e279a25353bd40071cd198c786deb96c5051'},
}
# Root-reviewed facts from the verified decrypted original run, not a new
# bootstrap claim. The historical full report remains private.
PROVENANCE = {
    'ci_run_id': '42017972962',
    'source_commit': '96a4fc457b7157bd9cda89b86db1d20d4fcdea95',
    'full_report_sha256': '3d9acc9e3ebf1dbaf20067cb2657f3691353713f7c705d7840e17c5e467a4cca',
    'original_bootstrap_status': 'PASS', 'original_bootstrap_http': 200,
    'original_fixture_created': True, 'original_bootstrap_only_title_label': True,
    'original_actor_id': 28, 'original_account_type': 'broker',
    'original_vm_exit_code': -9, 'original_owned_process_group_absent': True,
    'original_vm_ended_utc': '2026-11-05T11:54:28.386972+00:00',
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


REASON = 'إرجاع مسودة الاختبار الاصطناعية لتنظيفها فقط ' + TAG
PROPERTY = '/properties/101'
DRAFT = '/listing-editor-drafts/' + KEY
REVIEW = '/admin/listing-review/listings/101'


def exact_draft(api):
    code, body = api('GET',DRAFT)
    row = body.get('data')
    need(code == 200 and type(row) is dict and row.get('key') == KEY and
         type(row.get('property_id')) is int and row['property_id'] == PROPERTY_ID and
         type(row.get('revision')) is int and row['revision'] == EXACT_DRAFT_REVISION and
         row.get('payload',{}).get('fields',{}).get('title') == EXACT_TITLE and
         type(row.get('images')) is list,'exact_original_draft_required')
    return row


def exact_property(row, status, review, *, support=False):
    need(type(row) is dict and type(row.get('id')) is int and row['id'] == PROPERTY_ID and
         row.get('title') == EXACT_TITLE and row.get('status') == status and row.get('review_status') == review,
         'exact_property_state_required')
    if support:
        need(row.get('owner',{}).get('id') == 28 and row.get('published_at') is None,
             'exact_support_owner_unpublished_required')
    else:
        need(row.get('advertiser',{}).get('id') == 28,'exact_broker_owned_property_required')


def broker_preflight(api, receipt):
    receipt['stage']='broker_preflight'
    draft=exact_draft(api)
    code, body=api('GET',PROPERTY)
    need(code==200,'exact_property_read_required')
    exact_property(body.get('data'),'pending','submitted')
    need(body['data'].get('is_owner') is True,'normal_owner_detail_required')
    snapshot, rows=read_snapshot(api)
    owned=rows['properties'].get(str(PROPERTY_ID))
    exact_property(owned,'pending','submitted')
    need(KEY not in snapshot['drafts'],'submitted_draft_index_must_remain_filtered')
    baseline=copy.deepcopy(snapshot)
    del baseline['properties'][str(PROPERTY_ID)]
    need(summary(baseline)==EXPECTED_BASELINE,'historical_baseline_aggregate_mismatch')
    receipt['baseline_before']=summary(baseline)
    receipt['submitted_pair_verified']=True
    return baseline,helper.draft_projection(draft),helper.property_projection(owned)


class NormalSupportSession(c2.NormalOwnerSession):
    """The already-approved support credential, ordinary agent permissions only."""
    def run(self,work):
        need(not self.used,'support_session_already_consumed')
        self.used=True
        completed=False
        try:
            phone,otp=self._memory.resolve('support')
            code,_=self._call('POST','/auth/whatsapp/start',{'phone':phone,'intent':'login'})
            need(code==200,'support_normal_login_start_failed')
            code,body=self._call('POST','/auth/whatsapp/verify',{'phone':phone,'code':otp})
            del phone,otp
            token=body.get('data',{}).get('token')
            if type(token) is str and token:self._token=token;self._redactions.add(token)
            need(code==200 and self._token,'support_normal_login_verify_failed')
            code,body=self._call('GET','/auth/me')
            actor=body.get('data',{}).get('user',{})
            roles,permissions=actor.get('roles'),actor.get('permissions')
            need(code==200 and helper.positive_id(actor.get('id')) and actor['id']!=28 and
                 actor.get('account_type') in {'regular','broker'} and actor.get('account_status')=='active' and
                 actor.get('is_platform_owner') is False and type(roles) is list and type(permissions) is list and
                 'support_agent' in roles and not set(roles)&{'support_manager','super_admin'} and
                 'listings.moderate' in permissions and 'support.manage' not in permissions,
                 'known_ordinary_support_actor_required')
            self.actor_id=actor['id']
            result=work(self._call)
            completed=True
        finally:
            if self._token is not None:
                try: self.logout_200=self._call('POST','/auth/logout',{})[0]==200
                except Exception: pass
                try: self.me_401=self._call('GET','/auth/me')[0]==401
                except Exception: pass
                self._token=None
        need(completed and self.logout_200 and self.me_401,'support_logout_revocation_unconfirmed')
        return result


def support_return(api,receipt):
    receipt['stage']='support_exact_submitted_read'
    code,body=api('GET',REVIEW)
    need(code==200,'support_exact_listing_read_required')
    exact_property(body.get('data'),'pending','submitted',support=True)
    receipt['stage']='support_claim_once'
    code,body=api('POST',REVIEW+'/start',{})
    need(code==200,'support_claim_unconfirmed')
    exact_property(body.get('data'),'pending','under_review',support=True)
    code,body=api('GET',REVIEW)
    need(code==200,'support_claim_readback_required')
    exact_property(body.get('data'),'pending','under_review',support=True)
    receipt['normal_support_claim_confirmed']=True
    receipt['stage']='support_return_once'
    code,body=api('POST',REVIEW+'/return',{'reason':REASON})
    need(code==200,'support_return_unconfirmed')
    exact_property(body.get('data'),'draft','returned_for_correction',support=True)
    need(body['data'].get('last_review_reason')==REASON,'exact_return_reason_required')
    code,body=api('GET',REVIEW)
    need(code==200,'support_return_readback_required')
    exact_property(body.get('data'),'draft','returned_for_correction',support=True)
    need(body['data'].get('last_review_reason')==REASON,'exact_return_reason_required')
    receipt['normal_support_return_confirmed']=True
    return True


def broker_cleanup(api,receipt,pinned):
    baseline,draft_before,property_before=pinned
    receipt['stage']='returned_pair_and_baseline_readback'
    draft=exact_draft(api)
    need(helper.draft_projection(draft)==draft_before,'original_draft_changed_during_return')
    snapshot,rows=read_snapshot(api)
    owned=rows['properties'].get(str(PROPERTY_ID))
    exact_property(owned,'draft','returned_for_correction')
    need(owned.get('last_review_reason')==REASON,'owner_return_reason_required')
    after_property=helper.property_projection(owned)
    ignored={'updated_at','status','review_status','last_review_reason'}
    need({k:v for k,v in after_property.items() if k not in ignored}==
         {k:v for k,v in property_before.items() if k not in ignored},'property_content_changed_during_return')
    need(snapshot['drafts'].get(KEY)==helper.digest(draft_before),'returned_original_draft_index_required')
    after=copy.deepcopy(snapshot);del after['properties'][str(PROPERTY_ID)];del after['drafts'][KEY]
    need(after==baseline and summary(after)==EXPECTED_BASELINE,'protected_baseline_changed_during_return')
    state={'actor_id':28,'key':KEY,'tag':TAG,'creation_request_sent':True,'created_confirmed':True,
           'bootstrap_only_title_label':True,'baseline':baseline}
    cleaner=helper.PromotedFixtureCleanup(api,state)
    receipt['stage']='returned_pair_pin'
    receipt['pin']=cleaner.pin_candidate(native_writers_stopped=True)
    need(receipt['pin'].get('status')=='READY' and receipt['pin'].get('property_id')==PROPERTY_ID,'returned_pair_pin_not_ready')
    receipt['stage']='owner_property_then_draft_delete'
    receipt['cleanup']=cleaner.cleanup(native_writers_stopped=True)
    need(receipt['cleanup'].get('status')=='PASS','owner_cleanup_unconfirmed')
    final,_=read_snapshot(api)
    need(final==baseline and summary(final)==EXPECTED_BASELINE,'original_baseline_not_restored')
    receipt['baseline_after']=summary(final)
    return True


def run_cleanup(access,request_factory,*,source_commit):
    receipt={'scope':'Run85 synthetic normal support return and owner cleanup only','status':'BLOCKED',
        'source_commit':source_commit,'historical_provenance':dict(PROVENANCE),'fixture_key':KEY,
        'fixture_tag':TAG,'property_id':PROPERTY_ID,'actor_id':28,'sessions':[],
        'publication_or_rejection_requested':False,'automatic_retry_allowed':False,
        'credentials_persisted':False,'phase1_accepted':False,'native_acceptance_claimed':False,
        'started_utc':datetime.now(timezone.utc).isoformat()}
    memory=c2.roles.KnownRoleMemory(access);private_values=set();memory.add_redactions_to(private_values)
    def fixed_refusal(error):
        if len(error.args)==1 and type(error.args[0]) is str and re.fullmatch(r'[a-z_]{5,100}',error.args[0]):
            receipt['reason']=error.args[0]
    def session_run(phase,kind,work):
        session=kind(request_factory(phase),memory,private_values)
        def observed_work(api):
            try:return work(api)
            except CleanupRefused as error:
                fixed_refusal(error)
                raise
        try:return session.run(observed_work)
        finally:receipt['sessions'].append({'phase':phase,'logout_http_200':session.logout_200,
            'revoked_token_me_http_401':session.me_401})
    try:
        need(memory.available('support'),'known_support_credential_required')
        pinned=session_run('broker_preflight',c2.NormalOwnerSession,lambda api:broker_preflight(api,receipt))
        session_run('support_return',NormalSupportSession,lambda api:support_return(api,receipt))
        session_run('broker_cleanup',c2.NormalOwnerSession,lambda api:broker_cleanup(api,receipt,pinned))
        receipt.update(status='PASS',stage='complete')
    except CleanupRefused as error:
        fixed_refusal(error)
        receipt.setdefault('reason','exact_normal_cleanup_unconfirmed_no_retry')
    except Exception:
        receipt.setdefault('reason','exact_normal_cleanup_unconfirmed_no_retry')
    finally:
        memory.clear();receipt['ended_utc']=datetime.now(timezone.utc).isoformat()
    encoded=json.dumps(receipt,ensure_ascii=False,sort_keys=True)
    need(not any(value and value in encoded for value in private_values),'receipt_private_value_refused')
    private_values.clear()
    return receipt


def request_factory():
    total=time.monotonic()+600
    mutations=set();phases=set()
    def create(phase):
        need(phase in {'broker_preflight','support_return','broker_cleanup'} and phase not in phases,'normal_session_once_only')
        phases.add(phase);started=time.monotonic();revoking=False
        work=DeadlineTransport(deadline_getter=lambda:min(total-60,started+150))
        revoke=DeadlineTransport(deadline_getter=lambda:min(total,started+210))
        def request(method,path,body=None,token=None):
            nonlocal revoking
            if method=='POST' and path=='/auth/logout':revoking=True
            if revoking:
                need((method,path) in {('POST','/auth/logout'),('GET','/auth/me')},'revocation_only_after_work')
                return revoke(method,path,body,token)
            auth=method=='POST' and path in {'/auth/whatsapp/start','/auth/whatsapp/verify'}
            if method=='POST' and not auth:
                need(phase=='support_return' and ((path==REVIEW+'/start' and body=={}) or
                     (path==REVIEW+'/return' and body=={'reason':REASON})),'only_exact_claim_and_return_allowed')
            elif method=='DELETE':
                need(phase=='broker_cleanup' and path in {PROPERTY,DRAFT} and body is None,'exact_owner_delete_only')
            elif not auth:
                need(method=='GET' and (path=='/auth/me' or (phase=='support_return' and path==REVIEW) or
                     (phase!='support_return' and (path in {PROPERTY,DRAFT} or
                      re.fullmatch(r'/(?:properties/mine/list|listing-editor-drafts)\?per_page=50&page=(?:[1-9]|1[0-9]|20)',path) or
                      re.fullmatch(r'/property-media/[1-9][0-9]{0,18}',path)))),'fixed_cleanup_read_routes_only')
            if method in {'POST','DELETE'} and not auth:
                identity=(method,path);need(identity not in mutations,'mutation_attempt_already_consumed')
                mutations.add(identity)
            return work(method,path,body,token)
        return request
    return create


def context_valid(env):
    return (env.get('GITHUB_ACTIONS')=='true' and env.get('GITHUB_REPOSITORY')=='JJalal1/real-estate-uat-backend' and
        env.get('GITHUB_REF')==BRANCH and env.get('GITHUB_EVENT_NAME')=='push' and env.get('GITHUB_RUN_ATTEMPT')=='1' and
        re.fullmatch('[a-f0-9]{40}',env.get('GITHUB_SHA','')) is not None and env.get('UAT_API_BASE_URL')==API)


def main():
    raw=os.environ.pop(SECRET_NAME,None)
    try:
        need(context_valid(os.environ),'fixed_cleanup_ci_context_required')
        need(hashlib.sha256((ADAPTER/'variants/promoted_cleanup.py').read_bytes()).hexdigest()==HELPER_SHA256,'reviewed_helper_required')
        access=validate_access(raw);raw=None
        receipt=run_cleanup(access,request_factory(),source_commit=os.environ['GITHUB_SHA']);access.clear()
    except Exception:
        receipt={'status':'BLOCKED','reason':'cleanup_context_or_channel_unconfirmed','credentials_persisted':False,'phase1_accepted':False}
    finally:raw=None
    out=ROOT/'phase1-run85-cleanup';out.mkdir(mode=0o700,exist_ok=True);path=out/'receipt.json'
    with path.open('x',encoding='utf-8') as stream:json.dump(receipt,stream,ensure_ascii=False,indent=2);stream.write('\n')
    path.chmod(0o600);print('RUN85_EXACT_FIXTURE_CLEANUP_'+receipt['status'])
    return 0 if receipt['status']=='PASS' else 2


if __name__=='__main__':raise SystemExit(main())


