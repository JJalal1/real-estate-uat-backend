"""Offline list readiness/reveal contracts; no native actions or acceptance."""
import ast
import copy
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
SPEC = importlib.util.spec_from_file_location('_c2_list_readiness',
    HERE / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
c2 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(c2)
TITLE = 'اختبار استعادة المسودة AQER-C1-123456789abc'
REASON = 'تصحيح اختبار اصطناعي فقط AQER-C1-123456789abc'

# Exercise the existing bounded seek, without constructing a device/runner.
tree = ast.parse((HERE.parents[1] / 'probe_phase1_native_account.py').read_text())
method = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == 'seek')
scope = {'Blocked': c2.C2Blocked}
exec(compile(ast.Module(body=[method], type_ignores=[]), '<source-bounded-seek>', 'exec'), scope)
logout_method = next(n for n in ast.walk(tree)
                     if isinstance(n, ast.FunctionDef) and n.name == 'wait_account_logout_control')
logout_scope = {'Blocked': c2.C2Blocked, 'labels': c2.policy.names,
                'AUTH_LABELS': c2.roles.AUTH_LABELS, 'time': c2.time}
exec(compile(ast.Module(body=[logout_method], type_ignores=[]), '<source-account-wait>', 'exec'), logout_scope)


def rows(*labels):
    return [{'package': c2.roles.APP, 'visible': True, 'enabled': True,
             'path': '0.' + str(i), 'text': label, 'bounds': [0, i*40, 300, i*40+30]}
            for i, label in enumerate(labels, 1)]


class Clock:
    value = 0
    def monotonic(self): return self.value
    def sleep(self, seconds): self.value += seconds


class Probe:
    def __init__(self, snapshots, role='broker'):
        self.snapshots, self.reads = snapshots, 0
        self.authenticated, self.active_native_role = True, role
        self.native_auth_uncertain, self.recorder = False, None
        self.report, self.inputs, self.seeks, self.scrolls = {}, [], [], []
    def nodes(self):
        result = self.snapshots[min(self.reads, len(self.snapshots)-1)]
        self.reads += 1
        return copy.deepcopy(result)
    def matching(self, observed, label):
        return [r for r in observed if r.get('visible') and r.get('enabled') and label in c2.policy.names(r)]
    def c4_ai_field_scope(self, label): return False
    def scroll(self, direction='forward', *, short=False): self.scrolls.append((direction, short))
    def seek(self, label, attempts=12):
        self.seeks.append((label, attempts, self.reads))
        return scope['seek'](self, label, attempts=attempts)
    def act(self, kind, node): self.inputs.append((kind, node['path']))
    def tap(self, label): self.inputs.append(('tap', label))
    def wait(self, label, **kwargs): pass
    def save(self): pass


class AccountProbe(Probe):
    def __init__(self, snapshots):
        super().__init__(snapshots, 'regular')
        self.private_hashes, self.auth_during_inputs = [], []
    def tap(self, label, *, seek=True):
        self.inputs.append(('tap', label, seek))
        self.auth_during_inputs.append(self.authenticated)
        if self.authenticated: self.private_hashes.append('forbidden-account-hash')
    def scroll(self, direction='forward', *, short=False):
        super().scroll(direction, short=short)
        self.auth_during_inputs.append(self.authenticated)
        if self.authenticated: self.private_hashes.append('forbidden-account-hash')
    def wait_account_logout_control(self, seconds=30):
        return logout_scope['wait_account_logout_control'](self, seconds=seconds)


def executor(stage, snapshots, *, role='broker'):
    x = object.__new__(c2.C2Executor)
    x.probe = Probe(snapshots, role)
    x.title, x.tag, x.reason = TITLE, 'AQER-C1-123456789abc', REASON
    x.cursor, x.failed, x.inflight = c2.STAGES.index(stage), False, True
    x.preparation_attempt, x.pending_preparation = 0, None
    x.regular_logout_receipt, x.property_id = None, 99
    x.entry_mode, x.delivered_frames = 'standard_editor', {}
    x._fallback = lambda observed: None
    return x


class ListReadinessTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        for name in ('monotonic', 'sleep'):
            replacement = patch.object(c2.time, name, getattr(self.clock, name))
            replacement.start(); self.addCleanup(replacement.stop)

    def test_navigation_waits_for_data_then_reveals_own_submit_action(self):
        x = executor('open_my_listings', [rows('عقاراتي'), rows('عقاراتي', 'إضافة عقار'),
            rows('عقاراتي', TITLE), rows('عقاراتي', TITLE), rows('عقاراتي', TITLE, 'إرسال للمراجعة')])
        x._execute('open_my_listings', True)
        self.assertEqual(x.probe.inputs, [('tap', 'حسابي'), ('tap', 'عقاراتي')])
        self.assertEqual(x.probe.seeks, [(TITLE, 12, 2)])
        self.assertEqual(x.probe.scrolls, [('forward', True)])

    def test_support_loading_never_triggers_early_seek(self):
        title = 'تحقق نشر إعلان: ' + TITLE
        x = executor('support_inbox', [rows('الوارد', 'تحقيق إعلانات', 'جارٍ تحميل طلبات الدعم…'),
            rows('الوارد', 'تحقيق إعلانات', 'استلام'),
            rows('الوارد', 'تحقيق إعلانات', title, 'استلام')], role='support')
        x._execute('support_inbox', True)
        self.assertEqual(x.probe.inputs, [('tap', 'الوارد')])
        self.assertEqual(x.probe.seeks, [(title, 12, 2)])
        x = executor('support_claim', [rows('تحقيق الإعلانات', 'طلبات التحقيق', 'جارٍ تحميل طلبات التحقيق...'),
            rows('تحقيق الإعلانات', 'طلبات التحقيق', 'تم الاستلام - قيد التحقيق')], role='support')
        x._wait_loaded_list('support_queue')
        self.assertEqual(x.probe.reads, 2)
        self.assertEqual(x.probe.inputs + x.probe.scrolls, [])

    def test_support_reveals_only_the_exact_title_retained_control(self):
        for stage, title, anchors, controls in [
            ('support_inbox', 'تحقق نشر إعلان: ' + TITLE, ('الوارد', 'تحقيق إعلانات'), ('استلام',)),
            ('support_claim', TITLE, ('تحقيق الإعلانات', 'طلبات التحقيق'),
             ('تم الاستلام - قيد التحقيق', 'متابعة التحقيق')),
        ]:
            x = executor(stage, [rows(*anchors, title), rows(*anchors, title, *controls)], role='support')
            x._reveal_support_card_fields()
            self.assertEqual(x.probe.scrolls, [('forward', True)])
            self.assertEqual(x.probe.inputs, [])
            x = executor(stage, [rows(*anchors, title), rows(*anchors, *controls)], role='support')
            with self.assertRaises(c2.C2Blocked): x._reveal_support_card_fields()
            self.assertEqual(x.probe.scrolls, [('forward', True)])

    def test_submit_waits_for_modal_and_reload_after_only_one_confirmation(self):
        modal = rows('تحديد السعي قبل إرسال الإعلان')
        loaded = rows('عقاراتي', 'إضافة عقار', TITLE, 'مسودة')
        x = executor('submit_confirm', [modal, modal, rows('عقاراتي'), loaded, loaded,
            rows('عقاراتي'), rows('عقاراتي', 'إضافة عقار'),
            rows('عقاراتي', TITLE, 'بانتظار المراجعة'), rows('عقاراتي', TITLE, 'بانتظار المراجعة')])
        record = {'frame_sha256': 'a'*64, 'existing_platform_fallback_sai_reviewed': True,
                  'custom_terms_accepted': False}
        x._execute('submit_confirm', (record, {'path': '0.9'}))
        self.assertEqual(x.probe.inputs, [('click', '0.9')])
        self.assertEqual(len(x.probe.seeks), 2)
        self.assertEqual(x.delivered_frames['submit_confirm'], 'a'*64)

    def test_generic_overview_cannot_complete_pending_readiness(self):
        loaded = rows('عقاراتي', 'إضافة عقار', TITLE, 'قيد المراجعة')
        x = executor('submit_confirm', [loaded])
        with self.assertRaises(c2.C2Blocked): x._wait_submitted_listing()
        self.assertEqual(len(x.probe.seeks), 1)
        self.assertEqual(x.probe.inputs, [])

    def test_second_title_loss_refuses_a_third_seek(self):
        loaded = rows('عقاراتي', 'إضافة عقار', TITLE)
        x = executor('submit_confirm', [loaded, loaded, rows('عقاراتي', 'إضافة عقار'),
            loaded, rows('عقاراتي', 'إضافة عقار')])
        with self.assertRaises(c2.C2Blocked): x._wait_submitted_listing()
        self.assertEqual(len(x.probe.seeks), 2)
        self.assertEqual(x.probe.inputs, [])

    def test_returned_reason_reveal_requires_exact_title_note_and_resend(self):
        x = executor('open_reason', [rows('عقاراتي', TITLE),
            rows('عقاراتي', TITLE, REASON, 'ملاحظة فريق المراجعة'),
            rows('عقاراتي', TITLE, REASON, 'ملاحظة فريق المراجعة', 'إعادة الإرسال')])
        x._reveal_own_listing_fields()
        self.assertEqual(x.probe.scrolls, [('forward', True), ('forward', True)])
        self.assertEqual(x.probe.inputs, [])

    def test_reveal_stops_if_title_is_lost_or_duplicated(self):
        for last in [rows('عقاراتي', REASON, 'إعادة الإرسال'), rows('عقاراتي', TITLE, TITLE)]:
            x = executor('open_reason', [rows('عقاراتي', TITLE), last])
            with self.assertRaises(c2.C2Blocked): x._reveal_own_listing_fields()
            self.assertEqual(x.probe.scrolls, [('forward', True)])

    def test_reveal_has_six_scroll_limit_without_action_replay(self):
        x = executor('open_reason', [rows('عقاراتي', TITLE)])
        with self.assertRaises(c2.C2Blocked): x._reveal_own_listing_fields()
        self.assertEqual(len(x.probe.scrolls), 6)
        self.assertEqual(x.probe.inputs, [])

    def test_no_reveal_or_loaded_wait_during_prepare_or_wrong_stage(self):
        x = executor('open_reason', [rows('عقاراتي', TITLE)])
        x.inflight = False
        with self.assertRaises(c2.C2Blocked): x._reveal_own_listing_fields()
        with self.assertRaises(c2.C2Blocked): x._wait_loaded_list('my_listings')
        x.inflight, x.cursor = True, c2.STAGES.index('review_broker_reason')
        with self.assertRaises(c2.C2Blocked): x._reveal_own_listing_fields()
        self.assertEqual(x.probe.reads, 0)

    def test_auth_surface_refuses_wait_and_reveal_before_scroll(self):
        x = executor('open_reason', [rows('مرحبًا بعودتك')])
        with self.assertRaises(c2.C2Blocked): x._wait_loaded_list('my_listings')
        with self.assertRaises(c2.C2Blocked): x._reveal_own_listing_fields()
        self.assertEqual(x.probe.inputs + x.probe.scrolls, [])

    def test_actual_under_review_label_keeps_manual_card_requirements(self):
        x = executor('review_submitted', [rows('عقاراتي', TITLE, 'تحت المراجعة')])
        record = {'exact_tagged_card_status': 'تحت المراجعة', 'own_card_status_visually_verified': True,
                  'no_edit_action_on_exact_pending_card': True, 'published': False}
        x._review_observation('review_submitted', record)
        record['own_card_status_visually_verified'] = False
        with self.assertRaises(c2.C2Blocked): x._review_observation('review_submitted', record)
        record.update(exact_tagged_card_status='قيد المراجعة', own_card_status_visually_verified=True)
        with self.assertRaises(c2.C2Blocked): x._review_observation('review_submitted', record)

    def test_regular_account_witness_uses_one_count_only_tap_and_bounded_scrolls(self):
        account = rows('الأمان والخصوصية', 'الملف الشخصي')
        account[0]['scrollable'] = True
        x = executor('regular_return_account', [], role='regular')
        x.probe = AccountProbe([account]*4 + [rows('تسجيل الخروج')])
        x.regular_cycle, x.regular_account_witness = 1, None
        x._execute('regular_return_account', True)
        self.assertEqual(x.probe.inputs, [('tap', 'حسابي', False)])
        self.assertEqual(len(x.probe.scrolls), 4)
        self.assertEqual(x.probe.auth_during_inputs, [False]*5)
        self.assertEqual(x.probe.private_hashes, [])
        self.assertTrue(x.probe.authenticated)
        self.assertEqual(x.probe.active_native_role, 'regular')
        self.assertTrue(x.regular_account_witness['no_account_frame_or_hash_recorded'])

    def test_regular_account_timeout_restores_tracking_without_witness_or_hashes(self):
        account = rows('الأمان والخصوصية', 'الملف الشخصي')
        account[0]['scrollable'] = True
        x = executor('regular_return_account', [], role='regular')
        x.probe = AccountProbe([account])
        x.regular_cycle, x.regular_account_witness = 1, None
        with self.assertRaises(c2.C2Blocked): x._execute('regular_return_account', True)
        self.assertEqual(x.probe.inputs, [('tap', 'حسابي', False)])
        self.assertEqual(len(x.probe.scrolls), 4)
        self.assertEqual(x.probe.private_hashes, [])
        self.assertTrue(x.probe.authenticated)
        self.assertIsNone(x.regular_account_witness)
        self.assertNotIn('c2_v2_regular_nonimage_role_witness', x.probe.report)

    def test_previous_card_control_above_title_cannot_end_reveal(self):
        x = executor('open_my_listings', [rows('عقاراتي', 'إرسال للمراجعة', TITLE),
            rows('عقاراتي', TITLE, 'إرسال للمراجعة')])
        x._reveal_own_listing_fields()
        self.assertEqual(x.probe.scrolls, [('forward', True)])
        title = 'تحقق نشر إعلان: ' + TITLE
        x = executor('support_inbox', [rows('الوارد', 'تحقيق إعلانات', 'استلام', title),
            rows('الوارد', 'تحقيق إعلانات', title, 'استلام')], role='support')
        x._reveal_support_card_fields()
        self.assertEqual(x.probe.scrolls, [('forward', True)])

    def test_cleanup_receipt_survives_later_api_logout_failure(self):
        x = executor('cleanup', [])
        x.state, x.cleanup_helper, x.last_receipt = {}, None, None
        x.probe.fixture_possible, x.probe.auth_attempted = True, True
        saved = []
        x.probe.save = lambda: saved.append(copy.deepcopy(x.probe.report))
        receipt = {'status': 'PASS', 'known_application_rows_removed': True,
                   'protected_baseline_restored': True}
        helper = Mock()
        helper.pin_candidate.return_value = {'status': 'READY', 'property_id': x.property_id}
        helper.cleanup.return_value = receipt
        def late_failure(work):
            work(Mock())
            raise c2.C2Blocked('synthetic_api_logout_failure')
        x._api = late_failure
        with patch.object(c2.cleanup_module, 'PromotedFixtureCleanup', return_value=helper):
            with self.assertRaises(c2.C2Blocked): x._execute('cleanup', True)
        helper.cleanup.assert_called_once_with(native_writers_stopped=True)
        self.assertEqual(x.probe.report['c2_promoted_cleanup'], receipt)
        self.assertIsNot(x.probe.report['c2_promoted_cleanup'], receipt)
        self.assertTrue(any(item.get('c2_promoted_cleanup') == receipt for item in saved))
        self.assertIs(x.cleanup_helper, helper)
        self.assertTrue(x.probe.fixture_possible)


if __name__ == '__main__': unittest.main()
