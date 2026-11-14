"""Meaningful boundaries for offline history, role-shell and Android link evidence."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
from xml.sax.saxutils import escape
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_phase23_offline_journeys as collector
from phase23_preflight import GateError

SIZE = (1080, 1920)


def proof(stage, **changes):
    role, scope = collector.ROLES[stage]
    ids = list(collector.RECENTS[stage])
    row = dict(event='ready', stage=stage, role=role, scope=scope, recent_ids=ids,
               file_exists=bool(ids), file_bytes=500*len(ids), restart_count=0 if stage <= 4 else 1,
               requests=stage+1, failures=0)
    row.update(changes)
    return row


def logs(stage):
    return '\n'.join('I/flutter: AQER_JOURNEY '+json.dumps(proof(index)) for index in range(stage+1))


def node(text, box='[20,300][1000,400]', **attrs):
    value = {'package': collector.PACKAGE, 'content-desc': text, 'bounds': box, **attrs}
    return '<node '+' '.join(key+'="'+escape(str(item), {'"': '&quot;'}).replace('\n', '&#10;')+'"' for key,item in value.items())+' />'


def screen(stage, after_work=False, reverse_recent=False, banner=collector.BANNER):
    parts = [node(collector.TARGET), node(banner), node(collector.marker(stage)),
             node(collector.NEXT, '[800,80][1040,180]', enabled='false' if stage in (4,13,15) else 'true', clickable='true')]
    if stage in (0,4,5,6,7,8):
        parts.append(node('شوهد مؤخرًا'))
        ids = list(collector.RECENTS[stage])
        if reverse_recent: ids.reverse()
        if not ids: parts.append(node('ما شاهدت عقارات بعد', '[40,500][1000,700]'))
        for index, number in enumerate(ids):
            parts.append(node(collector.TITLES[number]+'\nمنزل اصطناعي', f'[40,{500+index*350}][1000,{750+index*350}]'))
    elif stage in (1,2,3):
        parts.append(node(collector.TITLES[9002 if stage==2 else 9001]))
    elif 9 <= stage <= 13:
        tabs = collector.REGULAR_TABS if stage==13 else collector.BROKER_TABS
        selected = 'العقارات' if stage==13 else ('عملي' if after_work or stage in (10,12) else 'الرئيسية')
        for index,label in enumerate(sorted(tabs)):
            parts.append(node(label, f'[{index*250},1700][{index*250+240},1850]',
                              enabled='true', clickable='true', selected='true' if label==selected else 'false'))
        if stage==10 or (stage==9 and after_work):
            parts += [node('لوحة الدلال'), node('يحتاج إجراء منك', '[40,600][1000,700]')]
        if stage==12 or (stage==11 and after_work):
            parts.append(node('أدوات الدلال بعد اعتماد التوثيق'))
    elif stage==14:
        parts += [node('محادثة اصطناعية للاختبار'), node('رسالة اصطناعية عبر رابط أندرويد', '[40,600][1000,750]')]
    elif stage==15:
        parts += [node('المفضلة'),node('لا توجد عقارات محفوظة\n'+collector.FAVORITES_HELPER,'[0,370][840,1346]'),
                  node('AQER_JOURNEY_SCROLL', '[0,223][840,1430]',scrollable='true',enabled='true')]
    result='<hierarchy>'+''.join(parts)+'</hierarchy>'
    return result.replace('[800,80][1040,180]','[600,80][820,180]').replace('[20,300][1000,400]','[20,300][800,400]') if stage==15 else result


class ProofTests(unittest.TestCase):
    def test_all_sixteen_stages_require_actual_expected_history_scope_and_ui(self):
        for stage in range(16):
            with self.subTest(stage=stage):
                size=collector.COMPACT_SIZE if stage==15 else SIZE
                nodes, value = collector.ready_for(screen(stage), logs(stage), stage, size)
                collector.assert_evidence(nodes, value, stage, size, proof(4), message_before=proof(13))
        for stage in (9,11):
            nodes, value = collector.ready_for(screen(stage, after_work=True), logs(stage), stage, SIZE)
            collector.assert_evidence(nodes, value, stage, SIZE, proof(4), after_work=True)

    def test_duplicate_order_and_account_leak_are_coverage_failures(self):
        for stage, ids in [(3,[9001,9002,9001]), (4,[9002,9001]), (6,[9001]), (7,[9002])]:
            with self.subTest(stage=stage), self.assertRaises(collector.CoverageIncomplete):
                collector.assert_evidence(collector.ui_guard(screen(stage),stage,SIZE),
                                          proof(stage,recent_ids=ids),stage,SIZE,proof(4))
        nodes=collector.ui_guard(screen(4,reverse_recent=True),4,SIZE)
        with self.assertRaisesRegex(collector.CoverageIncomplete,'recent_ui_mismatch'):
            collector.assert_evidence(nodes,proof(4),4,SIZE)

    def test_restart_requires_the_real_existing_file_with_preserved_size(self):
        nodes=collector.ui_guard(screen(5),5,SIZE)
        for value in (proof(5,file_exists=False),proof(5,file_bytes=999),proof(5,restart_count=0)):
            with self.subTest(value=value),self.assertRaises(collector.CoverageIncomplete):
                collector.assert_evidence(nodes,value,5,SIZE,proof(4))
        with self.assertRaises(collector.CoverageIncomplete):
            collector.assert_evidence(nodes,proof(5),5,SIZE,None)

    def test_unknown_fields_ids_failures_and_stale_ready_fail_closed(self):
        values=[proof(0,secret='private'),proof(0,recent_ids=[42]),proof(0,file_bytes=True),
                proof(0,failures=1),dict(proof(0),stage=True),proof(0,scope='live'),
                {'event':'failure','code':'socket_forbidden','failures':1}]
        for value in values:
            with self.subTest(value=value),self.assertRaises(GateError):
                collector.proof_events('AQER_JOURNEY '+json.dumps(value))
        for value in ('AQER_JOURNEY not-json','AQER_JOURNEY_FAILURE'):
            with self.assertRaises(GateError): collector.proof_events(value)
        with self.assertRaises(GateError): collector.ready_for(screen(2),logs(1),2,SIZE)
        with self.assertRaises(GateError): collector.ready_for(screen(2),'AQER_JOURNEY '+json.dumps(proof(2)),2,SIZE)

    def test_natural_workspace_gate_and_regular_bar_are_distinct(self):
        for stage in (9,11):
            nodes=collector.ui_guard(screen(stage),stage,SIZE)
            with self.assertRaises(collector.CoverageIncomplete):
                collector.assert_evidence(nodes,proof(stage),stage,SIZE,after_work=True)
        bad=screen(13).replace('إعلاناتي','العملاء')
        with self.assertRaisesRegex(collector.CoverageIncomplete,'shell_ui_mismatch'):
            collector.assert_evidence(collector.ui_guard(bad,13,SIZE),proof(13),13,SIZE)
        bad=screen(12).replace('أدوات الدلال بعد اعتماد التوثيق','لوحة الدلال')
        with self.assertRaises(collector.CoverageIncomplete):
            collector.assert_evidence(collector.ui_guard(bad,12,SIZE),proof(12),12,SIZE)

    def test_message_link_requires_both_actual_thread_anchors_and_new_get(self):
        nodes=collector.ui_guard(screen(14),14,SIZE)
        with self.assertRaises(collector.CoverageIncomplete):
            collector.assert_evidence(nodes,proof(14,requests=proof(13)['requests']),14,SIZE,message_before=proof(13))
        bad=screen(14).replace('رسالة اصطناعية عبر رابط أندرويد','property link only')
        with self.assertRaises(collector.CoverageIncomplete):
            collector.assert_evidence(collector.ui_guard(bad,14,SIZE),proof(14),14,SIZE,message_before=proof(13))


class InputTests(unittest.TestCase):
    def test_bidi_formatted_labels_match_but_fullscreen_merged_next_still_cannot_tap(self):
        value=screen(0)
        for label in (collector.TARGET,collector.BANNER,collector.marker(0),collector.NEXT):
            value=value.replace(label,'\u202a'+label+'\u202c')
        self.assertEqual(collector.input_point(value,logs(0),0,SIZE,collector.NEXT),(920,130))
        merged='<hierarchy>'+node('\n'.join('\u202a'+x+'\u202c' for x in
            (collector.TARGET,collector.BANNER,collector.marker(0),collector.NEXT)),
            '[0,0][1080,1920]',enabled='true',clickable='true')+'</hierarchy>'
        with self.assertRaisesRegex(GateError,'next_bounds_invalid'):
            collector.input_point(merged,logs(0),0,SIZE,collector.NEXT)

    def test_timeout_diagnostic_accepts_busy_synthetic_target_but_never_foreign_surface(self):
        class FakeDevice:
            value = screen(0).replace('enabled="true"', 'enabled="false"')
            def xml(self): return self.value
            def log(self): return ''
            def adb(self, *_args, **_kwargs):
                return b'\x89PNG\r\n\x1a\n'+b'\x00'*8+struct.pack('>II',*SIZE)
        failure=collector.ReadyTimeout(0,-1,'offline_journey_ready_missing')
        device=FakeDevice()
        with tempfile.TemporaryDirectory() as directory:
            private=Path(directory)
            diagnostic=collector.timeout_diagnostic(device,private,failure,SIZE)
            self.assertTrue(diagnostic['target_frame_verified'])
            self.assertEqual(diagnostic['last_ready_stage'],-1)
            self.assertEqual({p.name for p in private.iterdir()}, {'DIAGNOSTIC.json','DIAGNOSTIC.xml','DIAGNOSTIC.png'})
        device.value=device.value.replace(collector.PACKAGE,'com.other.app')
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(GateError,'foreign_surface'):
                collector.timeout_diagnostic(device,Path(directory),failure,SIZE)
            self.assertEqual(list(Path(directory).iterdir()),[])

    def test_timeout_without_target_marker_cannot_export_pixels(self):
        class FakeDevice:
            def xml(self): return screen(0).replace(collector.TARGET,'unready')
            def log(self): return ''
            def adb(self, *_args, **_kwargs): raise AssertionError('must not capture pixels')
        with tempfile.TemporaryDirectory() as directory:
            value=collector.timeout_diagnostic(FakeDevice(),Path(directory),
                collector.ReadyTimeout(0,-1,'offline_journey_expected_surface_missing'),SIZE)
            self.assertFalse(value['target_frame_verified'])
            self.assertEqual({p.name for p in Path(directory).iterdir()},{'DIAGNOSTIC.json'})
        with self.assertRaises(GateError):collector.ReadyTimeout(0,-1,'private arbitrary text')

    def test_missing_header_capture_requires_exact_installed_apk_and_resumed_activity(self):
        class FakeDevice:
            activity = collector.ACTIVITY
            apk = b'bound synthetic apk'
            def xml(self): return screen(0).replace(collector.TARGET,'unready')
            def log(self): return logs(0)
            def adb(self, *args, **_kwargs):
                if args[:3] == ('shell','dumpsys','activity'):
                    return 'topResumedActivity=ActivityRecord{abc u0 '+self.activity+' t12}'
                if args[:3] == ('shell','pm','path'): return 'package:/data/app/synthetic/base.apk'
                if args[:2] == ('exec-out','cat'): return self.apk
                if args[:2] == ('exec-out','screencap'):
                    return b'\x89PNG\r\n\x1a\n'+b'\x00'*8+struct.pack('>II',*SIZE)
                raise AssertionError(args)
        failure=collector.ReadyTimeout(0,0,'offline_journey_expected_surface_missing')
        device=FakeDevice();sha=hashlib.sha256(device.apk).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            value=collector.timeout_diagnostic(device,Path(directory),failure,SIZE,sha)
            self.assertTrue(value['target_frame_verified'])
            self.assertFalse(value['has_target'])
            self.assertTrue(value['has_banner']); self.assertTrue(value['has_next'])
            self.assertEqual(value['capture_identity'],'fresh_synthetic_apk_activity')
            self.assertEqual(value['ready_count'],1)
        for activity, expected_sha in [('other.package/Other','a'*64),(collector.ACTIVITY,'a'*64)]:
            device.activity=activity
            with tempfile.TemporaryDirectory() as directory,self.assertRaises(GateError):
                collector.timeout_diagnostic(device,Path(directory),failure,SIZE,expected_sha)
                self.assertEqual(list(Path(directory).iterdir()),[])

    def test_compact_supplement_forces_real_scroll_even_with_merged_helper_bounds(self):
        size=collector.COMPACT_SIZE
        gesture=collector.supplement_scroll(screen(15),logs(15),size)
        self.assertEqual(gesture,(420,1188,420,464))
        nested=screen(15).replace('</hierarchy>',node('', '[20,500][820,1350]',scrollable='true',enabled='true')+'</hierarchy>')
        self.assertEqual(collector.supplement_scroll(nested,logs(15),size),(420,1180,420,670))
        for xml,log,dimensions in [(screen(15).replace('scrollable="true"','scrollable="false"'),logs(15),size),
                                    (screen(14),logs(14),size),(screen(15),logs(15),SIZE),
                                    (screen(15).replace(collector.BANNER,'LIVE'),logs(15),size)]:
            with self.assertRaises(GateError):collector.supplement_scroll(xml,log,dimensions)

    def test_busy_semantics_frame_waits_but_unknown_surface_does_not(self):
        device=collector.JourneyDevice('emulator-5554',float('inf'))
        busy=screen(1).replace('enabled="true"','enabled="false"')
        with patch.object(device,'log',return_value=logs(1)), \
             patch.object(device,'xml',side_effect=[busy,screen(1)]), \
             patch.object(collector.time,'sleep'):
            xml,_nodes,value=device.wait_ready(1,SIZE)
            self.assertEqual(xml,screen(1));self.assertEqual(value,proof(1))
        foreign=screen(1).replace(collector.PACKAGE,'com.other.app')
        with patch.object(device,'log',return_value=logs(1)), \
             patch.object(device,'xml',return_value=foreign),self.assertRaises(GateError):
            device.wait_ready(1,SIZE)

    def test_only_next_and_observed_natural_work_tab_can_be_tapped(self):
        self.assertEqual(collector.input_point(screen(1),logs(1),1,SIZE,collector.NEXT),(920,130))
        point=collector.input_point(screen(9),logs(9),9,SIZE,'عملي')
        self.assertGreater(point[1],SIZE[1]*.75)
        for stage,label in [(0,'عملي'),(9,'العملاء'),(4,collector.NEXT),(13,collector.NEXT),(15,collector.NEXT)]:
            with self.subTest(stage=stage,label=label),self.assertRaises(GateError):
                collector.input_point(screen(stage),logs(stage),stage,SIZE,label)
        with self.assertRaises(GateError):
            collector.input_point(screen(9,banner='LIVE'),logs(9),9,SIZE,'عملي')

    def test_wrong_case_foreign_ui_xml_entities_and_ambiguous_controls_rejected(self):
        for value in (screen(0).replace(collector.PACKAGE,'com.other.app'),
                      '<!DOCTYPE x>'+screen(0),screen(0).replace(collector.marker(0),collector.marker(1)),
                      screen(0).replace('</hierarchy>',node(collector.NEXT)+'</hierarchy>')):
            with self.assertRaises(GateError): collector.ui_guard(value,0,SIZE)

    def test_restart_preserves_files_and_intent_is_fixed_android_view(self):
        device=collector.JourneyDevice('emulator-5554',1)
        with patch.object(device,'adb') as adb:
            device.restart_preserving_files()
            self.assertEqual(adb.call_args_list[0].args,('shell','am','force-stop',collector.PACKAGE))
            self.assertEqual(adb.call_args_list[1].args,('shell','am','start','-W','-n',collector.ACTIVITY))
            self.assertFalse(any('clear' in call.args or 'install' in call.args for call in adb.call_args_list))
            adb.reset_mock();device.open_message_link()
            self.assertEqual(adb.call_args.args,('shell','am','start','-W','-a','android.intent.action.VIEW',
                                               '-d','realestate://app/messages/9010','-p',collector.PACKAGE))

    def test_capture_rechecks_identity_before_retaining_pixels(self):
        value=screen(0)
        class FakeDevice:
            def wait_ready(self,*_args):return value,collector.ui_guard(value,0,SIZE),proof(0)
            def adb(self,*_args,**_kwargs):return b'\x89PNG\r\n\x1a\n'+b'\x00'*8+struct.pack('>II',*SIZE)
            def xml(self):return value.replace(collector.TARGET,'ordinary-app')
            def log(self):return logs(0)
        with tempfile.TemporaryDirectory() as directory:
            private=Path(directory);frames=[]
            with self.assertRaises(GateError):collector.capture(FakeDevice(),private,frames,0,SIZE)
            self.assertEqual(list(private.iterdir()),[])
            self.assertEqual(frames,[])


class ExportTests(unittest.TestCase):
    def identity(self):return {'source_sha':'a'*40,'run_id':'123','product_trees':collector.TREES,
                              'package':collector.PACKAGE,'version_code':1901,'apk_sha256':'b'*64}
    def frames(self,private,count=19):
        rows=[]
        for stage in range(16):
            for suffix in (('', '-after-work') if stage in (9,11) else ('','-after-scroll') if stage==15 else ('',)):
                name=f'stage-{stage:02d}'+suffix
                row={'frame':name,'stage':stage,'after_work':suffix=='-after-work','after_scroll':suffix=='-after-scroll',
                     'display_size_px':list(collector.COMPACT_SIZE if stage==15 else SIZE),'accepted':True}
                rows.append(row)
                for suffix in ('png','xml','json'):(private/(name+'.'+suffix)).write_text('SYNTHETIC_PRIVATE')
                if len(rows)==count:return rows
        return rows
    def encrypt(self,archive,destination,recipient):
        with zipfile.ZipFile(archive) as z:self.assertFalse(any(n.endswith('.apk') for n in z.namelist()))
        destination.write_bytes(b'\x30opaque-ciphertext')
        return {'file':destination.name,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
                'bytes':destination.stat().st_size,'cipher':'CMS-AES256GCM-RSAOAEP-SHA256'}

    def test_complete_public_receipt_has_nineteen_frames_and_no_plaintext(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'frames';private.mkdir();out=root/'sealed'
            rows=self.frames(private)
            receipt=collector.export(private,out,self.identity(),rows,1,encryptor=self.encrypt)
            self.assertEqual(receipt['frame_count'],19)
            self.assertEqual(receipt['completed_stages'],list(range(16)))
            self.assertEqual(receipt['display_sizes_px'],[list(SIZE),list(collector.COMPACT_SIZE)])
            self.assertTrue(receipt['compact_favorites_forced_scroll'])
            self.assertTrue(receipt['compact_favorites_manual_pixel_review_required'])
            self.assertTrue(receipt['coverage_complete'])
            self.assertTrue(receipt['message_custom_scheme_proven'])
            self.assertFalse(receipt['https_app_links_proven'])
            self.assertFalse(receipt['phase23_accepted'])
            self.assertEqual({p.name for p in out.iterdir()},{'checkpoints.cms','PUBLIC_RECEIPT.json'})
            self.assertNotIn('SYNTHETIC_PRIVATE',(out/'PUBLIC_RECEIPT.json').read_text())
            self.assertFalse((root/'frames.zip').exists())

    def test_controlled_partial_export_is_nonaccepting_and_bound_to_real_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'frames';private.mkdir();out=root/'sealed'
            rows=self.frames(private,6);rows[-1]['accepted']=False
            receipt=collector.export(private,out,self.identity(),rows,1,
                                      collector.CoverageIncomplete('file_persistence_mismatch',5),self.encrypt)
            self.assertFalse(receipt['coverage_complete'])
            self.assertEqual(receipt['result'],'INCOMPLETE')
            self.assertEqual(receipt['completed_stages'],list(range(5)))
            self.assertFalse(receipt['message_custom_scheme_proven'])
            self.assertEqual(receipt['failure_stage'],5)
            with self.assertRaises(GateError):
                collector.export(private,root/'other',self.identity(),rows,1,GateError('network'),self.encrypt)

    def test_timeout_keeps_prior_verified_prefix_or_zero_frames_without_promoting_failure(self):
        for count in (0,1,10):
            with self.subTest(count=count),tempfile.TemporaryDirectory() as directory:
                root=Path(directory); private=root/'frames'; private.mkdir()
                rows=self.frames(private,count) if count else []
                stage=0 if count==0 else 1 if count==1 else 9
                failure=collector.ReadyTimeout(stage,stage-1,'offline_journey_ready_missing')
                diagnostic={'stage':stage,'last_ready_stage':stage-1,'wait_reason':failure.wait_reason,
                            'target_frame_verified':False,'png_sha256':None,'xml_sha256':None,
                            'display_size_px':list(SIZE),'capture_identity':None,
                            'has_target':False,'has_banner':False,'has_next':False,'node_count':1,
                            'observed_stages':[],'structure_sha256':'a'*64,'ready_count':count,'next_enabled':'missing'}
                (private/'DIAGNOSTIC.json').write_text(json.dumps(diagnostic))
                receipt=collector.export(private,root/'sealed',self.identity(),rows,int(stage>=5),
                    failure,self.encrypt,diagnostic=diagnostic)
                self.assertFalse(receipt['coverage_complete'])
                self.assertEqual(receipt['frame_count'],count)
                self.assertEqual(receipt['failure_stage'],stage)
                self.assertEqual(receipt['result'],'INCOMPLETE')
                self.assertFalse(receipt['phase23_accepted'])

    def test_timeout_diagnostic_cannot_export_unknown_fields_or_skip_unverified_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'frames';private.mkdir();rows=self.frames(private,1)
            failure=collector.ReadyTimeout(1,0,'offline_journey_ready_missing')
            base={'stage':1,'last_ready_stage':0,'wait_reason':failure.wait_reason,
                  'target_frame_verified':False,'png_sha256':None,'xml_sha256':None,'display_size_px':list(SIZE),
                  'capture_identity':None,'has_target':False,'has_banner':False,'has_next':False,
                  'node_count':1,'observed_stages':[],'structure_sha256':'a'*64,'ready_count':1,'next_enabled':'missing'}
            for changes in ({'raw_log':'private'}, {'stage':2}, {'png_sha256':'a'*64}, {'target_frame_verified':True}):
                diagnostic=dict(base,**changes);(private/'DIAGNOSTIC.json').write_text(json.dumps(diagnostic))
                with self.subTest(changes=changes),self.assertRaises((GateError,FileNotFoundError)):
                    collector.export(private,root/'bad',self.identity(),rows,0,failure,self.encrypt,diagnostic=diagnostic)
            rows[0]['accepted']=False;(private/'DIAGNOSTIC.json').write_text(json.dumps(base))
            with self.assertRaises(GateError):
                collector.export(private,root/'bad',self.identity(),rows,0,failure,self.encrypt,diagnostic=base)

    def test_missing_steps_unverified_frames_unknown_public_fields_and_apk_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'frames';private.mkdir();rows=self.frames(private)
            with self.assertRaises(GateError):
                collector.export(private,root/'bad',dict(self.identity(),raw_log='private'),rows,1,encryptor=self.encrypt)
            with self.assertRaises(GateError):
                collector.export(private,root/'bad',self.identity(),rows[1:],1,encryptor=self.encrypt)
            rows[0]['accepted']=False
            with self.assertRaises(GateError):
                collector.export(private,root/'bad',self.identity(),rows,1,encryptor=self.encrypt)
            rows[0]['accepted']=True;(private/'target.apk').write_text('APK')
            with self.assertRaises(GateError):
                collector.export(private,root/'bad',self.identity(),rows,1,encryptor=self.encrypt)


class ContextAndWorkflowTests(unittest.TestCase):
    def test_only_x86_64_compiled_journey_target_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            apk=Path(directory)/'target.apk'
            for names,content in [(['lib/x86_64/libapp.so'],b'ordinary'),
                                  (['lib/arm64-v8a/libapp.so'],(collector.TARGET+' '+collector.BANNER).encode())]:
                with zipfile.ZipFile(apk,'w') as z:
                    for name in names:z.writestr(name,content)
                with self.assertRaises(GateError):collector.verify_archive(apk)
            with zipfile.ZipFile(apk,'w') as z:
                z.writestr('lib/x86_64/libapp.so',(collector.TARGET+' '+collector.BANNER).encode())
            collector.verify_archive(apk)

    def test_exact_reviewed_guard_and_secret_rejection_are_preserved(self):
        env={'PHASE23_OFFLINE_JOURNEYS':'true'}
        with patch.object(collector,'guard') as guard,patch.object(collector,'digest',return_value=collector.RECIPIENT_SHA256):
            collector.context(env);guard.assert_called_once_with(env)
            for name in ('AQER_PHASE1_TEST_ACCESS_JSON','AQER_RELEASE_KEY_PASSWORD'):
                with self.assertRaises(GateError):collector.context(dict(env,**{name:'secret'}))
        message=collector.failure_message(RuntimeError('private path and secret output'))
        self.assertNotIn('secret',message)
        self.assertIn('exception=RuntimeError',message)

    def test_workflow_builds_only_isolated_target_and_uploads_ciphertext_on_controlled_failure(self):
        text=(Path(__file__).resolve().parents[2]/'.github/workflows/phase23-offline-journeys.yml').read_text()
        self.assertIn('--target-platform android-x64',text)
        self.assertIn('--target=lib/phase23_offline_journeys_main.dart',text)
        self.assertIn('--dart-define=APP_SHARE_BASE_URL=https://synthetic.invalid',text)
        self.assertIn('timeout-minutes: 35',text)
        self.assertIn('--max-seconds 600',text)
        self.assertNotIn('${{ secrets.',text)
        self.assertNotIn('--target lib/main.dart',text)
        self.assertNotIn('prepare_phase23_visual_delivery',text)
        upload=text.split('name: Upload only recipient-encrypted synthetic checkpoints')[1].split('name: Stop the disposable emulator')[0]
        self.assertIn('always()',upload)
        self.assertIn('checkpoints.cms',upload)
        self.assertNotIn('.apk',upload)


if __name__=='__main__':unittest.main()
