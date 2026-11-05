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

    def test_each_boundary_preserves_response_before_separate_proposal_scan_without_request_replay(self):
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
            self.assertEqual(result['cursor'],'RESPONSE_READY')
            self.assertEqual(self.state['response_ready_frames'],{'C1-c4-response-ready.png':DIGEST})
            self.assertEqual(self.state['response_ready_scene'],DIGEST)
            self.assertNotIn('ai_frames',self.state)
            self.probe.seek.assert_not_called()
            self.probe.scroll.assert_not_called()
            self.assertIsNone(self.probe.adapter)
            result = self.c4.collect_response(self.probe,self.state)
        self.probe.tap.assert_called_once_with('جهّز الإعلان')
        self.probe.wait.assert_any_call(self.c4.APPLY,seconds=120)
        self.assertEqual(result['cursor'],'AI_REVIEW')
        self.assertEqual(len(self.state['ai_frames']),7)
        self.assertFalse(self.state['accepted'])
        self.assertIsNone(self.state['inflight'])

    def test_changed_response_scene_refuses_scrolling_and_cannot_replay(self):
        self.state.update(cursor='RESPONSE_READY',response_ready_scene=DIGEST)
        with patch.object(self.c4,'ai_scene',return_value='f'*64):
            with self.assertRaisesRegex(self.c4.C4Blocked,'c4_response_ready_scene_changed'):
                self.c4.collect_response(self.probe,self.state)
            with self.assertRaisesRegex(self.c4.C4Blocked,'no_replay'):
                self.c4.collect_response(self.probe,self.state)
        self.probe.tap.assert_not_called()
        self.probe.seek.assert_not_called()
        self.probe.scroll.assert_not_called()

    def test_short_notice_seek_stops_at_literal_visible_ai_notice(self):
        rows=[[],[],[{'text':self.c4.AI_NOTICE,'visible':True}]]
        with patch.object(self.c4,'safe_rows',side_effect=rows):
            self.c4.seek_ai_notice(self.probe,self.state)
        self.assertEqual(self.probe.scroll.call_args_list,
                         [unittest.mock.call('backward',short=True)]*2)
        self.assertEqual(self.state['notice_seek'],{'observations':3,'short_scrolls_completed':2,
            'ai_notice_seen':True,'literal_fallback_seen':False})

    def test_literal_fallback_stops_without_scroll_or_ai_acceptance(self):
        rows=[{'text':self.c4.FALLBACK_NOTICE,'visible':True}]
        with patch.object(self.c4,'safe_rows',return_value=rows):
            with self.assertRaisesRegex(self.c4.C4Blocked,'literal_fallback_observed_no_ai_acceptance'):
                self.c4.seek_ai_notice(self.probe,self.state)
        self.probe.scroll.assert_not_called()
        self.assertTrue(self.state['notice_seek']['literal_fallback_seen'])
        self.assertFalse(self.state['accepted'])

    def test_notice_seek_is_bounded_short_bidirectional_and_ignores_hidden_notice(self):
        rows=[{'text':self.c4.AI_NOTICE,'visible':False},{'text':'SYNTHETIC_OTHER','visible':True}]
        with patch.object(self.c4,'safe_rows',return_value=rows):
            with self.assertRaisesRegex(self.c4.C4Blocked,'bounded_short_seek'):
                self.c4.seek_ai_notice(self.probe,self.state)
        self.assertEqual(self.probe.scroll.call_args_list,
            [unittest.mock.call('backward',short=True)]*4+[unittest.mock.call('forward',short=True)]*8)
        self.assertEqual(self.state['notice_seek']['observations'],13)
        self.assertNotIn('SYNTHETIC_OTHER',json.dumps(self.state['notice_seek']))

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

    def _edit_reviewed_title(self, existing_title):
        self.probe.authenticated = True
        self.probe.recorder = None
        self.probe._host_stop_unconfirmed = False
        self.probe._capture_rows_private.return_value = False
        rows = [{'text':label, 'visible':True} for label in
                (self.c4.AI_NOTICE, self.c4.APPLY, 'عنوان الإعلان', 'نص الإعلان')]
        self.probe.nodes.return_value = rows
        self.probe._capture_full_rows.return_value = rows
        self.probe.matching.side_effect = lambda current,label: [
            row for row in current if row.get('text') == label]
        actual_title = {'text':existing_title}
        self.probe.field.return_value = actual_title
        self.probe.set.side_effect = lambda label,value: actual_title.update(text=value)
        self.probe.require_value.side_effect = lambda label,expected: self.assertEqual(
            actual_title['text'], expected)
        self.state.update(cursor='AI_REVIEW', ai_scene=self.c4.ai_scene(self.probe),
                          request_copy_sha256='b'*64)
        review = {'actual_ai_notice':self.c4.AI_NOTICE, 'literal_fallback_notice_visible':False,
                  'all_selected_fields_and_copy_reviewed':True, 'copy_has_only_supplied_facts':True,
                  'verified_existing_draft_copy_facts':{},
                  'selected_fields':{'floor_number':'2','unit_number':'7'},
                  'all_proposal_cards_visible_in_reviewed_frames':True}
        def capture(probe,name):
            self.c4.ai_context(probe)  # Keep the actual strict sheet guard in this test.
            probe.capture_observed(name)
            return {name+'.png':DIGEST}
        with patch.object(self.c4,'ai_capture',side_effect=capture), \
             patch.object(self.c4,'copy_digest',return_value='b'*64):
            result = self.c4.edit_title(self.probe,self.state,review)
        self.assertEqual(result['cursor'],'APPLY_REVIEW')
        self.assertEqual(len(self.state['apply_frames']),2)
        self.probe.require_value.assert_called_once_with('عنوان الإعلان',self.state['title'])
        self.probe.tap.assert_not_called()
        return self.probe.method_calls

    def test_exact_reviewed_title_is_preserved_without_text_input_or_ime_transition(self):
        self._edit_reviewed_title(self.state['title'])
        self.probe.set.assert_not_called()
        self.probe.adb.assert_not_called()
        self.probe.wait.assert_not_called()

    def test_changed_reviewed_title_is_set_once_then_footer_observed_before_capture(self):
        calls = self._edit_reviewed_title('SYNTHETIC_DIFFERENT_TITLE')
        self.probe.set.assert_called_once_with('عنوان الإعلان',self.state['title'])
        self.probe.wait.assert_called_once_with(self.c4.APPLY,seconds=5)
        readback = unittest.mock.call.require_value('عنوان الإعلان',self.state['title'])
        wait = unittest.mock.call.wait(self.c4.APPLY,seconds=5)
        capture = unittest.mock.call.capture_observed('C1-c4-edited-title')
        self.assertLess(calls.index(readback),calls.index(wait))
        self.assertLess(calls.index(wait),calls.index(capture))


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


