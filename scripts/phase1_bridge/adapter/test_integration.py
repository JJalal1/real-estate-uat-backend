"""Synthetic/offline contracts only; never device or actor acceptance tests."""
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'oneshot'))
import ci_probe_adapter as bridge
import ci_remote_evidence as evidence
import build_ci_variants as builder
from oneshot_adapter import AdmissionError


NOW = datetime(2026, 11, 3, 12, 0, 0, tzinfo=timezone.utc)
DIGEST = 'a' * 64
FRAME = 'C1-restored-title.png'


class EvidenceTests(unittest.TestCase):
    def review(self):
        result = {k: True for k in evidence.C4_EXTRA['C1_REVIEW']}
        result.update(kind=evidence.ROOT_KIND, phase='C4', case='C4-native-saved-draft',
            cursor='C1_REVIEW', fixture_key='synthetic', fixture_tag='SYNTHETIC',
            title='SYNTHETIC', privacy_checked=True, manual_review_completed=True,
            frames=evidence.frames_wire({FRAME: DIGEST}), review_completed_utc='2026-11-03T12:00:00Z')
        return result

    def test_actual_utc_age_edges_and_no_legacy_substitution(self):
        for age, wanted in [(-6, False), (-5, True), (0, True), (120, True), (121, False)]:
            self.assertEqual(evidence.fresh_remote_review(self.review(),
                now_utc=NOW + timedelta(seconds=age)), wanted)
        review = self.review()
        review['reviewed_monotonic'] = 123
        self.assertFalse(evidence.fresh_remote_review(review, now_utc=NOW))
        self.assertFalse(evidence.fresh_remote_review(self.review(), now_utc=NOW.replace(tzinfo=None)))

    def test_sorted_frame_records_bind_exact_filename_and_digest(self):
        frames = {'C1-z.png': DIGEST, 'C1-a.png': 'b' * 64}
        wire = evidence.frames_wire(frames)
        self.assertEqual(evidence.frame_map(wire), frames)
        for bad in [wire[::-1], [wire[0], wire[0]], [{'file': '../secret', 'sha256': DIGEST}],
                    [{'file': FRAME, 'sha256': DIGEST, 'approval': True}]]:
            with self.assertRaises(evidence.RemoteEvidenceError): evidence.frame_map(bad)

    def test_normalization_preserves_false_flags_and_checks_exact_schema(self):
        original_clock = evidence.utc_now
        evidence.utc_now = lambda: NOW
        try:
            review = self.review()
            review['manual_review_completed'] = False
            decoded = evidence.normalize_c4_review(review, expected_cursor='C1_REVIEW',
                expected_frames={FRAME: DIGEST})
            self.assertIs(decoded['manual_review_completed'], False)
            self.assertEqual(decoded['frames'], {FRAME: DIGEST})
            for bad in [dict(review, unreviewed_extra=True),
                        dict(review, review_completed_utc='2026-11-03T11:57:00Z')]:
                with self.assertRaises(evidence.RemoteEvidenceError):
                    evidence.normalize_c4_review(bad, expected_cursor='C1_REVIEW', expected_frames={FRAME: DIGEST})
            with self.assertRaises(evidence.RemoteEvidenceError):
                evidence.normalize_c4_review(review, expected_cursor='C1_REVIEW', expected_frames={FRAME: 'b' * 64})
        finally:
            evidence.utc_now = original_clock

    def test_video_decimal_is_exact_observed_tuple_not_new_duration(self):
        actual = {'file': 'C1-c4-restored-facts.webm', 'sha256': DIGEST, 'duration_s': 31.275}
        wire = evidence.video_wire(actual)
        self.assertEqual(wire['duration_s_decimal'], '31.275')
        self.assertEqual(evidence.video_tuple(wire, actual), actual)
        for changed in [dict(wire, duration_s_decimal='31.276'), dict(wire, file='other.webm'),
                        dict(wire, duration_s_decimal=31.275), dict(wire, duration_s_decimal='NaN')]:
            with self.assertRaises(evidence.RemoteEvidenceError): evidence.video_tuple(changed, actual)
        with self.assertRaises(evidence.RemoteEvidenceError):
            evidence.video_wire(dict(actual, duration_s=31.2751))

    def test_duplicate_json_keys_are_rejected(self):
        with self.assertRaises(evidence.RemoteEvidenceError):
            json.loads('{"privacy_checked":false,"privacy_checked":true}',
                       object_pairs_hook=evidence.reject_duplicate_pairs)

    def test_ai_copy_requires_explicit_grounding_record_and_rejects_private_or_untyped_context(self):
        review={k:True for k in evidence.C4_EXTRA['AI_REVIEW']}
        review.update({k:v for k,v in self.review().items() if k in evidence.C4_BASE})
        review.update(cursor='AI_REVIEW',actual_ai_notice='راجع التفاصيل والنص قبل تطبيقها على مسودتك.',
            literal_fallback_notice_visible=False,selected_fields={'floor_number':'2','unit_number':'7'},
            verified_existing_draft_copy_facts={'district':'SYNTHETIC_NEIGHBORHOOD','street':'SYNTHETIC_STREET'})
        with patch.object(evidence,'utc_now',return_value=NOW):
            actual=evidence.normalize_c4_review(review,expected_cursor='AI_REVIEW',expected_frames={FRAME:DIGEST})
            self.assertEqual(actual['verified_existing_draft_copy_facts'],review['verified_existing_draft_copy_facts'])
            for bad in [True,{'phone':'SYNTHETIC_PRIVATE'}, {'street':False}, {'street':''}, {'street':'x'*241}]:
                with self.assertRaises(evidence.RemoteEvidenceError):
                    evidence.normalize_c4_review(dict(review,verified_existing_draft_copy_facts=bad),
                        expected_cursor='AI_REVIEW',expected_frames={FRAME:DIGEST})
            old=dict(review);old.pop('verified_existing_draft_copy_facts');old['copy_has_only_explicit_brief_facts']=old.pop('copy_has_only_supplied_facts')
            with self.assertRaises(evidence.RemoteEvidenceError):
                evidence.normalize_c4_review(old,expected_cursor='AI_REVIEW',expected_frames={FRAME:DIGEST})


