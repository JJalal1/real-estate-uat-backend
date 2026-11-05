"""Offline tests for the single Run85 fixture; never opens a network connection."""
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
spec=importlib.util.spec_from_file_location('_run85_cleanup_test',SCRIPTS/'cleanup_phase1_run85_fixture.py')
cleanup=importlib.util.module_from_spec(spec);spec.loader.exec_module(cleanup)


class FakeApi:
    def __init__(self):
        self.properties={str(i):{'id':i,'title':'PROTECTED_'+str(i),'images':[]} for i in range(1,26)}
        self.drafts={str(uuid.UUID(int=i)):{'key':str(uuid.UUID(int=i)),'property_id':None,
            'revision':1,'payload':{'fields':{'title':'PROTECTED_DRAFT_'+str(i)}},'images':[]} for i in range(1,8)}
        self.expected=cleanup.summary({'properties':{k:cleanup.helper.digest(cleanup.helper.property_projection(v)) for k,v in self.properties.items()},
            'drafts':{k:cleanup.helper.digest(cleanup.helper.draft_projection(v)) for k,v in self.drafts.items()}})
        self.properties['101']={'id':101,'title':cleanup.EXACT_TITLE,'advertiser':{'id':28},
            'status':'pending','review_status':'submitted','type':'apartment','purpose':'rent',
            'floor_number':2,'unit_number':'7','images':[{'id':901}]}
        self.drafts[cleanup.KEY]={'key':cleanup.KEY,'property_id':101,'revision':24,
            'payload':{'fields':{'title':cleanup.EXACT_TITLE}},'images':[{'key':'synthetic-image'}]}
        self.calls=[];self.fail=None;self.support_roles=['support_agent'];self.foreign_owner=False
        self.change_after_return=False
        # Pre-existing hidden linked rows must never enter a cleanup target.
        self.hidden={93:'unchanged_old_row_93',94:'unchanged_old_row_94'}

    def factory(self,phase):
        logged_out=False
        def request(method,path,body=None,token=None):
            nonlocal logged_out
            self.calls.append((phase,method,path))
            if path=='/auth/whatsapp/start':return 200,{}
            if path=='/auth/whatsapp/verify':return 200,{'data':{'token':'PRIVATE_TOKEN_'+phase}}
            if path=='/auth/logout':logged_out=True;return 200,{}
            if path=='/auth/me':
                if logged_out:return 401,{}
                actor={'id':28,'account_type':'broker'}
                if phase=='support_return':actor={'id':29,'account_type':'regular','account_status':'active',
                    'is_platform_owner':False,'roles':self.support_roles,'permissions':['listings.moderate']}
                return 200,{'data':{'user':actor}}
            if method=='POST' and path.startswith(cleanup.REVIEW):
                if self.fail==path:raise TimeoutError('PRIVATE_TRANSPORT_SENTINEL')
                if path.endswith('/start'):
                    self.properties['101']['review_status']='under_review'
                elif path.endswith('/return'):
                    assert body=={'reason':cleanup.REASON}
                    self.properties['101'].update(status='draft',review_status='returned_for_correction',
                        last_review_reason=cleanup.REASON,updated_at='returned_timestamp')
                    if self.change_after_return:self.properties['1']['title']='CHANGED'
                else:raise AssertionError('forbidden action')
                return 200,{'data':self.support_row()}
            if path==cleanup.REVIEW:return 200,{'data':self.support_row()}
            if path.startswith('/properties/mine/list?'):
                return 200,{'data':copy.deepcopy(list(self.properties.values())),'meta':{'last_page':1}}
            if path.startswith('/listing-editor-drafts?'):
                rows=[row for key,row in self.drafts.items() if key!=cleanup.KEY or row.get('property_id') is None or
                    self.properties.get('101',{}).get('status')=='draft']
                return 200,{'data':copy.deepcopy(rows),'meta':{'last_page':1}}
            if path==cleanup.PROPERTY:
                if method=='DELETE':
                    if self.fail==path:raise TimeoutError('PRIVATE_TRANSPORT_SENTINEL')
                    self.properties.pop('101');self.drafts[cleanup.KEY]['property_id']=None;return 200,{}
                if '101' not in self.properties:return 404,{}
                row=copy.deepcopy(self.properties['101']);row['is_owner']=not self.foreign_owner
                return 200,{'data':row}
            if path==cleanup.DRAFT:
                if method=='DELETE':self.drafts.pop(cleanup.KEY);return 200,{}
                return (200,{'data':copy.deepcopy(self.drafts[cleanup.KEY])}) if cleanup.KEY in self.drafts else (404,{})
            if path=='/property-media/901':return 404,{}
            raise AssertionError('unexpected route')
        return request

    def support_row(self):
        row=copy.deepcopy(self.properties['101']);row['owner']={'id':28};row['published_at']=None
        return row

    def mutations(self):
        return [(method,path) for _,method,path in self.calls if method=='DELETE' or
            (method=='POST' and path.startswith(cleanup.REVIEW))]