class C2SupportTransitionTests(unittest.TestCase):
    def setUp(self):
        def load(name):
            spec=importlib.util.spec_from_file_location('_support_'+name,
                HERE/'variants/ROOT_C2_EXECUTOR_V2'/name)
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            return module
        self.c2,self.dispatch=load('phase_extensions.py'),load('root_extension_dispatch.py')
        self.executor=self.c2.C2Executor.__new__(self.c2.C2Executor)
        e=self.executor
        e.key,e.tag,e.title='synthetic-key','AQER-C1-'+'a'*12,'SYNTHETIC AQER-C1-'+'a'*12
        e.property_id=123;e.reason='تصحيح اختبار اصطناعي فقط '+e.tag
        e.case_review_frame=e.case_header_binding=e.return_confirmation_frame=e.return_queue_transition=None
        e.delivered_frames={'support_open':'a'*64};e.reviews={}
        self.probe=Mock(authenticated=True,active_native_role='support',native_auth_uncertain=False,
                        recorder=None,_host_stop_unconfirmed=False)
        self.probe._capture_rows_private.return_value=False
        e.probe=self.probe
        self.rows=[]
        self.probe.nodes.side_effect=lambda:self.rows
        self.probe._capture_full_rows.side_effect=lambda:self.rows
        self.probe.seek.side_effect=lambda label:self.action_view()
        self.title_view()

    def row(self,path,text,bounds,clickable=False):
        return {'path':path,'witness':hashlib.sha256(path.encode()).hexdigest(),
                'text':text,'package':self.c2.roles.APP,'visible':True,'enabled':True,
                'bounds':bounds,'clickable':clickable,
                'class':'android.widget.Button' if clickable else 'android.view.View'}

    def view(self,*labels):
        self.rows=[self.row('0','',[0,0,540,960])]
        self.rows += [self.row('0.'+str(i+1),label,[10,10+i*80,520,60+i*80],
                               label=='إرجاع للتصحيح') for i,label in enumerate(labels)]

    def title_view(self):self.view('تحقيق الإعلان',self.executor.title)
    def action_view(self):self.view('تحقيق الإعلان','إرجاع للتصحيح','قبول ونشر','رفض نهائي وحظر')
    def queue_view(self):self.view('تحقيق الإعلانات','طلبات التحقيق','لا توجد طلبات معلقة')

    def record(self,stage,**extra):
        e=self.executor
        return dict(kind='ROOT_ACTUAL_FRAME_REVIEW',context=stage,privacy_checked=True,
            manual_review_completed=True,fixture_key=e.key,fixture_tag=e.tag,exact_fixture_title=e.title,
            actual_frame_file='C2-'+stage+'-1.png',frame_sha256='b'*64,
            review_completed_utc=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),**extra)

    def accept_title(self):
        record=self.record('review_case',exact_own_case_title_observed=True)
        self.executor._review_observation('review_case',record)
        self.executor._execute('review_case',record)
        return record

    def action_record(self):
        bindings=self.dispatch._capture_rows(self.probe,self.c2,self.executor,'return_open')
        title,button=bindings['title_candidates'][0],bindings['button_candidates'][0]
        return self.record('return_open',root_witness=bindings['root']['witness'],
            title_path=title['path'],title_witness=title['witness'],button_path=button['path'],
            button_witness=button['witness'],same_serialized_support_case_chain_reviewed=True,
            serialized_case_binding=bindings['serialized_case_binding'],
            fixture_title_visible_in_action_frame=False)

    def test_exact_title_review_then_scoped_scroll_keeps_separate_frame_identity(self):
        record=self.accept_title()
        self.probe.seek.assert_called_once_with('إرجاع للتصحيح')
        self.probe.act.assert_not_called()
        self.assertNotIn(self.executor.title,self.c2._names(self.rows))
        self.assertEqual(self.executor._case_binding()['case_title_review_frame'],
                         {'file':record['actual_frame_file'],'sha256':record['frame_sha256']})

    def test_lower_action_review_binds_prior_title_and_never_requires_title_in_same_frame(self):
        self.accept_title();record=self.action_record()
        self.assertNotIn('same_exact_tagged_item_and_button_visually_verified',record)
        self.executor.reviews['return_open']=record
        prepared=self.executor._prepare('return_open')
        self.assertEqual(prepared[1]['text'],'إرجاع للتصحيح')
        self.executor._execute('return_open',prepared)
        self.probe.act.assert_called_once_with('click',prepared[1])

    def test_changed_case_binding_or_publish_button_cannot_authorize_return(self):
        self.accept_title();record=self.action_record()
        for change in ({'serialized_case_binding':{}}, {'fixture_title_visible_in_action_frame':True},
                       {'button_path':'0.3','button_witness':self.rows[3]['witness']}):
            self.executor.reviews['return_open']=dict(record,**change)
            self.assertIsNone(self.executor._prepare('return_open'))
        self.probe.act.assert_not_called()

    def test_case_action_capture_without_accepted_exact_title_is_refused(self):
        self.action_view()
        with self.assertRaises(self.dispatch.Hold):
            self.dispatch._capture_rows(self.probe,self.c2,self.executor,'return_open')

    def test_changed_case_header_or_private_full_tree_refuses_action_capture(self):
        self.accept_title()
        self.rows[1]['witness']='f'*64
        with self.assertRaisesRegex(self.dispatch.Hold,'REVIEWED_CASE_HEADER_CHANGED'):
            self.dispatch._capture_rows(self.probe,self.c2,self.executor,'return_open')
        self.action_view();self.probe._capture_rows_private.return_value=True
        with self.assertRaisesRegex(self.dispatch.Hold,'PRIVATE_CONTEXT'):
            self.dispatch._capture_rows(self.probe,self.c2,self.executor,'return_open')

    def test_successful_return_uses_actual_queue_and_defers_exact_outcome(self):
        self.accept_title();record=self.record('return_confirm')
        self.view('إرجاع الإعلان للتصحيح',self.executor.reason,'تأكيد')
        self.probe.act.side_effect=lambda *a:self.queue_view()
        self.executor._execute('return_confirm',(record,{'text':'تأكيد'}))
        self.assertNotIn(self.executor.title,self.c2._names(self.rows))
        bindings=self.dispatch._capture_rows(self.probe,self.c2,self.executor,'review_returned')
        transition=bindings['return_queue_transition']
        self.assertFalse(transition['exact_returned_state_proved'])
        self.assertEqual(transition['return_confirmation_frame']['sha256'],record['frame_sha256'])
        review=self.record('review_returned',return_queue_transition=transition,
            return_queue_transition_reviewed=True,exact_outcome_deferred_to_broker_reason=True,
            native_return_confirmed=False,publication_or_rejection_executed=False,
            exact_reason=self.executor.reason)
        self.executor._review_observation('review_returned',review)
        for change in ({'native_return_confirmed':True},{'publication_or_rejection_executed':True},
                       {'exact_outcome_deferred_to_broker_reason':False}):
            with self.assertRaises(self.c2.C2Blocked):
                self.executor._review_observation('review_returned',dict(review,**change))
        self.probe.act.assert_called_once()

    def test_loading_dialog_or_still_visible_fixture_is_not_return_completion(self):
        for extra in ('جارٍ تحميل طلبات التحقيق...','إرجاع الإعلان للتصحيح',self.executor.title):
            self.view('تحقيق الإعلانات','طلبات التحقيق','لا توجد طلبات معلقة',extra)
            self.assertFalse(self.executor._return_queue_observed())

    def test_claim_and_open_wait_for_source_confirmed_destinations(self):
        record=self.record('support_claim')
        self.executor._execute('support_claim',(record,{'text':'استلام'}))
        self.probe.wait.assert_any_call('تحقيق الإعلانات',seconds=45)
        self.probe.seek.assert_called_once_with(self.executor.title)
        self.probe.wait.assert_any_call('تم الاستلام - قيد التحقيق',seconds=45)
        self.probe.wait.reset_mock()
        self.executor._execute('support_open',(self.record('support_open'),{'text':'متابعة التحقيق'}))
        self.assertEqual(self.probe.wait.call_args_list,[
            unittest.mock.call('تحقيق الإعلان',seconds=45),
            unittest.mock.call(self.executor.title,seconds=45)])



