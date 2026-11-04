"""Synthetic official-console hook tests; no device or account is accessed."""
import ast
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'oneshot'))
import ci_probe_adapter as bridge
import c1_home_capture as home

spec=importlib.util.spec_from_file_location('_home_frozen_console',HERE/'variants/runtime/host_console_capture.py')
capture=importlib.util.module_from_spec(spec);spec.loader.exec_module(capture)


def png(width=540,height=960):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    raw=(b'\0'+b'\x20\x60\x80'*width)*height
    return (b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))
            +chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))


PNG=png()


def rows():
    result=[{'package':'com.aqer.yemen.uat','path':'0','witness':'a'*64,'visible':True,
             'enabled':True,'bounds':[0,0,540,960]}]
    for index,label in enumerate(home.HOME_LABELS,1):
        result.append({'package':'com.aqer.yemen.uat','path':'0.'+str(index),
            'witness':format(index,'064x'),'visible':True,'enabled':True,
            'bounds':[10,index*100,530,index*100+40],
            'hint':label if label.startswith('ابحث') else '',
            'text':'' if label.startswith('ابحث') else label})
    return result


class Authority:
    authority_kind='SOURCE_PLAN_ONLY'
    def __init__(self):self.active=True
    def require_input(self,context,category):
        if not self.active:raise RuntimeError('SYNTHETIC_EXPIRED')
        return True


class Base:
    def __init__(self,private,env):
        self.private=Path(private);self.out=self.private/'evidence';self.out.mkdir(mode=0o700)
        self.private_values=set();self.report={'frames':[],'videos':[]}
        self.authenticated=True;self.recorder=None;self._active_case='C1-photo-save'
        self.rows=rows();self.after=None;self.console_calls=[];self.png=PNG
        self.extra_console_file=False;self.video_name=None
    def instrument(self,op,**extras):
        if op!='account-snapshot':raise AssertionError('Home diagnostics never dispatch UI input')
        return {'passed':'true','op':op,'tree_b64':base64.b64encode(json.dumps(self.rows).encode()).decode()}
    def initial_home_capture_name(self):
        if not self.authenticated or self._active_case not in home.HOME_NAMES:
            raise RuntimeError('initial_c1_add_scope_required')
        return home.HOME_NAMES[self._active_case]
    def broker_home_ready(self,current):
        names=set().union(*(home.labels(row) for row in current))
        return all(label in names for label in home.HOME_LABELS)
    def nodes(self):
        return [row for row in self.rows if row.get('package')=='com.aqer.yemen.uat' and row.get('visible')]
    def adb(self,*args,**kwargs):
        if tuple(args[:3])!=('emu','screenrecord','screenshot') or len(args)!=4:
            raise AssertionError('Only the official host-console screenshot route is allowed')
        self.console_calls.append(tuple(str(a) for a in args))
        directory=Path(args[3]);(directory/'capture.png').write_bytes(self.png)
        if self.extra_console_file:(directory/'extra.png').write_bytes(self.png)
        if self.after is not None:self.after()
        return 'OK'
    def save(self):pass


def access(_):return {'otp':'258147','phones':{'broker':'+9000000001','support':'+9000000002','regular':'+9000000003'}}
Probe=bridge.make_probe_class(base_class=Base,host_capture_mixin=capture.HostConsoleCaptureMixin,
    validate_access=access,secret_name='SYNTHETIC_ACCESS',install_known_roles=lambda p,a:None,
    authority_types=(Authority,),app='com.aqer.yemen.uat',activity='synthetic.activity',helper='synthetic.helper')


class HomeCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='offline-home-',dir=HERE)
        self.authority=Authority()
        self.probe=Probe(self.temp.name,{},authority_getter=lambda:self.authority,
            context_getter=lambda:type('Context',(),{'phase':'C1','cursor':'INITIAL_C1'})(),
            verify_helper_identity=lambda:True,verify_guest_utc=lambda:True)
        self.probe.start_session()
    def tearDown(self):self.temp.cleanup()
    def fail_capture(self):
        with self.assertRaises(RuntimeError):self.probe.capture_initial_broker_home()
        self.assertEqual(self.probe.report['frames'],[])
        self.assertEqual(list(self.probe.out.iterdir()),[])

    def test_actual_console_png_has_truthful_home_scope_and_private_mode(self):
        self.assertIsNone(self.probe.capture_initial_broker_home())
        self.assertEqual(len(self.probe.console_calls),1)
        record=self.probe.report['frames'][0]
        self.assertEqual(record['file'],'C1-before-add-home.png')
        self.assertEqual(record['capture'],'official_emulator_console_host_png')
        self.assertIs(record['authenticated_editor_only'],False)
        self.assertIs(record['authenticated_broker_home_only'],True)
        self.assertEqual(record['capture_scope'],home.HOME_SCOPE)
        self.assertIs(record['privacy_before_and_after'],True)
        self.assertIs(record['home_binding_unchanged'],True)
        self.assertEqual((record['width'],record['height']),(540,960))
        file=self.probe.out/record['file']
        self.assertEqual(file.read_bytes(),PNG)
        self.assertEqual(file.stat().st_mode&0o777,0o600)
        self.assertEqual(record['sha256'],hashlib.sha256(PNG).hexdigest())
        self.assertNotIn('home_binding',json.dumps({k:v for k,v in record.items() if k!='home_binding_unchanged'}))

    def test_restore_uses_distinct_fixed_filename(self):
        self.probe.capture_initial_broker_home()
        self.probe._active_case='C1-force-stop-restore'
        self.probe.capture_initial_broker_home()
        self.assertEqual([r['file'] for r in self.probe.report['frames']],
            ['C1-before-add-home.png','C1-restore-before-add-home.png'])

    def test_full_hidden_contact_and_visible_auth_profile_private_value_block_before_console(self):
        for extra in [{'hint':'رقم الاتصال *','visible':False},
                      {'text':'رمز التحقق','visible':True},
                      {'text':'تسجيل الخروج','visible':True},
                      {'text':'+9000000001','visible':True}]:
            with self.subTest(extra=extra):
                self.probe.rows=rows()+[dict(extra,package='com.aqer.yemen.uat')]
                self.fail_capture()
                self.assertEqual(self.probe.console_calls,[])

    def test_private_transition_after_console_discards_image_and_receipt(self):
        self.probe.after=lambda:setattr(self.probe,'rows',rows()+[
            {'package':'com.aqer.yemen.uat','hint':'الإيجار الشهري بالريال اليمني *','visible':False}])
        self.fail_capture()
        self.assertEqual(len(self.probe.console_calls),1)

    def test_home_anchor_identity_change_after_console_discards_image(self):
        self.probe.after=lambda:self.probe.rows[1].update(witness='b'*64)
        self.fail_capture()
        self.assertEqual(len(self.probe.console_calls),1)

    def test_missing_hidden_foreign_or_ambiguous_home_anchor_refuses(self):
        for mode in ['missing','hidden','foreign','duplicate']:
            with self.subTest(mode=mode):
                current=rows()
                if mode=='missing':current.pop(1)
                elif mode=='hidden':current[1]['visible']=False
                elif mode=='foreign':current[1]['package']='foreign.synthetic'
                else:current.append(dict(current[1],path='0.99'))
                self.probe.rows=current
                self.fail_capture()
                self.assertEqual(self.probe.console_calls,[])

    def test_regular_guest_footer_and_nonhome_editor_do_not_pass(self):
        self.probe.rows=[{'package':'com.aqer.yemen.uat','text':name,'visible':True} for name in
                         ['العقارات','الرسائل','إعلاناتي','حسابي','عنوان الإعلان *']]
        self.fail_capture()
        self.assertEqual(self.probe.console_calls,[])

    def test_only_initial_c1_cases_source_lease_and_no_recorder_are_allowed(self):
        self.probe._active_case='C2'
        self.fail_capture()
        self.probe._active_case='C1-photo-save';self.probe.recorder='synthetic-recorder'
        self.fail_capture()
        self.probe.recorder=None;self.authority.authority_kind='ROOT_VERIFIED'
        self.fail_capture()
        self.assertEqual(self.probe.console_calls,[])

    def test_wrong_name_or_expired_source_lease_never_opens_console(self):
        original=self.probe.initial_home_capture_name
        self.probe.initial_home_capture_name=lambda:'C1-other-home'
        self.fail_capture()
        self.probe.initial_home_capture_name=original;self.authority.active=False
        self.fail_capture()
        self.assertEqual(self.probe.console_calls,[])

    def test_bad_crc_dimensions_or_multiple_console_outputs_are_refused(self):
        bad=bytearray(PNG);bad[-1]^=1
        for data,extra in [(bytes(bad),False),(png(541,960),False),(PNG,True)]:
            with self.subTest(extra=extra,size=len(data)):
                self.probe.png=data;self.probe.extra_console_file=extra
                self.fail_capture()

    def test_existing_filename_or_dangling_symlink_is_never_overwritten(self):
        path=self.probe.out/'C1-before-add-home.png'
        path.write_bytes(b'SYNTHETIC_EXISTING')
        with self.assertRaises(RuntimeError):self.probe.capture_initial_broker_home()
        self.assertEqual(path.read_bytes(),b'SYNTHETIC_EXISTING')
        self.assertEqual(self.probe.console_calls,[])
        path.unlink();path.symlink_to(self.probe.out/'missing.png')
        with self.assertRaises(RuntimeError):self.probe.capture_initial_broker_home()
        self.assertTrue(path.is_symlink())
        self.assertEqual(self.probe.console_calls,[])

    def test_wrong_physical_png_dimensions_are_observed_without_resizing_or_export(self):
        self.probe.png = png(1080,1920)
        self.fail_capture()
        self.assertEqual(self.probe.report['home_console_observed_dimensions'], {
            'C1-before-add-home': {'width':1080,'height':1920,'acceptance_claimed':False}})
        self.assertEqual(self.probe.report['frames'], [])
        self.assertEqual(list(self.probe.out.iterdir()), [])

    def test_frozen_editor_path_and_all_old_probe_logic_remain_unchanged(self):
        self.assertIs(Probe.safe_capture,capture.HostConsoleCaptureMixin.safe_capture)
        self.assertIs(Probe._capture_guard,capture.HostConsoleCaptureMixin._capture_guard)
        self.assertIs(Probe._capture_rows_private,capture.HostConsoleCaptureMixin._capture_rows_private)
        self.assertEqual(hashlib.sha256((HERE/'variants/runtime/host_console_capture.py').read_bytes()).hexdigest(),
                         '2ec10b2659ea3f073c47d02c1800cd49b35b58e51ce8430517af74a1ecadcafa')
        with self.assertRaises(RuntimeError):self.probe.safe_capture('C1-editor-test')
        self.assertEqual(self.probe.console_calls,[])
        tree=ast.parse((HERE/'ci_probe_adapter.py').read_text())
        class Normalize(ast.NodeTransformer):
            def visit_ImportFrom(self,node):return None if node.module in {'c1_home_capture','c1_basics_capture'} else node
            def visit_ClassDef(self,node):
                self.generic_visit(node)
                if node.name=='CIProbe':node.bases=[b for b in node.bases if not isinstance(b,ast.Name) or b.id not in {'C1HomeConsoleCaptureMixin','C1BasicsConsoleCaptureMixin'}]
                return node
        normalized=Normalize().visit(tree)
        self.assertEqual(hashlib.sha256(ast.dump(normalized,include_attributes=False).encode()).hexdigest(),
                         'af0167dbe03c23ac10d81482e0c4c7c7eb88274164de756ee38abfa3113b91aa')
        # The reviewed extensions add only their imports, diagnostic methods
        # and a timeout handler around the original base photo-picker call.
        # Strip precisely that extension and keep the prior whole-core pin.
        class PriorCore(Normalize):
            def visit_Import(self,node):
                return None if all(a.name in {'hashlib','json','math','subprocess','tempfile','xml.etree.ElementTree'} for a in node.names) else node
            def visit_ImportFrom(self,node):
                return None if node.module=='pathlib' else super().visit_ImportFrom(node)
            def visit_FunctionDef(self,node):
                if node.name in {'_initial_os_picker_observation','capture_initial_os_picker_diagnostic','_validate_webm'}:return None
                self.generic_visit(node)
                if node.name=='photo_picker':
                    assert isinstance(node.body[-1],ast.Try) and len(node.body[-1].body)==1
                    assert isinstance(node.body[-1].body[0],ast.Return)
                    node.body[-1]=node.body[-1].body[0]
                return node
        prior=PriorCore().visit(ast.parse((HERE/'ci_probe_adapter.py').read_text()))
        self.assertEqual(hashlib.sha256(ast.dump(prior,include_attributes=False).encode()).hexdigest(),
                         '9b431d9a8d0ef7ad7ad54a055b397aa94eb889e7e4fcf0a2c774f593d0a43707')


if __name__=='__main__':unittest.main()
