import copy
import sys
from pathlib import Path
import unittest
import tempfile
import subprocess
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
        run=object.__new__(NativeRun);run.driver=Mock()
        run.apply({'op':'tap','args':{'label':'تنفيذ'}})
        run.driver.tap.assert_called_once_with('تنفيذ',seek=False)


if __name__ == '__main__': unittest.main()
