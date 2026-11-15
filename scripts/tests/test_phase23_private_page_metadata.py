import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, call
sys.path.insert(0, str(Path(__file__).parents[1]))
from phase23_private_page_metadata import (META, EVENT, safe_private_page_label,
    private_page_events, read_only_private_page_command)
from run_phase23_native import NativeRun, Phase23Account, validate_command

class PrivatePageSafety(unittest.TestCase):
    def test_closed_numeric_schema_and_no_arbitrary_private_labels(self):
        meta={k:0 for k in META};meta.update(v=1,actor=2)
        self.assertIsNotNone(safe_private_page_label('PC-META:'+json.dumps(meta)))
        for changes in [{'secret':'PRIVATE'},{'v':2},{'actor':66},{'errors':False},{'epoch':-1}]:
            self.assertIsNone(safe_private_page_label('PC-META:'+json.dumps(dict(meta,**changes))))
        self.assertIsNone(safe_private_page_label('PRIVATE PERSON'))
        event={k:0 for k in EVENT};event.update(seq=1,actor=2,surface=2,page=1,phase=2)
        self.assertEqual(private_page_events('flutter AQER_PRIVATE:'+json.dumps(event)),[event])
        known=dict(event,totalKnown=1,total=2)
        self.assertEqual(private_page_events('AQER_PRIVATE:'+json.dumps(known)),[known])
        for change in [{'body':'PRIVATE'},{'actor':66},{'phase':9},{'count':True},
                       {'totalKnown':2},{'totalKnown':True},{'totalKnown':-1}]:
            self.assertEqual(private_page_events('AQER_PRIVATE:'+json.dumps(dict(event,**change))),[])
        missing=dict(event)
        del missing['totalKnown']
        self.assertEqual(private_page_events('AQER_PRIVATE:'+json.dumps(missing)),[event])
        missing['total']=2
        self.assertEqual(private_page_events('AQER_PRIVATE:'+json.dumps(missing)),
                         [dict(event,total=2,totalKnown=0)])

    def test_read_only_target_allows_only_real_bounded_emulator_network_profiles(self):
        run=object.__new__(NativeRun)
        run.private_pages=True
        run.driver=Mock(recorder=None)
        for mode in ('slow','normal'):
            command={'run_id':'1234','seq':1,'challenge':'a'*64,
                     'op':'network_profile','args':{'mode':mode}}
            self.assertTrue(read_only_private_page_command(command))
            validated=validate_command(command,'1234',1,'a'*64)
            self.assertEqual(run.apply(validated)['mode'],mode)
        self.assertEqual(run.driver.adb.call_args_list,[
            call('emu','network','speed','gsm'),
            call('emu','network','delay','gprs'),
            call('shell','svc','data','enable'),
            call('shell','svc','wifi','disable'),
            call('emu','network','speed','full'),
            call('emu','network','delay','none'),
            call('shell','svc','data','enable'),
            call('shell','svc','wifi','enable'),
        ])
        self.assertFalse(run.network_profile_changed)
        for args in ({'mode':'full; arbitrary'},{'mode':'custom'},
                     {'mode':'slow','endpoint':'PRIVATE'},{}):
            self.assertFalse(read_only_private_page_command({'op':'network_profile','args':args}))

    def test_verified_target_only_exports_fixed_controls_and_never_pixels_or_content(self):
        rows=[{'text':'PC controls'},{'text':'PRIVATE PERSON'},{'text':'إعادة المحاولة'}]
        clean,protected=NativeRun.private_ui_controls(rows,private_pages=True)
        self.assertTrue(protected)
        self.assertNotIn('PRIVATE PERSON',str(clean))
        self.assertEqual({x['description'] for x in clean},{'PC controls','إعادة المحاولة'})
        clean,_=NativeRun.private_ui_controls(rows,force_private=True)
        self.assertNotIn('PC controls',str(clean))

    def test_deleted_actor_and_every_write_escape_are_refused_including_batches(self):
        for op,args in [('login',{'alias':'erasure'}),('set',{'label':'field','value':'x'}),
            ('api_get',{'alias':'admin','path':'/admin/users'}),('tap',{'label':'حذف الحساب'}),
            ('tap',{'label':'حفظ'}),('record_start',{}),('touch',{'x':10,'y':10})]:
            command={'op':op,'args':args}
            self.assertFalse(read_only_private_page_command(command))
            self.assertFalse(read_only_private_page_command({'op':'batch','args':{'steps':[command]}}))
        for op,args in [('login',{'alias':'advertiser'}),('tap',{'label':'PC listings'}),('private_metrics',{}),('finish',{})]:
            self.assertTrue(read_only_private_page_command({'op':op,'args':args}))
        self.assertEqual(validate_command({'run_id':'1234','seq':1,'challenge':'a'*64,'op':'private_metrics','args':{}},'1234',1,'a'*64)['op'],'private_metrics')

    def test_passive_static_label_wait_does_not_weaken_enabled_input_guard(self):
        driver=object.__new__(Phase23Account)
        row={'text':'لا توجد طلبات بهذه الفلاتر.','visible':True,'enabled':False}
        driver.nodes=Mock(return_value=[row])
        driver.wait(row['text'],seconds=1)
        self.assertEqual(driver.matching([row],row['text']),[])

    def test_product_entrypoint_is_independent_and_target_build_is_explicit(self):
        root=Path(__file__).parents[2]
        self.assertNotIn('phase23_private_pages_main',(root/'mobile_app/lib/main.dart').read_text())
        workflow=(root/'.github/workflows/phase23-native-private-pages.yml').read_text()
        self.assertIn("contains(github.event.head_commit.message, '[run-private-pages]')",workflow)
        self.assertIn('--target lib/phase23_private_pages_main.dart',workflow)
        self.assertIn('--dart-define=AQER_PHASE23_PRIVATE_PAGES=true',workflow)
