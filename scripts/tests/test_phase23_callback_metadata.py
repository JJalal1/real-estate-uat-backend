import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]))
from phase23_callback_metadata import FIELDS,safe_callback_label,completed_callback_proof,read_only_callback_command
from run_phase23_native import NativeRun

class CallbackMetadataPrivacy(unittest.TestCase):
    def test_only_known_controls_and_bounded_numeric_schema_are_exported(self):
        value={k:0 for k in FIELDS};value.update(v=1,actor=2)
        raw='CB-META:'+json.dumps(value)
        self.assertIsNotNone(safe_callback_label(raw))
        for changes in [{'token':'private'},{'v':2},{'errors':False},{'actor':66},{'bEpoch':100001},{'bEpoch':-2}]:
            candidate=dict(value,**changes)
            self.assertIsNone(safe_callback_label('CB-META:'+json.dumps(candidate)))
        self.assertIsNone(safe_callback_label('CB-META:'+json.dumps({'v':1})))
        self.assertIsNone(safe_callback_label('CB-META:invalid'))
        self.assertIsNone(safe_callback_label('CB arbitrary private task'))

    def test_unverified_product_cannot_export_harness_text(self):
        rows=[{'text':'CB controls'},{'text':'CB AI PASS'},{'text':'PRIVATE PERSON'}]
        controls,protected=NativeRun.private_ui_controls(rows,force_private=True)
        self.assertEqual(controls,[]);self.assertTrue(protected)
        controls,protected=NativeRun.private_ui_controls(rows,callback_harness=True)
        self.assertTrue(protected)
        self.assertEqual({x['description'] for x in controls},{'CB controls','CB AI PASS'})
        self.assertNotIn('PRIVATE PERSON',str(controls))

    def test_default_entrypoint_does_not_reference_the_alternate_target(self):
        root=Path(__file__).parents[2]
        self.assertNotIn('phase23_native_callback_main',(root/'mobile_app/lib/main.dart').read_text())
        workflow=(root/'.github/workflows/phase23-native-callbacks.yml').read_text()
        self.assertIn("contains(github.event.head_commit.message, '[run-callbacks]')",workflow)
        self.assertIn('--target lib/phase23_native_callback_main.dart',workflow)
        self.assertIn('--dart-define=AQER_PHASE23_CALLBACK_HARNESS=true',workflow)

    def test_acceptance_requires_all_completions_after_normal_replacement_and_clean_scopes(self):
        v={k:0 for k in FIELDS}
        v.update(v=1,actor=2,bLogin=4,bSeed=5,bEpoch=3,aiCapture=1,resultsCapture=2,gpsCapture=3,aiEpoch=1,resultsEpoch=1,gpsEpoch=1,aiRelease=6,aiComplete=7,resultsRelease=8,resultsComplete=9,gpsRelease=10,gpsComplete=11,cancelled=1,cacheClean=1)
        label=lambda x:'CB-META:'+json.dumps(x)
        self.assertTrue(completed_callback_proof(label(v)))
        for changes in [{'aiComplete':3},{'gpsRelease':4},{'resultsEpoch':3},{'errors':1},{'forbidden':1},{'writes':1},{'cacheClean':0},{'cancelled':0},{'actor':1}]:
            self.assertFalse(completed_callback_proof(label(dict(v,**changes))))

    def test_callback_executor_cannot_delete_accounts_or_create_fixtures(self):
        for op,args in [('tap',{'label':'حذف الحساب نهائيًا'}),('tap',{'label':'حذف الحساب'}),('tap',{'label':'حفظ المسودة'}),('tap',{'label':'قراءة الكل'}),('set',{'label':'حذف حسابي نهائيًا','value':'حذف حسابي نهائيًا'}),('fixture_contact',{}),('send_synthetic_message',{}),('login',{'alias':'admin'}),('api_get',{'alias':'erasure','path':'/admin/users'})]:
            command={'op':op,'args':args}
            self.assertFalse(read_only_callback_command(command))
            self.assertFalse(read_only_callback_command({'op':'batch','args':{'steps':[command]}}))
        for op,args in [('login',{'alias':'erasure'}),('logout_in_place',{}),('tap',{'label':'CB release GPS'}),('api_get',{'alias':'regular','path':'/auth/me'}),('finish',{})]:
            self.assertTrue(read_only_callback_command({'op':op,'args':args}))