class Context:
    phase = 'C4'
    cursor = 'AI_REVIEW'


class C4RequestBoundaryTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('c4_request_boundary_actual',
            HERE/'variants/ROOT_C4_EXECUTOR/phase_extensions.py')
        self.c4 = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.c4)
        self.probe = Mock()
        self.probe.adapter = object()
        self.probe.stop_session.side_effect = lambda *a: setattr(self.probe, 'adapter', None)
        self.probe.start_session.side_effect = lambda: setattr(self.probe, 'adapter', object())
        self.probe.nodes.return_value = [{'text':self.c4.AI_NOTICE, 'visible':True}]
        self.state = {'cursor':'C1_REVIEW','inflight':None,'uncertain':False,
                      'title':'SYNTHETIC','accepted':False}

    def test_preparation_ends_before_request_then_fresh_segment_captures_actual_proposals(self):
        with patch.object(self.c4, 'safe_rows', return_value=[{'text':self.c4.AI_NOTICE,'visible':True}]), \
             patch.object(self.c4, 'ai_scene', return_value=DIGEST), \
             patch.object(self.c4, 'copy_digest', return_value='b'*64), \
             patch.object(self.c4, 'ai_capture', side_effect=lambda p,n:{n+'.png':DIGEST}) as capture:
            result = self.c4.prepare(self.probe, self.state)
            self.assertEqual(result['cursor'], 'REQUEST')
            self.assertIsNone(self.state['inflight'])
            self.assertEqual(self.state['prepared_brief_scene'], DIGEST)
            self.assertEqual([x.args[0] for x in self.probe.tap.call_args_list],
                             ['جهّز الإعلان بالصوت أو المساعد'])
            self.probe.require_value.assert_any_call('صف العقار',self.c4.BRIEF)
            capture.assert_not_called()
            self.assertIsNone(self.probe.adapter)
            self.probe.tap.reset_mock()
            result = self.c4.request_prepared(self.probe, self.state)
        self.probe.tap.assert_called_once_with('جهّز الإعلان')
        self.probe.wait.assert_any_call(self.c4.APPLY,seconds=120)
        self.assertEqual(result['cursor'],'AI_REVIEW')
        self.assertEqual(len(self.state['ai_frames']),7)
        self.assertFalse(self.state['accepted'])
        self.assertIsNone(self.state['inflight'])

    def test_changed_prepared_scene_refuses_request_and_never_replays_reserved_stage(self):
        self.state.update(cursor='REQUEST',prepared_brief_scene=DIGEST)
        with patch.object(self.c4,'ai_scene',return_value='f'*64):
            with self.assertRaisesRegex(self.c4.C4Blocked,'c4_prepared_brief_scene_changed'):
                self.c4.request_prepared(self.probe,self.state)
            with self.assertRaisesRegex(self.c4.C4Blocked,'no_replay'):
                self.c4.request_prepared(self.probe,self.state)
        self.probe.tap.assert_not_called()

    def test_exact_brief_is_read_again_before_request(self):
        self.state.update(cursor='REQUEST',prepared_brief_scene=DIGEST)
        self.probe.require_value.side_effect=RuntimeError('SYNTHETIC_BRIEF_CHANGED')
        with patch.object(self.c4,'ai_scene',return_value=DIGEST):
            with self.assertRaisesRegex(RuntimeError,'SYNTHETIC_BRIEF_CHANGED'):
                self.c4.request_prepared(self.probe,self.state)
        self.probe.require_value.assert_called_once_with('صف العقار',self.c4.BRIEF)
        self.probe.tap.assert_not_called()


class SyntheticAuthority:
    authority_kind = 'ROOT_VERIFIED'
    expires_utc = NOW + timedelta(seconds=120)
    def __init__(self):
        self.active = True
        self.checked = []
    def require_input(self, context, category, minimum_remaining_seconds=0):
        if not self.active: raise RuntimeError('synthetic-expired')
        self.checked.append(category)
        return True


class SourceAuthority(SyntheticAuthority):
    authority_kind = 'SOURCE_PLAN_ONLY'


class SyntheticHost:
    def record_start(self, name): self.recorder = name
    def photo_picker(self): raise AssertionError('host photo_picker is not the base method')


class SyntheticBase:
    def __init__(self, private, env):
        self.access = {'otp': 'discarded', 'phones': {'broker': 'discarded'}}
        self.private_values = set()
        self.report = {'cases': [], 'frames': [], 'videos': []}
        self.recorder, self.authenticated = None, False
        self.photo_name = 'synthetic-photo.jpg'
        self.serial = 'synthetic'
        self.calls = []
        self.capable, self.enforced = True, True
        self.ime_visible, self.ime_dismissed = 'true', 'true'
        self.after_driver = None
        self._active_case, self._auth_phase = 'C1-force-stop-restore', None
    def instrument(self, op, **extras):
        args = ['shell', 'am', 'instrument', '-w', '-e', 'op', op]
        for key, value in extras.items(): args.extend(['-e', key, str(value)])
        self.adb(*args, 'synthetic.helper')
        result = {'passed': 'true', 'op': op,
            'deadline_capable': 'true' if self.capable else 'false',
            'deadline_enforced': 'true' if self.enforced else 'false'}
        if op == 'account-snapshot': result['tree_b64'] = base64.b64encode(b'[]').decode()
        elif op == 'account-dismiss-ime':
            result.update(ime_was_visible=self.ime_visible, ime_dismissed=self.ime_dismissed)
        else: result.update(account_action_delivered='true', set_text_delivered='true')
        if self.after_driver is not None: self.after_driver()
        return result
    def adb(self, *args, **kwargs): return self.command(['adb', '-s', self.serial, *args], **kwargs)
    def command(self, args, **kwargs):
        self.calls.append(tuple(str(a) for a in args))
        if tuple(args[-3:]) == ('shell', 'wm', 'size'): return 'Physical size: 1080x1920\nOverride size: 540x960'
        if tuple(args[-3:]) == ('shell', 'wm', 'density'): return 'Physical density: 420\nOverride density: 210'
        return 'OK'
    def startup(self): self.adb('shell', 'am', 'start', '-W', '-n', 'synthetic.activity')
    def save(self): pass
    def photo_picker(self): self.report['synthetic_photo_selected'] = self.recorder is not None


