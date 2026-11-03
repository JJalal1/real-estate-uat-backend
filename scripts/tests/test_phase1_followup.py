import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import prepare_phase1_followup as prepare
from probe_phase1_followup import input_receipt, input_failure_diagnostic, photo_difference, visible_map_handle, Blocked, Followup


def context():
    return dict(GITHUB_REPOSITORY='JJalal1/real-estate-uat-backend',GITHUB_REF=prepare.REF,
        GITHUB_EVENT_NAME='push',AQER_PHASE1_FOLLOWUP='true',GITHUB_SHA='a'*40,
        SOURCE_COMMIT='a'*40,GITHUB_RUN_ID='12345',GITHUB_RUN_NUMBER='1')


def gesture(**replace):
    values=dict(passed='true',op='double-tap',events='4',inter_tap_ms='82',
        inter_tap_lower_ms='80',inter_tap_upper_ms='85',event_ms='0,35,117,152',return_ms='1,37,120,153')
    values.update(replace)
    return '\n'.join('INSTRUMENTATION_RESULT: '+k+'='+v for k,v in values.items())+'\nINSTRUMENTATION_CODE: -1\n'


class FollowupTests(unittest.TestCase):
    def test_explicit_branch_context_and_independent_version(self):
        self.assertEqual(prepare.guard(context()),1458)
        for key,value in [('AQER_PHASE1_FOLLOWUP','false'),('GITHUB_REF',prepare.REF+'-other'),
                          ('GITHUB_REPOSITORY','other/repo'),('SOURCE_COMMIT','b'*40),
                          ('GITHUB_RUN_ID',''),('GITHUB_EVENT_NAME','pull_request')]:
            env=context();env[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError): prepare.guard(env)

    def test_product_component_change_refuses_before_build(self):
        calls=[]
        def fake(argv):
            calls.append(argv)
            if argv[1]=='diff': return ''
            if argv[-1]=='HEAD': return 'a'*40
            return 'old' if argv[-1].startswith(prepare.BASE) else 'changed'
        with patch.object(prepare,'run',fake),self.assertRaisesRegex(RuntimeError,'product_component_changed'):
            prepare.source_receipt(context())
        self.assertTrue(any(c[1]=='diff' for c in calls))

    def test_doubletap_requires_delivery_bounds_not_just_invocation(self):
        receipt=input_receipt(gesture(),'double-tap')
        self.assertEqual(receipt['events'],4)
        self.assertEqual(receipt['inter_tap_lower_ms'],80)
        for values in [dict(inter_tap_ms='0'),dict(inter_tap_lower_ms='39'),
                       dict(inter_tap_upper_ms='301'),dict(events='3'),
                       dict(return_ms='0,34,120,153'),dict(event_ms='0,35,117')]:
            with self.subTest(values=values),self.assertRaises(Blocked): input_receipt(gesture(**values),'double-tap')

    def test_duplicate_receipts_and_unexpected_op_refused(self):
        with self.assertRaises(Blocked): input_receipt(gesture()+'INSTRUMENTATION_RESULT: passed=true\n','double-tap')
        with self.assertRaises(Blocked): input_receipt(gesture(),'pinch-in')

    def test_query_receipt_requires_focused_flutter_handler(self):
        raw='INSTRUMENTATION_RESULT: passed=true\nINSTRUMENTATION_RESULT: op=fixture-query\nINSTRUMENTATION_RESULT: text_matched=true\n'
        with self.assertRaises(Blocked): input_receipt(raw+'INSTRUMENTATION_CODE: -1\n','fixture-query')
        good=raw+'INSTRUMENTATION_RESULT: focused_set_text_handler=true\nINSTRUMENTATION_CODE: -1\n'
        self.assertTrue(input_receipt(good,'fixture-query')['focused_set_text_handler'])

    def test_semantic_submit_receipt_requires_actual_click(self):
        raw='INSTRUMENTATION_RESULT: passed=true\nINSTRUMENTATION_RESULT: op=submit-query\n'
        with self.assertRaises(Blocked): input_receipt(raw+'INSTRUMENTATION_CODE: -1\n','submit-query')
        self.assertTrue(input_receipt(raw+'INSTRUMENTATION_RESULT: semantic_click_delivered=true\nINSTRUMENTATION_CODE: -1\n','submit-query')['semantic_click_delivered'])

    def test_arbitrary_output_never_enters_receipt(self):
        raw=gesture()+'secret-echo=DO_NOT_EXPORT\nINSTRUMENTATION_RESULT: unknown=DO_NOT_EXPORT\n'
        self.assertNotIn('DO_NOT_EXPORT',json.dumps(input_receipt(raw,'double-tap')))

    def test_failed_input_retains_only_bounded_diagnostics(self):
        raw='INSTRUMENTATION_RESULT: stage=double_tap\nINSTRUMENTATION_RESULT: events=4\nINSTRUMENTATION_RESULT: event_ms=0,35,400,435\nINSTRUMENTATION_RESULT: return_ms=1,36,401,436\nsecret=DO_NOT_EXPORT\n'
        self.assertEqual(input_failure_diagnostic(raw)['events'],4)
        self.assertNotIn('DO_NOT_EXPORT',json.dumps(input_failure_diagnostic(raw)))
        self.assertEqual(input_failure_diagnostic('INSTRUMENTATION_RESULT: stage=DO_NOT_EXPORT\nINSTRUMENTATION_RESULT: events=100000\n'),{})

    def test_emulator_block_removed_even_when_input_fails(self):
        probe=object.__new__(Followup);probe.report={};probe.serial='emulator-5554'
        probe.home=lambda:None;probe.home_entry=lambda _:None;probe.wait=lambda *a:None;probe.save=lambda:None
        calls=[];probe.adb=lambda *args,**kwargs:calls.append(args) or ''
        probe.run=lambda argv:type('Result',(),{'returncode':1})()
        def refuse(*args): raise Blocked('injected_test_failure')
        probe.native=refuse
        with self.assertRaises(Blocked): probe.timeout_recovery()
        self.assertEqual([call[1] for call in calls if '-D' in call],['ip6tables','iptables'])
        self.assertTrue(probe.report['network_fault']['block_removed'])

    def test_photo_analysis_excludes_counter_changes(self):
        from PIL import Image,ImageDraw
        with tempfile.TemporaryDirectory() as directory:
            first,second=Path(directory)/'a.png',Path(directory)/'b.png'
            a=Image.new('RGB',(1080,1920),(80,70,60));a.save(first)
            ImageDraw.Draw(a).rectangle((0,0,1080,300),fill='white');a.save(second)
            self.assertEqual(photo_difference(first,second)['changed_fraction'],0)
            ImageDraw.Draw(a).rectangle((216,720,864,1200),fill='white');a.save(second)
            self.assertGreater(photo_difference(first,second)['changed_fraction'],.99)

    def test_visible_handle_rejects_ambiguous_and_wrong_geometry(self):
        from PIL import Image,ImageDraw
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'geometry.png'
            im=Image.new('RGB',(1080,1920),'white');draw=ImageDraw.Draw(im)
            draw.rounded_rectangle((485,633,595,643),radius=5,fill=(227,234,241));im.save(path)
            self.assertEqual(visible_map_handle(path),[485,633,596,644])
            draw.rounded_rectangle((485,1233,595,1243),radius=5,fill=(227,234,241));im.save(path)
            with self.assertRaises(Blocked): visible_map_handle(path)
            Image.new('RGB',(540,960),'white').save(path)
            with self.assertRaises(Blocked): visible_map_handle(path)


if __name__=='__main__': unittest.main()
