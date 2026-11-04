"""Synthetic loaded-basics capture contracts; no native/account execution."""
import hashlib
from pathlib import Path
import tempfile
import unittest

import test_home_capture as scaffold
import ci_probe_adapter as bridge
import c1_basics_capture as basics


def rows():
    current=scaffold.rows()
    for index,label in enumerate(basics.BASICS_LABELS,1):
        current[index]['text']=label;current[index]['hint']=''
    return current


class Base(scaffold.Base):
    def __init__(self,private,env):
        super().__init__(private,env)
        self.rows=rows();self.loaded=True;self.delegations=[]
    def basic_editor_loaded(self,visible):
        names=set().union(*(scaffold.home.labels(row) for row in visible))
        return bool(self.loaded and set(basics.BASICS_LABELS)<=names
                    and not names&{'لديك إعلان غير مكتمل','مسوداتي'})
    def capture_basic_editor(self,name,expected_title=None):
        self.delegations.append((name,expected_title))
        if name!='C1-owned-editor-title':raise RuntimeError('fixed_basic_editor_capture_required')
        return ('original-owned-title-route',expected_title)
    def tap(self,*args,**kwargs):raise AssertionError('capture must never tap')
    def act(self,*args,**kwargs):raise AssertionError('capture must never dispatch input')
    def scroll(self,*args,**kwargs):raise AssertionError('capture must never scroll')
    def set(self,*args,**kwargs):raise AssertionError('capture must never set text')


Probe=bridge.make_probe_class(base_class=Base,host_capture_mixin=scaffold.capture.HostConsoleCaptureMixin,
    validate_access=scaffold.access,secret_name='SYNTHETIC_ACCESS',install_known_roles=lambda p,a:None,
    authority_types=(scaffold.Authority,),app='com.aqer.yemen.uat',activity='synthetic.activity',helper='synthetic.helper')
HERE=Path(__file__).resolve().parent


class BasicsCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='offline-basics-',dir=HERE)
        self.authority=scaffold.Authority()
        self.probe=Probe(self.temp.name,{},authority_getter=lambda:self.authority,
            context_getter=lambda:type('Context',(),{'phase':'C1','cursor':'INITIAL_C1'})(),
            verify_helper_identity=lambda:True,verify_guest_utc=lambda:True)
        self.probe.start_session()
    def tearDown(self):self.temp.cleanup()
    def fail(self):
        with self.assertRaises(RuntimeError):self.probe.capture_basic_editor('C1-basic-editor')
        self.assertEqual(self.probe.report['frames'],[])
        self.assertEqual(list(self.probe.out.iterdir()),[])

    def test_official_console_basics_png_is_editor_state_without_title_uuid_proof(self):
        self.assertIsNone(self.probe.capture_basic_editor('C1-basic-editor'))
        record=self.probe.report['frames'][0]
        self.assertEqual(record['file'],'C1-basic-editor.png')
        self.assertEqual(record['capture'],'official_emulator_console_host_png')
        self.assertEqual(record['capture_scope'],basics.BASICS_SCOPE)
        self.assertIs(record['authenticated_editor_only'],True)
        self.assertIs(record['privacy_before_and_after'],True)
        self.assertIs(record['basics_binding_unchanged'],True)
        self.assertIs(record['title_identity_proved'],False)
        self.assertIs(record['fixture_uuid_identity_proved'],False)
        file=self.probe.out/record['file']
        self.assertEqual(file.read_bytes(),scaffold.PNG)
        self.assertEqual(file.stat().st_mode&0o777,0o600)
        self.assertEqual(record['sha256'],hashlib.sha256(scaffold.PNG).hexdigest())
        self.assertEqual(len(self.probe.console_calls),1)
        self.assertEqual(self.probe.delegations,[])

    def test_owned_title_delegates_original_method_and_arguments_unchanged(self):
        self.probe._active_case='C4';self.authority.authority_kind='ROOT_VERIFIED'
        result=self.probe.capture_basic_editor('C1-owned-editor-title','SYNTHETIC EXACT TITLE')
        self.assertEqual(result,('original-owned-title-route','SYNTHETIC EXACT TITLE'))
        self.assertEqual(self.probe.delegations,[('C1-owned-editor-title','SYNTHETIC EXACT TITLE')])
        self.assertEqual(self.probe.console_calls,[])

    def test_full_hidden_contact_visible_auth_profile_or_alias_refuses_before_console(self):
        for extra in [{'hint':'رقم الاتصال *','visible':False},{'text':'رمز التحقق','visible':True},
                      {'text':'تسجيل الخروج','visible':True},{'text':'+9000000001','visible':True}]:
            with self.subTest(extra=extra):
                self.probe.rows=rows()+[dict(extra,package='com.aqer.yemen.uat')]
                self.fail();self.assertEqual(self.probe.console_calls,[])

    def test_after_capture_private_transition_discards_frame(self):
        self.probe.after=lambda:setattr(self.probe,'rows',rows()+[
            {'package':'com.aqer.yemen.uat','hint':'الإيجار الشهري بالريال اليمني *','visible':False}])
        self.fail();self.assertEqual(len(self.probe.console_calls),1)

    def test_after_capture_anchor_binding_change_discards_frame(self):
        self.probe.after=lambda:self.probe.rows[2].update(witness='b'*64)
        self.fail();self.assertEqual(len(self.probe.console_calls),1)

    def test_only_photo_save_authenticated_source_plan_without_recorder_is_allowed(self):
        for attribute,value in [('_active_case','C1-force-stop-restore'),('_active_case','C2'),
                                ('authenticated',False),('recorder','synthetic')]:
            with self.subTest(attribute=attribute,value=value):
                original=getattr(self.probe,attribute);setattr(self.probe,attribute,value)
                self.fail();setattr(self.probe,attribute,original)
        self.authority.authority_kind='ROOT_VERIFIED';self.fail()
        self.authority.authority_kind='SOURCE_PLAN_ONLY';self.authority.active=False;self.fail()
        self.assertEqual(self.probe.console_calls,[])

    def test_missing_hidden_foreign_or_ambiguous_basic_anchor_refuses(self):
        for mode in ['missing','hidden','foreign','duplicate']:
            with self.subTest(mode=mode):
                current=rows()
                if mode=='missing':current.pop(2)
                elif mode=='hidden':current[2]['visible']=False
                elif mode=='foreign':current[2]['package']='foreign.synthetic'
                else:current.append(dict(current[2],path='0.99'))
                self.probe.rows=current;self.fail()
        self.assertEqual(self.probe.console_calls,[])

    def test_original_loaded_basics_and_no_recovery_context_are_indispensable(self):
        self.probe.loaded=False;self.fail()
        self.probe.loaded=True
        self.probe.rows=rows()+[{'package':'com.aqer.yemen.uat','text':'مسوداتي','visible':True}]
        self.fail();self.assertEqual(self.probe.console_calls,[])

    def test_bad_crc_size_or_multiple_console_files_are_not_saved(self):
        broken=bytearray(scaffold.PNG);broken[-1]^=1
        for data,extra in [(bytes(broken),False),(scaffold.png(540,961),False),(scaffold.PNG,True)]:
            with self.subTest(extra=extra,size=len(data)):
                self.probe.png=data;self.probe.extra_console_file=extra;self.fail()

    def test_existing_filename_or_dangling_symlink_is_not_overwritten(self):
        file=self.probe.out/'C1-basic-editor.png';file.write_bytes(b'SYNTHETIC_EXISTING')
        with self.assertRaises(RuntimeError):self.probe.capture_basic_editor('C1-basic-editor')
        self.assertEqual(file.read_bytes(),b'SYNTHETIC_EXISTING');self.assertEqual(self.probe.console_calls,[])
        file.unlink();file.symlink_to(self.probe.out/'missing.png')
        with self.assertRaises(RuntimeError):self.probe.capture_basic_editor('C1-basic-editor')
        self.assertTrue(file.is_symlink());self.assertEqual(self.probe.console_calls,[])

    def test_generic_guard_is_unchanged_and_unknown_capture_names_delegate_refusal(self):
        self.assertIs(Probe.safe_capture,scaffold.capture.HostConsoleCaptureMixin.safe_capture)
        self.assertIs(Probe._capture_guard,scaffold.capture.HostConsoleCaptureMixin._capture_guard)
        with self.assertRaises(RuntimeError):self.probe.safe_capture('C1-basic-editor')
        self.assertEqual(self.probe.console_calls,[])
        with self.assertRaisesRegex(RuntimeError,'^fixed_basic_editor_capture_required$'):
            self.probe.capture_basic_editor('C1-unknown')
        self.assertEqual(self.probe.delegations,[('C1-unknown',None)])


if __name__=='__main__':unittest.main()