def synthetic_access(_):
    return {'otp': '258147', 'phones': {'broker': '+9000000001', 'support': '+9000000002', 'regular': '+9000000003'}}


def install_roles(probe, access):
    # Type identity of real KnownRoleMemory is tested through generated imports;
    # this synthetic class never stands in for native actor proof.
    probe.role_names = tuple(sorted(access['phones']))
    probe.private_values.add(access['otp'])


PROBE = bridge.make_probe_class(base_class=SyntheticBase, host_capture_mixin=SyntheticHost,
    validate_access=synthetic_access, secret_name='SYNTHETIC_ACCESS', install_known_roles=install_roles,
    authority_types=(SyntheticAuthority, SourceAuthority), app='synthetic.app',
    activity='synthetic.activity', helper='synthetic.helper')


class ProbeTests(unittest.TestCase):
    def test_real_base_short_scroll_crosses_deployed_bridge_and_one_shot_with_original_authority(self):
        source=HERE.parents[1]/'probe_phase1_native_account.py'
        sys.path.insert(0,str(source.parent))
        spec=importlib.util.spec_from_file_location('_actual_scroll_base_contract',source)
        actual=importlib.util.module_from_spec(spec);spec.loader.exec_module(actual)
        container={'path':'0.1','witness':DIGEST,'package':actual.APP,'visible':True,
                   'enabled':True,'scrollable':True,'bounds':[0,110,540,830]}
        class ActualScrollBase(SyntheticBase):
            instrument=actual.NativeAccount.instrument
            nodes=actual.NativeAccount.nodes
            act=actual.NativeAccount.act
            scroll=actual.NativeAccount.scroll
            def command(self,args,**kwargs):
                self.calls.append(tuple(str(a)for a in args))
                op=args[args.index('op')+1]
                fields={'passed':'true','op':op,'deadline_capable':'true','deadline_enforced':'true'}
                if op=='account-snapshot':fields['tree_b64']=base64.b64encode(json.dumps([container]).encode()).decode()
                else:fields.update(account_action_delivered='true',native_pointer_used='true',native_pointer_events='14')
                return '\n'.join('INSTRUMENTATION_RESULT: '+k+'='+v for k,v in fields.items())+'\nINSTRUMENTATION_CODE: -1'
        cls=bridge.make_probe_class(base_class=ActualScrollBase,host_capture_mixin=SyntheticHost,
            validate_access=synthetic_access,secret_name='SYNTHETIC_ACCESS',install_known_roles=install_roles,
            authority_types=(SyntheticAuthority,SourceAuthority),app=actual.APP,activity=actual.ACTIVITY,helper=actual.HELPER)
        for authority in [SourceAuthority(),SyntheticAuthority()]:
            context=Context()
            if isinstance(authority,SourceAuthority):context.phase,context.cursor='C1','INITIAL_C1'
            p=cls(None,{},authority_getter=lambda:authority,context_getter=lambda:context,
                  verify_helper_identity=lambda:True,verify_guest_utc=lambda:True)
            p.start_session();p.preflight_deadline_helper();p.authenticated=True;p.report['actions']=[]
            with patch.object(actual.time,'sleep'):
                p.scroll('forward',short=True)
            calls=[c for c in p.calls if c[c.index('op')+1]=='account-scroll']
            self.assertEqual(len(calls),1);call=calls[0]
            for key,value in [('scroll_step','short'),('input_mode','physical_scroll'),
                              ('node_path','0.1'),('node_witness',DIGEST)]:
                self.assertEqual(call[call.index(key)+1],value)
            self.assertEqual(authority.checked.count('scroll'),1)
            if authority.authority_kind=='ROOT_VERIFIED':
                self.assertEqual(call[call.index('deadline_utc_ms')+1],bridge.exact_deadline_ms(authority))
            self.assertEqual(p.admission_metrics['state'],'open')
            self.assertEqual(p.report['actions'][0]['native_pointer_events'],14)

    def probe(self, authority=None, context=None):
        authority = authority or SyntheticAuthority()
        context = context or Context()
        probe = PROBE(None, {}, authority_getter=lambda: authority, context_getter=lambda: context,
            verify_helper_identity=lambda: True, verify_guest_utc=lambda: True)
        probe.start_session()
        probe.preflight_deadline_helper()
        return probe, authority

    def click(self, p): return p.instrument('account-click', node_path='0.1', node_witness=DIGEST)

    def test_three_roles_retained_before_base_discards_and_metrics_redacted(self):
        p, _ = self.probe()
        self.assertEqual(set(p.access['phones']), {'broker', 'support', 'regular'})
        safe = json.dumps(p.admission_metrics) + repr(p)
        self.assertFalse(any(value in safe for value in p.private_values))
        p.clear_role_memory()
        self.assertEqual(p.access, {'otp': '', 'phones': {}})

    def test_each_dispatch_uses_original_signed_expiry_and_no_caller_override(self):
        p, authority = self.probe()
        self.click(p)
        p.instrument('account-set', node_path='0.1', node_witness=DIGEST, value_b64='eA==')
        p.adb('shell', 'input', 'keyevent', '4')
        calls = [call for call in p.calls if 'deadline_utc_ms' in call]
        self.assertEqual(len(calls), 3)
        wanted = bridge.exact_deadline_ms(authority)
        self.assertTrue(all(call[call.index('deadline_utc_ms')+1] == wanted for call in calls))
        self.assertEqual(authority.checked.count('tap'), 1)
        self.assertEqual(authority.checked.count('text'), 1)
        self.assertTrue(all(call[-1] == 'synthetic.helper' for call in calls))
        with self.assertRaises(AdmissionError):
            p.instrument('account-click', node_path='0.1', node_witness=DIGEST, deadline_utc_ms=wanted)

    def test_expiry_between_actions_prevents_second_dispatch_and_latches(self):
        p, authority = self.probe()
        self.click(p)
        dispatched = len(p.calls)
        authority.active = False
        with self.assertRaises(AdmissionError): self.click(p)
        self.assertEqual(len(p.calls), dispatched)
        self.assertEqual(p.admission_metrics['state'], 'uncertain')
        with self.assertRaises(AdmissionError): p.stop_session()
        with self.assertRaises(bridge.BridgeRefused): p.start_session()

    def test_missing_capability_blocks_first_root_input(self):
        p, _ = self.probe()
        p.capable = False
        with self.assertRaises(bridge.BridgeRefused): p.preflight_deadline_helper()
        dispatched = len(p.calls)
        with self.assertRaises(AdmissionError): self.click(p)
        self.assertEqual(len(p.calls), dispatched)

    def test_missing_enforcement_after_attempt_latches_uncertainty(self):
        p, _ = self.probe()
        p.enforced = False
        with self.assertRaises(AdmissionError): self.click(p)
        self.assertEqual(p.admission_metrics['state'], 'uncertain')
        dispatched = len(p.calls)
        with self.assertRaises(bridge.BridgeRefused): p.adb('shell', 'input', 'keyevent', '4')
        self.assertEqual(len(p.calls), dispatched)

    def test_ime_noop_is_checked_and_bad_pair_latches(self):
        p, _ = self.probe()
        p.ime_visible = p.ime_dismissed = 'false'
        self.assertEqual(p.adb('shell', 'input', 'keyevent', '4')['ime_dismissed'], 'false')
        p.ime_visible, p.ime_dismissed = 'true', 'false'
        with self.assertRaises(AdmissionError): p.adb('shell', 'input', 'keyevent', '4')
        self.assertEqual(p.admission_metrics['state'], 'uncertain')

    def test_lifecycle_guard_and_closed_transport_allowlist(self):
        p, authority = self.probe()
        p.adb('shell', 'am', 'force-stop', 'synthetic.app')
        self.assertIn('app_stop', authority.checked)
        dispatched = len(p.calls)
        for args in [('shell', 'input', 'tap', 1, 2), ('shell', 'rm', '-rf', '/sdcard'),
                     ('shell', 'am', 'start', '-n', 'other'), ('shell', 'input', 'text', 'private')]:
            with self.assertRaises(bridge.BridgeRefused): p.adb(*args)
        with self.assertRaises(bridge.BridgeRefused): p.command(['adb', 'shell', 'input', 'keyevent', '4'])
        authority.active = False
        with self.assertRaises(bridge.BridgeRefused): p.adb('shell', 'am', 'force-stop', 'synthetic.app')
        self.assertEqual(len(p.calls), dispatched)

    def test_source_lease_cannot_enter_phase_executor_or_impersonate_root(self):
        context = Context()
        context.phase, context.cursor = 'C1', 'INITIAL_C1'
        p, _ = self.probe(SourceAuthority(), context)
        with self.assertRaises(bridge.BridgeRefused): p.require_phase_scope('C4')
        root, _ = self.probe()
        self.assertTrue(root.require_phase_scope('C4'))
        with self.assertRaises(bridge.BridgeRefused): root.require_phase_scope('C2')

    def test_real_thread_reservation_prevents_second_driver_dispatch(self):
        p, _ = self.probe()
        entered, release = threading.Event(), threading.Event()
        p.after_driver = lambda: (entered.set(), release.wait(timeout=3))
        failures = []
        def work():
            try: self.click(p)
            except BaseException as error: failures.append(type(error).__name__)
        thread = threading.Thread(target=work)
        thread.start()
        self.assertTrue(entered.wait(timeout=3))
        dispatched = len(p.calls)
        with self.assertRaises(AdmissionError): self.click(p)
        with self.assertRaises(AdmissionError): p.stop_session()
        self.assertEqual(len(p.calls), dispatched)
        release.set()
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(failures, [])

    def test_source_creation_clip_starts_at_photo_not_long_map(self):
        context = Context()
        context.phase, context.cursor = 'C1', 'INITIAL_C1'
        p, _ = self.probe(SourceAuthority(), context)
        p.record_start('C1-create-photo')
        self.assertIsNone(p.recorder)
        p.photo_picker()
        self.assertEqual(p.recorder, 'C1-create-photo')
        self.assertIs(p.report['synthetic_photo_selected'], True)
        self.assertEqual(p.report['create_clip_scope'], 'actual_specs_photo_selection_only')

    def test_display_actual_readback_and_c1_diagnostic_boundary(self):
        context = Context()
        context.phase, context.cursor = 'C1', 'INITIAL_C1'
        p, _ = self.probe(SourceAuthority(), context)
        self.assertIs(p.configure_host_display()['actual_readback_checked'], True)
        with self.assertRaises(bridge.BridgeRefused): p.hold_after_initial_c1()
        p.report['cases'] = [{'id': 'C1-force-stop-restore', 'status': 'PASS'}]
        p.hold_after_initial_c1()
        self.assertIsNone(p._active_case)
        with self.assertRaises(bridge.BridgeRefused): p.cleanup()
        with self.assertRaises(bridge.BridgeRefused): p.execute()


