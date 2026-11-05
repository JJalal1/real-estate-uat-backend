"""Offline Run78 cleanup boundary tests; no network or credential discovery."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import uuid

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('_run78_cleanup_test', SCRIPTS/'cleanup_phase1_run78_fixture.py')
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class FakeApi:
    def __init__(self):
        self.properties = {str(i):{'id':i,'title':'PROTECTED_'+str(i),'images':[]}
                           for i in range(1,26)}
        self.drafts = {str(uuid.UUID(int=i)):{'key':str(uuid.UUID(int=i)), 'property_id':None,
            'revision':1,'payload':{'fields':{'title':'PROTECTED_DRAFT_'+str(i)}},'images':[]}
            for i in range(1,8)}
        self.expected = {'properties':{'count':25,'sha256':cleanup.helper.digest({key:cleanup.helper.digest(
            cleanup.helper.property_projection(row)) for key,row in self.properties.items()})},
            'drafts':{'count':7,'sha256':cleanup.helper.digest({key:cleanup.helper.digest(
            cleanup.helper.draft_projection(row)) for key,row in self.drafts.items()})}}
        title=cleanup.EXACT_TITLE
        self.properties['97']={'id':97,'title':title,'advertiser':{'id':28},'status':'draft',
            'review_status':'draft','type':'apartment','purpose':'rent','floor_number':2,'unit_number':'7','images':[{'id':901}]}
        self.drafts[cleanup.KEY]={'key':cleanup.KEY,'property_id':97,'revision':cleanup.EXACT_DRAFT_REVISION,
            'payload':{'fields':{'title':title}},'images':[{'key':'synthetic-image'}]}
        self.calls=[];self.logged_out=False;self.fail_delete=False;self.foreign_owner=False

    def request(self, method, path, body=None, token=None):
        self.calls.append((method,path))
        if path=='/auth/whatsapp/start':return 200,{}
        if path=='/auth/whatsapp/verify':return 200,{'data':{'token':'PRIVATE_TOKEN_SECRET'}}
        if path=='/auth/logout':self.logged_out=True;return 200,{}
        if path=='/auth/me':return (401,{}) if self.logged_out else (200,{'data':{'user':{'id':28,'account_type':'broker'}}})
        if path.startswith('/properties/mine/list?'):return 200,{'data':copy.deepcopy(list(self.properties.values())),'meta':{'last_page':1}}
        if path.startswith('/listing-editor-drafts?'):return 200,{'data':copy.deepcopy(list(self.drafts.values())),'meta':{'last_page':1}}
        if path=='/properties/97':
            if method=='DELETE':
                if self.fail_delete:raise TimeoutError('PRIVATE_TRANSPORT_SENTINEL')
                self.properties.pop('97');self.drafts[cleanup.KEY]['property_id']=None;return 200,{}
            if '97' not in self.properties:return 404,{}
            row=copy.deepcopy(self.properties['97']);row['is_owner']=not self.foreign_owner
            return 200,{'data':row}
        if path=='/listing-editor-drafts/'+cleanup.KEY:
            if method=='DELETE':self.drafts.pop(cleanup.KEY);return 200,{}
            return (200,{'data':copy.deepcopy(self.drafts[cleanup.KEY])}) if cleanup.KEY in self.drafts else (404,{})
        if path=='/property-media/901':return 404,{}
        raise AssertionError('unexpected test route')


class CleanupTests(unittest.TestCase):
    def run_fixture(self, api):
        with patch.object(cleanup,'EXPECTED_BASELINE',api.expected):
            return cleanup.run_cleanup({'otp':'258147','phones':{'broker':'+9000000001'}},
                api.request,source_commit='a'*40)

    def test_exact_original_pair_property_first_then_draft_restores_baseline_and_revokes(self):
        api=FakeApi();receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'PASS')
        self.assertEqual([call for call in api.calls if call[0]=='DELETE'],
            [('DELETE','/properties/97'),('DELETE','/listing-editor-drafts/'+cleanup.KEY)])
        self.assertEqual(receipt['baseline_before'],api.expected)
        self.assertEqual(receipt['baseline_after'],api.expected)
        self.assertTrue(receipt['logout_http_200'] and receipt['revoked_token_me_http_401'])
        self.assertEqual(api.calls[-2:],[('POST','/auth/logout'),('GET','/auth/me')])
        encoded=json.dumps(receipt)
        for private in ('PRIVATE_','258147','9000000001','PROTECTED_'):
            self.assertNotIn(private,encoded)

    def test_changed_protected_state_extra_row_or_wrong_pair_prevents_every_delete(self):
        for fault in ('changed_property','changed_draft','extra_property','extra_draft','wrong_pair','wrong_tag','same_tag_other_title','changed_revision','missing_pair','owner'):
            with self.subTest(fault=fault):
                api=FakeApi()
                if fault=='changed_property':api.properties['1']['title']='CHANGED'
                elif fault=='changed_draft':api.drafts[str(uuid.UUID(int=1))]['revision']=2
                elif fault=='extra_property':api.properties['98']={'id':98,'title':'EXTRA','images':[]}
                elif fault=='extra_draft':api.drafts[str(uuid.UUID(int=99))]={'key':str(uuid.UUID(int=99)),'images':[]}
                elif fault=='wrong_pair':api.drafts[cleanup.KEY]['property_id']=98
                elif fault=='wrong_tag':api.properties['97']['title']='OTHER'
                elif fault=='same_tag_other_title':
                    api.properties['97']['title']=api.drafts[cleanup.KEY]['payload']['fields']['title']='OTHER '+cleanup.TAG
                elif fault=='changed_revision':api.drafts[cleanup.KEY]['revision']+=1
                elif fault=='missing_pair':api.properties.pop('97')
                else:api.foreign_owner=True
                receipt=self.run_fixture(api)
                self.assertEqual(receipt['status'],'BLOCKED')
                self.assertFalse(any(method=='DELETE' for method,path in api.calls))
                self.assertTrue(receipt['logout_http_200'] and receipt['revoked_token_me_http_401'])

    def test_unknown_delete_completion_is_not_retried_or_followed_by_draft_delete(self):
        api=FakeApi();api.fail_delete=True;receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'BLOCKED')
        self.assertEqual([call for call in api.calls if call[0]=='DELETE'],[('DELETE','/properties/97')])
        self.assertTrue(receipt['logout_http_200'] and receipt['revoked_token_me_http_401'])
        self.assertNotIn('PRIVATE_',json.dumps(receipt))

    def test_transport_reserves_only_exact_deletes_and_revocation_cannot_restart_work(self):
        calls=[]
        class Transport:
            def __init__(self,**kwargs):pass
            def __call__(self,method,path,body=None,token=None):
                calls.append((method,path))
                if method=='DELETE':raise TimeoutError('PRIVATE')
                return 200,{},0
        with patch.object(cleanup,'DeadlineTransport',Transport):
            request=cleanup.bounded_request()
            with self.assertRaises(cleanup.CleanupRefused):request('DELETE','/properties/98')
            with self.assertRaises(TimeoutError):request('DELETE','/properties/97')
            with self.assertRaises(cleanup.CleanupRefused):request('DELETE','/properties/97')
            request('POST','/auth/logout',{})
            with self.assertRaises(cleanup.CleanupRefused):request('GET','/properties/97')
        self.assertEqual(calls,[('DELETE','/properties/97'),('POST','/auth/logout')])

    def test_only_reviewed_cleanup_branch_push_first_attempt_can_execute(self):
        env={'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'JJalal1/real-estate-uat-backend',
             'GITHUB_REF':cleanup.BRANCH,'GITHUB_EVENT_NAME':'push','GITHUB_RUN_ATTEMPT':'1',
             'GITHUB_SHA':'a'*40,'UAT_API_BASE_URL':cleanup.API}
        self.assertTrue(cleanup.context_valid(env))
        for key,value in [('GITHUB_REF','refs/heads/work/phase1-completion-20261105'),
                          ('GITHUB_RUN_ATTEMPT','2'),('GITHUB_EVENT_NAME','workflow_dispatch'),
                          ('GITHUB_REPOSITORY','other/repository'),('UAT_API_BASE_URL','https://foreign.invalid')]:
            self.assertFalse(cleanup.context_valid(dict(env,**{key:value})))


if __name__=='__main__':unittest.main()
