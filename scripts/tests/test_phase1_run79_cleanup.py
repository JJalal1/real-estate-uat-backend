"""Offline tests for Run79 read-only cleanup verification."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import uuid

SCRIPTS=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(SCRIPTS))
spec=importlib.util.spec_from_file_location('_run79_verification_test',SCRIPTS/'verify_phase1_run79_cleanup.py')
verification=importlib.util.module_from_spec(spec)
spec.loader.exec_module(verification)


class FakeApi:
    def __init__(self):
        self.properties=[{'id':i,'title':'PRIVATE_PROTECTED_'+str(i),'images':[]} for i in range(1,26)]
        self.drafts=[{'key':str(uuid.UUID(int=i)),'property_id':None,'revision':1,
            'payload':{'fields':{'title':'PRIVATE_DRAFT_'+str(i)}},'images':[]} for i in range(1,8)]
        self.calls=[];self.logged_out=False;self.actor=28;self.property_http=self.draft_http=404
        self.expected=verification.read_baseline(lambda method,path:self.request(method,path))
        self.calls.clear()
    def request(self,method,path,body=None,token=None):
        self.calls.append((method,path))
        if method not in {'GET','POST'}:raise AssertionError('listing mutation attempted')
        if path=='/auth/whatsapp/start':return 200,{}
        if path=='/auth/whatsapp/verify':return 200,{'data':{'token':'PRIVATE_TOKEN_SECRET'}}
        if path=='/auth/logout':self.logged_out=True;return 200,{}
        if path=='/auth/me':return (401,{}) if self.logged_out else (200,{'data':{'user':{'id':self.actor,'account_type':'broker'}}})
        if path=='/properties/98':return self.property_http,{}
        if path=='/listing-editor-drafts/'+verification.KEY:return self.draft_http,{}
        if path.startswith('/properties/mine/list?'):return 200,{'data':copy.deepcopy(self.properties),'meta':{'last_page':1}}
        if path.startswith('/listing-editor-drafts?'):return 200,{'data':copy.deepcopy(self.drafts),'meta':{'last_page':1}}
        raise AssertionError('unexpected test route')


class VerificationTests(unittest.TestCase):
    def run_fixture(self,api):
        with patch.object(verification,'EXPECTED_BASELINE',api.expected):
            return verification.run_verification({'otp':'258147','phones':{'broker':'+9000000001'}},
                api.request,source_commit='a'*40)

    def test_exact_absence_baseline_and_revocation_pass_without_listing_writes(self):
        api=FakeApi();receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'PASS')
        self.assertEqual((receipt['property_readback_http'],receipt['draft_readback_http']),(404,404))
        self.assertEqual(receipt['baseline_after'],api.expected)
        self.assertTrue(receipt['protected_baseline_restored'] and receipt['known_fixture_absent'])
        self.assertTrue(receipt['logout_http_200'] and receipt['revoked_token_me_http_401'])
        self.assertFalse(receipt['listing_mutations_requested'])
        self.assertEqual([path for method,path in api.calls if method=='POST'],
                         ['/auth/whatsapp/start','/auth/whatsapp/verify','/auth/logout'])
        for private in ('PRIVATE_','258147','9000000001'):
            self.assertNotIn(private,json.dumps(receipt))

    def test_remaining_fixture_changed_baseline_or_wrong_actor_block_and_still_revoke(self):
        for fault in ('property_present','draft_present','changed_property','changed_draft','extra_property','wrong_actor'):
            with self.subTest(fault=fault):
                api=FakeApi()
                if fault=='property_present':api.property_http=200
                elif fault=='draft_present':api.draft_http=200
                elif fault=='changed_property':api.properties[0]['title']='CHANGED'
                elif fault=='changed_draft':api.drafts[0]['revision']=2
                elif fault=='extra_property':api.properties.append({'id':98,'images':[]})
                else:api.actor=29
                receipt=self.run_fixture(api)
                self.assertEqual(receipt['status'],'BLOCKED')
                self.assertTrue(receipt['logout_http_200'] and receipt['revoked_token_me_http_401'])
                self.assertFalse(any(method in {'PUT','PATCH','DELETE'} for method,path in api.calls))

    def test_snapshot_rejects_duplicates_and_unbounded_pagination(self):
        api=FakeApi();api.properties.append(dict(api.properties[0]))
        with self.assertRaises(verification.VerificationRefused):verification.read_baseline(api.request)
        with self.assertRaises(verification.VerificationRefused):
            verification.read_baseline(lambda method,path:(200,{'data':[],'meta':{'last_page':21}}))

    def test_transport_blocks_every_listing_mutation_and_foreign_route(self):
        calls=[]
        class Transport:
            def __init__(self,**kwargs):pass
            def __call__(self,method,path,body=None,token=None):calls.append((method,path));return 200,{},0
        with patch.object(verification,'DeadlineTransport',Transport):
            request=verification.bounded_request()
            for method,path in [('DELETE','/properties/98'),('DELETE','/listing-editor-drafts/'+verification.KEY),
                                ('PUT','/properties/98'),('POST','/properties'),('GET','/properties/97'),
                                ('GET','https://foreign.invalid/')]:
                with self.assertRaises(verification.VerificationRefused):request(method,path)
            request('GET','/properties/98')
            request('POST','/auth/logout',{})
            with self.assertRaises(verification.VerificationRefused):request('GET','/properties/98')
        self.assertEqual(calls,[('GET','/properties/98'),('POST','/auth/logout')])

    def test_only_separate_branch_push_first_attempt_is_allowed(self):
        env={'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'JJalal1/real-estate-uat-backend',
             'GITHUB_REF':verification.BRANCH,'GITHUB_EVENT_NAME':'push','GITHUB_RUN_ATTEMPT':'1',
             'GITHUB_SHA':'a'*40,'UAT_API_BASE_URL':verification.API}
        self.assertTrue(verification.context_valid(env))
        for key,value in [('GITHUB_REF','refs/heads/work/phase1-completion-20261105'),('GITHUB_RUN_ATTEMPT','2'),
                          ('GITHUB_EVENT_NAME','workflow_dispatch'),('GITHUB_REPOSITORY','foreign/repo')]:
            self.assertFalse(verification.context_valid(dict(env,**{key:value})))


if __name__=='__main__':unittest.main()