class OsPickerDiagnosticTests(unittest.TestCase):
    """Synthetic snapshots/PNG only; no real device or account acceptance."""

    def probe(self, views):
        spec=importlib.util.spec_from_file_location('_diagnostic_host',HERE/'variants/runtime/host_console_capture.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        cls=bridge.make_probe_class(base_class=SyntheticBase,host_capture_mixin=module.HostConsoleCaptureMixin,
            validate_access=synthetic_access,secret_name='SYNTHETIC_ACCESS',install_known_roles=install_roles,
            authority_types=(SyntheticAuthority,SourceAuthority),app='synthetic.app',
            activity='synthetic.activity',helper='synthetic.helper')
        context=Context();context.phase,context.cursor='C1','INITIAL_C1'
        authority=SourceAuthority()
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        root=Path(temp.name)
        p=cls(root,{},authority_getter=lambda:authority,context_getter=lambda:context,
              verify_helper_identity=lambda:True,verify_guest_utc=lambda:True)
        p.private=root;p.out=root/'out';p.out.mkdir(mode=0o700)
        p.start_session();p.authenticated=True;p._active_case='C1-photo-save'
        p.recorder='official-host-console';p.video_name='C1-create-photo';p.record_tainted=False
        sequence=iter(views)
        def adb(*args,**kwargs):
            if args==('exec-out','cat','/sdcard/phase1-os-picker.xml'):return next(sequence)
            if args[:3] in {('shell','uiautomator','dump'),('shell','rm','-f')}:return 'OK'
            raise AssertionError('diagnostic must not deliver UI input or APP instrumentation')
        p.adb=Mock(side_effect=adb)
        from PIL import Image
        png=io.BytesIO();Image.new('RGB',(540,960),'white').save(png,format='PNG');data=png.getvalue()
        def console(*args):
            self.assertEqual(args[0],'screenshot');(args[1]/'actual.png').write_bytes(data)
        p._console=Mock(side_effect=console)
        return p,authority

    def xml(self,text='Downloads',package='com.android.documentsui',extra=''):
        return '<hierarchy><node package="'+package+'" text="'+text+'" class="android.widget.FrameLayout" enabled="true">'+extra+'</node></hierarchy>'

    def test_stable_trusted_picker_diagnostic_is_separate_from_accepted_editor_media(self):
        xml=self.xml(extra='<node package="com.android.documentsui" text="synthetic-photo.jpg" enabled="true"/>')
        p,_=self.probe([xml,xml]);p.capture_initial_os_picker_diagnostic()
        result=p.report['os_picker_diagnostic'];image=p.out/result['file']
        self.assertEqual(result['status'],'CAPTURED')
        self.assertEqual(result['sha256'],hashlib.sha256(image.read_bytes()).hexdigest())
        self.assertEqual((result['width'],result['height']),(540,960))
        self.assertFalse(result['acceptance_claimed'])
        self.assertTrue(result['privacy_before_and_after'])
        self.assertEqual(result['observed_controls']['exact_filename_matches'],1)
        self.assertEqual((p.report['frames'],p.report['videos']),([],[]))
        self.assertFalse(p.record_tainted)
        self.assertFalse(any('instrument' in call.args or 'tap' in call.args for call in p.adb.call_args_list))

    def test_private_foreign_or_account_picker_scenes_never_export_or_hash_auth_data(self):
        cases=[self.xml(package='synthetic.app'),self.xml(text='258147'),self.xml(text='Password'),
               self.xml(text='someone@example.test'),
               self.xml(extra='<node package="synthetic.app" text="رقم الاتصال *" visible-to-user="false"/>')]
        for xml in cases:
            p,_=self.probe([xml])
            with self.subTest(scene=cases.index(xml)),self.assertRaises(bridge.BridgeRefused):
                p.capture_initial_os_picker_diagnostic()
            self.assertEqual(list(p.out.iterdir()),[])
            self.assertTrue(p.record_tainted)
            p._console.assert_not_called()
            self.assertNotIn('os_picker_diagnostic',p.report)

    def test_changed_picker_scene_discards_png_and_root_authority_cannot_capture_it(self):
        p,_=self.probe([self.xml(),self.xml(text='Images')])
        with self.assertRaisesRegex(bridge.BridgeRefused,'binding_changed'):
            p.capture_initial_os_picker_diagnostic()
        self.assertEqual(list(p.out.iterdir()),[]);self.assertTrue(p.record_tainted)
        p,_=self.probe([self.xml()]);p._owner_authority=lambda:SyntheticAuthority()
        with self.assertRaisesRegex(bridge.BridgeRefused,'initial_source_picker_diagnostic_only'):
            p.capture_initial_os_picker_diagnostic()
        p.adb.assert_not_called();p._console.assert_not_called()

    def test_known_picker_timeout_only_gets_one_diagnostic_and_original_failure_stays(self):
        context=Context();context.phase,context.cursor='C1','INITIAL_C1'
        for code,wanted in [('genuine_os_photo_selection_not_observed',1),('synthetic_unknown_failure',0)]:
            p=PROBE(None,{},authority_getter=SourceAuthority,context_getter=lambda:context,
                verify_helper_identity=lambda:True,verify_guest_utc=lambda:True)
            p.capture_initial_os_picker_diagnostic=Mock()
            p.record_start('C1-create-photo')
            with patch.object(SyntheticBase,'photo_picker',side_effect=RuntimeError(code)):
                with self.assertRaisesRegex(RuntimeError,'^'+code+'$'):p.photo_picker()
            self.assertEqual(p.capture_initial_os_picker_diagnostic.call_count,wanted)
            self.assertEqual(p.report['cases'],[])


    def video_probe(self):
        p,authority=self.probe([])
        folder=p._host_capture_root()/'webm-synthetic';folder.mkdir(mode=0o700)
        path=folder/'capture.webm';path.write_bytes(b'\x1a\x45\xdf\xa3'+b'X'*2048)
        p._host_video_path=path;p.recorder=None;p._host_stop_unconfirmed=False
        frozen=next(cls for cls in type(p).__mro__ if cls.__name__=='HostConsoleCaptureMixin')
        return p,authority,path,frozen

    def test_valid_video_uses_original_validator_once_without_diagnostic_or_new_claim(self):
        p,_,path,frozen=self.video_probe();actual={'duration_s':12.5,'codec':'vp8','width':540,'height':960}
        with patch.object(frozen,'_validate_webm',return_value=actual) as validate, \
                patch.object(bridge.subprocess,'run') as probe:
            self.assertIs(p._validate_webm(path),actual)
        validate.assert_called_once_with(path);probe.assert_not_called()
        self.assertNotIn('host_video_diagnostic',p.report)
        self.assertEqual((p.report['frames'],p.report['videos']),([],[]))

    def test_refused_video_records_bounded_actual_metadata_and_rethrows_original_refusal(self):
        p,_,path,frozen=self.video_probe();failure=bridge.BridgeRefused('host_webm_stream_or_duration_invalid')
        raw={'streams':[{'codec_type':'video','codec_name':'vp8','width':1080,'height':1920,
                         'avg_frame_rate':'10/1','private_extra':'PRIVATE_SENTINEL'},
                        {'codec_type':'PRIVATE_SENTINEL','codec_name':'PRIVATE_SENTINEL'}],
             'format':{'format_name':'matroska,webm','duration':'31.250','private_extra':'PRIVATE_SENTINEL'}}
        with patch.object(frozen,'_validate_webm',side_effect=failure) as validate, \
                patch.object(bridge.subprocess,'run',return_value=Mock(returncode=0,stdout=json.dumps(raw).encode(),stderr=b'PRIVATE_SENTINEL')) as probe:
            with self.assertRaises(bridge.BridgeRefused) as caught:p._validate_webm(path)
        self.assertIs(caught.exception,failure);validate.assert_called_once_with(path)
        self.assertEqual(probe.call_count,2)  # native-format check plus refusal-only diagnostic
        result=p.report['host_video_diagnostic'];self.assertFalse(result['acceptance_claimed'])
        self.assertEqual((result['stream_count'],result['duration_s']),(2,31.25))
        self.assertEqual(result['streams'][0]['width'],1080)
        self.assertEqual(result['native_format_refusal'],'one_video_one_silent_native_audio_required')
        self.assertIsNone(result['streams'][1]['channels']);self.assertIsNone(result['streams'][1]['sample_rate'])
        self.assertEqual(result['streams'][1]['codec'],'OTHER')
        self.assertTrue(result['ebml_header_observed']);self.assertTrue(result['webm_format_observed'])
        self.assertNotIn('PRIVATE_SENTINEL',json.dumps(p.report))
        self.assertEqual((p.report['frames'],p.report['videos']),([],[]));self.assertTrue(path.exists())
        p.adb.assert_not_called();p._console.assert_not_called()

    def test_native_refusal_diagnostic_has_only_fixed_codes_and_bounded_audio_metadata(self):
        raw={'streams':[{'codec_type':'audio','codec_name':'vorbis','channels':2,'sample_rate':'44100','nb_read_packets':'0'},
                        {'codec_type':'video','codec_name':'vp9','width':540,'height':960}],
             'format':{'format_name':'webm','duration':'1.0'}}
        failures=[(bridge.BridgeRefused('native_audio_exact_silence_required'),'native_audio_exact_silence_required'),
                  (bridge.BridgeRefused('PRIVATE_SENTINEL'),'native_media_verification_refused'),
                  (FileNotFoundError('PRIVATE_SENTINEL'),'native_media_tool_unavailable'),
                  (subprocess.TimeoutExpired('PRIVATE_SENTINEL',25),'native_media_read_timeout')]
        for failure,expected in failures:
            p,_,path,frozen=self.video_probe()
            original=bridge.BridgeRefused('host_webm_stream_or_duration_invalid')
            with self.subTest(expected=expected),patch.object(frozen,'_validate_webm',side_effect=original), \
                    patch.object(type(p),'_validate_native_silent_audio_webm',side_effect=failure), \
                    patch.object(bridge.subprocess,'run',return_value=Mock(returncode=0,stdout=json.dumps(raw).encode(),stderr=b'PRIVATE_SENTINEL')):
                with self.assertRaises(bridge.BridgeRefused) as caught:p._validate_webm(path)
            self.assertIs(caught.exception,original)
            facts=p.report['host_video_diagnostic'];self.assertFalse(facts['acceptance_claimed'])
            self.assertEqual(facts['native_format_refusal'],expected)
            self.assertEqual((facts['streams'][0]['channels'],facts['streams'][0]['sample_rate']),(2,'44100'))
            self.assertEqual(facts['streams'][0]['packet_count'],0)
            self.assertNotIn('PRIVATE_SENTINEL',json.dumps(p.report))
            self.assertEqual((p.report['frames'],p.report['videos']),([],[]))

    def test_video_diagnostic_refuses_root_authority_or_symlink_and_never_replaces_original_failure(self):
        for mode in ('root','symlink'):
            p,_,path,frozen=self.video_probe();failure=bridge.BridgeRefused('host_webm_file_invalid')
            if mode=='root':p._owner_authority=lambda:SyntheticAuthority()
            else:
                path.unlink();path.symlink_to(Path(p.private)/'foreign-missing')
            with self.subTest(mode=mode),patch.object(frozen,'_validate_webm',side_effect=failure), \
                    patch.object(bridge.subprocess,'run') as probe:
                with self.assertRaises(bridge.BridgeRefused) as caught:p._validate_webm(path)
            self.assertIs(caught.exception,failure);probe.assert_not_called()
            self.assertEqual(p.report['host_video_diagnostic'],{'status':'REFUSED','acceptance_claimed':False})

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'Video tools unavailable')
    def test_actual_native_two_track_WebM_is_accepted_only_with_exact_digital_silence(self):
        for silence in (True,False):
            p,_,path,frozen=self.video_probe()
            audio='anullsrc=r=44100:cl=stereo' if silence else 'sine=frequency=1000:sample_rate=44100'
            subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i','color=c=blue:s=540x960:r=10',
                '-f','lavfi','-i',audio,'-t','0.3','-c:v','libvpx-vp9','-c:a','libvorbis','-y',str(path)],
                check=True,capture_output=True,timeout=25)
            original=path.read_bytes()
            with self.subTest(silence=silence):
                with self.assertRaisesRegex(bridge.BridgeRefused,'host_webm_stream_or_duration_invalid'):
                    frozen._validate_webm(p,path)
                if silence:
                    facts=p._validate_webm(path)
                    self.assertEqual((facts['codec'],facts['width'],facts['height']),('vp9',540,960))
                    self.assertTrue(p.report['native_silent_audio_tracks']['C1-create-photo.webm']['all_decoded_samples_zero'])
                else:
                    with self.assertRaisesRegex(bridge.BridgeRefused,'host_webm_stream_or_duration_invalid'):
                        p._validate_webm(path)
                    self.assertNotIn('native_silent_audio_tracks',p.report)
            self.assertEqual(path.read_bytes(),original)
            self.assertEqual((p.report['frames'],p.report['videos']),([],[]))
            p.adb.assert_not_called();p._console.assert_not_called()

    def test_native_audio_decoder_refuses_nonzero_or_nan_samples_without_saving_audio(self):
        value={'streams':[{'codec_type':'video','codec_name':'vp9','width':540,'height':960,'avg_frame_rate':'10/1'},
                          {'codec_type':'audio','codec_name':'vorbis','channels':2,'sample_rate':'44100'}],
               'format':{'format_name':'matroska,webm','duration':'1.0'}}
        for sample in (0.0,0.00001,float('nan')):
            p,_,path,_=self.video_probe()
            def run(argv,**kwargs):
                return Mock(returncode=0,stdout=json.dumps(value).encode() if argv[0]=='ffprobe' else struct.pack('<f',sample))
            with self.subTest(sample=sample),patch.object(bridge.subprocess,'run',side_effect=run):
                if sample==0.0:p._validate_native_silent_audio_webm(path)
                else:
                    with self.assertRaisesRegex(bridge.BridgeRefused,'native_audio_exact_silence_required'):
                        p._validate_native_silent_audio_webm(path)
                    self.assertNotIn('native_silent_audio_tracks',p.report)

    def test_failed_empty_or_misaligned_decoder_output_never_becomes_silence(self):
        value={'streams':[{'codec_type':'video','codec_name':'vp9','width':540,'height':960},
                          {'codec_type':'audio','codec_name':'vorbis','channels':2,'sample_rate':'44100'}],
               'format':{'format_name':'webm','duration':'1.0'}}
        for status,data,code in [(1,b'\0'*4,'native_audio_decode_failed'),
                                 (0,b'','native_audio_decode_empty'),
                                 (0,b'\0'*3,'native_audio_decode_misaligned')]:
            p,_,path,_=self.video_probe()
            def run(argv,**kwargs):
                return Mock(returncode=0,stdout=json.dumps(value).encode()) if argv[0]=='ffprobe' else Mock(returncode=status,stdout=data)
            with self.subTest(code=code),patch.object(bridge.subprocess,'run',side_effect=run):
                with self.assertRaisesRegex(bridge.BridgeRefused,code):p._validate_native_silent_audio_webm(path)
            self.assertNotIn('native_silent_audio_tracks',p.report)
            self.assertEqual((p.report['frames'],p.report['videos']),([],[]))

    def test_audio_decode_size_cap_is_a_refusal_not_acceptance_of_partial_silence(self):
        class AtLimit(bytes):
            def __len__(self):return 50_000_000
        p,_,path,_=self.video_probe()
        value={'streams':[{'codec_type':'video','codec_name':'vp9','width':540,'height':960},
                          {'codec_type':'audio','codec_name':'vorbis','channels':2,'sample_rate':'44100'}],
               'format':{'format_name':'webm','duration':'1.0'}}
        commands=[]
        def run(argv,**kwargs):
            commands.append(argv)
            return Mock(returncode=0,stdout=json.dumps(value).encode() if argv[0]=='ffprobe' else AtLimit(b'\0'*4))
        with patch.object(bridge.subprocess,'run',side_effect=run):
            with self.assertRaisesRegex(bridge.BridgeRefused,'native_audio_decode_capped'):
                p._validate_native_silent_audio_webm(path)
        self.assertIn('-fs',commands[1]);self.assertIn('50000000',commands[1])
        self.assertNotIn('native_silent_audio_tracks',p.report)

    def test_native_layout_never_accepts_extra_video_or_foreign_audio(self):
        video={'codec_type':'video','codec_name':'vp9','width':540,'height':960}
        native={'codec_type':'audio','codec_name':'vorbis','channels':2,'sample_rate':'44100'}
        for streams in ([video,video],[video,dict(native,codec_name='opus')],[video,native,native],
                        [video,dict(native,channels=8)],[video,dict(native,sample_rate='96000')]):
            p,_,path,_=self.video_probe()
            data=json.dumps({'streams':streams,'format':{'format_name':'webm','duration':'1.0'}}).encode()
            with self.subTest(streams=streams),patch.object(bridge.subprocess,'run',return_value=Mock(returncode=0,stdout=data)) as run:
                with self.assertRaises(bridge.BridgeRefused):p._validate_native_silent_audio_webm(path)
            self.assertEqual(run.call_count,1)  # no audio decoding of a refused layout
            self.assertNotIn('native_silent_audio_tracks',p.report)