class C2FailureDiagnosticTests(unittest.TestCase):
    def modules(self):
        def load(name, path):
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            return module
        source = HERE.parents[1] / 'probe_phase1_native_account.py'
        sys.path.insert(0, str(source.parent))
        return (load('_c2_failure_base', source),
                load('_c2_failure_executor', HERE / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py'))

    def native_probe(self):
        actual, c2 = self.modules()
        p = actual.NativeAccount.__new__(actual.NativeAccount)
        p.report = {}; p.authenticated = True; p.recorder = None; p.save = Mock()
        p._root_c2_executor_v2 = Mock(probe=p, inflight=True, cursor=2)
        p._root_c2_executor_v2._diagnostic_operation = {'control': 'rent', 'substage': 'instrument'}
        return actual, p

    def test_c2_native_failure_records_fixed_focus_shapes_without_private_output(self):
        actual, p = self.native_probe()
        p.c2_input_failure('account-set', {
            'stage': 'account_focus_hint_match', 'foreground_category': 'APP', 'passed': 'false',
            'focus_hint_original_shape': 'MONTHLY_RENT_LABEL',
            'focus_hint_current_shape': 'MONTHLY_RENT_LABEL_AND_ZERO',
            'focus_source_node_same': 'true', 'focus_observed_focused': 'true',
            'focus_observation_count': '3', 'tree_b64': 'PRIVATE_TOKEN',
            'message': 'PRIVATE_PHONE'}, 'PRIVATE_OUTPUT', 'native_input_not_delivered')
        row = p.report['c2_v2_native_input_failure']
        self.assertEqual(row['java_stage'], 'account_focus_hint_match')
        self.assertEqual(row['current_hint_shape'], 'MONTHLY_RENT_LABEL_AND_ZERO')
        self.assertTrue(row['same_original_android_node'])
        self.assertEqual(row['observations'], 3)
        self.assertNotIn('PRIVATE', json.dumps(p.report))
        p.save.assert_called_once()

    def test_c2_native_failure_ignores_unknown_shapes_and_requires_exact_active_scope(self):
        actual, p = self.native_probe()
        result = {'stage': 'PRIVATE_STAGE', 'focus_hint_original_shape': 'PRIVATE_HINT',
                  'focus_observation_count': '9999', 'foreground_category': 'PRIVATE_PACKAGE'}
        p._root_c2_executor_v2.cursor = 20
        p.c2_input_failure('account-set', result, 'PRIVATE_OUTPUT', 'PRIVATE_REASON')
        self.assertEqual(p.report, {})
        p._root_c2_executor_v2.cursor = 2
        p.c2_input_failure('account-set', result, 'PRIVATE_OUTPUT', 'PRIVATE_REASON')
        row = p.report['c2_v2_native_input_failure']
        self.assertIsNone(row['java_stage'])
        self.assertEqual(row['reason'], 'native_instrumentation_unobserved')
        self.assertNotIn('original_hint_shape', row)
        self.assertNotIn('observations', row)
        self.assertNotIn('PRIVATE', json.dumps(p.report))

    def test_c2_contact_failure_keeps_only_fixed_context_without_contact_payload(self):
        for control, substage, op in (
                ('fixture_contact', 'instrument', 'account-set'),
                ('fixture_contact', 'dismiss_ime', 'account-dismiss-ime'),
                ('fixture_contact', 'contact_policy_observation', 'account-snapshot'),
                ('fixture_contact', 'contact_readback', 'account-scroll'),
                ('validation_preview', 'instrument', 'account-click'),
                ('draft_options', 'instrument', 'account-click')):
            with self.subTest(control=control, substage=substage):
                actual, p = self.native_probe()
                p._root_c2_executor_v2._diagnostic_operation = {'control': control, 'substage': substage}
                p.c2_input_failure(op, {
                    'stage': 'account_focus_hint_match', 'passed': 'false',
                    'focus_hint_original_shape': 'PRIVATE_CONTACT_HINT',
                    'contact': 'PRIVATE_CONTACT', 'prefixes': 'PRIVATE_PREFIX',
                    'message': 'PRIVATE_VALIDATION_ERROR', 'tree_b64': 'PRIVATE_TREE',
                    'node_witness': 'PRIVATE_HASH'}, 'PRIVATE_OUTPUT', 'native_input_not_delivered')
                row = p.report['c2_v2_native_input_failure']
                self.assertEqual((row['stage'], row['control'], row['substage'], row['op']),
                                 ('complete_rent', control, substage, op))
                self.assertNotIn('PRIVATE', json.dumps(p.report))
                p.save.assert_called_once()

    def test_c2_contact_readback_failure_requires_exact_later_stage_and_active_scope(self):
        for cursor, stage in ((5, 'return_next_step3'), (6, 'back_gaps_to_completion'), (7, 'full_save')):
            actual, p = self.native_probe()
            p._root_c2_executor_v2.cursor = cursor
            p._root_c2_executor_v2._diagnostic_operation = {
                'control': 'fixture_contact', 'substage': 'contact_readback'}
            p.c2_input_failure('account-scroll', {'stage': 'account_scroll'}, '', 'native_input_not_delivered')
            self.assertEqual(p.report['c2_v2_native_input_failure']['stage'], stage)
        for change in ('other_cursor', 'late_set', 'late_preview', 'not_inflight', 'unauthenticated', 'recording'):
            actual, p = self.native_probe()
            e = p._root_c2_executor_v2
            e.cursor = 7
            e._diagnostic_operation = {'control': 'fixture_contact', 'substage': 'contact_readback'}
            if change == 'other_cursor': e.cursor = 8
            elif change == 'late_set': e._diagnostic_operation['substage'] = 'instrument'
            elif change == 'late_preview': e._diagnostic_operation['control'] = 'validation_preview'
            elif change == 'not_inflight': e.inflight = False
            elif change == 'unauthenticated': p.authenticated = False
            else: p.recorder = object()
            p.c2_input_failure('account-snapshot', {}, 'PRIVATE_OUTPUT', 'native_input_not_delivered')
            self.assertEqual(p.report, {}, change)
            p.save.assert_not_called()

    def test_c2_ime_failure_retains_only_fixed_phase_substage_and_bounded_counts(self):
        actual, p = self.native_probe()
        p._root_c2_executor_v2._diagnostic_operation = {'control': 'sai_rate', 'substage': 'dismiss_ime'}
        p.c2_input_failure('account-dismiss-ime', {
            'stage': 'ime_windows', 'ime_observation_phase': 'AFTER_KEY',
            'ime_observation_substage': 'APP_WINDOW_UNIQUE', 'ime_observation_count': '4',
            'ime_window_count': '3', 'ime_focused_app_matches': '0',
            'raw_windows': 'PRIVATE_WINDOW_TEXT'}, 'PRIVATE_OUTPUT', 'native_input_not_delivered')
        row = p.report['c2_v2_native_input_failure']
        self.assertEqual(row['ime_observation'], {'phase': 'AFTER_KEY',
            'substage': 'APP_WINDOW_UNIQUE', 'observations': 4, 'window_count': 3,
            'focused_app_matches': 0})
        self.assertNotIn('PRIVATE', json.dumps(p.report))
        actual, p = self.native_probe()
        p.c2_input_failure('account-dismiss-ime', {
            'stage': 'ime_windows', 'ime_observation_phase': 'BEFORE_KEY',
            'ime_observation_substage': 'CACHE_CLEAR', 'ime_observation_count': '1'},
            '', 'native_input_not_delivered')
        self.assertEqual(p.report['c2_v2_native_input_failure']['ime_observation'],
                         {'phase': 'BEFORE_KEY', 'substage': 'CACHE_CLEAR', 'observations': 1})

    def test_c2_ime_failure_refuses_unknown_categories_and_out_of_range_counts(self):
        for change in ({'ime_observation_phase': 'PRIVATE_PHASE'},
                       {'ime_observation_substage': 'PRIVATE_SUBSTAGE'},
                       {'ime_observation_count': '151'}):
            actual, p = self.native_probe()
            result = {'stage': 'ime_windows', 'ime_observation_phase': 'BEFORE_KEY',
                      'ime_observation_substage': 'WINDOW_LIST', 'ime_observation_count': '1'}
            result.update(change)
            p.c2_input_failure('account-dismiss-ime', result, '', 'native_input_not_delivered')
            self.assertNotIn('ime_observation', p.report['c2_v2_native_input_failure'])
            self.assertNotIn('PRIVATE', json.dumps(p.report))
        actual, p = self.native_probe()
        p.c2_input_failure('account-dismiss-ime', {
            'ime_observation_phase': 'BEFORE_KEY', 'ime_observation_substage': 'WINDOW_ENTRY',
            'ime_observation_count': '2', 'ime_window_count': '34',
            'ime_focused_app_matches': '3'}, '', 'native_input_not_delivered')
        self.assertEqual(p.report['c2_v2_native_input_failure']['ime_observation'],
                         {'phase': 'BEFORE_KEY', 'substage': 'WINDOW_ENTRY', 'observations': 2})

    def test_c2_ime_retained_field_diagnostic_accepts_only_fixed_true_false_strings(self):
        actual, p = self.native_probe()
        fixed = {key: ('true' if index % 2 else 'false')
                 for index, key in enumerate(actual.IME_RETAINED_FIELD_BOOLEAN_KEYS)}
        p.c2_input_failure('account-dismiss-ime', dict(fixed,
            ime_observation_phase='AFTER_KEY', ime_observation_substage='ORIGINAL_FIELD_RETAINED',
            ime_observation_count='4', original_text='PRIVATE_TEXT',
            original_class='PRIVATE_CLASS', arbitrary_flag='true'),
            'PRIVATE_OUTPUT', 'native_input_not_delivered')
        observation = p.report['c2_v2_native_input_failure']['ime_observation']
        for key, value in fixed.items():
            self.assertIs(observation[key.removeprefix('ime_')], value == 'true')
        self.assertEqual(set(observation), {'phase', 'substage', 'observations'} |
                         {key.removeprefix('ime_') for key in fixed})
        self.assertNotIn('PRIVATE', json.dumps(p.report))

    def test_c2_ime_retained_field_diagnostic_rejects_other_values_and_preserves_bounds(self):
        for value in (True, False, 1, 0, None, 'TRUE', 'False', 'PRIVATE', {}, []):
            actual, p = self.native_probe()
            result = {key: value for key in actual.IME_RETAINED_FIELD_BOOLEAN_KEYS}
            result.update(ime_observation_phase='AFTER_KEY',
                          ime_observation_substage='ORIGINAL_FIELD_REFRESH',
                          ime_observation_count='2', ime_window_count='99')
            p.c2_input_failure('account-dismiss-ime', result, '', 'native_input_not_delivered')
            self.assertEqual(p.report['c2_v2_native_input_failure']['ime_observation'],
                             {'phase': 'AFTER_KEY', 'substage': 'ORIGINAL_FIELD_REFRESH', 'observations': 2})
            self.assertNotIn('PRIVATE', json.dumps(p.report))

    def test_c2_ime_logical_rebind_failure_preserves_fixed_false_and_true_evidence(self):
        actual, p = self.native_probe()
        p.c2_input_failure('account-dismiss-ime', {
            'ime_observation_phase': 'AFTER_KEY', 'ime_observation_substage': 'LOGICAL_FIELD_REBIND',
            'ime_observation_count': '3', 'ime_original_refreshed': 'false',
            'ime_logical_field_rebound': 'false', 'ime_logical_field_unique': 'false',
            'ime_logical_anchor_present': 'true', 'ime_logical_field_value': 'PRIVATE_VALUE',
            'ime_logical_field_hint': 'PRIVATE_HINT'}, '', 'native_input_not_delivered')
        self.assertEqual(p.report['c2_v2_native_input_failure']['ime_observation'], {
            'phase': 'AFTER_KEY', 'substage': 'LOGICAL_FIELD_REBIND', 'observations': 3,
            'original_refreshed': False, 'logical_field_rebound': False,
            'logical_field_unique': False, 'logical_anchor_present': True})
        self.assertNotIn('PRIVATE', json.dumps(p.report))

    def test_real_native_receiver_records_c2_failure_before_rethrow(self):
        actual, p = self.native_probe()
        p._active_case = None
        p.c4_prepare_input_failure = Mock()
        p.adb = Mock(return_value='INSTRUMENTATION_RESULT: passed=false\n'
                    'INSTRUMENTATION_RESULT: stage=account_focus_hint_match\n'
                    'INSTRUMENTATION_RESULT: message=PRIVATE_VALUE\nINSTRUMENTATION_CODE: 0')
        with self.assertRaisesRegex(actual.Blocked, '^native_input_not_delivered$'):
            p.instrument('account-set', node_path='0.1', node_witness=DIGEST, value_b64='MA==')
        self.assertEqual(p.report['c2_v2_native_input_failure']['java_stage'], 'account_focus_hint_match')
        self.assertNotIn('PRIVATE', json.dumps(p.report))
        p.adb.assert_called_once()

    def test_complete_rent_failure_keeps_exact_substage_and_latches_without_replay(self):
        actual, c2 = self.modules()
        e = c2.C2Executor.__new__(c2.C2Executor)
        e.cursor = 2; e.failed = e.inflight = False; e.monthly_rent = '50000'
        e.fixture_contact = '770000028'
        e._nonimage_field = Mock(return_value={'path': '0.1', 'witness': DIGEST})
        e.regular_logout_receipt = None; e.property_id = None
        p = Mock(report={}, explicit_pointer_mode=False)
        p.field.return_value = {'path': '0.1', 'witness': DIGEST}
        p.instrument.side_effect = AdmissionError('PRIVATE_TOKEN PRIVATE_PHONE')
        e.probe = p; e._prepare = Mock(return_value=True); e._actor = Mock()
        with self.assertRaisesRegex(c2.C2Blocked, '^c2_stage_uncertain_root_readback_required$'):
            e.advance()
        row = p.report['c2_v2_stage_failure']
        self.assertEqual((row['stage'], row['control'], row['substage']),
                         ('complete_rent', 'rent', 'instrument'))
        self.assertEqual(row['exception_type'], 'AdmissionError')
        self.assertTrue(row['source_frames'])
        self.assertNotIn('PRIVATE', json.dumps(p.report))
        self.assertTrue(e.failed)
        with self.assertRaisesRegex(c2.C2Blocked, '^c2_uncertain_stage_no_replay$'):
            e.advance()
        p.instrument.assert_called_once()

    def test_pin_failure_fixed_reason_survives_wrapped_normal_session_without_payload(self):
        actual, c2 = self.modules()
        e = c2.C2Executor.__new__(c2.C2Executor)
        p = Mock(report={}, adapter=None, private_values=set())
        p._known_role_memory.resolve.return_value = ('PRIVATE_PHONE', 'PRIVATE_OTP')
        e.probe = p; e.state = {}; e._guest = Mock(); e.property_id = None
        logged_out = False
        def request(method, path, body, token):
            nonlocal logged_out
            if path == '/auth/whatsapp/verify': return 200, {'data': {'token': 'PRIVATE_TOKEN'}}
            if path == '/auth/logout': logged_out = True; return 200, {}
            if path == '/auth/me':
                return (401, {}) if logged_out else (200, {'data': {'user': {'id': 28, 'account_type': 'broker'}}})
            return 200, {}
        e.request = request
        receipt = {'status': 'BLOCKED', 'reason': 'new_property_ownership_required',
                   'payload': 'PRIVATE_BODY', 'token': 'PRIVATE_TOKEN', 'property_id': 'PRIVATE_ID'}
        with patch.object(c2.cleanup_module, 'PromotedFixtureCleanup') as helper:
            helper.return_value.pin_candidate.return_value = receipt
            with self.assertRaisesRegex(c2.C2Blocked, '^normal_api_work_or_auth_uncertain$'):
                e._execute('pin_promotion', True)
        self.assertEqual(p.report['c2_pin_promotion_diagnostic'],
                         {'status': 'BLOCKED', 'reason': 'new_property_ownership_required'})
        self.assertTrue(logged_out)
        self.assertTrue(p.report['c2_normal_api_sessions'][0]['revoked_token_me_http_401'])
        self.assertIsNone(e.property_id)
        p.save.assert_called_once()
        self.assertNotIn('PRIVATE', json.dumps(p.report))
        for receipt in ({'status': 'PRIVATE_STATUS', 'reason': 'PRIVATE_REASON'},
                        {'status': {}, 'reason': []}, None):
            self.assertEqual(c2.pin_candidate_diagnostic(receipt),
                             {'status': 'UNOBSERVED', 'reason': 'UNOBSERVED'})

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
            self.assertEqual(c2_text.count('fresh_remote_review('), 3)
            dispatch = (output / 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py').read_text()
            self.assertIn('root_review_utc_expired', dispatch)
            self.assertIn("'frame_sha256', 'review_completed_utc'", dispatch)
        for relative, row in json.loads((HERE / 'variants/VARIANT_MANIFEST.json').read_text())['manifest'].items():
            self.assertEqual(hashlib.sha256((HERE / 'variants' / relative).read_bytes()).hexdigest(), row['sha256'])


if __name__ == '__main__':
    unittest.main()