class CleanupTests(unittest.TestCase):
    def run_fixture(self,api):
        with patch.object(cleanup,'EXPECTED_BASELINE',api.expected):
            return cleanup.run_cleanup({'otp':'258147','phones':{'broker':'+9000000001','support':'+9000000002'}},
                api.factory,source_commit='a'*40)

    def assert_revoked(self,receipt):
        self.assertTrue(receipt['sessions'])
        self.assertTrue(all(s['logout_http_200'] and s['revoked_token_me_http_401'] for s in receipt['sessions']))

    def test_normal_claim_return_then_owner_property_first_cleanup_and_all_sessions_revoked(self):
        api=FakeApi();receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'PASS',receipt)
        self.assertEqual(api.mutations(),[('POST',cleanup.REVIEW+'/start'),('POST',cleanup.REVIEW+'/return'),
            ('DELETE',cleanup.PROPERTY),('DELETE',cleanup.DRAFT)])
        self.assertEqual(receipt['baseline_before'],api.expected);self.assertEqual(receipt['baseline_after'],api.expected)
        self.assertEqual(len(receipt['sessions']),3);self.assert_revoked(receipt)
        self.assertEqual(api.hidden,{93:'unchanged_old_row_93',94:'unchanged_old_row_94'})
        self.assertIn(('broker_cleanup','GET','/property-media/901'),api.calls)
        encoded=json.dumps(receipt)
        for private in ('PRIVATE_','258147','9000000001','9000000002','PROTECTED_'):
            self.assertNotIn(private,encoded)

    def test_wrong_exact_pair_or_original_baseline_prevents_all_mutations(self):
        for fault in ('title','revision','pair','owner','state','protected_property','protected_draft','extra_property'):
            with self.subTest(fault=fault):
                api=FakeApi()
                if fault=='title':api.properties['101']['title']='OTHER '+cleanup.TAG
                elif fault=='revision':api.drafts[cleanup.KEY]['revision']=25
                elif fault=='pair':api.drafts[cleanup.KEY]['property_id']=102
                elif fault=='owner':api.foreign_owner=True
                elif fault=='state':api.properties['101']['review_status']='under_review'
                elif fault=='protected_property':api.properties['1']['title']='CHANGED'
                elif fault=='protected_draft':api.drafts[str(uuid.UUID(int=1))]['revision']=2
                else:api.properties['102']={'id':102,'title':'EXTRA','images':[]}
                receipt=self.run_fixture(api)
                self.assertEqual(receipt['status'],'BLOCKED');self.assertEqual(api.mutations(),[])
                self.assert_revoked(receipt);self.assertNotEqual(receipt['reason'],'exact_normal_cleanup_unconfirmed_no_retry')

    def test_support_role_and_changed_state_after_return_stop_before_owner_delete(self):
        api=FakeApi();api.support_roles=['support_manager'];receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'BLOCKED');self.assertEqual(api.mutations(),[])
        self.assertEqual(receipt['reason'],'known_ordinary_support_actor_required');self.assert_revoked(receipt)
        api=FakeApi();api.change_after_return=True;receipt=self.run_fixture(api)
        self.assertEqual(receipt['status'],'BLOCKED');self.assertFalse(any(m=='DELETE' for m,p in api.mutations()))
        self.assertEqual(receipt['reason'],'protected_baseline_changed_during_return');self.assert_revoked(receipt)

    def test_unknown_claim_return_or_delete_is_single_attempt_then_logout(self):
        ordered=[('POST',cleanup.REVIEW+'/start'),('POST',cleanup.REVIEW+'/return'),('DELETE',cleanup.PROPERTY)]
        for i,(_,failure) in enumerate(ordered):
            with self.subTest(stage=i):
                api=FakeApi();api.fail=failure;receipt=self.run_fixture(api)
                self.assertEqual(receipt['status'],'BLOCKED');self.assertEqual(api.mutations(),ordered[:i+1])
                self.assert_revoked(receipt);self.assertNotIn('PRIVATE_',json.dumps(receipt))

    def test_transport_only_fixed_routes_and_no_mutation_replay_after_uncertain_result(self):
        calls=[]
        class Transport:
            def __init__(self,**kwargs):pass
            def __call__(self,method,path,body=None,token=None):
                calls.append((method,path))
                if path.endswith('/start'):raise TimeoutError('PRIVATE')
                return 200,{},0
        with patch.object(cleanup,'DeadlineTransport',Transport):
            factory=cleanup.request_factory();request=factory('support_return')
            for method,path,body in [('POST',cleanup.REVIEW+'/approve',{}),('POST',cleanup.REVIEW+'/reject-final',{}),
                                     ('POST',cleanup.REVIEW+'/return',{'reason':'different'}),('DELETE',cleanup.PROPERTY,None)]:
                with self.assertRaises(cleanup.CleanupRefused):request(method,path,body)
            with self.assertRaises(TimeoutError):request('POST',cleanup.REVIEW+'/start',{})
            with self.assertRaises(cleanup.CleanupRefused):request('POST',cleanup.REVIEW+'/start',{})
            request('POST','/auth/logout',{})
            with self.assertRaises(cleanup.CleanupRefused):request('GET',cleanup.REVIEW)
            with self.assertRaises(cleanup.CleanupRefused):factory('support_return')
        self.assertEqual(calls,[('POST',cleanup.REVIEW+'/start'),('POST','/auth/logout')])

    def test_only_fixed_cleanup_branch_push_first_attempt_can_execute(self):
        env={'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'JJalal1/real-estate-uat-backend',
             'GITHUB_REF':cleanup.BRANCH,'GITHUB_EVENT_NAME':'push','GITHUB_RUN_ATTEMPT':'1',
             'GITHUB_SHA':'a'*40,'UAT_API_BASE_URL':cleanup.API}
        self.assertTrue(cleanup.context_valid(env))
        for key,value in [('GITHUB_REF','refs/heads/work/phase1-completion-20261105'),('GITHUB_RUN_ATTEMPT','2'),
                          ('GITHUB_EVENT_NAME','workflow_dispatch'),('UAT_API_BASE_URL','https://foreign.invalid')]:
            self.assertFalse(cleanup.context_valid(dict(env,**{key:value})))


if __name__=='__main__':unittest.main()
