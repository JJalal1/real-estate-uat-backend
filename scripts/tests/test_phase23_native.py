import copy
import sys
from pathlib import Path
import unittest
import tempfile
import subprocess
import shutil
from unittest.mock import Mock
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
from run_phase23_native import validate_command, GateError
from run_phase23_native import NativeRun
from run_phase23_native import Phase23Account
from phase23_checkpoint_state import advance_checkpoint
from probe_phase1_native_account import NativeAccount


class CommandSafetyTest(unittest.TestCase):
    def setUp(self):
        self.command = {'run_id': '1234', 'seq': 1, 'challenge': 'a' * 64, 'op': 'observe', 'args': {}}

    def test_stale_or_cross_run_commands_cannot_execute(self):
        for field, bad in [('run_id', '1235'), ('seq', 0), ('challenge', 'b' * 64)]:
            value = copy.deepcopy(self.command)
            value[field] = bad
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)

    def test_credentials_and_arbitrary_operations_cannot_enter_commands(self):
        for op, args in [('shell', {}), ('set', {'label': 'رمز التحقق', 'value': 'example'}),
                         ('login', {'alias': 'broker', 'otp': 'example'})]:
            value = dict(self.command, op=op, args=args)
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)

    def test_coordinate_boundary_is_checked_before_native_input(self):
        for x in [-1, 1080, True]:
            value = dict(self.command, op='touch', args={'x': x, 'y': 200})
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)
        self.assertEqual(validate_command(dict(self.command, op='touch', args={'x': 500, 'y': 800}), '1234', 1, 'a' * 64)['op'], 'touch')

    def test_fresh_picker_directory_is_prepared_before_any_fixture_write(self):
        class Device:
            ready = False
            directory = False
            writes = []
            def require_preauth_runtime(self): self.ready = True
            def adb(self, *args, **kwargs):
                if args[:2] == ('shell', 'mkdir'):
                    self.directory = True
                if args[0] == 'push':
                    if not self.ready or not self.directory:
                        raise RuntimeError('fresh Download directory is not ready')
                    self.writes.append(args[-1])
                return ''
        with tempfile.TemporaryDirectory() as folder:
            private = Path(folder)
            for name in ['phase23-property.jpg', 'phase23-rotated-exif.jpg', 'phase23-unsuitable.jpg', 'phase23-large.jpg']:
                (private / name).write_bytes(b'synthetic test bytes')
            run = object.__new__(NativeRun)
            run.driver = Device()
            with patch('run_phase23_native.PRIVATE', private):
                receipt = run.seed_media()
            self.assertEqual(len(receipt['files']), 4)
            self.assertEqual(len(run.driver.writes), 4)
            self.assertTrue(all(p.startswith('/sdcard/Download/phase23-') for p in run.driver.writes))

    def test_video_recorder_cannot_consume_supervisor_acknowledgements(self):
        driver = object.__new__(NativeAccount)
        driver.safe_capture = Mock()
        driver.recorder = None
        driver.serial = 'emulator-5554'
        with patch('probe_phase1_native_account.subprocess.Popen') as launch:
            driver.record_start('C1-phase23-regression')
            self.assertEqual(launch.call_args.kwargs['stdin'], subprocess.DEVNULL)
            self.assertEqual(launch.call_args.kwargs['stdout'], subprocess.DEVNULL)

    def test_field_entry_without_ime_does_not_navigate_back(self):
        driver = object.__new__(Phase23Account)
        driver.act, driver.field, driver.adb = Mock(), Mock(), Mock(return_value='mInputShown=false')
        driver.set('عنوان الإعلان *', 'synthetic')
        driver.adb.assert_called_once_with('shell', 'dumpsys', 'input_method')
        driver.adb.reset_mock()
        driver.adb.return_value = 'mInputShown=true'
        driver.set('عنوان الإعلان *', 'synthetic')
        self.assertEqual(driver.adb.call_args.args, ('shell', 'input', 'keyevent', '4'))

    def test_support_and_manager_shells_do_not_require_broker_navigation(self):
        driver = object.__new__(Phase23Account)
        for names in [('لوحة الدعم','الوارد','مهامي','الرسائل','حسابي'),
                      ('لوحة الفريق','الأعمال','الفريق','الرسائل','حسابي')]:
            rows = [{'path':'0.'+str(i),'witness':str(i)*64,'bounds':[i*100,1600,(i+1)*100,1700],
                     'package':'com.aqer.yemen.uat','visible':True,'enabled':True,'text':name}
                    for i,name in enumerate(names)]
            self.assertIsNotNone(driver.startup_home_binding(rows))
            rows.append(dict(rows[0], path='0.9', text='رمز التحقق'))
            self.assertIsNone(driver.startup_home_binding(rows))

    def test_large_scroll_container_stays_above_app_navigation(self):
        driver = object.__new__(Phase23Account)
        rows = [{'path':'0','package':'com.aqer.yemen.uat','bounds':[0,50,1080,1860]},
                {'path':'0.1','witness':'a'*64,'bounds':[-100,-500,1400,4000],
                 'scrollable':True,'enabled':True},
                {'path':'0.2','text':'حسابي','bounds':[700,1700,850,1800]}]
        driver.nodes,driver.adb=Mock(return_value=rows),Mock()
        with patch('run_phase23_native.time.sleep'):
            driver.scroll()
        args=driver.adb.call_args.args
        self.assertEqual(args[:3],('shell','input','swipe'))
        self.assertTrue(0<args[3]<1080 and 50<args[4]<1700 and 50<args[6]<1700)
        driver.adb.reset_mock()
        driver.nodes.side_effect=[rows,[dict(rows[1],witness='b'*64)]]
        with self.assertRaisesRegex(Exception,'native_scroll_witness_changed'):
            driver.scroll()
        driver.adb.assert_not_called()

    def test_logout_accepts_observed_guest_account_without_repeating_logout(self):
        run=object.__new__(NativeRun)
        run.driver=Mock(recorder=None)
        run.driver.has.return_value=True
        result=run.logout()
        run.driver.wait_account_logout_control.assert_not_called()
        run.driver.wait_guest_boundary.assert_called_once()
        self.assertTrue(result['native_logout_observed'])
        self.assertIsNone(run.actor)

    def test_stale_checkpoint_cannot_roll_control_state_back(self):
        state={'activeNativeRun':1234,'current_seq':10,'current_challenge':'a'*64}
        ob={'run_id':'1234','source_sha':'c'*40,'seq':9,'challenge':'b'*64,'apk':{}}
        with self.assertRaisesRegex(ValueError,'rollback'):
            advance_checkpoint(state,ob,run_id=1234,source_sha='c'*40)
        ob['seq']=11
        updated=advance_checkpoint(state,ob,run_id=1234,source_sha='c'*40)
        self.assertEqual(updated['current_seq'],11)
        self.assertEqual(state['current_seq'],10)
        with self.assertRaisesRegex(ValueError,'foreign'):
            advance_checkpoint(state,ob,run_id=1235,source_sha='c'*40)

    def test_multiphoto_gesture_requires_exact_current_visible_counter(self):
        driver=object.__new__(Phase23Account)
        rows=[{'package':'com.aqer.yemen.uat','visible':True,'text':'صورة العقار 2 من 3','bounds':[0,0,1080,1920]},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'2/3'},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'إغلاق الصور'}]
        driver.nodes=Mock(return_value=rows);driver.instrument=Mock()
        driver.gesture('pinch-out',540,960)
        driver.instrument.assert_called_once_with('pinch-out',x=540,y=960,phase23_surface='gallery',gallery_index=2,gallery_count=3)
        driver.instrument.reset_mock();rows[1]['text']='1/3'
        with self.assertRaisesRegex(Exception,'counter'):
            driver.gesture('pinch-out',540,960)
        driver.instrument.assert_not_called()
        rows[1]['text']='2/3';rows.append({'text':'رمز التحقق'})
        with self.assertRaisesRegex(Exception,'authentication'):
            driver.gesture('pinch-out',540,960)
        driver.instrument.assert_not_called()

    def test_map_gesture_cannot_hit_the_filter_panel(self):
        driver=object.__new__(Phase23Account)
        rows=[{'package':'com.aqer.yemen.uat','visible':True,'text':'البحث على الخريطة'},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'Showing a Map created with MapLibre. Scroll by dragging two fingers. Zoom by pinching two fingers.','bounds':[0,210,1080,1920]},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'اسحب لتوسيع الفلاتر والعقارات أو تصغيرها','bounds':[0,980,1080,1920]}]
        driver.nodes=Mock(return_value=rows);driver.instrument=Mock()
        with self.assertRaisesRegex(Exception,'outside'):
            driver.gesture('pinch-out',540,1200)
        driver.instrument.assert_not_called()
        driver.gesture('pinch-out',540,600)
        self.assertEqual(driver.instrument.call_args.kwargs['phase23_surface'],'map')

    def test_guest_home_requires_a_followup_guest_account_observation(self):
        driver=object.__new__(Phase23Account)
        names=['العقارات','الرسائل','إعلاناتي','حسابي','ماذا تبحث عنه؟','ابحث عن عقار أو منطقة…']
        driver.nodes=Mock(return_value=[{'text':n,'enabled':True} for n in names])
        driver.tap=Mock();driver.wait_guest_account=Mock()
        driver.wait_guest_boundary(seconds=2)
        driver.tap.assert_called_once_with('حسابي')
        driver.wait_guest_account.assert_called_once()

    def test_device_controls_and_link_are_fixed_and_bounded(self):
        for op,args in [('network',{'state':'arbitrary'}),('display',{'mode':'huge'}),
                        ('open_link',{'uri':'realestate://app/properties/107'}),
                        ('open_link',{'uri':'https://example.com'}),('wait',{'label':'x','seconds':31})]:
            with self.assertRaises(GateError):
                validate_command(dict(self.command,op=op,args=args),'1234',1,'a'*64)
        for op,args in [('network',{'state':'offline'}),('display',{'mode':'compact_large'}),
                        ('open_link',{'uri':'realestate://app/properties/106'}),('wait',{'label':'x','seconds':20})]:
            self.assertEqual(validate_command(dict(self.command,op=op,args=args),'1234',1,'a'*64)['op'],op)

    def test_cleanup_restores_the_disposable_device_before_session_logout(self):
        run=object.__new__(NativeRun);run.network_changed=True;run.display_changed=True
        run.driver=Mock();run.sessions={};run.actor=None;run.native_auth_attempted=False
        run.report={'cleanup':{}};run.access={};run.apply=Mock()
        run.cleanup()
        self.assertEqual([x.args[0]['op'] for x in run.apply.call_args_list],['network','display'])
        self.assertTrue(run.report['cleanup']['network_restored'])
        self.assertTrue(run.report['cleanup']['display_restored'])

    def test_reviewed_tap_does_not_scroll_unrelated_screens_for_a_missing_control(self):
        run=object.__new__(NativeRun);run.driver=Mock(recorder=None)
        run.apply({'op':'tap','args':{'label':'تنفيذ'}})
        run.driver.tap.assert_called_once_with('تنفيذ',seek=False)

    def test_private_conversation_exports_only_fixed_controls_and_no_frame_content(self):
        rows=[{'description':'خيارات المحادثة','bounds':[0,0,100,100]},
              {'description':'A participant name'}, {'text':'A private message'},
              {'text':'A typed draft','hint':'اكتب رسالة...','editable':True,'bounds':[0,100,100,200]}]
        controls,protected=NativeRun.private_ui_controls(rows)
        self.assertTrue(protected)
        self.assertEqual({r['description'] for r in controls},{'خيارات المحادثة','اكتب رسالة...'})
        self.assertNotIn('private message',str(controls))
        self.assertNotIn('participant',str(controls))
        self.assertNotIn('typed draft',str(controls))
        self.assertEqual(NativeRun.private_ui_controls([{'description':'تفاصيل العقار'}])[1],False)
        run=object.__new__(NativeRun);run.private_values=set()
        run.driver=Mock(recorder=None);run.driver.nodes.return_value=rows
        exported,frame,protected=run.observe()
        self.assertTrue(protected);self.assertIsNone(frame)
        run.driver.adb.assert_not_called()
        self.assertNotIn('private message',str(exported))
        self.assertNotIn('participant',str(exported))
        account=[{'description':'شوهد مؤخرًا'},{'description':'A real user name'},
                 {'text':'private@example.invalid'},{'description':'المظهر'}]
        controls,protected=NativeRun.private_ui_controls(account)
        self.assertTrue(protected)
        self.assertEqual({r['description'] for r in controls},{'شوهد مؤخرًا','المظهر'})
        self.assertNotIn('real user',str(controls));self.assertNotIn('@',str(controls))

    def test_private_backdrop_remains_protected_through_modal_and_popup_until_public_home(self):
        run=object.__new__(NativeRun);run.private_values=set();run.seq=5
        account=[{'description':'شوهد مؤخرًا'}, {'text':'private@example.invalid'}]
        modal=[{'description':'تفاصيل العقار'}, {'text':'public property106'}]
        popup=[{'description':'أخرى'}, {'text':'hidden private backdrop'}]
        home=[{'description':name} for name in (
            'ماذا تبحث عنه؟','ابحث عن عقار أو منطقة…','العقارات','حسابي')]
        run.driver=Mock(recorder=None)
        run.driver.nodes.side_effect=[account,modal,popup,home]
        run.driver.adb.return_value=b'\x89PNG\r\n\x1a\nfixture'
        with tempfile.TemporaryDirectory() as folder:
            run.root=Path(folder)
            for expected in ({'شوهد مؤخرًا'},set(),{'أخرى'}):
                controls,frame,protected=run.observe()
                self.assertTrue(protected);self.assertIsNone(frame)
                self.assertEqual({r['description'] for r in controls},expected)
                run.driver.adb.assert_not_called()
            controls,frame,protected=run.observe()
            self.assertFalse(protected);self.assertTrue(frame.is_file())
            run.driver.adb.assert_called_once_with('exec-out','screencap','-p',binary=True)
            self.assertFalse(run.private_surface_open)

    def test_synthetic_thread_read_exports_only_bound_metadata(self):
        body={'data':{'thread':{'id':37,'property_id':106,'other_user':{'id':28,'name':'private'},
                              'can_send':True,'blocked_by_me':False,'last_message_preview':'secret'},
                      'messages':[{'body':'secret','sender_name':'private'}]}}
        out=NativeRun.synthetic_thread_metadata(body)
        self.assertEqual(out['data']['message_count_on_page'],1)
        self.assertNotIn('secret',str(out));self.assertNotIn('private',str(out))
        body['data']['thread']['id']=38
        with self.assertRaisesRegex(GateError,'identity'):
            NativeRun.synthetic_thread_metadata(body)

    def test_private_index_cannot_be_fetched_or_recorded(self):
        run=object.__new__(NativeRun);run.access={'phones':{'regular':'not-a-credential'}}
        run.actor='regular';run.driver=Mock(recorder=None);run.observe=Mock(return_value=([],None,True))
        with patch('run_phase23_native.http') as request:
            with self.assertRaisesRegex(GateError,'export_refused'):
                run.apply({'op':'api_get','args':{'alias':'regular','path':'/messages/threads'}})
            request.assert_not_called()
        with self.assertRaisesRegex(GateError,'private_surface'):
            run.apply({'op':'record_start','args':{}})
        run.driver.record_start.assert_not_called()

    def test_fixed_closed_drawing_requires_the_fresh_default_canvas(self):
        driver=object.__new__(Phase23Account)
        rows=[{'path':'0','package':'com.aqer.yemen.uat','visible':True,'bounds':[0,0,1080,1920]},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'البحث على الخريطة'},
              {'package':'com.aqer.yemen.uat','visible':True,'text':driver.DRAWING_INSTRUCTION},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'Showing a Map created with MapLibre. Scroll by dragging two fingers. Zoom by pinching two fingers.'},
              {'package':'com.aqer.yemen.uat','visible':True,'text':'إلغاء','bounds':[713,1651,1033,1787]}]
        driver.nodes=Mock(return_value=rows);driver.instrument=Mock()
        driver.draw_area()
        driver.instrument.assert_called_once_with('phase23-draw-area',phase23_surface='drawing')
        driver.instrument.reset_mock();rows[0]['bounds']=[0,0,840,1493]
        with self.assertRaisesRegex(Exception,'drawing_surface'):
            driver.draw_area()
        driver.instrument.assert_not_called()
        rows[0]['bounds']=[0,0,1080,1920];rows[2]['text']='ordinary map'
        with self.assertRaisesRegex(Exception,'drawing_surface'):
            driver.draw_area()
        driver.instrument.assert_not_called()
        rows[2]['text']=driver.DRAWING_INSTRUCTION;rows.append({'text':'رمز التحقق'})
        with self.assertRaisesRegex(Exception,'authentication'):
            driver.draw_area()
        driver.instrument.assert_not_called()
        with self.assertRaises(GateError):
            validate_command(dict(self.command,op='draw_area',args={'points':[[1,2]]}),'1234',1,'a'*64)

    def test_input_failure_receipt_contains_no_arbitrary_output_or_field_values(self):
        driver=object.__new__(Phase23Account)
        driver.c4_prepare_input_failure('pinch-out',{'stage':'root_ready','events':'0','passed':'false',
            'foreground_category':'APP','private_body':'not for export'},'arbitrary private stdout','native_input_not_delivered')
        self.assertEqual(driver.phase23_last_input_failure['events'],0)
        self.assertEqual(driver.phase23_last_input_failure['java_stage'],'root_ready')
        self.assertNotIn('private',str(driver.phase23_last_input_failure))

    def test_negative_message_probe_refuses_unblocked_or_foreign_fixture_before_a_write(self):
        run=object.__new__(NativeRun);run.sessions={'regular':Mock(token='synthetic-local-test')}
        body={'data':{'thread':{'id':37,'property_id':106,'can_send':True,'other_user':{'id':28}},'messages':[]}}
        with patch('run_phase23_native.http',return_value=(200,body)) as request:
            with self.assertRaisesRegex(GateError,'observed_block'):
                run.blocked_message_probe('regular')
            self.assertEqual(request.call_count,1)
        body['data']['thread'].update(id=38,can_send=False)
        with patch('run_phase23_native.http',return_value=(200,body)) as request:
            with self.assertRaisesRegex(GateError,'identity'):
                run.blocked_message_probe('regular')
            self.assertEqual(request.call_count,1)

    def test_negative_message_probe_is_fixed_to_the_synthetic_pair_and_omits_content(self):
        run=object.__new__(NativeRun);run.sessions={'regular':Mock(token='synthetic-local-test')}
        body={'data':{'thread':{'id':37,'property_id':106,'can_send':False,'other_user':{'id':28}},
                      'messages':[{'body':'not for export'}]}}
        public={'data':{'id':33,'status':'published','advertiser':{'id':28}}}
        with patch('run_phase23_native.http',side_effect=[(200,body),(403,{'private':'not for export'}),(200,public),(403,{})]) as request:
            out=run.blocked_message_probe('regular')
            self.assertTrue(out['rejected']);self.assertTrue(out['other_property_start']['rejected'])
            self.assertNotIn('not for export',str(out))
            self.assertEqual([(x.args[0],x.args[1]) for x in request.call_args_list],
                [('GET','/messages/threads/37'),('POST','/messages/threads/37/messages'),
                 ('GET','/properties/33'),('POST','/properties/33/conversation')])
        with self.assertRaises(GateError):
            validate_command(dict(self.command,op='blocked_message_probe',args={'alias':'support'}),'1234',1,'a'*64)

    def test_synthetic_send_preserves_existing_messages_and_unsent_text(self):
        run=object.__new__(NativeRun);run.actor='broker'
        with self.assertRaisesRegex(GateError,'regular_native_actor'):
            run.send_synthetic_message()
        run.actor='regular';run.sessions={'regular':Mock(token='synthetic-local-test')};run.driver=Mock()
        body={'data':{'thread':{'id':37,'property_id':106,'can_send':True,'other_user':{'id':28}},'messages':[{}]}}
        with patch('run_phase23_native.http',return_value=(200,body)):
            with self.assertRaisesRegex(GateError,'empty_unblocked'):
                run.send_synthetic_message()
        run.driver.adb.assert_not_called()
        body['data']['messages']=[];run.driver.field.return_value={'text':'existing unsent private text'}
        with patch('run_phase23_native.http',return_value=(200,body)):
            with self.assertRaisesRegex(GateError,'unsent_draft_preserved'):
                run.send_synthetic_message()
        run.driver.set.assert_not_called();run.driver.act.assert_not_called()
        with self.assertRaises(GateError):
            validate_command(dict(self.command,op='send_synthetic_message',args={'body':'arbitrary'}),'1234',1,'a'*64)

    def test_synthetic_send_clicks_only_the_witnessed_composer_and_returns_no_body(self):
        run=object.__new__(NativeRun);run.actor='regular';run.sessions={'regular':Mock(token='synthetic-local-test')};run.driver=Mock()
        message='رسالة اختبار اصطناعية للمرحلة23 على الإعلان106؛ ليست استفسارًا حقيقيًا.'
        run.driver.field.return_value={'text':''}
        button={'class':'android.widget.Button','clickable':True,'enabled':True,'bounds':[26,1672,152,1798],'path':'0.9','witness':'a'*64}
        run.driver.nodes.return_value=[{'path':'0','bounds':[0,0,1080,1920]},
            {'editable':True,'text':message},{'text':'خيارات المحادثة'},button]
        thread={'id':37,'property_id':106,'can_send':True,'other_user':{'id':28}}
        before={'data':{'thread':thread,'messages':[]}}
        after={'data':{'thread':thread,'messages':[{'sender_user_id':26,'body':message}]}}
        with patch('run_phase23_native.http',side_effect=[(200,before),(200,after)]) as request:
            out=run.send_synthetic_message()
            self.assertTrue(out['normal_native_send_observed']);self.assertEqual(out['after_count'],1)
            self.assertNotIn(message,str(out));self.assertNotIn('body',str(out).replace('private_body_exported',''))
            self.assertTrue(all(x.args[0]=='GET' for x in request.call_args_list))
        run.driver.act.assert_called_once_with('click',button)

    @unittest.skipUnless(shutil.which('javac') and shutil.which('java'),'JDK17 required; available explicitly in collector CI')
    def test_actual_java_visible_label_gate_accepts_tooltips_and_rejects_hidden_foreign_nodes(self):
        source=(Path(__file__).parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        def method(signature):
            start=source.index(signature);brace=source.index('{',start);depth=1;end=brace+1
            while depth:
                depth+=(source[end]=='{')-(source[end]=='}');end+=1
            return source[start:end]
        methods='\n'.join(method(s) for s in ['private static String plain(',
            'private static String accessibleDescription(','private static boolean containsVisible('])
        fixture='''
import java.util.*;
public class LabelGateProbe {
static final String APP="com.aqer.yemen.uat";
static class AccessibilityNodeInfo {
 String p=APP,t="",d="",tip="";boolean v=true;List<AccessibilityNodeInfo> children=new ArrayList<>();
 boolean isVisibleToUser(){return v;} CharSequence getPackageName(){return p;}
 CharSequence getText(){return t;} CharSequence getContentDescription(){return d;}
 CharSequence getTooltipText(){return tip;} int getChildCount(){return children.size();}
 AccessibilityNodeInfo getChild(int i){return children.get(i);}
}
METHODS
public static void main(String[] args){
 AccessibilityNodeInfo n=new AccessibilityNodeInfo();n.tip="إغلاق الصور";
 if(!containsVisible(n,"إغلاق الصور"))throw new AssertionError("visible tooltip");
 n.v=false;if(containsVisible(n,"إغلاق الصور"))throw new AssertionError("hidden");
 n.v=true;n.p="other.app";if(containsVisible(n,"إغلاق الصور"))throw new AssertionError("foreign");
 n.p=APP;n.tip="إغلاق الصور لاحقًا";if(containsVisible(n,"إغلاق الصور"))throw new AssertionError("exact");
 AccessibilityNodeInfo root=new AccessibilityNodeInfo();n.tip="إغلاق الصور";root.children.add(n);
 if(!containsVisible(root,"إغلاق الصور"))throw new AssertionError("nested");
}
}'''.replace('METHODS',methods)
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'LabelGateProbe.java';p.write_text(fixture)
            subprocess.run(['javac','-encoding','UTF-8',str(p)],check=True,capture_output=True)
            subprocess.run(['java','-cp',folder,'LabelGateProbe'],check=True,capture_output=True)


if __name__ == '__main__': unittest.main()