class VariantTests(unittest.TestCase):
    def load(self, relative):
        spec = importlib.util.spec_from_file_location('_synthetic_' + relative.replace('/', '_'),
                                                       HERE / 'variants' / relative)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_all_three_active_freshness_paths_execute_real_utc_checks(self):
        module = self.load('ROOT_C2_EXECUTOR_V2/phase_extensions.py')
        tag = 'AQER-C1-' + 'a' * 12
        title = 'SYNTHETIC ' + tag
        record = dict(kind=evidence.ROOT_KIND, context='submit_open', privacy_checked=True,
            manual_review_completed=True, fixture_key='synthetic', fixture_tag=tag,
            exact_fixture_title=title, frame_sha256=DIGEST,
            review_completed_utc='2026-11-03T12:00:00Z',
            same_exact_tagged_item_and_button_visually_verified=True)
        old_clock = evidence.utc_now
        evidence.utc_now = lambda: NOW
        try:
            self.assertTrue(module._valid_review(record, 'submit_open', 'synthetic', tag, title))
            stale = dict(record, review_completed_utc='2026-11-03T11:57:00Z')
            self.assertFalse(module._valid_review(stale, 'submit_open', 'synthetic', tag, title))
            # A fresh record reaches the preserved scene validator; a stale one
            # stops at freshness before any tree/input is used.
            for candidate, expected in [(record, 'fresh_app_root_required'),
                                         (stale, 'actual_manual_frame_review_expired')]:
                with self.assertRaisesRegex(module.policy.RemainingBlocked, '^' + expected + '$'):
                    module.policy.reviewed_action_node([], 'submit_open', title, tag, candidate,
                                                       native_role='broker', auth_uncertain=False)
            executor = module.C2Executor.__new__(module.C2Executor)
            executor.key, executor.tag, executor.title = 'synthetic', tag, title
            regular = dict(record, context='regular_isolation')
            del regular['frame_sha256']
            executor.reviews = {'regular_isolation': regular}
            self.assertEqual(executor._fresh_review('regular_isolation'), regular)
            executor.reviews['regular_isolation'] = dict(regular, review_completed_utc='2026-11-03T11:57:00Z')
            with self.assertRaisesRegex(module.C2Blocked, '^regular_prior_frames_nonimage_review_required$'):
                executor._fresh_review('regular_isolation')
        finally:
            evidence.utc_now = old_clock

    def test_original_full_tree_privacy_predicate_still_blocks_hidden_contact_fields(self):
        module = self.load('runtime/host_console_capture.py')
        capture = module.HostConsoleCaptureMixin()
        capture.private_values = {'synthetic-secret'}
        hidden_contact = [{'hint': 'رقم الاتصال *', 'visible': False}]
        self.assertTrue(capture._capture_rows_private(hidden_contact))
        self.assertTrue(capture._capture_rows_private([{'text': 'synthetic-secret', 'visible': True}]))
        self.assertTrue(capture._capture_rows_private([{'text': 'تسجيل الخروج', 'visible': True}]))
        self.assertFalse(capture._capture_rows_private([{'text': 'المواصفات', 'visible': True}]))

    def test_all_clock_sites_adapted_original_hashes_and_capture_unchanged(self):
        root = HERE.parents[2]
        originals = root / 'native-fixture'
        capture = root / 'android-alt/api36-proposal/runtime/host_console_capture.py'
        with tempfile.TemporaryDirectory(prefix='offline-variants-', dir=HERE) as directory:
            output = Path(directory) / 'variants'
            manifest = builder.build(originals, capture, output)
            for relative, digest in builder.PINS.items():
                self.assertEqual(hashlib.sha256((originals / relative).read_bytes()).hexdigest(), digest)
                self.assertNotIn('reviewed_monotonic', (output / relative).read_text())
                compile((output / relative).read_text(), relative, 'exec')
            self.assertEqual((output / 'runtime/host_console_capture.py').read_bytes(), capture.read_bytes())
            self.assertEqual(len(manifest), 8)
            policy_text = (output / 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py').read_text()
            self.assertIn('fresh_remote_review(review, now_utc=now_utc)', policy_text)
            c2_text = (output / 'ROOT_C2_EXECUTOR_V2/phase_extensions.py').read_text()
            self.assertEqual(c2_text.count('fresh_remote_review('), 2)
            dispatch = (output / 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py').read_text()
            self.assertIn('root_review_utc_expired', dispatch)
            self.assertIn("'frame_sha256', 'review_completed_utc'", dispatch)
        for relative, row in json.loads((HERE / 'variants/VARIANT_MANIFEST.json').read_text())['manifest'].items():
            self.assertEqual(hashlib.sha256((HERE / 'variants' / relative).read_bytes()).hexdigest(), row['sha256'])


if __name__ == '__main__':
    unittest.main()
