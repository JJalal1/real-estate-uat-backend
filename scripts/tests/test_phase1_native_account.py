"""Safety/control-flow tests only; no device, network or real account access."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import probe_phase1_native_account as native


class NativeAccountSafetyTest(unittest.TestCase):
    def test_fixed_mode_selected_before_account_input_dispatch(self):
        for op in ('account-click', 'account-set', 'account-scroll', 'account-snapshot', 'account-dismiss-ime'):
            receipt = ['INSTRUMENTATION_RESULT: passed=true',
                       'INSTRUMENTATION_RESULT: op=' + op, 'INSTRUMENTATION_CODE: -1']
            self.probe.adb = Mock(return_value='\n'.join(receipt))
            self.probe.instrument(op)
            argv = self.probe.adb.call_args.args
            if op in ('account-click', 'account-set'):
                index = argv.index('input_mode')
                self.assertEqual(argv[index + 1], 'physical_click_focus')
                self.assertEqual(argv.count('input_mode'), 1)
            elif op == 'account-scroll':
                index = argv.index('input_mode')
                self.assertEqual(argv[index + 1], 'physical_scroll')
                self.assertEqual(argv.count('input_mode'), 1)
            else:
                self.assertNotIn('input_mode', argv)
            self.probe.adb.assert_called_once()

    def test_caller_cannot_override_fixed_mode_before_any_dispatch(self):
        for value in ('semantic', 'physical_click_focus', 'physical_scroll', 'PRIVATE_SYNTHETIC_SENTINEL'):
            self.probe.adb = Mock()
            with self.assertRaisesRegex(native.Blocked, '^fixed_native_input_mode_required$'):
                self.probe.instrument('account-click', input_mode=value)
            self.probe.adb.assert_not_called()

    def test_failed_physical_call_is_not_replayed_or_recorded_as_delivered(self):
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: stage=account_pointer_tap',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.act('click', self.node('synthetic button', clickable=True))
        self.probe.adb.assert_called_once()
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['native_input_failures'][0]['java_stage'], 'account_pointer_tap')

    def test_selection_diagnostic_stage_retains_no_path_witness_or_value(self):
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: stage=pointer_bounds_containment',
            'INSTRUMENTATION_RESULT: foreground_category=APP',
            'INSTRUMENTATION_RESULT: node_witness=' + 'f' * 64,
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-click', node_path='0.999', node_witness='f' * 64)
        self.probe.adb.assert_called_once()
        row = self.probe.report['native_input_failures'][0]
        self.assertEqual(row['java_stage'], 'pointer_bounds_containment')
        self.assertNotIn('0.999', json.dumps(row))
        self.assertNotIn('f' * 64, json.dumps(row))
        self.assertEqual(self.probe.report['actions'], [])

    def test_failed_physical_scroll_is_never_replayed(self):
        self.probe.case_phase('C1-cleanup')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-scroll',
            'INSTRUMENTATION_RESULT: stage=account_pointer_swipe',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-scroll', node_path='0.1', node_witness='a' * 64)
        self.probe.adb.assert_called_once()
        self.assertEqual(self.probe.adb.call_args.args.count('physical_scroll'), 1)
        self.assertEqual(self.probe.report['actions'], [])

    def test_scroll_waits_readonly_for_observed_container_and_never_replays_dispatch(self):
        self.stability_clock()
        container=self.node('',path='0.8',scrollable=True)
        self.probe.nodes=Mock(side_effect=[[],[],[container]])
        self.probe.act=Mock()
        self.probe.scroll('backward')
        self.assertEqual(self.probe.nodes.call_count,3)
        self.probe.act.assert_called_once_with('scroll',container,direction='backward')
        self.probe.nodes=Mock(return_value=[container])
        self.probe.act=Mock(side_effect=native.Blocked('native_input_not_delivered'))
        with self.assertRaisesRegex(native.Blocked,'^native_input_not_delivered$'):
            self.probe.scroll()
        self.probe.nodes.assert_called_once();self.probe.act.assert_called_once()

    def test_missing_scroll_container_is_bounded_without_any_ui_dispatch_or_capture(self):
        clock=self.stability_clock()
        self.probe.nodes=Mock(return_value=[])
        self.probe.act,self.probe.safe_capture=Mock(),Mock()
        with self.assertRaisesRegex(native.Blocked,'^scrollable_native_container_missing$'):
            self.probe.scroll()
        self.assertLessEqual(clock[0],3)
        self.probe.act.assert_not_called();self.probe.safe_capture.assert_not_called()

    def test_java_snapshot_settling_is_bounded_readonly_and_reacquires_the_app_root(self):
        source=(Path(__file__).resolve().parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        block=source.split('if("account-snapshot".equals(op)) {',1)[1].split('AccessibilityNodeInfo node=selected(root);',1)[0]
        self.assertIn('waitForIdle(250,1500)',block)
        self.assertIn('catch(java.util.concurrent.TimeoutException busy)',block)
        self.assertLess(block.index('waitForIdle('),block.index('observed=readyRoot(op)'))
        self.assertIn('snapshot(observed,',block)
        for forbidden in ('checkedAction(', 'pointerTap(', 'send(', 'snapshot(root,'):
            self.assertNotIn(forbidden,block)

    def test_java_settle_precedes_original_set_target_binding_without_any_input(self):
        source=(Path(__file__).resolve().parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        block=source.split('if("account-set".equals(op)) {',1)[1].split('AccessibilityNodeInfo node=selected(root);',1)[0]
        self.assertIn('stage="account_set_settle"',block)
        self.assertIn('waitForIdle(250,1500)',block)
        self.assertIn('catch(java.util.concurrent.TimeoutException busy)',block)
        self.assertLess(block.index('waitForIdle('),block.index('root=readyRoot(op)'))
        for forbidden in ('pointerTap(', 'checkedAction(', 'send(', 'putBoolean('):
            self.assertNotIn(forbidden,block)

    def test_actual_java_pointer_focus_requires_same_source_and_stable_geometry_before_one_tap(self):
        source=(Path(__file__).resolve().parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        bounds='private Rect pointerBounds('+source.split('    private Rect pointerBounds(',1)[1].split('\n    private void pointerTap(',1)[0]
        tap='private void pointerTap('+source.split('    private void pointerTap(',1)[1].split('\n    private void pointerSwipe(',1)[0]
        selection=source.split('    private Selection selectedExpected(boolean pointerRecheck,long end)',1)[1].split('    private AccessibilityNodeInfo atPath(',1)[0]
        self.assertNotIn('uptimeMillis()+1000',selection)  # Caller owns the ONE absolute budget.
        harness=r"""public class FocusTargetStability {
          static final String APP="APP";
          static class SystemClock { static long now; static long uptimeMillis(){return now;} static void sleep(long ms){now+=ms;} }
          static class MotionEvent { static final int ACTION_DOWN=0,ACTION_UP=1; }
          static class Rect {
            int left,top,right,bottom;
            Rect(){} Rect(int l,int t,int r,int b){left=l;top=t;right=r;bottom=b;}
            int width(){return right-left;} int height(){return bottom-top;}
            boolean contains(Rect r){return left<=r.left && top<=r.top && right>=r.right && bottom>=r.bottom;}
            float exactCenterX(){return (left+right)/2f;} float exactCenterY(){return (top+bottom)/2f;}
            public boolean equals(Object o){if(!(o instanceof Rect))return false;Rect r=(Rect)o;return left==r.left&&top==r.top&&right==r.right&&bottom==r.bottom;}
            public String toString(){return left+","+top+","+right+","+bottom;}
          }
          static class AccessibilityNodeInfo {
            int id; String pkg=APP,label="target"; boolean editable=true; Rect bounds; AccessibilityNodeInfo child;
            AccessibilityNodeInfo(int id,Rect bounds){this.id=id;this.bounds=bounds;}
            void getBoundsInScreen(Rect r){r.left=bounds.left;r.top=bounds.top;r.right=bounds.right;r.bottom=bounds.bottom;}
            boolean isEditable(){return editable;} boolean isScrollable(){return true;} boolean isClickable(){return true;}
            String getClassName(){return "android.widget.EditText";} String getPackageName(){return pkg;}
            public boolean equals(Object o){return o instanceof AccessibilityNodeInfo && id==((AccessibilityNodeInfo)o).id;}
          }
          static class Args {
            java.util.Map<String,String> values=new java.util.HashMap<>();
            String getString(String key,String fallback){return values.getOrDefault(key,fallback);}
          }
          static class Selection { final AccessibilityNodeInfo root,node;Selection(AccessibilityNodeInfo r,AccessibilityNodeInfo n){root=r;node=n;} }
          class Automation {
            int clears; boolean ready=true; long readCost; AccessibilityNodeInfo root;
            boolean clearCache(){clears++;SystemClock.now+=readCost;return ready;}
            AccessibilityNodeInfo getRootInActiveWindow(){return root;}
          }
          Args args=new Args(); Automation automation=new Automation(); Selection first;
          String stage="guard",foreground="UNOBSERVED"; int events,selections; long firstReadCost,seenEnd;
          Selection selectedExpected(boolean recheck,long end){require(recheck);selections++;seenEnd=end;SystemClock.now+=firstReadCost;require(SystemClock.now<end);return first;}
          AccessibilityNodeInfo atPath(AccessibilityNodeInfo root,String path){require("0.1".equals(path));return root.child;}
          String witness(AccessibilityNodeInfo node){return node.label+"|"+node.bounds;}
          String foregroundCategory(CharSequence pkg){return pkg==null?"UNOBSERVED":pkg.toString();}
          static void require(boolean value){if(!value)throw new IllegalStateException();}
          void send(long down,int action,float[] x,float[] y){events++;}
          static FocusTargetStability scenario(){
            SystemClock.now=0;FocusTargetStability h=new FocusTargetStability();
            AccessibilityNodeInfo original=new AccessibilityNodeInfo(7,new Rect(10,100,200,180));
            AccessibilityNodeInfo firstRoot=new AccessibilityNodeInfo(1,new Rect(0,0,540,960));
            AccessibilityNodeInfo firstNode=new AccessibilityNodeInfo(7,new Rect(10,100,200,180));
            AccessibilityNodeInfo secondRoot=new AccessibilityNodeInfo(1,new Rect(0,0,540,960));
            secondRoot.child=new AccessibilityNodeInfo(7,new Rect(10,100,200,180));
            h.first=new Selection(firstRoot,firstNode);h.automation.root=secondRoot;
            h.args.values.put("op","account-set");h.args.values.put("node_path","0.1");h.args.values.put("node_witness",h.witness(original));return h;
          }
          void run(String expected) throws Exception {
            AccessibilityNodeInfo original=new AccessibilityNodeInfo(7,new Rect(10,100,200,180));
            boolean failed=false;
            try{pointerTap(original);}catch(IllegalStateException refusal){failed=true;}
            require(selections==1 && seenEnd==1000);
            if(expected==null){require(!failed && events==2 && automation.clears==1 && SystemClock.now==160);}
            else{require(failed && events==0 && expected.equals(stage));}
          }
          public static void main(String[] ignored) throws Exception {
            FocusTargetStability h=scenario();h.run(null);
            h=scenario();h.first.node.id=8;h.run("pointer_focus_source_match");require(h.automation.clears==0);
            h=scenario();h.automation.root.child.id=8;h.run("pointer_focus_stable_source_match");
            h=scenario();h.automation.root.child.editable=false;h.run("pointer_focus_stable_source_match");
            h=scenario();h.automation.root.child.label="other";h.run("pointer_focus_stable_witness_match");
            h=scenario();h.automation.root.child.bounds.top=101;h.run("pointer_focus_stable_witness_match");
            h=scenario();h.automation.root.bounds.bottom=959;h.run("pointer_focus_stable_bounds_match");
            h=scenario();h.automation.root.pkg="OTHER";h.run("pointer_focus_stable_root_guard");
            h=scenario();h.automation.ready=false;h.run("pointer_focus_stable_cache_clear");
            h=scenario();h.firstReadCost=950;h.run("pointer_focus_stable_deadline");require(h.automation.clears==0);
            h=scenario();h.automation.readCost=950;h.run("pointer_focus_stable_deadline");
            System.out.print("FOCUS_TARGET_STABILITY_PASS");
          }
        """+bounds+tap+'\n}'
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'FocusTargetStability.java';file.write_text(harness)
            compiled=subprocess.run(['java','-m','jdk.compiler/com.sun.tools.javac.Main','-d',folder,str(file)],
                                    capture_output=True,text=True,timeout=30)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run(['java','-cp',folder,'FocusTargetStability'],capture_output=True,text=True,timeout=10)
            self.assertEqual((result.returncode,result.stdout),(0,'FOCUS_TARGET_STABILITY_PASS'),result.stderr)

    def test_focus_identity_failure_diagnostics_never_export_field_or_input_data(self):
        stages = ('account_focus_editable_match', 'account_focus_class_match',
                  'account_focus_description_match', 'account_focus_hint_match',
                  'account_focus_pending', 'account_focus_text_action_pending')
        self.probe.case_phase('C1-photo-save')
        for stage in stages:
            with self.subTest(stage=stage):
                self.probe.report['native_input_failures'] = []
                self.probe.adb = Mock(return_value='\n'.join([
                    'INSTRUMENTATION_RESULT: passed=false',
                    'INSTRUMENTATION_RESULT: op=account-set',
                    'INSTRUMENTATION_RESULT: stage=' + stage,
                    'INSTRUMENTATION_RESULT: foreground_category=APP',
                    'INSTRUMENTATION_RESULT: hint=PRIVATE_FIELD_SENTINEL',
                    'INSTRUMENTATION_CODE: 0']))
                with self.assertRaises(native.Blocked):
                    self.probe.instrument('account-set', node_path='0.999',
                                          value_b64='PRIVATE_INPUT_SENTINEL')
                self.probe.adb.assert_called_once()
                failure = self.probe.report['native_input_failures'][0]
                self.assertEqual(failure['java_stage'], stage)
                serialized = json.dumps(self.probe.report)
                for secret in ('PRIVATE_FIELD_SENTINEL', 'PRIVATE_INPUT_SENTINEL', '0.999'):
                    self.assertNotIn(secret, serialized)

    def test_actual_java_focus_hint_policy_keeps_cross_field_and_changed_label_refusals(self):
        source=(Path(__file__).resolve().parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        method=source.split('    private static boolean focusHintMatches(',1)[1].split('\n    }',1)[0]
        body='private static boolean focusHintMatches('+method+'\n}'
        harness='public class FocusHintPolicy {\n'+body+'''
          private static void check(boolean actual,boolean expected) {
            if(actual!=expected) throw new AssertionError("focus identity policy");
          }
          public static void main(String[] ignored) {
            check(focusHintMatches("bedrooms","bedrooms",false,false),true);
            check(focusHintMatches("bedrooms","",true,true),true);
            check(focusHintMatches("bedrooms","",true,false),false);
            check(focusHintMatches("bedrooms","",false,true),false);
            check(focusHintMatches("bedrooms","bathrooms",true,true),false);
            check(focusHintMatches("","bedrooms",true,true),false);
            check(focusHintMatches("","",false,false),true);
            System.out.print("FOCUS_HINT_POLICY_PASS");
          }
        }'''
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'FocusHintPolicy.java';file.write_text(harness)
            compiled=subprocess.run(['java','-m','jdk.compiler/com.sun.tools.javac.Main','-d',folder,str(file)],
                                    capture_output=True,text=True,timeout=30)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run(['java','-cp',folder,'FocusHintPolicy'],capture_output=True,text=True,timeout=10)
            self.assertEqual((result.returncode,result.stdout),(0,'FOCUS_HINT_POLICY_PASS'))

    def test_focus_transition_retains_original_pointer_binding_and_reads_only_exact_focused_source(self):
        source=(Path(__file__).resolve().parents[1]/'phase1_device_input/Phase1Input.java').read_text()
        observe=source.split('stage="account_focus_observe";',1)[1].split('require(field!=null);',1)[0]
        for required in ('fresh.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)','require(candidate.isEditable())',
                         'plain(node.getClassName()).equals(plain(candidate.getClassName()))',
                         'plain(node.getContentDescription()).equals(plain(candidate.getContentDescription()))',
                         'boolean sameNode=node.equals(candidate)','if(!sameNode) continue',
                         'focusHintMatches(originalHint,currentHint,candidate.isFocused(),sameNode)',
                         'candidate.getActions()&AccessibilityNodeInfo.ACTION_SET_TEXT'):
            self.assertIn(required,observe)
        self.assertIn('if(!focusHintMatches(originalHint,currentHint,candidate.isFocused(),sameNode)) continue',observe)
        before=source.split('private Selection selectedExpected(',1)[1].split('private AccessibilityNodeInfo atPath(',1)[0]
        self.assertIn('node=atPath(fresh,path)',before)
        self.assertIn('expected.equals(witness(node))',before)
        self.assertIn('Selection selection=selectedExpected(true,end)',source)
        for forbidden in ('pointerTap(', 'checkedAction(', 'send(', 'findAccessibilityNodeInfos'):
            self.assertNotIn(forbidden,observe)

    def test_focus_failure_exports_only_bounded_identity_categories_without_field_values(self):
        self.probe.case_phase('C1-photo-save');self.probe.authenticated=True
        self.probe.adb=Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-set','INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=account_focus_pending',
            'INSTRUMENTATION_RESULT: focus_hint_transition=NONEMPTY_CHANGED',
            'INSTRUMENTATION_RESULT: focus_source_node_same=false',
            'INSTRUMENTATION_RESULT: focus_observed_focused=true',
            'INSTRUMENTATION_RESULT: focus_observation_count=150',
            'INSTRUMENTATION_RESULT: hint=PRIVATE_FIELD_SENTINEL','INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):self.probe.instrument('account-set',node_path='0.999',value_b64='PRIVATE_INPUT_SENTINEL')
        self.assertEqual(self.probe.report['native_input_failures'][0]['focus_identity_observation'],{
            'hint_transition':'NONEMPTY_CHANGED','same_original_android_node':False,'focused':True,'observations':150})
        self.probe.adb.assert_called_once()
        for value in ('PRIVATE_FIELD_SENTINEL','PRIVATE_INPUT_SENTINEL','0.999'):
            self.assertNotIn(value,json.dumps(self.probe.report))

    def test_invalid_focus_diagnostic_or_auth_case_does_not_export_focus_state(self):
        for case,count,transition in [('C1-photo-save','151','SAME'),('C1-photo-save','1','PRIVATE_SENTINEL'),('C1-auth','1','SAME')]:
            self.probe.case_phase(case);self.probe.report['native_input_failures']=[]
            self.probe.adb=Mock(return_value='\n'.join([
                'INSTRUMENTATION_RESULT: op=account-set','INSTRUMENTATION_RESULT: passed=false',
                'INSTRUMENTATION_RESULT: focus_hint_transition='+transition,
                'INSTRUMENTATION_RESULT: focus_source_node_same=true',
                'INSTRUMENTATION_RESULT: focus_observed_focused=true',
                'INSTRUMENTATION_RESULT: focus_observation_count='+count,'INSTRUMENTATION_CODE: 0']))
            with self.subTest(case=case,count=count,transition=transition),self.assertRaises(native.Blocked):
                self.probe.instrument('account-set')
            self.assertNotIn('focus_identity_observation',self.probe.report['native_input_failures'][0])
            self.assertNotIn('PRIVATE_SENTINEL',json.dumps(self.probe.report))




    def test_initial_entry_waits_after_single_exact_fixture_tap_before_return(self):
        self.probe.fixture_api = self.fixture()
        wanted = self.probe.fixture_api.state['title']
        order = []
        self.probe.tap = Mock(side_effect=lambda label: order.append(('tap', label)))
        self.probe.has = Mock(return_value=False)
        self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل')])
        self.probe.wait = Mock()
        self.probe.seek = Mock(return_value=([self.node(wanted)], [self.node(wanted)]))
        self.probe.wait_owned_title_editor = Mock(side_effect=lambda title: order.append(('editor', title)))
        self.probe.manual_entry(wanted, title_editor_required=True)
        self.assertEqual(order, [('tap', 'إضافة عقار'), ('tap', 'مسوداتي'),
                                 ('tap', wanted), ('editor', wanted)])
        self.probe.wait_owned_title_editor.assert_called_once_with(wanted)

    def test_creation_demands_editor_readiness_before_any_purpose_or_fact_input(self):
        self.probe.manual_entry = Mock(side_effect=native.Blocked('native_owned_editor_title_not_observed'))
        self.probe.tap, self.probe.set, self.probe.record_start = Mock(), Mock(), Mock()
        with self.assertRaises(native.Blocked):
            self.probe.create_and_save()
        self.probe.manual_entry.assert_called_once_with(self.probe.bootstrap_title, title_editor_required=True)
        self.probe.tap.assert_not_called()
        self.probe.set.assert_not_called()
        self.probe.record_start.assert_not_called()

    def test_restore_entry_keeps_saved_step_route_without_demanding_basic_title_field(self):
        self.probe.fixture_api = self.fixture()
        wanted = self.probe.fixture_api.state['title']
        self.probe.tap = Mock()
        self.probe.has = Mock(return_value=False)
        self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل')])
        self.probe.wait = Mock()
        self.probe.seek = Mock(return_value=([self.node(wanted)], [self.node(wanted)]))
        self.probe.wait_owned_title_editor = Mock()
        self.probe.manual_entry(wanted)
        self.probe.wait_owned_title_editor.assert_not_called()

    def test_logout_readiness_failure_blocks_all_account_logout_taps(self):
        self.probe.case_phase('C1-cleanup')
        self.probe.record_stop, self.probe.adb, self.probe.startup = Mock(), Mock(), Mock()
        self.probe.authenticated_account_evidence = Mock(side_effect=native.Blocked('native_broker_auth_not_observed'))
        self.probe.tap, self.probe.has, self.probe.wait = Mock(), Mock(), Mock()
        with self.assertRaisesRegex(native.Blocked, '^native_broker_auth_not_observed$'):
            self.probe.native_logout()
        self.probe.authenticated_account_evidence.assert_called_once_with(seconds=45)
        for operation in (self.probe.tap, self.probe.has, self.probe.wait):
            operation.assert_not_called()
        self.assertNotIn('session_logged_out', self.probe.report)
        self.assertFalse(self.probe.authenticated)



    def test_journey_stages_are_fixed_bounded_and_preserve_each_case_failure_context(self):
        self.probe.case_phase('C1-photo-save')
        self.probe.journey_stage('editor_wait')
        self.probe.case_phase('C1-cleanup')
        self.probe.journey_stage('logout_account_ready')
        with self.assertRaisesRegex(native.Blocked, '^fixed_native_journey_stage_required$'):
            self.probe.journey_stage('PRIVATE_STAGE_SENTINEL')
        self.assertEqual(self.probe.report['native_journey_stages'], {
            'C1-photo-save': 'editor_wait', 'C1-cleanup': 'logout_account_ready'})
        self.assertNotIn('PRIVATE_STAGE_SENTINEL', (self.probe.out/'report.json').read_text())

    def editor_rows(self, title=None, basics=True):
        names = ['إضافة عقار', '1/4', 'التالي']
        if basics:
            names += ['نوع الإعلان والعقار', 'للبيع', 'للإيجار', 'شقة']
        rows = [self.node(name, path='0.'+str(i)) for i, name in enumerate(names)]
        if title is not None:
            rows.append(self.node(title, path='0.99', hint='عنوان الإعلان *', editable=True))
        return rows

    def guest_rows(self, account=False):
        names = ['العقارات', 'الرسائل', 'إعلاناتي', 'حسابي']
        names += ['تسجيل الدخول أو إنشاء حساب'] if account else ['ماذا تبحث عنه؟', 'ابحث عن عقار أو منطقة…']
        return [self.node(name, path='0.'+str(i)) for i, name in enumerate(names)]

    def test_owned_editor_wait_observes_delayed_exact_title_without_any_input(self):
        self.probe.case_phase('C1-photo-save')
        wanted = self.fixture().state['title']
        self.probe.nodes = Mock(side_effect=[[], self.editor_rows(wanted)])
        self.probe.tap, self.probe.seek, self.probe.scroll, self.probe.act = Mock(), Mock(), Mock(), Mock()
        self.probe.capture_basic_editor, self.probe.return_to_basic_editor = Mock(), Mock()
        self.probe.wait_stable_owned_title = Mock()
        with patch.object(native.time, 'monotonic', side_effect=[0, 0, .5, 1]), patch.object(native.time, 'sleep'):
            self.probe.wait_owned_title_editor(wanted)
        self.assertEqual(self.probe.nodes.call_count, 2)
        for operation in (self.probe.tap, self.probe.seek, self.probe.scroll, self.probe.act):
            operation.assert_not_called()
        self.assertEqual(self.probe.report['native_journey_stages']['C1-photo-save'], 'editor_ready')
        self.assertEqual(self.probe.report['actions'], [])

    def test_owned_editor_wait_supports_separate_unique_label_without_scrolling(self):
        wanted = self.fixture().state['title']
        self.probe.nodes = Mock(return_value=self.editor_rows()+[
            self.node('عنوان الإعلان *', path='0.98'), self.node(wanted, path='0.99', editable=True)])
        self.probe.seek, self.probe.scroll = Mock(), Mock()
        self.probe.capture_basic_editor, self.probe.return_to_basic_editor = Mock(), Mock()
        self.probe.wait_stable_owned_title = Mock()
        self.probe.wait_owned_title_editor(wanted)
        self.probe.seek.assert_not_called(); self.probe.scroll.assert_not_called()

    def test_owned_editor_wait_refuses_wrong_or_ambiguous_title_on_bounded_readonly_poll(self):
        wanted = self.fixture().state['title']
        cases = [[], self.editor_rows('wrong'), self.editor_rows(wanted)+[
                 self.node(wanted, hint='عنوان الإعلان *', path='0.100', editable=True)]]
        self.probe.case_phase('C1-photo-save')
        self.probe.tap, self.probe.seek, self.probe.scroll = Mock(), Mock(), Mock()
        self.probe.capture_basic_editor = Mock()
        for rows in cases:
            self.probe.nodes = Mock(return_value=rows)
            with self.subTest(rows=len(rows)), patch.object(native.time, 'monotonic', side_effect=[0, 0, 61]), \
                    patch.object(native.time, 'sleep'):
                with self.assertRaises(native.Blocked):
                    self.probe.wait_owned_title_editor(wanted)
            self.probe.nodes.assert_called_once()
        for operation in (self.probe.tap, self.probe.seek, self.probe.scroll, self.probe.capture_basic_editor):
            operation.assert_not_called()
        self.assertEqual(self.probe.report['native_journey_stages']['C1-photo-save'], 'editor_wait')

    def test_offscreen_title_scrolls_only_after_loaded_basics_and_returns_before_facts(self):
        wanted = self.fixture().state['title']
        self.probe.nodes = Mock(side_effect=[self.editor_rows(), self.editor_rows(wanted, basics=False),
                                            self.editor_rows(wanted, basics=False), self.editor_rows()])
        self.probe.scroll, self.probe.tap, self.probe.set = Mock(), Mock(), Mock()
        self.probe.capture_basic_editor = Mock()
        self.probe.wait_stable_owned_title = Mock()
        self.probe.wait_owned_title_editor(wanted)
        self.assertEqual([call.args[0] for call in self.probe.scroll.call_args_list], ['forward','backward'])
        self.probe.capture_basic_editor.assert_not_called()
        self.probe.wait_stable_owned_title.assert_called_once()
        self.probe.tap.assert_not_called(); self.probe.set.assert_not_called()

    def test_reviewed_basics_and_exact_title_with_visible_input_targets_need_no_return_scroll(self):
        # Actual API36 viewport: the section heading is above the screen, while
        # both purpose choices, apartment choice and the owned title are visible.
        wanted = self.fixture().state['title']
        target_scene = self.editor_rows(wanted, basics=False) + [
            self.node(name, path='0.5' + str(i))
            for i, name in enumerate(('للبيع', 'للإيجار', 'شقة'))]
        self.probe.nodes = Mock(side_effect=[self.editor_rows(), target_scene, target_scene])
        self.probe.capture_basic_editor = Mock()
        self.probe.wait_stable_owned_title = Mock()
        def scroll(direction):
            if direction != 'forward':
                raise native.Blocked('scrollable_native_container_missing')
        self.probe.scroll = Mock(side_effect=scroll)
        self.probe.tap, self.probe.set = Mock(), Mock()
        self.probe.case_phase('C1-photo-save')
        self.probe.wait_owned_title_editor(wanted)
        self.assertEqual([call.args[0] for call in self.probe.scroll.call_args_list], ['forward'])
        self.assertEqual(self.probe.report['native_journey_stages']['C1-photo-save'], 'editor_ready')
        self.probe.tap.assert_not_called(); self.probe.set.assert_not_called()

    def test_visible_targets_without_prior_loaded_basics_or_owned_title_still_return(self):
        wanted = self.fixture().state['title']
        targets = [self.node(name, path='0.5' + str(i))
                   for i, name in enumerate(('للبيع', 'للإيجار', 'شقة'))]
        for observed, title in ((False, wanted), (True, None)):
            self.probe.nodes = Mock(side_effect=[self.editor_rows(title, basics=False) + targets,
                                                self.editor_rows()])
            self.probe.scroll = Mock()
            self.probe.return_to_basic_editor(native.time.monotonic() + 60,
                expected_title=wanted, loaded_basics_observed=observed)
            self.probe.scroll.assert_called_once_with('backward')

    def test_changed_title_during_return_refuses_before_any_gesture(self):
        self.probe.nodes = Mock(return_value=self.editor_rows('different-owned-title'))
        self.probe.scroll = Mock()
        with self.assertRaisesRegex(native.Blocked, '^native_owned_editor_title_mismatch$'):
            self.probe.return_to_basic_editor(native.time.monotonic() + 60,
                expected_title=self.fixture().state['title'], loaded_basics_observed=True)
        self.probe.scroll.assert_not_called()

    def test_scrollable_loading_scene_does_not_trigger_premature_scroll(self):
        wanted = self.fixture().state['title']; order = []
        scenes = iter([[self.node('loading', scrollable=True)], self.editor_rows(),
                       self.editor_rows(wanted, basics=False), self.editor_rows()])
        self.probe.nodes = Mock(side_effect=lambda: order.append('read') or next(scenes))
        self.probe.scroll = Mock(side_effect=lambda direction: order.append('scroll'))
        self.probe.capture_basic_editor = Mock(side_effect=lambda *args: order.append('anchored-capture'))
        self.probe.wait_stable_owned_title = Mock()
        with patch.object(native.time,'sleep'):
            self.probe.wait_owned_title_editor(wanted)
        self.assertEqual(order[:4], ['read','read','scroll','read'])
        self.probe.capture_basic_editor.assert_not_called()

    def test_wrong_title_or_changed_route_after_viewport_scroll_holds_without_more_input(self):
        wanted = self.fixture().state['title']
        for scene in (self.editor_rows('another draft',basics=False), [self.node('لديك إعلان غير مكتمل')]):
            self.probe.nodes = Mock(side_effect=[self.editor_rows(),scene])
            self.probe.scroll, self.probe.tap, self.probe.set = Mock(), Mock(), Mock()
            self.probe.capture_basic_editor = Mock()
            with self.subTest(scene=len(scene)),self.assertRaises(native.Blocked):
                self.probe.wait_owned_title_editor(wanted)
            self.probe.scroll.assert_called_once_with('forward')
            self.probe.tap.assert_not_called();self.probe.set.assert_not_called()
            self.probe.capture_basic_editor.assert_not_called()

    def test_uncertain_viewport_scroll_is_not_replayed(self):
        self.probe.nodes = Mock(return_value=self.editor_rows())
        self.probe.scroll = Mock(side_effect=native.Blocked('native_input_not_delivered'))
        self.probe.capture_basic_editor = Mock()
        with self.assertRaises(native.Blocked):self.probe.wait_owned_title_editor(self.fixture().state['title'])
        self.probe.scroll.assert_called_once_with('forward')

    def test_basic_diagnostic_captures_require_editor_anchor_no_contact_and_existing_private_guard(self):
        self.probe.authenticated=True; self.probe.adb=Mock()
        for rows in ([self.node('unknown')], self.editor_rows()+[self.node('رقم الاتصال *')],
                     self.editor_rows()+[self.node(self.access['phones']['broker'])],
                     self.editor_rows()+[self.node('رمز التحقق')]):
            self.probe.nodes=Mock(return_value=rows)
            with self.subTest(rows=len(rows)),self.assertRaises(native.Blocked):
                self.probe.capture_basic_editor('C1-basic-editor')
        self.probe.adb.assert_not_called()
        self.assertEqual(self.probe.report['frames'],[])

    def test_title_diagnostic_capture_requires_exact_expected_title_and_known_name(self):
        self.probe.nodes=Mock(return_value=self.editor_rows('wrong'))
        self.probe.safe_capture=Mock()
        with self.assertRaises(native.Blocked):self.probe.capture_basic_editor('C1-owned-editor-title','wanted')
        with self.assertRaises(native.Blocked):self.probe.capture_basic_editor('C1-unknown','wanted')
        self.probe.safe_capture.assert_not_called()

    def test_owned_title_settles_before_facts_without_preinput_diagnostic_capture(self):
        wanted = self.fixture().state['title']
        field_scene = self.editor_rows(wanted, basics=False)
        scenes = [self.editor_rows(), field_scene,
                  self.editor_rows(basics=False), field_scene, field_scene, field_scene,
                  field_scene, field_scene, field_scene, field_scene, field_scene]
        self.probe.nodes = Mock(side_effect=scenes)
        self.probe.scroll, self.probe.return_to_basic_editor = Mock(), Mock()
        self.probe.safe_capture = Mock()
        ticks = iter(i * .5 for i in range(100))
        with patch.object(native.time, 'monotonic', side_effect=lambda: next(ticks)), patch.object(native.time, 'sleep'):
            self.probe.wait_owned_title_editor(wanted)
        self.probe.safe_capture.assert_not_called()
        self.assertEqual(self.probe.report['initial_owned_editor_observation'], {
            'bootstrap_title_matched':True, 'stable_title_field_observed':True,
            'pre_input_png_exported':False, 'acceptance_claimed':False})
        self.probe.scroll.assert_called_once_with('forward')

    def test_owned_title_settling_refuses_changed_identity_or_route_without_any_input(self):
        for rows, code in ((self.editor_rows('another draft'), 'title_mismatch'),
                           ([self.node('رمز التحقق')], 'context_changed')):
            self.probe.nodes = Mock(return_value=rows)
            self.probe.tap, self.probe.scroll, self.probe.safe_capture = Mock(), Mock(), Mock()
            with self.subTest(code=code), self.assertRaisesRegex(native.Blocked, code):
                self.probe.wait_stable_owned_title(self.fixture().state['title'], native.time.monotonic()+60)
            for operation in (self.probe.tap, self.probe.scroll, self.probe.safe_capture):
                operation.assert_not_called()

    def test_owned_title_settling_resets_on_missing_headers_and_needs_fresh_full_stability(self):
        wanted = self.fixture().state['title']
        full = self.editor_rows(wanted, basics=False)
        partial = [row for row in full if '1/4' not in native.labels(row)]
        self.probe.nodes = Mock(side_effect=[full, full, partial, [], full, full, full])
        self.probe.tap, self.probe.scroll, self.probe.safe_capture = Mock(), Mock(), Mock()
        ticks = iter(i * .4 for i in range(100))
        with patch.object(native.time, 'monotonic', side_effect=lambda: next(ticks)), patch.object(native.time, 'sleep'):
            self.probe.wait_stable_owned_title(wanted, 60)
        self.assertEqual(self.probe.nodes.call_count, 7)
        for operation in (self.probe.tap, self.probe.scroll, self.probe.safe_capture):
            operation.assert_not_called()

    def test_owned_title_settling_is_deadline_bounded_and_exports_no_nodes(self):
        self.probe.nodes = Mock(return_value=self.editor_rows(basics=False))
        self.probe.tap, self.probe.scroll, self.probe.safe_capture = Mock(), Mock(), Mock()
        ticks = iter(i * .5 for i in range(20))
        with patch.object(native.time, 'monotonic', side_effect=lambda: next(ticks)), patch.object(native.time, 'sleep'):
            with self.assertRaisesRegex(native.Blocked, '^native_owned_editor_title_not_stable$'):
                self.probe.wait_stable_owned_title(self.fixture().state['title'], 2)
        for operation in (self.probe.tap, self.probe.scroll, self.probe.safe_capture):
            operation.assert_not_called()
        self.assertEqual(self.probe.report['frames'], [])

    def test_logout_profile_ready_avoids_reopening_account_before_single_logout(self):
        order=[]
        self.probe.record_stop,self.probe.adb,self.probe.startup=Mock(),Mock(),Mock()
        self.probe.authenticated_account_evidence=Mock(side_effect=lambda **kw:order.append('broker-ready'))
        self.probe.has=Mock(return_value=True)
        self.probe.wait_account_logout_control=Mock(side_effect=lambda *args,**kw:order.append('logout-ready'))
        self.probe.tap=Mock(side_effect=lambda label,**kw:order.append(label))
        self.probe.wait_guest_marketplace=Mock(side_effect=lambda:order.append('guest-marketplace'))
        self.probe.wait_guest_account=Mock(side_effect=lambda:order.append('guest-account'))
        self.probe.safe_capture,self.probe.record_start=Mock(),Mock()
        self.probe.native_logout()
        self.assertEqual(order,['broker-ready','logout-ready','تسجيل الخروج','guest-marketplace','حسابي','guest-account'])
        self.assertEqual(sum(call.args[0]=='تسجيل الخروج' for call in self.probe.tap.call_args_list),1)
        self.probe.tap.assert_any_call('حسابي',seek=False)
        self.assertTrue(self.probe.report['session_logged_out'])
        self.probe.safe_capture.assert_not_called();self.probe.record_start.assert_not_called()

    def test_logout_footer_ready_uses_normal_account_then_logout_after_evidence(self):
        order=[]
        self.probe.record_stop,self.probe.adb,self.probe.startup=Mock(),Mock(),Mock()
        self.probe.authenticated_account_evidence=Mock(side_effect=lambda **kw:order.append('broker-ready'))
        self.probe.has=Mock(return_value=False)
        self.probe.wait_account_logout_control=Mock(side_effect=lambda *args,**kw:order.append('logout-ready'))
        self.probe.tap=Mock(side_effect=lambda label,**kw:order.append(label))
        self.probe.wait_guest_marketplace=Mock(side_effect=lambda:order.append('guest-marketplace'))
        self.probe.wait_guest_account=Mock(side_effect=lambda:order.append('guest-account'))
        self.probe.native_logout()
        self.assertEqual(order,['broker-ready','حسابي','logout-ready','تسجيل الخروج','guest-marketplace','حسابي','guest-account'])

    def test_logout_waits_readonly_for_account_transition_before_the_one_logout(self):
        self.probe.record_stop, self.probe.adb, self.probe.startup = Mock(), Mock(), Mock()
        self.probe.authenticated_account_evidence = Mock()
        self.probe.nodes = Mock(side_effect=[self.broker_home_rows(), self.broker_home_rows(),
                                            [self.node('تسجيل الخروج')]])
        self.probe.tap = Mock()
        self.probe.wait_guest_marketplace, self.probe.wait_guest_account = Mock(), Mock()
        self.probe.scroll, self.probe.safe_capture = Mock(), Mock()
        with patch.object(native.time, 'sleep'):
            self.probe.native_logout()
        self.assertEqual([c.args[0] for c in self.probe.tap.call_args_list],
                         ['حسابي', 'تسجيل الخروج', 'حسابي'])
        self.probe.tap.assert_any_call('تسجيل الخروج', seek=False)
        self.probe.scroll.assert_not_called(); self.probe.safe_capture.assert_not_called()

    def test_offscreen_logout_scrolls_only_after_positive_account_route_observation(self):
        home = self.broker_home_rows()
        account = [self.node('الأمان والخصوصية'), self.node('الملف الشخصي', path='0.2'),
                   self.node('', path='0.3', scrollable=True)]
        self.probe.nodes = Mock(side_effect=[home, account, [self.node('تسجيل الخروج')]])
        self.probe.scroll, self.probe.tap, self.probe.safe_capture = Mock(), Mock(), Mock()
        with patch.object(native.time,'sleep'):
            self.probe.wait_account_logout_control()
        self.probe.scroll.assert_called_once_with('forward')
        self.probe.tap.assert_not_called(); self.probe.safe_capture.assert_not_called()
        self.assertNotIn('الأمان والخصوصية', json.dumps(self.probe.report,ensure_ascii=False))

    def test_logout_search_refuses_recording_or_auth_transition_before_any_scroll(self):
        self.probe.scroll = Mock()
        self.probe.recorder = object()
        with self.assertRaisesRegex(native.Blocked,'recording_must_be_stopped'):
            self.probe.wait_account_logout_control()
        self.probe.recorder = None
        self.probe.nodes = Mock(return_value=[self.node('رمز التحقق')])
        with self.assertRaisesRegex(native.Blocked,'logout_context_changed'):
            self.probe.wait_account_logout_control()
        self.probe.scroll.assert_not_called()

    def test_logout_marketplace_and_guest_account_are_readonly_exact_scope_checks(self):
        self.probe.tap,self.probe.scroll=Mock(),Mock()
        self.probe.nodes=Mock(side_effect=[self.guest_rows()[:-1],self.guest_rows()])
        with patch.object(native.time,'sleep'):self.probe.wait_guest_marketplace()
        self.probe.nodes=Mock(return_value=self.guest_rows(account=True));self.probe.wait_guest_account()
        self.probe.tap.assert_not_called();self.probe.scroll.assert_not_called()

    def test_guest_scope_observation_rejects_missing_anchors_logout_or_auth_fields(self):
        for account in (False,True):
            valid=self.guest_rows(account=account)
            for rows in (valid[:-1],valid+[self.node('تسجيل الخروج')],valid+[self.node('رقم واتساب')]):
                self.probe.nodes=Mock(return_value=rows)
                wait=self.probe.wait_guest_account if account else self.probe.wait_guest_marketplace
                with self.subTest(account=account),patch.object(native.time,'monotonic',side_effect=[0,0,61]),patch.object(native.time,'sleep'):
                    with self.assertRaises(native.Blocked):wait()

    def test_logout_transition_failure_never_replays_logout_or_claims_success(self):
        for failure in ('home','account'):
            self.probe.record_stop,self.probe.adb,self.probe.startup=Mock(),Mock(),Mock()
            self.probe.authenticated_account_evidence=Mock();self.probe.has=Mock(return_value=True)
            self.probe.wait_account_logout_control=Mock()
            self.probe.tap=Mock();self.probe.wait_guest_marketplace=Mock();self.probe.wait_guest_account=Mock()
            if failure=='home':self.probe.wait_guest_marketplace.side_effect=native.Blocked('native_guest_marketplace_not_observed')
            else:self.probe.wait_guest_account.side_effect=native.Blocked('native_guest_account_not_observed')
            with self.subTest(failure=failure),self.assertRaises(native.Blocked):self.probe.native_logout()
            self.assertEqual(sum(call.args[0]=='تسجيل الخروج' for call in self.probe.tap.call_args_list),1)
            self.assertEqual(sum(call.args[0]=='حسابي' for call in self.probe.tap.call_args_list),0 if failure=='home' else 1)
            self.assertNotIn('session_logged_out',self.probe.report)

    def broker_home_rows(self, add=True, **changes):
        names = ['ماذا تبحث عنه؟','ابحث عن عقار أو منطقة…','الرئيسية','عملي','العملاء','حسابي']
        rows = [self.node(name,path='0.'+str(i),clickable=name=='الرئيسية') for i,name in enumerate(names)]
        if add:
            row=self.node('إضافة عقار',path='0.99',clickable=True,description='إضافة عقار')
            row.update(changes);rows.append(row)
        return rows

    def initial_add_scope(self):
        self.probe.authenticated=True
        self.probe.case_phase('C1-photo-save')

    def stability_clock(self):
        now=[0.0]
        mono=patch.object(native.time,'monotonic',side_effect=lambda:now[0])
        sleep=patch.object(native.time,'sleep',side_effect=lambda seconds:now.__setitem__(0,now[0]+seconds))
        mono.start();sleep.start();self.addCleanup(mono.stop);self.addCleanup(sleep.stop)
        return now

    def test_initial_add_requires_three_identical_observations_and_two_seconds_before_one_dispatch(self):
        self.initial_add_scope();clock=self.stability_clock()
        self.probe.nodes=Mock(return_value=self.broker_home_rows())
        self.probe.act=Mock(side_effect=lambda *args:self.assertGreaterEqual(clock[0],2))
        self.probe.tap=Mock()
        self.probe.dispatch_stable_initial_add()
        self.assertEqual(self.probe.nodes.call_count,3)
        self.probe.act.assert_called_once_with('click',{'path':'0.99','witness':'a'*64})
        self.probe.tap.assert_not_called()
        self.assertEqual(self.probe.report['native_journey_stages']['C1-photo-save'],'add_dispatch')

    def test_initial_add_signature_changes_reset_the_whole_preinput_stability_window(self):
        self.initial_add_scope();clock=self.stability_clock()
        for change in ({'path':'0.98'},{'witness':'b'*64},{'bounds':[0,0,201,50]}, {'description':'changed label'}):
            clock[0]=0
            original=self.broker_home_rows();changed=self.broker_home_rows(**change)
            self.probe.nodes=Mock(side_effect=[original,changed,changed,changed])
            self.probe.act=Mock()
            with self.subTest(change=next(iter(change))):self.probe.dispatch_stable_initial_add()
            self.assertEqual(self.probe.nodes.call_count,4)
            self.assertEqual(clock[0],3)
            self.probe.act.assert_called_once()
            lease=self.probe.act.call_args.args[1]
            self.assertEqual(lease['path'],change.get('path','0.99'))
            self.assertEqual(lease['witness'],change.get('witness','a'*64))

    def test_initial_add_missing_home_or_control_resets_without_navigating_or_input(self):
        self.initial_add_scope();self.stability_clock()
        home=self.broker_home_rows()
        self.probe.nodes=Mock(side_effect=[home,self.broker_home_rows(add=False),home,home,home])
        self.probe.act,self.probe.tap=Mock(),Mock()
        self.probe.dispatch_stable_initial_add()
        self.assertEqual(self.probe.nodes.call_count,5)
        self.probe.act.assert_called_once();self.probe.tap.assert_not_called()

    def test_initial_add_timed_out_or_wrong_scope_never_dispatches(self):
        self.initial_add_scope();self.stability_clock()
        self.probe.nodes=Mock(return_value=self.broker_home_rows())
        self.probe.act=Mock()
        with self.assertRaisesRegex(native.Blocked,'^native_named_add_not_stable$'):
            self.probe.dispatch_stable_initial_add(seconds=2)
        self.probe.act.assert_not_called()
        self.probe.case_phase('C1-auth');self.probe.nodes=Mock()
        with self.assertRaisesRegex(native.Blocked,'^initial_c1_add_scope_required$'):
            self.probe.dispatch_stable_initial_add()
        self.probe.nodes.assert_not_called()

    def test_failed_initial_add_dispatch_is_not_retried_or_reselected(self):
        self.initial_add_scope();self.stability_clock()
        self.probe.nodes=Mock(return_value=self.broker_home_rows())
        self.probe.act=Mock(side_effect=native.Blocked('native_input_not_delivered'))
        with self.assertRaisesRegex(native.Blocked,'^native_input_not_delivered$'):
            self.probe.dispatch_stable_initial_add()
        self.assertEqual(self.probe.nodes.call_count,3)
        self.probe.act.assert_called_once()
        self.assertEqual(self.probe.report['actions'],[])

    def test_broker_home_wait_opens_home_once_then_observes_without_further_taps(self):
        self.initial_add_scope();self.stability_clock()
        footer=self.broker_home_rows(add=False)[2:]
        self.probe.nodes=Mock(side_effect=[footer,footer,footer,self.broker_home_rows(add=False)])
        self.probe.tap,self.probe.act,self.probe.safe_capture=Mock(),Mock(),Mock()
        self.probe.ensure_initial_broker_home()
        self.probe.act.assert_called_once_with('click',{'path':'0.2','witness':'a'*64})
        self.probe.tap.assert_not_called()
        self.assertEqual(self.probe.nodes.call_count,4)
        self.probe.safe_capture.assert_not_called()

    def test_home_navigation_resets_on_changed_or_missing_scene_and_uses_final_observed_lease(self):
        self.initial_add_scope();self.stability_clock()
        footer=self.broker_home_rows(add=False)[2:]
        changed=[dict(row, witness='b'*64) if row['text']=='الرئيسية' else row for row in footer]
        self.probe.nodes=Mock(side_effect=[footer,changed,[],changed,changed,changed,
                                          self.broker_home_rows(add=False)])
        def dispatch(*args):
            self.assertEqual(self.probe.nodes.call_count,6)
        self.probe.act=Mock(side_effect=dispatch);self.probe.tap=Mock()
        self.probe.ensure_initial_broker_home()
        self.probe.act.assert_called_once_with('click',{'path':'0.2','witness':'b'*64})
        self.probe.tap.assert_not_called()

    def test_uncertain_home_tap_prevents_add_stability_and_is_never_replayed(self):
        self.initial_add_scope();self.stability_clock()
        self.probe.fixture_api=self.fixture()
        self.probe.nodes=Mock(return_value=self.broker_home_rows(add=False)[2:])
        self.probe.act=Mock(side_effect=native.Blocked('native_input_not_delivered'))
        self.probe.tap=Mock()
        self.probe.dispatch_stable_initial_add,self.probe.capture_initial_broker_home=Mock(),Mock()
        with self.assertRaises(native.Blocked):self.probe.manual_entry(self.probe.fixture_api.state['title'])
        self.probe.act.assert_called_once_with('click',{'path':'0.2','witness':'a'*64})
        self.probe.tap.assert_not_called()
        self.probe.dispatch_stable_initial_add.assert_not_called()
        self.probe.capture_initial_broker_home.assert_not_called()

    def test_manual_entry_requires_home_and_stable_add_without_preinput_home_capture(self):
        self.initial_add_scope();self.probe.fixture_api=self.fixture();title=self.probe.fixture_api.state['title']
        order=[]
        self.probe.ensure_initial_broker_home=Mock(side_effect=lambda:order.append('home'))
        self.probe.capture_initial_broker_home=Mock(side_effect=lambda:order.append('capture'))
        self.probe.dispatch_stable_initial_add=Mock(side_effect=lambda:order.append('one-add'))
        self.probe.has=Mock(return_value=False);self.probe.nodes=Mock(return_value=[self.node('لديك إعلان غير مكتمل')])
        self.probe.tap=Mock(side_effect=lambda label:order.append(label));self.probe.wait=Mock()
        self.probe.seek=Mock(return_value=([self.node(title)],[self.node(title)]))
        self.probe.manual_entry(title)
        self.assertEqual(order,['home','one-add','مسوداتي',title])
        self.probe.capture_initial_broker_home.assert_not_called()
        self.assertNotIn('إضافة عقار',[call.args[0] for call in self.probe.tap.call_args_list])

    def test_home_diagnostic_refuses_profile_auth_contact_private_values_before_image(self):
        self.initial_add_scope();self.probe.adb=Mock()
        for rows in ([self.node('حسابي')],self.broker_home_rows()+[self.node('رقم الاتصال *')],
                     self.broker_home_rows()+[self.node('رمز التحقق')],
                     self.broker_home_rows()+[self.node(self.access['phones']['broker'])]):
            self.probe.nodes=Mock(return_value=rows)
            with self.subTest(rows=len(rows)),self.assertRaises(native.Blocked):
                self.probe.capture_initial_broker_home()
        self.probe.adb.assert_not_called();self.assertEqual(self.probe.report['frames'],[])

    def test_home_diagnostic_receipt_is_truthful_unique_and_case_specific(self):
        self.initial_add_scope();self.probe.nodes=Mock(return_value=self.broker_home_rows())
        self.probe.adb=Mock(return_value=b'\x89PNG\r\n\x1a\nSYNTHETIC_TEST_BYTES_ONLY')
        self.probe.capture_initial_broker_home()
        row=self.probe.report['frames'][0]
        self.assertFalse(row['authenticated_editor_only'])
        self.assertEqual(row['capture_scope'],'authenticated_broker_marketplace_before_add')
        self.assertEqual(row['file'],'C1-before-add-home.png')
        with self.assertRaisesRegex(native.Blocked,'^initial_home_capture_already_exists$'):
            self.probe.capture_initial_broker_home()
        self.probe.adb.assert_called_once()
        self.probe.case_phase('C1-force-stop-restore')
        self.assertEqual(self.probe.initial_home_capture_name(),'C1-restore-before-add-home')

    def test_unloaded_home_never_stabilizes_even_if_add_named_control_is_visible(self):
        self.initial_add_scope();self.stability_clock()
        self.probe.nodes=Mock(return_value=[self.node('إضافة عقار',clickable=True)])
        self.probe.act,self.probe.tap=Mock(),Mock()
        with self.assertRaisesRegex(native.Blocked,'^native_named_add_not_stable$'):
            self.probe.dispatch_stable_initial_add(seconds=3)
        self.probe.act.assert_not_called();self.probe.tap.assert_not_called()

    def startup_home_rows(self, broker=False):
        footer = ['الرئيسية', 'عملي', 'العملاء', 'حسابي'] if broker else ['العقارات', 'الرسائل', 'إعلاناتي', 'حسابي']
        return [self.node(name, path='0.' + str(index)) for index, name in enumerate(
            ['ماذا تبحث عنه؟', 'ابحث عن عقار أو منطقة…'] + footer)]

    def startup_intro_rows(self):
        rows = [self.node(name, path='0.' + str(index)) for index, name in enumerate(
            ['عقارات في منطقتك', 'تحديد موقعي', 'اختيار المحافظة يدويًا', 'المتابعة الآن'])]
        rows[-1].update(clickable=True)
        return rows

    def startup_scope(self):
        self.probe.case_phase('C1-native-network')
        self.probe.adb, self.probe.act, self.probe.tap = Mock(), Mock(), Mock()
        return self.stability_clock()

    def test_startup_dispatches_one_original_continue_lease_only_after_stable_intro(self):
        clock = self.startup_scope()
        intro, home = self.startup_intro_rows(), self.startup_home_rows()
        self.probe.nodes = Mock(side_effect=[intro] * 5 + [home] * 5)
        def dispatch(*args):
            self.assertGreaterEqual(clock[0], 2)
            self.assertGreaterEqual(self.probe.nodes.call_count, 3)
        self.probe.act.side_effect = dispatch
        self.probe.startup()
        self.probe.act.assert_called_once_with('click', {'path': '0.3', 'witness': 'a' * 64})
        self.probe.tap.assert_not_called()
        row = self.probe.report['native_startup_diagnostics']['C1-native-network']
        self.assertEqual((row['stage'], row['continue_attempts']), ('home_ready', 1))

    def test_startup_requires_three_reads_even_when_two_seconds_already_elapsed(self):
        clock = self.startup_scope()
        intro, home = self.startup_intro_rows(), self.startup_home_rows()
        def read():
            if self.probe.nodes.call_count == 2:
                clock[0] = 2
            return intro if self.probe.nodes.call_count <= 3 else home
        self.probe.nodes = Mock(side_effect=read)
        self.probe.act.side_effect = lambda *args: self.assertEqual(self.probe.nodes.call_count, 3)
        self.probe.startup()
        self.probe.act.assert_called_once()

    def test_startup_stable_guest_or_retained_broker_home_requires_no_continue_click(self):
        clock = self.startup_scope()
        for broker in (False, True):
            clock[0] = 0
            self.probe.authenticated = False
            self.probe.nodes = Mock(return_value=self.startup_home_rows(broker))
            self.probe.act.reset_mock()
            self.probe.startup()
            self.assertEqual(self.probe.nodes.call_count, 5)
            self.assertEqual(clock[0], 2)
            self.probe.act.assert_not_called()

    def test_startup_initial_home_then_intro_resets_before_one_continue_dispatch(self):
        clock = self.startup_scope()
        home, intro = self.startup_home_rows(), self.startup_intro_rows()
        self.probe.nodes = Mock(side_effect=[home] * 2 + [intro] * 5 + [home] * 5)
        self.probe.act.side_effect = lambda *args: self.assertGreaterEqual(clock[0], 3)
        self.probe.startup()
        self.probe.act.assert_called_once()
        self.assertGreaterEqual(self.probe.report['native_startup_diagnostics']['C1-native-network']['stability_resets'], 1)

    def test_startup_home_anchor_change_restarts_readonly_home_stability(self):
        clock = self.startup_scope()
        original, changed = self.startup_home_rows(), self.startup_home_rows()
        changed[0]['bounds'] = [0, 0, 201, 50]
        self.probe.nodes = Mock(side_effect=[original] * 2 + [changed] * 5)
        self.probe.startup()
        self.assertEqual(self.probe.nodes.call_count, 7)
        self.assertEqual(clock[0], 3)
        self.probe.act.assert_not_called()

    def test_startup_continue_can_disappear_into_stable_home_without_any_dispatch(self):
        self.startup_scope()
        self.probe.nodes = Mock(side_effect=[self.startup_intro_rows()] * 2 + [self.startup_home_rows()] * 5)
        self.probe.startup()
        self.probe.act.assert_not_called()
        self.assertEqual(self.probe.report['native_startup_diagnostics']['C1-native-network']['continue_attempts'], 0)

    def test_startup_candidate_or_public_intro_binding_changes_reset_full_window(self):
        clock = self.startup_scope()
        for change in ('path', 'witness', 'bounds', 'intro'):
            clock[0] = 0
            original, changed = self.startup_intro_rows(), self.startup_intro_rows()
            if change == 'path': changed[-1]['path'] = '0.99'
            elif change == 'witness': changed[-1]['witness'] = 'b' * 64
            elif change == 'bounds': changed[-1]['bounds'] = [0, 0, 201, 50]
            else: changed[0]['witness'] = 'b' * 64
            self.probe.nodes = Mock(side_effect=[original] * 2 + [changed] * 5 + [self.startup_home_rows()] * 5)
            self.probe.act.reset_mock()
            self.probe.act.side_effect = lambda *args: self.assertGreaterEqual(clock[0], 3)
            with self.subTest(change=change): self.probe.startup()
            self.probe.act.assert_called_once_with('click', {'path': changed[-1]['path'], 'witness': changed[-1]['witness']})

    def test_startup_incomplete_or_absent_intro_resets_without_input(self):
        self.startup_scope()
        intro = self.startup_intro_rows()
        self.probe.nodes = Mock(side_effect=[intro] * 2 + [intro[1:], []] + [intro] * 5 + [self.startup_home_rows()] * 5)
        self.probe.startup()
        self.assertEqual(self.probe.nodes.call_count, 14)
        self.probe.act.assert_called_once()

    def test_startup_deadline_before_dispatch_never_clicks(self):
        clock = self.startup_scope()
        def read():
            if self.probe.nodes.call_count == 3: clock[0] = 60
            return self.startup_intro_rows()
        self.probe.nodes = Mock(side_effect=read)
        with self.assertRaisesRegex(native.Blocked, '^native_startup_not_ready$'): self.probe.startup()
        self.probe.act.assert_not_called()

    def test_startup_uncertain_continue_propagates_without_replay_or_os_fallback(self):
        self.startup_scope()
        self.probe.nodes = Mock(return_value=self.startup_intro_rows())
        self.probe.act.side_effect = native.Blocked('native_input_not_delivered')
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'): self.probe.startup()
        self.probe.act.assert_called_once()
        self.assertEqual(self.probe.nodes.call_count, 5)
        self.probe.adb.assert_called_once_with('shell', 'am', 'start', '-W', '-n', native.ACTIVITY)
        self.assertEqual(self.probe.report['native_startup_diagnostics']['C1-native-network']['stage'], 'continue_dispatch')

    def test_startup_delivered_but_persistent_intro_never_gets_second_continue_click(self):
        self.startup_scope()
        self.probe.nodes = Mock(return_value=self.startup_intro_rows())
        with self.assertRaisesRegex(native.Blocked, '^native_startup_not_ready$'): self.probe.startup()
        self.probe.act.assert_called_once()
        self.assertEqual(self.probe.report['native_startup_diagnostics']['C1-native-network']['continue_attempts'], 1)

    def test_startup_partial_hidden_foreign_or_private_home_never_returns(self):
        clock = self.startup_scope()
        cases = [[self.node('حسابي')], self.startup_home_rows()[:-1]]
        hidden, foreign = self.startup_home_rows(), self.startup_home_rows()
        hidden[0]['visible'] = False; foreign[0]['package'] = 'synthetic.foreign'
        cases += [hidden, foreign, self.startup_home_rows() + [self.node('تسجيل الخروج')]]
        for rows in cases:
            clock[0] = 0
            self.probe.nodes = Mock(return_value=rows)
            with self.subTest(rows=len(rows)), self.assertRaisesRegex(native.Blocked, '^native_startup_not_ready$'):
                self.probe.startup()
            self.probe.act.assert_not_called()

    def test_startup_observed_permission_deny_preserves_scope_and_resets_stability(self):
        self.startup_scope()
        intro, home = self.startup_intro_rows(), self.startup_home_rows()
        self.probe.nodes = Mock(side_effect=[intro] * 2 + [native.Blocked('unobserved')] + [intro] * 5 + [home] * 5)
        xml = '<hierarchy><node package="com.android.permissioncontroller" resource-id="com.android.permissioncontroller:id/permission_deny_button" bounds="[0,0][100,100]"/></hierarchy>'
        self.probe.adb.side_effect = lambda *args, **kwargs: xml if args[:2] == ('exec-out', 'cat') else ''
        self.probe.startup()
        self.assertEqual(sum(call.args[:3] == ('shell', 'input', 'tap') for call in self.probe.adb.call_args_list), 1)
        self.probe.adb.assert_any_call('shell', 'input', 'tap', 50, 50)
        self.probe.act.assert_called_once()
        self.assertEqual(self.probe.report['native_startup_diagnostics']['C1-native-network']['permission_denials'], 1)

    def test_startup_foreign_permission_control_never_receives_input(self):
        self.startup_scope(); self.probe.nodes = Mock(side_effect=native.Blocked('PRIVATE_STARTUP_EXCEPTION_SENTINEL'))
        xml = '<hierarchy><node package="synthetic.foreign" resource-id="synthetic.foreign:id/permission_deny_button" bounds="[0,0][100,100]"/></hierarchy>'
        self.probe.adb.side_effect = lambda *args, **kwargs: xml if args[:2] == ('exec-out', 'cat') else ''
        with self.assertRaisesRegex(native.Blocked, '^native_startup_window_unexpected$'): self.probe.startup()
        self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap') for call in self.probe.adb.call_args_list))
        self.probe.act.assert_not_called()
        self.assertNotIn('PRIVATE_STARTUP_EXCEPTION_SENTINEL', (self.probe.out / 'report.json').read_text())

    def test_startup_report_contains_only_fixed_stage_counts_and_no_source_tree_or_hash(self):
        self.startup_scope()
        private_row = self.node('PRIVATE_STARTUP_TREE_SENTINEL', path='0.999')
        private_row['witness'] = 'c' * 64
        rows = self.startup_home_rows() + [private_row]
        self.probe.nodes = Mock(return_value=rows)
        self.probe.startup()
        row = self.probe.report['native_startup_diagnostics']['C1-native-network']
        self.assertEqual(set(row), {'stage', 'observations', 'stable_observations', 'stability_resets', 'continue_attempts', 'permission_denials'})
        self.assertEqual(row['stage'], 'home_ready')
        self.assertTrue(all(type(value) is int and 0 <= value <= 120 for key, value in row.items() if key != 'stage'))
        serialized = (self.probe.out / 'report.json').read_text()
        for private in ('PRIVATE_STARTUP_TREE_SENTINEL', '0.999', 'c' * 64): self.assertNotIn(private, serialized)
        self.assertEqual((self.probe.report['frames'], self.probe.report['videos']), ([], []))

    def test_future_ime_deadline_diagnostic_is_fixed_and_does_not_echo_expiry(self):
        self.probe.case_phase('C1-cleanup')
        self.probe.authenticated = True
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false', 'INSTRUMENTATION_RESULT: op=account-dismiss-ime',
            'INSTRUMENTATION_RESULT: stage=input_deadline_expired',
            'INSTRUMENTATION_RESULT: foreground_category=APP',
            'INSTRUMENTATION_RESULT: deadline_utc_ms=1700000000123',
            'INSTRUMENTATION_RESULT: deadline_enforced=true', 'INSTRUMENTATION_CODE: 0']))
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-dismiss-ime', deadline_utc_ms='1700000000123')
        self.probe.adb.assert_called_once()
        failure = self.probe.report['native_input_failures'][0]
        self.assertEqual(failure['op'], 'account-dismiss-ime')
        self.assertEqual(failure['java_stage'], 'input_deadline_expired')
        self.assertNotIn('1700000000123', json.dumps(self.probe.report))
        self.assertNotIn('deadline_enforced', failure)
        self.assertEqual(self.probe.report['actions'], [])


    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.patch_root = patch.object(native, 'ROOT', self.root)
        self.patch_root.start()
        self.addCleanup(self.patch_root.stop)
        self.private = self.root / 'private'
        self.private.mkdir()
        # These are invented test strings; never import task-private credentials.
        self.access = {'otp': ''.join(str((index * 7 + 3) % 10) for index in range(6)), 'phones': {
            'broker': '+967700000001', 'support': '+967700000002',
            'regular': '+967700000003'}}
        self.probe = native.NativeAccount(self.private, {
            native.SECRET_NAME: json.dumps(self.access),
            'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40})
        self.probe.serial = 'emulator-5554'

    @staticmethod
    def node(text='', path='0.1', package=native.APP, bounds=None, **extra):
        return dict(text=text, path=path, package=package, visible=True,
                    enabled=True, bounds=bounds or [0, 0, 200, 50],
                    witness='a' * 64, **extra)

    def test_receipt_rejects_private_values_without_replacing_safe_previous_copy(self):
        path = self.probe.out / 'report.json'
        before = path.read_bytes()
        self.probe.report['unexpected'] = self.access['otp']
        with self.assertRaisesRegex(native.Blocked, 'private_value'):
            self.probe.save()
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn(self.access['otp'], path.read_text())

    def test_driver_retains_only_the_broker_and_never_activates_optional_accounts(self):
        self.assertEqual(set(self.probe.access['phones']), {'broker'})
        self.assertNotIn(self.access['phones']['support'], self.probe.private_values)
        self.assertNotIn(self.access['phones']['regular'], self.probe.private_values)
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_login_records_fixed_phase_before_each_unchanged_normal_operation(self):
        phases = []
        self.probe.tap = Mock(side_effect=lambda label: phases.append(self.probe.report['native_auth_phase']))
        self.probe.set = Mock(side_effect=lambda label, value: phases.append(self.probe.report['native_auth_phase']))
        self.probe.wait = Mock()
        self.probe.authenticated_account_evidence = Mock(
            side_effect=lambda: phases.append(self.probe.report['native_auth_phase']) or {})
        self.probe.login()
        self.assertEqual(phases, ['account_open', 'login_open', 'phone_entry', 'code_request',
                                  'otp_entry', 'confirm', 'postcondition'])
        self.assertEqual([call.args[0] for call in self.probe.tap.call_args_list],
                         ['حسابي', 'تسجيل الدخول أو إنشاء حساب', 'إرسال رمز واتساب', 'تأكيد والدخول'])
        self.probe.set.assert_any_call('رقم واتساب', self.access['phones']['broker'])
        self.probe.set.assert_any_call('رمز التحقق', self.access['otp'])
        self.assertIsNone(self.probe._auth_phase)
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.assertEqual(self.probe.report['frames'], [])

    def test_auth_input_failure_retains_only_fixed_phase_stage_op_and_booleans(self):
        witness = 'f' * 64
        private_blob = base64.b64encode(self.access['phones']['broker'].encode()).decode()
        self.probe.case_phase('C1-auth')
        self.probe.auth_phase('code_request')
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=account_pointer_tap',
            'INSTRUMENTATION_RESULT: foreground_category=APP',
            'INSTRUMENTATION_RESULT: tree_b64=' + private_blob,
            'INSTRUMENTATION_RESULT: reason=' + self.access['otp'],
            'INSTRUMENTATION_RESULT: witness=' + witness,
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.instrument('account-click', node_path='0.1', node_witness=witness)
        self.assertEqual(self.probe.report['native_input_failures'], [{
            'case': 'C1-auth', 'auth_phase': 'code_request', 'op': 'account-click',
            'java_stage': 'account_pointer_tap', 'foreground_category': 'APP',
            'passed_true': False, 'passed_false': True, 'code_minus_one': False,
            'code_zero': True, 'reason': 'native_input_not_delivered'}])
        serialized = (self.probe.out / 'report.json').read_text()
        for forbidden in [private_blob, witness, self.access['otp'], self.access['phones']['broker']]:
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['frames'], [])

    def test_private_exception_or_injected_stage_cannot_enter_auth_diagnostic(self):
        raw = self.access['phones']['broker'] + ' private framework exception ' + self.access['otp']
        for observation in [native.Blocked(raw), RuntimeError(raw),
                            native.Blocked('device_command_timeout'), '\n'.join([
                'INSTRUMENTATION_RESULT: op=account-set',
                'INSTRUMENTATION_RESULT: passed=false',
                'INSTRUMENTATION_RESULT: stage=' + raw,
                'INSTRUMENTATION_RESULT: foreground_category=' + raw,
                'INSTRUMENTATION_RESULT: arbitrary=' + raw,
                'INSTRUMENTATION_CODE: 0'])]:
            self.probe.report['native_input_failures'] = []
            self.probe.case_phase('C1-auth')
            self.probe.auth_phase('phone_entry')
            self.probe.adb = Mock(side_effect=observation) if isinstance(observation, Exception) \
                else Mock(return_value=observation)
            with self.subTest(observation_type=type(observation).__name__):
                with self.assertRaises(native.Blocked) as failure:
                    self.probe.instrument('account-set', value_b64=base64.b64encode(raw.encode()).decode())
                self.assertIn(str(failure.exception), native.INPUT_FAILURE_REASONS)
                diagnostic = self.probe.report['native_input_failures'][0]
                self.assertIsNone(diagnostic['java_stage'])
                self.assertEqual(diagnostic['foreground_category'], 'UNOBSERVED')
                self.assertIn(diagnostic['reason'], native.INPUT_FAILURE_REASONS)
                if isinstance(observation, native.Blocked) and str(observation) in native.INPUT_FAILURE_REASONS:
                    self.assertEqual(diagnostic['reason'], str(observation))
                self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())
                self.assertNotIn(self.access['otp'], json.dumps(diagnostic))

    def test_unknown_phase_and_requested_operation_never_enter_auth_diagnostic(self):
        raw = 'private-' + self.access['phones']['broker']
        with self.assertRaisesRegex(native.Blocked, '^fixed_native_auth_phase_required$'):
            self.probe.auth_phase(raw)
        self.assertNotIn('native_auth_phase', self.probe.report)
        self.probe.auth_phase('account_open')
        self.probe.case_phase('C1-auth')
        self.probe.adb = Mock(return_value='INSTRUMENTATION_RESULT: passed=false\nINSTRUMENTATION_CODE: 0')
        with self.assertRaises(native.Blocked):
            self.probe.instrument(raw)
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())

    def test_failure_diagnostic_is_disabled_outside_owned_case_and_covers_postauth(self):
        self.probe.adb = Mock(return_value='INSTRUMENTATION_RESULT: passed=false\nINSTRUMENTATION_CODE: 0')
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-snapshot')
        self.assertEqual(self.probe.report['native_input_failures'], [])
        self.probe.case_phase('C1-photo-save')
        self.probe.authenticated = True
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-snapshot')
        self.assertEqual(len(self.probe.report['native_input_failures']), 1)
        self.assertEqual(self.probe.report['native_input_failures'][0]['case'], 'C1-photo-save')
        self.assertIsNone(self.probe.report['native_input_failures'][0]['auth_phase'])

    def test_login_failure_clears_active_phase_without_auth_images_or_witness_hashes(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=root_ready', 'INSTRUMENTATION_CODE: 0']))
        self.probe.tap = Mock(side_effect=lambda label: self.probe.instrument('account-click'))
        with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
            self.probe.login()
        self.assertIsNone(self.probe._auth_phase)
        self.assertEqual(self.probe.report['native_auth_phase'], 'account_open')
        self.assertEqual(self.probe.report['native_input_failures'][0]['java_stage'], 'root_ready')
        self.assertFalse(self.probe.auth_attempted)
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_input_diagnostics_keep_only_first_failure_for_each_fixed_case_and_six_total(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=initial_witness_match',
            'INSTRUMENTATION_RESULT: foreground_category=APP', 'INSTRUMENTATION_CODE: 0']))
        for case in native.C1_CASES:
            self.probe.case_phase(case)
            self.probe.authenticated = True
            self.probe._auth_phase = self.access['phones']['broker']
            for repeated_failure in range(2):
                with self.assertRaisesRegex(native.Blocked, '^native_input_not_delivered$'):
                    self.probe.instrument('account-click', node_witness='f' * 64)
        failures = self.probe.report['native_input_failures']
        self.assertEqual(len(failures), 6)
        self.assertEqual([row['case'] for row in failures], list(native.C1_CASES))
        self.assertTrue(all(row['auth_phase'] is None and row['java_stage'] == 'initial_witness_match'
                            and row['foreground_category'] == 'APP' for row in failures))
        for row in failures:
            self.assertEqual(set(row), {'case', 'auth_phase', 'op', 'java_stage', 'foreground_category',
                                        'passed_true', 'passed_false', 'code_minus_one', 'code_zero', 'reason'})
        with self.assertRaisesRegex(native.Blocked, '^fixed_native_case_required$'):
            self.probe.case_phase(self.access['otp'])
        serialized = (self.probe.out / 'report.json').read_text()
        self.assertNotIn(self.access['phones']['broker'], serialized)
        self.assertNotIn('f' * 64, serialized)
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(self.probe.report['videos'], [])

    def test_cleanup_instrument_failure_is_retained_separately_from_original_case(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: op=account-click', 'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: stage=selected_path_resolve',
            'INSTRUMENTATION_RESULT: foreground_category=SYSTEM_UI', 'INSTRUMENTATION_CODE: 0']))
        self.probe.case_phase('C1-photo-save')
        with self.assertRaises(native.Blocked):
            self.probe.instrument('account-click')
        self.probe.native_logout = Mock(side_effect=lambda: self.probe.instrument('account-click'))
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        self.assertEqual([row['case'] for row in self.probe.report['native_input_failures']],
                         ['C1-photo-save', 'C1-cleanup'])
        fixture.cleanup.assert_called_once_with()

    def test_global_diagnostic_preserves_unexpected_exception_control_flow_without_its_text(self):
        raw = self.access['phones']['broker'] + ' private framework error'
        self.probe.case_phase('C1-native-network')
        self.probe.adb = Mock(side_effect=RuntimeError(raw))
        with self.assertRaises(RuntimeError):
            self.probe.instrument('account-snapshot')
        failure = self.probe.report['native_input_failures'][0]
        self.assertEqual(failure['case'], 'C1-native-network')
        self.assertEqual(failure['reason'], 'native_instrumentation_unobserved')
        self.assertNotIn(raw, (self.probe.out / 'report.json').read_text())

    def test_diagnostic_stage_and_foreground_allowlists_match_fixed_java_literals(self):
        source = Path(__file__).resolve().parents[1] / 'phase1_device_input/Phase1Input.java'
        text = source.read_text()
        stages = set(native.re.findall(r'stage="([a-z_]+)"', text))
        self.assertTrue(native.INPUT_JAVA_STAGES <= stages)
        classifier = text.split('private static String foregroundCategory', 1)[1].split(
            'private static String numbers', 1)[0]
        self.assertEqual(set(native.re.findall(r'return "([A-Z_]+)"', classifier)),
                         set(native.FOREGROUND_CATEGORIES))
        success, failure = text.split('} catch (Throwable failure)', 1)
        self.assertNotIn('putString("foreground_category"', success)
        self.assertIn('putString("foreground_category", foreground)', failure)

    def test_capture_requires_authenticated_state_before_any_device_read(self):
        self.probe.nodes = Mock()
        self.probe.adb = Mock()
        with self.assertRaisesRegex(native.Blocked, 'authentication_capture'):
            self.probe.safe_capture('C1-untrusted')
        self.probe.nodes.assert_not_called()
        self.probe.adb.assert_not_called()
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_capture_refuses_auth_screens_and_visible_private_account_values(self):
        self.probe.authenticated = True
        for unsafe in ['رمز التحقق', self.access['phones']['broker'],
                       self.access['phones']['broker'].lstrip('+')]:
            with self.subTest(unsafe_type='auth' if unsafe == 'رمز التحقق' else 'private'):
                self.probe.nodes = Mock(return_value=[self.node(unsafe)])
                self.probe.adb = Mock()
                with self.assertRaisesRegex(native.Blocked, 'private_native_capture'):
                    self.probe.safe_capture('C1-refused')
                self.probe.adb.assert_not_called()
        self.assertEqual(list(self.probe.out.glob('*.png')), [])

    def test_short_backend_phone_is_kept_whole_and_not_treated_as_a_country_prefix(self):
        digits = ''.join(str((index * 3 + 1) % 10) for index in range(7))
        env = {native.SECRET_NAME: json.dumps({'otp': self.access['otp'], 'phones': {'broker': digits}}),
               'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40}
        probe = native.NativeAccount(self.private, env)
        self.assertEqual(probe.access['phones']['broker'], digits)
        self.assertIn(digits, probe.private_values)
        self.assertNotIn(digits[3:], probe.private_values)

    def test_login_passes_the_provided_backend_phone_to_the_ui_without_country_rewriting(self):
        digits = ''.join(str((index * 7 + 2) % 10) for index in range(8))
        env = {native.SECRET_NAME: json.dumps({'otp': self.access['otp'], 'phones': {'broker': '+' + digits}}),
               'GITHUB_RUN_ID': '9', 'GITHUB_SHA': 'a' * 40}
        probe = native.NativeAccount(self.private, env)
        probe.tap = Mock(); probe.wait = Mock(); probe.set = Mock()
        probe.nodes = Mock(return_value=[self.node('عملي'), self.node('العملاء')])
        probe.login()
        self.assertEqual(probe.set.call_args_list[0].args, ('رقم واتساب', '+' + digits))
        self.assertTrue(probe.report['native_auth_executed'])

    def test_recording_is_tainted_on_observed_auth_transition(self):
        self.probe.recorder = Mock()
        rows = [self.node('رمز التحقق')]
        encoded = base64.b64encode(json.dumps(rows).encode()).decode()
        self.probe.instrument = Mock(return_value={'tree_b64': encoded})
        with self.assertRaisesRegex(native.Blocked, 'authentication_transition'):
            self.probe.nodes()
        self.assertTrue(self.probe.record_tainted)
        self.assertEqual(self.probe.report['videos'], [])

    def test_profile_authentication_can_pin_broker_role_from_revoked_api_setup_without_footer_assumption(self):
        self.probe.report['api_bootstrap'] = {'status': 'PASS', 'fresh_session_cleaned': True,
            'identity': {'actor_id': 28, 'account_type': 'broker'}}
        self.probe.nodes = Mock(return_value=[self.node('تسجيل الخروج'), self.node('عقاراتي')])
        result = self.probe.authenticated_account_evidence()
        self.assertEqual(result['native_auth_witness'], 'authenticated_profile_logout_control')
        self.assertTrue(result['broker_role_api_pinned'])
        self.assertFalse(result['broker_role_ui_witness'])
        self.assertTrue(result['professional_controls_visible'])

    def test_profile_logout_or_professional_controls_alone_do_not_prove_broker_role(self):
        self.probe.nodes = Mock(return_value=[self.node('تسجيل الخروج'), self.node('عقاراتي')])
        with patch.object(native.time, 'sleep'), patch.object(native.time, 'monotonic', side_effect=[0, 1, 91]):
            with self.assertRaisesRegex(native.Blocked, '^native_broker_auth_not_observed$'):
                self.probe.authenticated_account_evidence()

    def test_current_public_reference_and_exact_native_match_are_recorded_as_hashes_not_full_list(self):
        references = [{'id': 71, 'title': 'fresh-host-title'}, {'id': 72, 'title': 'other-current-title'}]
        self.probe.nodes = Mock(return_value=[self.node('fresh-host-title')])
        with patch.object(native, 'read_public_reference', return_value=references) as read:
            self.probe.public_network_readiness()
        read.assert_called_once_with()
        case = next(row for row in self.probe.report['cases'] if row['id'] == 'C1-native-network')
        self.assertEqual(case['status'], 'PASS')
        self.assertEqual(case['public_reference_count'], 2)
        self.assertEqual(case['visible_match_count'], 1)
        self.assertEqual(case['public_reference_sha256'], native.digest(references))
        serialized = json.dumps(self.probe.report)
        self.assertNotIn('fresh-host-title', serialized); self.assertNotIn('other-current-title', serialized)

    def test_old_or_unrelated_native_title_does_not_satisfy_a_fresh_host_reference(self):
        self.probe.nodes = Mock(return_value=[self.node('old-hardcoded-title')])
        self.probe.scroll = Mock()
        with patch.object(native, 'read_public_reference', return_value=[{'id': 71, 'title': 'current-host-title'}]), \
                patch.object(native.time, 'sleep'), patch.object(native.time, 'monotonic', side_effect=[0, 1, 61]):
            with self.assertRaisesRegex(native.Blocked, '^native_public_uat_response_not_observed$'):
                self.probe.public_network_readiness()
        self.assertEqual(next(row for row in self.probe.report['cases'] if row['id'] == 'C1-native-network')['status'], 'NOT RUN')

    def test_missing_real_public_response_never_attempts_native_match_or_api_bootstrap(self):
        self.probe.nodes = Mock(); self.probe.fixture_api = None
        with patch.object(native, 'read_public_reference', side_effect=native.FixtureError('public_reference_http_or_shape')):
            with self.assertRaises(native.FixtureError): self.probe.public_network_readiness()
        self.probe.nodes.assert_not_called()
        self.assertIsNone(self.probe.fixture_api)

    def test_failed_or_unfinished_recording_is_discarded_by_default(self):
        recorder = Mock()
        recorder.poll.return_value = 0
        self.probe.recorder = recorder
        self.probe.video_name = 'C1-unfinished'
        self.probe.adb = Mock(return_value='')
        self.probe.safe_capture = Mock()
        self.probe.record_stop()
        self.probe.safe_capture.assert_not_called()
        self.assertFalse(any(call.args[:2] == ('exec-out', 'cat')
                             for call in self.probe.adb.call_args_list))
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(list(self.probe.out.glob('*.mp4')), [])
        self.probe.adb.assert_any_call('shell', 'rm', '-f',
                                      '/sdcard/phase1-account.mp4', codes=(0, 1))

    def test_explicit_video_export_still_refuses_a_tainted_segment(self):
        recorder = Mock()
        recorder.poll.return_value = 0
        self.probe.recorder = recorder
        self.probe.record_tainted = True
        self.probe.video_name = 'C1-tainted'
        self.probe.adb = Mock(return_value='')
        self.probe.safe_capture = Mock()
        with self.assertRaisesRegex(native.Blocked, 'tainted_native_video'):
            self.probe.record_stop(export=True)
        self.probe.safe_capture.assert_not_called()
        self.assertEqual(self.probe.report['videos'], [])
        self.assertEqual(list(self.probe.out.glob('*.mp4')), [])

    def test_instrumentation_duplicate_receipt_is_not_accepted(self):
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=true',
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_CODE: -1']))
        with self.assertRaisesRegex(native.Blocked, 'ambiguous_native_input'):
            self.probe.instrument('account-click')

    def test_success_fields_without_successful_instrumentation_exit_are_refused(self):
        for ending in ['', 'INSTRUMENTATION_CODE: 0', 'INSTRUMENTATION_CODE: 1']:
            self.probe.adb = Mock(return_value='\n'.join([
                'INSTRUMENTATION_RESULT: passed=true',
                'INSTRUMENTATION_RESULT: op=account-click', ending]))
            with self.subTest(ending=ending):
                with self.assertRaisesRegex(native.Blocked, 'native_input_not_delivered'):
                    self.probe.instrument('account-click')

    def test_rejected_stale_witness_does_not_record_a_delivered_action(self):
        row = self.node('التالي', path='0.2.3', clickable=True)
        self.probe.adb = Mock(return_value='\n'.join([
            'INSTRUMENTATION_RESULT: passed=false',
            'INSTRUMENTATION_RESULT: op=account-click',
            'INSTRUMENTATION_RESULT: reason=input_precondition_or_delivery_failed',
            'INSTRUMENTATION_CODE: 0']))
        with self.assertRaisesRegex(native.Blocked, 'native_input_not_delivered'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'], [])
        invocation = self.probe.adb.call_args.args
        self.assertIn(row['path'], invocation)
        self.assertIn(row['witness'], invocation)

    def test_nonclickable_named_button_uses_only_that_observed_node(self):
        button = self.node('حسابي', path='0.2.4', clickable=False,
                           **{'class': 'android.widget.Button'})
        self.probe.nodes = Mock(return_value=[button])
        self.probe.act = Mock()
        self.probe.tap('حسابي', seek=False)
        self.probe.act.assert_called_once_with('click', button)

    def test_nonclickable_generic_view_has_no_coordinate_fallback(self):
        text = self.node('حسابي', clickable=False, **{'class': 'android.view.View'})
        self.probe.nodes = Mock(return_value=[text])
        self.probe.act = Mock()
        with self.assertRaisesRegex(native.Blocked, 'semantic_native_click_unavailable'):
            self.probe.tap('حسابي', seek=False)
        self.probe.act.assert_not_called()

    def test_duplicate_named_pointer_buttons_are_refused_instead_of_guessing_bounds(self):
        buttons = [self.node('التالي', path='0.2', clickable=False,
                             bounds=[0, 0, 150, 50], **{'class': 'android.widget.Button'}),
                   self.node('التالي', path='0.3', clickable=False,
                             bounds=[0, 80, 300, 160], **{'class': 'android.widget.Button'})]
        self.probe.nodes = Mock(return_value=buttons)
        self.probe.act = Mock()
        with self.assertRaisesRegex(native.Blocked, 'ambiguous_native_pointer_target'):
            self.probe.tap('التالي', seek=False)
        self.probe.act.assert_not_called()

    def test_existing_semantic_ancestor_remains_preferred_to_button_pointer_fallback(self):
        container = self.node('', path='0.1', clickable=True,
                              **{'class': 'android.view.View'})
        button = self.node('التالي', path='0.1.3', clickable=False,
                           **{'class': 'android.widget.Button'})
        self.probe.nodes = Mock(return_value=[container, button])
        self.probe.act = Mock()
        self.probe.tap('التالي', seek=False)
        self.probe.act.assert_called_once_with('click', container)

    def test_auth_pointer_action_keeps_only_count_and_never_the_node_witness(self):
        row = self.node('تأكيد والدخول')
        row['witness'] = 'f' * 64
        self.probe.instrument = Mock(return_value={
            'account_action_delivered': 'true', 'native_pointer_used': 'true',
            'native_pointer_events': '2'})
        with patch.object(native.time, 'sleep'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'], [])
        self.assertEqual(self.probe.report['auth_input_operations_delivered'], 1)
        self.assertNotIn(row['witness'], (self.probe.out / 'report.json').read_text())

    def test_postauth_pointer_action_keeps_the_verified_mode_and_exact_event_count(self):
        row = self.node('التالي')
        self.probe.authenticated = True
        self.probe.instrument = Mock(return_value={
            'account_action_delivered': 'true', 'native_pointer_used': 'true',
            'native_pointer_events': '2'})
        with patch.object(native.time, 'sleep'):
            self.probe.act('click', row)
        self.assertEqual(self.probe.report['actions'][0]['delivery'], 'pointer_tap')
        self.assertEqual(self.probe.report['actions'][0]['native_pointer_events'], 2)

    def test_failed_device_command_does_not_expose_captured_output(self):
        raw = self.access['otp'] + ' arbitrary private framework exception'
        result = subprocess.CompletedProcess(['adb'], 1, raw.encode(), raw.encode())
        with patch.object(native.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(native.Blocked, '^device_command_failed$') as failure:
                self.probe.command(['adb', 'shell', 'example'])
        self.assertNotIn(raw, str(failure.exception))

    def picker_xml(self, include_done=False, package='com.android.documentsui'):
        file = '<node package="' + package + '" text="' + self.probe.photo_name + \
               '" bounds="[10,10][30,30]" enabled="true" />'
        done = '<node package="' + package + '" text="OPEN" bounds="[90,190][110,210]" enabled="true" />'
        return '<hierarchy>' + file + (done if include_done else '') + '</hierarchy>'

    def test_os_picker_selects_file_once_then_the_observed_open_action(self):
        # A transient empty/IME tree and a delayed repeated Open are not an
        # APP return. Neither file selection nor final Open may be replayed.
        frames = iter([self.picker_xml(), self.picker_xml(include_done=True),
                       '<hierarchy/>', self.picker_xml(include_done=True),
                       '<hierarchy><node package="' + native.APP + '" text="صور الإعلان (1/12)" /></hierarchy>'])
        taps = []
        reads = []

        def adb(*args, **kwargs):
            if args[:2] == ('exec-out', 'cat'):
                reads.append(True)
                return next(frames)
            if args[:3] == ('shell', 'input', 'tap'):
                taps.append(args[3:])
            return ''

        self.probe.adb = Mock(side_effect=adb)
        self.probe.tap = Mock()
        self.probe.wait = Mock()
        with patch.object(native.time, 'sleep'):
            self.probe.photo_picker()
        self.assertEqual(taps, [(20, 20), (100, 200)])
        self.assertEqual(len(reads), 5)
        self.probe.wait.assert_called_once_with('صور الإعلان (1/12)', seconds=30)
        self.assertEqual(self.probe.report['os_photo_selection_observation'], {
            'exact_fixture_filename_observed': True, 'file_tap_sent_once': True,
            'final_open_sent_once': True, 'app_window_return_observed': True})

    def test_os_picker_selects_complete_grid_filename_metadata_not_preview_or_similar_name(self):
        package = 'com.android.documentsui'
        name = self.probe.photo_name
        xml = ('<hierarchy><node package="' + package + '">' +
               '<node package="' + package + '" enabled="true" clickable="true" '
               'content-desc="' + name + ', 12.4 kB, 8:00 AM" bounds="[10,20][90,100]" />' +
               '<node package="' + package + '" enabled="true" clickable="true" '
               'resource-id="' + package + ':id/preview_icon" content-desc="Preview the file ' + name +
               '" bounds="[70,20][90,40]" />' +
               '<node package="' + package + '" enabled="true" clickable="true" '
               'content-desc="other-' + name + ', 12.4 kB, 8:00 AM" bounds="[100,20][180,100]" />' +
               '</node></hierarchy>')
        frames = iter([xml, '<hierarchy><node package="' + native.APP + '" /></hierarchy>'])
        self.probe.adb = Mock(side_effect=lambda *a, **kw: next(frames)
                             if a[:2] == ('exec-out', 'cat') else '')
        self.probe.tap, self.probe.wait = Mock(), Mock()
        with patch.object(native.time, 'sleep'):
            self.probe.photo_picker()
        taps = [c.args[3:] for c in self.probe.adb.call_args_list
                if c.args[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [(50, 60)])
        self.probe.wait.assert_called_once_with('صور الإعلان (1/12)', seconds=30)

    def test_os_picker_uses_drawer_scoped_downloads_once_before_uncovered_file(self):
        package = 'com.android.documentsui'
        menu = '<node package="' + package + '" enabled="true" content-desc="Show roots" bounds="[0,0][20,20]" />'
        drawer = ('<hierarchy><node package="' + package + '">' + menu +
                  '<node package="' + package + '" enabled="true" text="Downloads" bounds="[200,0][300,30]" />' +
                  '<node package="' + package + '" resource-id="' + package + ':id/roots_list">' +
                  '<node package="' + package + '" enabled="true" text="Downloads" bounds="[10,70][90,110]" />' +
                  '</node>' + self.picker_xml().removeprefix('<hierarchy>').removesuffix('</hierarchy>') +
                  '</node></hierarchy>')
        frames = iter(['<hierarchy>' + menu + '</hierarchy>', drawer, drawer,
                       self.picker_xml(), '<hierarchy><node package="' + native.APP + '" /></hierarchy>'])
        self.probe.adb = Mock(side_effect=lambda *a, **kw: next(frames)
                             if a[:2] == ('exec-out', 'cat') else '')
        self.probe.tap, self.probe.wait = Mock(), Mock()
        with patch.object(native.time, 'sleep'):
            self.probe.photo_picker()
        taps = [c.args[3:] for c in self.probe.adb.call_args_list
                if c.args[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [(10, 10), (50, 90), (20, 20)])

    def test_os_picker_recycler_photo_can_be_focusable_without_own_click_listener(self):
        package='com.android.documentsui'
        item=('<node package="'+package+'" enabled="true" clickable="false" focusable="true" '
              'content-desc="'+self.probe.photo_name+', 12 kB, today" bounds="[10,20][90,100]" />')
        for in_documents in (True,False):
            wrapper='<node package="'+package+'" resource-id="'+package+':id/dir_list">' if in_documents else '<node package="'+package+'">'
            xml='<hierarchy>'+wrapper+item+'</node></hierarchy>'
            frames=iter([xml,'<hierarchy><node package="'+native.APP+'" /></hierarchy>'])
            self.probe.adb=Mock(side_effect=lambda *a,**kw: next(frames) if a[:2]==('exec-out','cat') else '')
            self.probe.tap,self.probe.wait=Mock(),Mock()
            with self.subTest(in_documents=in_documents),patch.object(native.time,'sleep'):
                if in_documents:self.probe.photo_picker()
                else:
                    self.probe.adb=Mock(side_effect=lambda *a,**kw: xml if a[:2]==('exec-out','cat') else '')
                    with patch.object(native.time,'monotonic',side_effect=[0,1,46]):
                        with self.assertRaisesRegex(native.Blocked,'^genuine_os_photo_selection_not_observed$'):
                            self.probe.photo_picker()
            taps=[c.args[3:] for c in self.probe.adb.call_args_list if c.args[:3]==('shell','input','tap')]
            self.assertEqual(taps,[(50,60)] if in_documents else [])

    def test_os_picker_duplicate_grid_files_or_preview_only_never_select(self):
        package = 'com.android.documentsui'
        name = self.probe.photo_name
        for descriptions in [(name + ', 12 kB, today',) * 2, ('Preview the file ' + name,)]:
            xml = '<hierarchy><node package="' + package + '">' + ''.join(
                '<node package="' + package + '" enabled="true" clickable="true" content-desc="' +
                description + '" bounds="[10,10][30,30]" />' for description in descriptions) + '</node></hierarchy>'
            self.probe.adb = Mock(side_effect=lambda *a, **kw: xml
                                 if a[:2] == ('exec-out', 'cat') else '')
            self.probe.tap = Mock()
            with self.subTest(descriptions=descriptions), patch.object(native.time, 'sleep'), \
                    patch.object(native.time, 'monotonic', side_effect=[0, 1, 46]):
                with self.assertRaisesRegex(native.Blocked, '^genuine_os_photo_selection_not_observed$'):
                    self.probe.photo_picker()
            self.assertFalse(any(c.args[:3] == ('shell', 'input', 'tap')
                                 for c in self.probe.adb.call_args_list))

    def test_os_picker_missing_app_return_never_opens_native_snapshot_or_repeats_open(self):
        frames = iter([self.picker_xml(), self.picker_xml(include_done=True),
                       self.picker_xml(include_done=True),
                       '<hierarchy><node package="com.example.other"><node package="' +
                       native.APP + '" text="underlying APP is not foreground" /></node></hierarchy>'])
        self.probe.adb = Mock(side_effect=lambda *a, **kw: next(frames)
                             if a[:2] == ('exec-out', 'cat') else '')
        self.probe.tap, self.probe.wait = Mock(), Mock()
        with patch.object(native.time, 'sleep'), patch.object(native.time, 'monotonic',
                side_effect=[0, 1, 2, 3, 4, 46]):
            with self.assertRaisesRegex(native.Blocked, '^genuine_os_picker_return_not_observed$'):
                self.probe.photo_picker()
        taps = [c.args[3:] for c in self.probe.adb.call_args_list
                if c.args[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [(20, 20), (100, 200)])
        self.probe.wait.assert_not_called()
        self.assertNotIn('os_photo_selection_observation', self.probe.report)

    def test_os_picker_private_app_return_taints_recording_without_export_or_native_read(self):
        for private in ('رمز التحقق', self.access['phones']['broker'], 'رقم الاتصال *'):
            frames = iter([self.picker_xml(), '<hierarchy><node package="' + native.APP +
                           '" text="' + private + '" /></hierarchy>'])
            self.probe.adb = Mock(side_effect=lambda *a, **kw: next(frames)
                                 if a[:2] == ('exec-out', 'cat') else '')
            self.probe.tap, self.probe.wait = Mock(), Mock()
            with self.subTest(private=private), patch.object(native.time, 'sleep'):
                with self.assertRaisesRegex(native.Blocked, '^private_transition_during_os_picker$'):
                    self.probe.photo_picker()
            self.assertTrue(self.probe.record_tainted)
            self.probe.wait.assert_not_called()
            self.assertEqual(self.probe.report['frames'], [])
            self.assertEqual(self.probe.report['videos'], [])
            self.assertNotIn(private, (self.probe.out / 'report.json').read_text())

    def test_os_picker_never_clicks_a_foreign_package_file(self):
        xml = self.picker_xml(include_done=True, package='com.example.untrusted')

        def adb(*args, **kwargs):
            return xml if args[:2] == ('exec-out', 'cat') else ''

        self.probe.adb = Mock(side_effect=adb)
        self.probe.tap = Mock()
        with patch.object(native.time, 'sleep'), \
                patch.object(native.time, 'monotonic', side_effect=[0, 1, 46]):
            with self.assertRaisesRegex(native.Blocked, 'genuine_os_photo_selection'):
                self.probe.photo_picker()
        self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap')
                             for call in self.probe.adb.call_args_list))

    def fixture(self):
        fixture = Mock()
        fixture.state = {'key': '83f56a55-1ee7-4b4f-a36b-7687f2e310e9',
                         'tag': 'AQER-C1-aabbccddeeff',
                         'title': 'مسودة اختبار الواجهة AQER-C1-aabbccddeeff',
                         'creation_request_sent': True}
        fixture.last_receipt = {'status': 'PASS', 'fresh_session_cleaned': True,
                                'revoked_token_http': 401}
        fixture.has_pending_fixture = False  # Its successful mocked cleanup removes only this UUID.
        return fixture

    def verified_install_environment(self):
        apk, helper = self.private / 'target.apk', self.private / 'input.apk'
        apk.write_bytes(b'synthetic product artifact for an offline boundary test')
        helper.write_bytes(b'synthetic helper artifact for an offline boundary test')
        proof = {'source_commit': self.probe.env['GITHUB_SHA'], 'package': native.APP,
                 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                 'input_driver': {'sha256': hashlib.sha256(helper.read_bytes()).hexdigest()},
                 'version_code': 1467}
        (self.private / 'APK_VERIFICATION.json').write_text(json.dumps(proof))
        self.probe.env['ANDROID_HOME'] = '/offline-test-sdk'
        self.probe.command = Mock(side_effect=lambda args, **kwargs:
                                  'List of devices attached\nemulator-5554\tdevice\n'
                                  if args == ['adb', 'devices'] else 'KVM is installed and usable')
        package_patch = patch.object(native.subprocess, 'run',
                                     return_value=subprocess.CompletedProcess(['fixed-pm-query'], 1, b'', b''))
        self.package_query = package_patch.start()
        self.addCleanup(package_patch.stop)

    @staticmethod
    def ready_adb(*args, **kwargs):
        if args[:2] == ('shell', 'getprop'):
            return {'ro.boot.qemu': '1', 'ro.build.version.sdk': '36',
                    'sys.boot_completed': '1', 'sys.user.0.ce_available': 'true'}[args[2]]
        if args == ('shell', 'service', 'check', 'package'):
            return 'Service package: found'
        if args == ('shell', 'pidof', 'system_server'):
            return '669'
        return ''

    def test_incomplete_boot_or_CE_blocks_package_queries_and_all_installs(self):
        self.verified_install_environment()
        for key, value in [('sys.boot_completed', ''), ('sys.boot_completed', '0'),
                           ('sys.user.0.ce_available', ''), ('sys.user.0.ce_available', 'false'),
                           ('sys.user.0.ce_available', 'True')]:
            def adb(*args, **kwargs):
                return value if args == ('shell', 'getprop', key) else self.ready_adb(*args, **kwargs)
            with self.subTest(property=key, observed=value):
                self.probe.adb = Mock(side_effect=adb)
                with self.assertRaisesRegex(native.Blocked, 'native_boot_CE_not_ready'):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' or call.args[:3] == ('shell', 'pm', 'path')
                                     for call in self.probe.adb.call_args_list))
                self.package_query.assert_not_called()

    def test_unready_or_unobserved_framework_blocks_package_queries_and_all_installs(self):
        self.verified_install_environment()
        checks = [
            (('shell', 'service', 'check', 'package'), ''),
            (('shell', 'service', 'check', 'package'), 'Service package: not found'),
            (('shell', 'service', 'check', 'package'), native.Blocked('device_command_timeout')),
            (('shell', 'pidof', 'system_server'), ''),
            (('shell', 'pidof', 'system_server'), '0'),
            (('shell', 'pidof', 'system_server'), '669 invalid'),
            (('shell', 'pidof', 'system_server'), '669 669'),
            (('shell', 'pidof', 'system_server'), native.Blocked('device_command_failed')),
        ]
        for command, value in checks:
            def adb(*args, **kwargs):
                if args == command:
                    if isinstance(value, Exception):
                        raise value
                    return value
                return self.ready_adb(*args, **kwargs)
            with self.subTest(command=command[1], observation_type=type(value).__name__):
                self.probe.adb = Mock(side_effect=adb)
                with self.assertRaises(native.Blocked):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' or call.args[:3] == ('shell', 'pm', 'path')
                                     for call in self.probe.adb.call_args_list))
                self.package_query.assert_not_called()

    def test_present_unobserved_and_error_package_queries_never_allow_install(self):
        self.verified_install_environment()
        self.probe.adb = Mock(side_effect=self.ready_adb)
        observations = [
            subprocess.CompletedProcess([], 1, b'', b'cmd: package service failed'),
            subprocess.CompletedProcess([], 1, b'', b'\n'),
            subprocess.CompletedProcess([], 1, b'unexpected response', b''),
            subprocess.CompletedProcess([], 0, b'', b''),
            subprocess.CompletedProcess([], 20, b'', b''),
            subprocess.CompletedProcess([], 0, b'package:/data/app/base.apk\n', b''),
            subprocess.TimeoutExpired(['fixed-pm-query'], 20),
            OSError('synthetic unobserved transport'),
        ]
        for observation in observations:
            self.probe.adb.reset_mock()
            self.package_query.reset_mock()
            self.package_query.side_effect = observation if isinstance(observation, Exception) else None
            self.package_query.return_value = observation
            with self.subTest(observation_type=type(observation).__name__):
                with self.assertRaises(native.Blocked):
                    self.probe.validate_and_install()
                self.assertFalse(any(call.args[0] == 'install' for call in self.probe.adb.call_args_list))
                self.package_query.assert_called_once_with(
                    ['adb', '-s', 'emulator-5554', 'shell', 'pm', 'path', native.APP],
                    capture_output=True, timeout=20)

    def test_absent_package_still_requires_fresh_healthy_framework_after_query(self):
        self.verified_install_environment()
        def adb(*args, **kwargs):
            if self.package_query.called and args == ('shell', 'service', 'check', 'package'):
                return 'Service package: not found'
            return self.ready_adb(*args, **kwargs)
        self.probe.adb = Mock(side_effect=adb)
        with self.assertRaisesRegex(native.Blocked, 'native_package_service_not_ready'):
            self.probe.validate_and_install()
        self.package_query.assert_called_once()
        self.assertFalse(any(call.args[0] == 'install' for call in self.probe.adb.call_args_list))

    def test_healthy_runtime_allows_only_verified_product_and_helper_installs(self):
        self.verified_install_environment()
        self.probe.adb = Mock(side_effect=self.ready_adb)
        self.probe.validate_and_install()
        installs = [call.args for call in self.probe.adb.call_args_list if call.args[0] == 'install']
        self.assertEqual(installs, [('install', '--no-streaming', self.private / 'target.apk'),
                                    ('install', '--no-streaming', '-t', self.private / 'input.apk')])
        self.assertEqual(self.probe.report['android_api'], 36)
        self.assertFalse(self.probe.report['native_auth_attempted'])

    def test_runtime_failure_after_product_install_blocks_helper_install(self):
        self.verified_install_environment()
        installed = []
        def adb(*args, **kwargs):
            if args[0] == 'install':
                installed.append(args)
            if installed and args == ('shell', 'service', 'check', 'package'):
                return 'Service package: not found'
            return self.ready_adb(*args, **kwargs)
        self.probe.adb = Mock(side_effect=adb)
        with self.assertRaisesRegex(native.Blocked, 'native_package_service_not_ready'):
            self.probe.validate_and_install()
        self.assertEqual(installed, [('install', '--no-streaming', self.private / 'target.apk')])

    def test_unhealthy_runtime_blocks_API_fixture_before_construction_or_authentication(self):
        for command in [('shell', 'service', 'check', 'package'), ('shell', 'pidof', 'system_server')]:
            def adb(*args, **kwargs):
                return '' if args == command else self.ready_adb(*args, **kwargs)
            self.probe.adb = Mock(side_effect=adb)
            with self.subTest(command=command[1]), patch.object(native, 'FixtureApi') as factory:
                with self.assertRaises(native.Blocked):
                    self.probe.bootstrap_fixture()
                factory.assert_not_called()
                self.assertIsNone(self.probe.fixture_api)
                self.assertFalse(self.probe.fixture_possible)
                self.assertFalse(self.probe.report['native_auth_attempted'])

    def test_bootstrap_receipt_distinguishes_api_setup_from_native_creation(self):
        fixture = self.fixture()
        self.probe.require_preauth_runtime = Mock()
        with patch.object(native, 'FixtureApi', return_value=fixture) as factory:
            self.probe.bootstrap_fixture()
        fixture.bootstrap.assert_called_once_with()
        factory.assert_called_once_with(self.access['phones']['broker'],
                                        self.access['otp'], '9')
        self.assertTrue(self.probe.fixture_possible)
        self.assertEqual(self.probe.bootstrap_title, fixture.state['title'])
        self.assertIn(fixture.state['tag'], self.probe.title)
        row = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-api-empty-fixture')
        self.assertEqual(row['status'], 'PASS')
        self.assertFalse(row['native_creation_claim'])
        self.assertFalse(row['facts_entered'])
        self.assertFalse(row['photos_uploaded'])
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_native_entry_refuses_unknown_or_foreign_fixture_before_any_ui_action(self):
        self.probe.tap = Mock()
        self.probe.fixture_api = self.fixture()
        for title in ['', 'protected old draft', None]:
            with self.subTest(title=title):
                with self.assertRaisesRegex(native.Blocked, 'known_new_fixture'):
                    self.probe.manual_entry(title)
        self.probe.tap.assert_not_called()

    def test_saved_fixture_entry_ignores_default_old_recovery_and_opens_exact_own_title(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        title = fixture.state['title']
        self.probe.tap = Mock()
        self.probe.has = Mock(return_value=False)
        self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل'),
                                             self.node('protected preexisting draft')])
        self.probe.wait = Mock()
        own = self.node(title)
        self.probe.seek = Mock(return_value=([own], [own]))
        self.probe.manual_entry(title)
        self.assertEqual([c.args[0] for c in self.probe.tap.call_args_list],
                         ['إضافة عقار', 'مسوداتي', title])
        self.probe.seek.assert_called_once_with(title)
        self.assertNotIn('متابعة الإعلان', [c.args[0] for c in self.probe.tap.call_args_list])
        self.assertNotIn('بدء إعلان جديد', [c.args[0] for c in self.probe.tap.call_args_list])

    def test_saved_fixture_entry_refuses_missing_or_duplicate_owned_title(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        title = fixture.state['title']
        for matches in [[], [self.node(title), self.node(title, path='0.2')]]:
            self.probe.tap = Mock()
            self.probe.has = Mock(return_value=False)
            self.probe.nodes = Mock(return_value=[self.node('لديك إعلان غير مكتمل')])
            self.probe.wait = Mock()
            self.probe.seek = Mock(return_value=(matches, matches))
            with self.subTest(matches=len(matches)):
                with self.assertRaisesRegex(native.Blocked, 'unique_owned_saved_fixture'):
                    self.probe.manual_entry(title)
            self.assertEqual([c.args[0] for c in self.probe.tap.call_args_list],
                             ['إضافة عقار', 'مسوداتي'])

    def test_network_prerequisite_prevents_api_bootstrap_or_login_when_blocked(self):
        self.probe.validate_and_install = Mock()
        self.probe.startup = Mock()
        self.probe.public_network_readiness = Mock(side_effect=native.Blocked('mock_network_unready'))
        self.probe.bootstrap_fixture = Mock()
        self.probe.login = Mock()
        self.probe.cleanup = Mock()
        self.probe.record_stop = Mock()
        self.assertFalse(self.probe.execute())
        self.probe.bootstrap_fixture.assert_not_called()
        self.probe.login.assert_not_called()
        self.probe.cleanup.assert_not_called()
        network = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-native-network')
        self.assertEqual(network['status'], 'BLOCKED')
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_execute_orders_real_network_then_api_setup_logout_then_native_login(self):
        order = []
        fixture = self.fixture()
        fixture.bootstrap.side_effect = lambda: order.extend(['api-bootstrap', 'api-logout-401'])
        self.probe.require_preauth_runtime = Mock(side_effect=lambda: order.append('fresh-framework'))
        self.probe.validate_and_install = Mock(side_effect=lambda: order.append('install'))
        self.probe.startup = Mock(side_effect=lambda: order.append('startup'))
        self.probe.public_network_readiness = Mock(side_effect=lambda: order.append('public-app-network'))
        self.probe.login = Mock(side_effect=lambda: order.append('native-login'))
        self.probe.create_and_save = Mock(side_effect=lambda: order.append('native-edit-save'))
        self.probe.restore = Mock(side_effect=lambda: order.append('native-restore'))
        self.probe.cleanup = Mock(side_effect=lambda: order.append('cleanup'))
        self.probe.record_stop = Mock()
        with patch.object(native, 'FixtureApi', return_value=fixture):
            self.assertFalse(self.probe.execute())  # Mocked UI does not earn native PASS.
        self.assertEqual(order, ['install', 'startup', 'public-app-network', 'fresh-framework', 'api-bootstrap',
                                 'api-logout-401', 'native-login', 'native-edit-save',
                                 'native-restore', 'cleanup'])
        self.assertFalse(self.probe.report['native_auth_executed'])

    def test_api_cleanup_runs_after_partial_setup_even_without_native_authentication(self):
        fixture = self.fixture()
        fixture.bootstrap.side_effect = native.FixtureError('mock_setup_reply_lost')
        fixture.last_receipt = {'status': 'BLOCKED', 'fresh_session_cleaned': True}
        self.probe.validate_and_install = Mock()
        self.probe.startup = Mock()
        self.probe.public_network_readiness = Mock()
        self.probe.require_preauth_runtime = Mock()
        self.probe.login = Mock()
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock()
        self.probe.adb = Mock(return_value='')
        with patch.object(native, 'FixtureApi', return_value=fixture):
            self.assertFalse(self.probe.execute())
        self.probe.login.assert_not_called()
        self.probe.native_logout.assert_not_called()
        fixture.cleanup.assert_called_once_with()
        self.assertFalse(self.probe.fixture_possible)
        self.assertFalse(self.probe.report['native_auth_executed'])
        self.assertFalse(self.probe.report['session_may_remain'])

    def test_native_logout_failure_does_not_skip_known_uuid_api_cleanup(self):
        fixture = self.fixture()
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock(side_effect=native.Blocked('mock_logout_unavailable'))
        self.probe.adb = Mock(return_value='')
        self.probe.tap = Mock()
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        fixture.cleanup.assert_called_once_with()
        self.probe.adb.assert_called_once_with('shell', 'am', 'force-stop', native.APP)
        self.probe.tap.assert_not_called()  # No native delete or unrelated recovery action.
        self.assertFalse(self.probe.fixture_possible)
        self.assertEqual(self.probe.report['api_cleanup'], fixture.last_receipt)

    def test_cleanup_orders_native_logout_writer_stop_and_only_known_api_fixture(self):
        order = []
        fixture = self.fixture()
        fixture.cleanup.side_effect = lambda: order.append('own-api-cleanup')
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.auth_attempted = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock(side_effect=lambda: order.append('native-logout'))
        self.probe.adb = Mock(side_effect=lambda *a, **k: order.append('native-writer-stop'))
        self.probe.tap = Mock()
        self.probe.cleanup()
        self.assertEqual(order, ['native-logout', 'native-writer-stop', 'own-api-cleanup'])
        self.probe.tap.assert_not_called()
        fixture.cleanup.assert_called_once_with()
        self.assertFalse(self.probe.fixture_possible)

    def test_api_cleanup_failure_preserves_pending_fixture_and_receipt(self):
        fixture = self.fixture()
        fixture.cleanup.side_effect = native.FixtureError('mock_protected_baseline_inconclusive')
        fixture.last_receipt = {'status': 'BLOCKED', 'fresh_session_cleaned': True}
        fixture.has_pending_fixture = True
        self.probe.fixture_api = fixture
        self.probe.fixture_possible = True
        self.probe.record_stop = Mock()
        self.probe.native_logout = Mock()
        self.probe.adb = Mock(return_value='')
        with self.assertRaisesRegex(native.Blocked, 'native_or_api_cleanup_incomplete'):
            self.probe.cleanup()
        self.probe.native_logout.assert_not_called()
        self.assertTrue(self.probe.fixture_possible)
        self.assertEqual(self.probe.report['api_cleanup'], fixture.last_receipt)
        case = next(r for r in self.probe.report['cases'] if r['id'] == 'C1-cleanup')
        self.assertNotEqual(case['status'], 'PASS')


class AccountDeliverySafetyTest(unittest.TestCase):
    def test_only_complete_semantic_and_native_pointer_receipts_are_accepted(self):
        fixtures = [
            ('click', {'semantic_action_used': 'true'}, 'semantic_action', 0),
            ('scroll', {'semantic_action_used': 'true'}, 'semantic_action', 0),
            ('set', {'set_text_delivered': 'true'}, 'semantic_text', 0),
            ('click', {'native_pointer_used': 'true', 'native_pointer_events': '2'},
             'pointer_tap', 2),
            ('scroll', {'native_pointer_used': 'true', 'native_pointer_events': '14'},
             'pointer_swipe', 14),
            ('set', {'set_text_delivered': 'true', 'native_pointer_used': 'true',
                     'native_pointer_events': '2'}, 'pointer_focus', 2),
        ]
        for kind, fields, mode, events in fixtures:
            with self.subTest(kind=kind, mode=mode):
                result = native.account_delivery({'account_action_delivered': 'true', **fields}, kind)
                self.assertEqual(result, {'delivery': mode, 'native_pointer_events': events})

    def test_pointer_attempt_without_exact_complete_event_count_is_refused(self):
        for kind in ['click', 'scroll', 'set']:
            right = '14' if kind == 'scroll' else '2'
            for count in [None, '', '0', '1', '3', '02', right + '.0', int(right)]:
                fields = {'account_action_delivered': 'true', 'native_pointer_used': 'true',
                          'set_text_delivered': 'true'}
                if count is not None:
                    fields['native_pointer_events'] = count
                with self.subTest(kind=kind, count=count):
                    with self.assertRaisesRegex(native.Blocked, 'native_pointer_event_count_mismatch'):
                        native.account_delivery(fields, kind)

    def test_semantic_and_pointer_modes_cannot_both_claim_the_same_delivery(self):
        fields = {'account_action_delivered': 'true', 'semantic_action_used': 'true',
                  'native_pointer_used': 'true', 'native_pointer_events': '2',
                  'set_text_delivered': 'true'}
        for kind in ['click', 'scroll', 'set']:
            with self.subTest(kind=kind):
                with self.assertRaisesRegex(native.Blocked, 'native_delivery_receipt_ambiguous'):
                    native.account_delivery(fields, kind)

    def test_missing_delivery_or_invalid_boolean_flags_are_refused(self):
        for kind in ['click', 'scroll']:
            with self.subTest(kind=kind):
                with self.assertRaisesRegex(native.Blocked, 'native_delivery_mode_missing'):
                    native.account_delivery({'account_action_delivered': 'true'}, kind)
        for flag in ['native_pointer_used', 'semantic_action_used']:
            for value in [True, 1, 'yes', 'TRUE', '1', None]:
                with self.subTest(flag=flag, value=value):
                    with self.assertRaisesRegex(native.Blocked, 'native_delivery_receipt_invalid'):
                        native.account_delivery({'account_action_delivered': 'true', flag: value}, 'click')

    def test_semantic_receipt_cannot_include_unclaimed_pointer_events(self):
        for count in ['0', '2', 0]:
            with self.subTest(count=count):
                with self.assertRaisesRegex(native.Blocked, 'unexpected_native_pointer_events'):
                    native.account_delivery({'account_action_delivered': 'true',
                                             'semantic_action_used': 'true',
                                             'native_pointer_events': count}, 'click')

    def test_set_requires_confirmed_text_delivery_even_when_focus_pointer_succeeded(self):
        for fields in [{}, {'native_pointer_used': 'true', 'native_pointer_events': '2'}]:
            with self.subTest(fields=fields):
                with self.assertRaisesRegex(native.Blocked, 'native_set_text_not_delivered'):
                    native.account_delivery({'account_action_delivered': 'true', **fields}, 'set')

    def test_no_receipt_bypasses_failed_delivery_or_unsupported_action_kind(self):
        with self.assertRaisesRegex(native.Blocked, 'native_action_not_delivered'):
            native.account_delivery({'semantic_action_used': 'true'}, 'click')
        with self.assertRaisesRegex(native.Blocked, 'native_action_kind_invalid'):
            native.account_delivery({'account_action_delivered': 'true'}, 'shell')


if __name__ == '__main__':
    unittest.main()
