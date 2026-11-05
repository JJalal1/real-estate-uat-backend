"""Synthetic C2-only setup contracts; no native acceptance is produced."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, call

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('_c2_entry_executor',
    HERE / 'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
c2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c2)

KEY = '10000000-0000-4000-8000-000000000001'
TAG = 'AQER-C1-123456789abc'
TITLE = 'اختبار استعادة المسودة ' + TAG
TITLE_SHA = 'a' * 64
PHOTO_SHA = 'b' * 64


def rows(*labels):
    return [{'text': label, 'description': '', 'hint': '', 'path': str(i),
             'witness': 'c' * 64, 'enabled': True, 'visible': True,
             'clickable': True, 'class': 'android.widget.Button',
             'package': c2.roles.APP} for i, label in enumerate(labels)]


class Probe:
    def __init__(self):
        self.authenticated = True
        self.active_native_role = 'broker'
        self.native_auth_uncertain = False
        self.recorder = None
        self.report = {}
        self.private_values = set()
        self.events = []
        self.surface = rows('خيارات المسودة', 'إرسال للمراجعة', 'السابق')

    def nodes(self): return self.surface
    def _capture_full_rows(self): return self.surface
    def _capture_rows_private(self, value): return False
    def field(self, label): return {'text': ''}
    def require_value(self, label, value): self.events.append(('require', label, value))
    def tap(self, label): self.events.append(('tap', label))
    def wait(self, label, **kwargs): self.events.append(('wait', label))
    def save(self): pass


class C2EntryTests(unittest.TestCase):
    def setUp(self):
        self.probe = Probe()
        self.state = {'key': KEY, 'tag': TAG, 'actor_id': 28,
                      'creation_request_sent': True, 'created_confirmed': True,
                      'baseline': {'properties': {str(i): 'd' * 64 for i in range(1, 26)},
                                   'drafts': {'draft-' + str(i): 'e' * 64 for i in range(7)}}}
        self.c1 = {'manual_review_completed': True, 'c1_accepted': True,
                   'fixture_key': KEY, 'fixture_tag': TAG, 'native_title': TITLE,
                   'restored_frame_sha256': TITLE_SHA, 'monthly_rent_still_blank': True}
        self.entry = {'kind': 'ROOT_ACTUAL_FRAME_REVIEW', 'phase': 'C2',
            'privacy_checked': True, 'manual_review_completed': True,
            'fixture_key': KEY, 'fixture_tag': TAG, 'restored_title': TITLE,
            'monthly_rent_still_blank': True, 'property_id': None,
            'same_unpromoted_uuid_verified': True, 'restored_editor_step': 0,
            'restored_frame_sha256': TITLE_SHA, 'restored_photo_frame_sha256': PHOTO_SHA,
            'entry_mode': 'standard_editor', 'current_fixture_visually_verified': True,
            'review_completed_utc': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}

    def executor(self, **changes):
        entry = dict(self.entry, **changes)
        return c2.C2Executor(self.probe, self.state, self.c1, None, entry_review=entry)

    def test_c1_only_configuration_does_no_input_or_ai_and_binds_current_title(self):
        executor = self.executor()
        self.assertEqual(executor.entry_mode, 'standard_editor')
        self.assertIsNone(executor.c4)
        self.assertEqual(executor.fixture_title_frame,
                         {'file': 'C1-restored-title.png', 'sha256': TITLE_SHA})
        self.assertEqual(self.probe.events, [])
        self.assertNotIn('local_c4_executor', self.probe.report)
        self.assertFalse(executor._receipt('CONFIGURED')['phase1_accepted'])

    def test_entry_rejects_foreign_fixture_stale_review_promoted_uuid_or_fake_c4(self):
        variants = [dict(fixture_key='20000000-0000-4000-8000-000000000001'),
            dict(fixture_tag='AQER-C1-ffffffffffff'), dict(restored_title='other'),
            dict(property_id=50), dict(restored_editor_step=True), dict(restored_editor_step=1),
            dict(restored_frame_sha256='f' * 64), dict(restored_photo_frame_sha256=''),
            dict(current_fixture_visually_verified=False), dict(entry_mode='completed_review'),
            dict(c4_accepted=True), dict(monthly_rent_still_blank=False),
            dict(review_completed_utc=(datetime.now(timezone.utc)-timedelta(minutes=3)).strftime('%Y-%m-%dT%H:%M:%SZ'))]
        for change in variants:
            with self.subTest(change=change), self.assertRaises(c2.C2Blocked):
                self.executor(**change)
        with self.assertRaises(c2.C2Blocked):
            c2.C2Executor(self.probe, self.state, self.c1, {'c4_accepted': True}, entry_review=self.entry)
        self.assertEqual(self.probe.events, [])

    def test_standard_open_rent_uses_real_three_next_actions_and_requires_standard_footer(self):
        executor = self.executor()
        executor._execute('open_rent', True)
        self.assertEqual([e for e in self.probe.events if e[0] == 'tap'], [('tap', 'التالي')] * 3)
        self.probe.surface = rows('العودة إلى النواقص', 'السابق')
        with self.assertRaisesRegex(c2.C2Blocked, 'standard_editor'):
            executor._rent_editor_surface()

    def test_photo_review_binds_actual_c1_title_and_rejects_fabricated_c4_binding(self):
        executor = self.executor()
        self.probe.surface = rows('المواصفات', 'صور الإعلان (1/12)', 'مكتمل')
        executor.rent_sai_readback = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW'}
        review = {'evidence_kind': 'SAFE_SPEC_PHOTO_PLUS_NONIMAGE_POLICY_AND_SERIALIZED_IDENTITY',
            'same_serialized_editor_chain_reviewed': True, 'editor_chain': executor.editor_chain,
            'original_fixture_receipt_reviewed': True,
            'bound_fixture_title_frame': copy.deepcopy(executor.fixture_title_frame),
            'photo_visually_unchanged': True, 'actual_safe_spec_photo_reviewed': True,
            'semantic_preview': copy.deepcopy(executor.rent_sai_readback),
            'policy_was_visually_reviewed': False}
        executor._review_observation('review_photo_before_save', review)
        for changed in [dict(review, bound_c4_title_frame=executor.fixture_title_frame),
                        dict(review, bound_fixture_title_frame={'file': 'C1-c4-restored-final-title.png', 'sha256': TITLE_SHA})]:
            with self.assertRaises(c2.C2Blocked):
                executor._review_observation('review_photo_before_save', changed)

    def test_scrolled_photo_scene_preserves_specs_review_and_real_next_navigation(self):
        executor = self.executor()
        self.probe.surface = rows('3/4', 'صور الإعلان (1/12)', 'مكتمل', 'إضافة صور', 'السابق', 'التالي')
        self.assertNotIn('المواصفات', c2._names(self.probe.surface))
        executor._safe_specs()
        preview = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'rent_text': '50000', 'sai_rate_text': '0'}
        executor.rent_sai_readback = preview
        record = {'evidence_kind': 'SAFE_SPEC_PHOTO_PLUS_NONIMAGE_POLICY_AND_SERIALIZED_IDENTITY',
            'same_serialized_editor_chain_reviewed': True, 'editor_chain': executor.editor_chain,
            'original_fixture_receipt_reviewed': True, 'bound_fixture_title_frame': executor.fixture_title_frame,
            'photo_visually_unchanged': True, 'actual_safe_spec_photo_reviewed': True,
            'semantic_preview': preview, 'policy_was_visually_reviewed': False}
        executor._review_observation('review_photo_before_save', record)
        self.assertEqual(self.probe.events, [])
        executor._rent_sai_preview = Mock(return_value=preview)
        def next_step(label):
            self.assertEqual(label, 'التالي')
            self.probe.surface = rows('4/4', 'خيارات المسودة', 'إرسال للمراجعة', 'السابق')
        self.probe.tap = Mock(side_effect=next_step)
        executor._execute('return_next_step3', True)
        self.probe.tap.assert_called_once_with('التالي')
        self.assertEqual(executor.rent_sai_recheck, preview)

    def test_scrolled_specs_refuses_missing_wrong_hidden_foreign_or_private_context(self):
        executor = self.executor()
        required = ('3/4', 'صور الإعلان (1/12)', 'مكتمل', 'إضافة صور', 'السابق', 'التالي')
        for missing in required:
            with self.subTest(missing=missing):
                self.probe.surface = rows(*(label for label in required if label != missing))
                with self.assertRaisesRegex(c2.C2Blocked, 'actual_specification_step_required'):
                    executor._safe_specs()
        for extra in ('العودة إلى النواقص', 'رمز التحقق'):
            self.probe.surface = rows(*required, extra)
            with self.assertRaises(c2.C2Blocked): executor._safe_specs()
        for changed in ({'visible': False}, {'enabled': False}, {'package': 'foreign.app'}):
            self.probe.surface = rows(*required)
            self.probe.surface[2].update(changed)
            with self.assertRaises(c2.C2Blocked): executor._safe_specs()
        self.probe.surface = rows(*required, 'رمز التحقق')
        self.probe.surface[-1]['visible'] = False
        with self.assertRaisesRegex(c2.C2Blocked, 'safe_specs_auth_surface_refused'):
            executor._safe_specs()
        self.probe.surface = rows(*required)
        self.probe._capture_rows_private = Mock(return_value=True)
        with self.assertRaisesRegex(c2.C2Blocked, 'safe_specs_full_tree_privacy_required'):
            executor._safe_specs()

    def test_legacy_scrolled_specs_requires_its_actual_completed_review_footer(self):
        executor = self.executor()
        executor.entry_mode = 'completed_review'
        self.probe.surface = rows('3/4', 'صور الإعلان (1/12)', 'مكتمل', 'إضافة صور', 'السابق', 'التالي')
        with self.assertRaises(c2.C2Blocked): executor._safe_specs()
        self.probe.surface += rows('العودة إلى النواقص')
        executor._safe_specs()

    def test_pending_prepare_has_fresh_fixed_proof_and_never_executes(self):
        executor = self.executor()
        executor.cursor = c2.STAGES.index('review_photo_before_save')
        executor._prepare = Mock(side_effect=c2.C2Blocked('actual_specification_step_required'))
        executor._execute = Mock()
        first = executor.advance()
        self.assertEqual(first['pending_preparation'], {
            'attempt': 1, 'stage': 'review_photo_before_save', 'cursor': 4,
            'preparation_only': True, 'execution_called': False, 'reservation_created': False,
            'failed': False, 'inflight': False, 'reason': 'actual_specification_step_required'})
        self.assertEqual(first['pending_preparation'], executor.pending_preparation)
        self.assertIsNot(first['pending_preparation'], executor.pending_preparation)
        executor._prepare = Mock(return_value=None)
        second = executor.advance()
        self.assertEqual(second['pending_preparation']['attempt'], 2)
        self.assertEqual(second['pending_preparation']['reason'], 'root_review_not_validated')
        self.assertEqual(executor.cursor, 4)
        self.assertFalse(executor.failed or executor.inflight)
        executor._execute.assert_not_called()
        executor._prepare = Mock(return_value=True)
        third = executor.advance()
        self.assertEqual(third['status'], 'STAGE_COMPLETED')
        self.assertNotIn('pending_preparation', third)
        self.assertIsNone(executor.pending_preparation)
        self.assertEqual(executor.preparation_attempt, 3)
        executor._execute.assert_called_once()

    def test_prepare_exception_diagnostic_is_constant_and_targets_are_not_resumable(self):
        executor = self.executor()
        executor.cursor = c2.STAGES.index('review_photo_before_save')
        executor._execute = Mock()
        for error in (ValueError('PRIVATE_VALUE 777888999'), c2.C2Blocked('PRIVATE_TOKEN')):
            executor._prepare = Mock(side_effect=error)
            receipt = executor.advance()
            self.assertEqual(receipt['pending_preparation']['reason'], 'preparation_exception_unclassified')
            self.assertNotIn('PRIVATE', json.dumps(receipt))
            self.assertNotIn('777888999', json.dumps(receipt))
        executor.cursor = c2.STAGES.index('submit_confirm')
        executor._prepare = Mock(return_value=None)
        receipt = executor.advance()
        self.assertFalse(receipt['pending_preparation']['preparation_only'])
        executor._execute.assert_not_called()

    def test_execution_failure_never_gets_resumable_prepare_proof(self):
        executor = self.executor()
        executor.cursor = c2.STAGES.index('review_photo_before_save')
        executor._prepare = Mock(return_value=True)
        executor._execute = Mock(side_effect=ValueError('PRIVATE_VALUE'))
        with self.assertRaisesRegex(c2.C2Blocked, 'c2_stage_uncertain_root_readback_required'):
            executor.advance()
        self.assertTrue(executor.failed)
        self.assertIsNone(executor.pending_preparation)
        self.assertNotIn('PRIVATE_VALUE', json.dumps(self.probe.report))
        with self.assertRaisesRegex(c2.C2Blocked, 'c2_uncertain_stage_no_replay'):
            executor.advance()
        executor._execute.assert_called_once()

    def test_standard_completion_stage_never_invents_a_back_gaps_click_and_save_remains_native(self):
        executor = self.executor()
        preview = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'rent_text': '50000', 'sai_rate_text': '0'}
        executor.rent_sai_readback = executor.rent_sai_recheck = preview
        executor._rent_sai_preview = Mock(return_value=preview)
        executor._nonimage_input = Mock()
        executor._execute('back_gaps_to_completion', True)
        executor._nonimage_input.assert_not_called()
        self.assertEqual(self.probe.report['c2_v2_completion_transition'], {
            'entry_mode': 'standard_editor', 'native_input_delivered': False,
            'outcome': 'not_required_standard_editor_save_surface_observed'})
        executor._execute('full_save', True)
        self.assertEqual(executor._nonimage_input.call_args_list,
                         [call('click', 'خيارات المسودة'), call('click', 'حفظ مسودة')])
        self.assertIn(('wait', 'عقاراتي'), self.probe.events)

    def test_legacy_c4_entry_still_requires_its_actual_review_and_completion_navigation(self):
        legacy = {'manual_review_completed': True, 'c4_accepted': True,
            'fixture_key': KEY, 'fixture_tag': TAG, 'restored_title': TITLE,
            'monthly_rent_still_blank': True, 'property_id': None,
            'same_unpromoted_uuid_verified': True, 'restored_editor_step': 0,
            'restored_frame_sha256': 'f' * 64}
        executor = c2.C2Executor(self.probe, self.state, self.c1, legacy)
        self.assertEqual(executor.entry_mode, 'completed_review')
        self.probe.surface = rows('العودة إلى النواقص', 'السابق')
        self.assertTrue(executor._rent_editor_surface())
        executor.rent_sai_readback = executor.rent_sai_recheck = {'rent_text': '50000'}
        executor._rent_sai_preview = Mock(return_value=executor.rent_sai_readback)
        executor._nonimage_input = Mock()
        executor._execute('back_gaps_to_completion', True)
        executor._nonimage_input.assert_called_once_with('click', 'العودة إلى النواقص')

    def preview_executor(self, rent='50000', rate='0', extra=()):
        executor = self.executor()
        executor.cursor = c2.STAGES.index('complete_rent')
        values = {'الإيجار الشهري بالريال اليمني *': rent, 'نسبة السعي %': rate}
        self.probe.field = Mock(side_effect=lambda label: {'text': values[label]})
        self.probe.surface = rows('خيارات المسودة', 'إرسال للمراجعة', 'السابق',
                                  'اختيار 0% يفعّل السعي الثابت 5% تلقائيًا.', *extra)
        return executor

    def dismissal_row(self, **changes):
        # Flutter ModalBarrier: standalone Arabic dismiss label, generic View,
        # onTap/onDismiss actions; it is clickable but has no button semantics.
        return dict(text='', description='رفض', hint='', path='0.1',
                    package=c2.roles.APP, visible=True, enabled=True,
                    editable=False, clickable=True, focused=False,
                    actions=16 | 1048576, **changes)

    def test_editor_route_dismissal_is_not_a_custom_sai_decision(self):
        executor = self.preview_executor()
        dismissal = self.dismissal_row()
        dismissal['class'] = 'android.view.View'
        self.probe.surface.append(dismissal)
        result = executor._rent_sai_preview()
        self.assertEqual((result['rent_text'], result['sai_rate_text']), ('50000', '0'))
        self.assertFalse(result['custom_terms_visible'])
        diagnostic = self.probe.report['c2_v2_rent_sai_readback_diagnostic']
        self.assertFalse(diagnostic['accept_reject_absent'])
        self.assertTrue(diagnostic['route_dismissal_only'])
        self.assertTrue(diagnostic['custom_sai_sheet_absent'])
        self.assertEqual(self.probe.events, [])

    def test_editor_dismissal_exception_rejects_decision_nodes_and_combined_labels(self):
        for change in ({'class': 'android.widget.Button'},
                       {'class': 'android.widget.EditText', 'editable': True},
                       {'class': 'android.view.View', 'editable': True},
                       {'class': 'android.view.View', 'editable': None},
                       {'class': 'android.view.View', 'description': 'رفض\nPRIVATE_CONTACT'},
                       {'class': 'android.view.View', 'text': 'PRIVATE_PARENT'},
                       {'class': 'unknown'},
                       {'class': 'android.view.View', 'package': 'foreign.app'},
                       {'class': 'android.view.View', 'visible': False}):
            with self.subTest(change=change):
                executor = self.preview_executor()
                dismissal = self.dismissal_row()
                dismissal.update(change)
                self.probe.surface.append(dismissal)
                with self.assertRaisesRegex(c2.C2Blocked, 'actual_synthetic_rent_and_sai_zero_text_required'):
                    executor._rent_sai_preview()
                diagnostic = self.probe.report['c2_v2_rent_sai_readback_diagnostic']
                self.assertFalse(diagnostic['route_dismissal_only'])
                self.assertNotIn('PRIVATE', json.dumps(self.probe.report))

    def test_editor_dismissal_never_admits_acceptance_auth_or_submission_sheet(self):
        for label in ('قبول', 'رمز التحقق', 'تحديد السعي قبل إرسال الإعلان',
                      'إرسال الإعلان للمراجعة؟', 'العودة بدون إرسال', 'تأكيد السعي والمتابعة'):
            with self.subTest(label=label):
                executor = self.preview_executor(extra=(label,))
                dismissal = self.dismissal_row()
                dismissal['class'] = 'android.view.View'
                self.probe.surface.append(dismissal)
                with self.assertRaisesRegex(c2.C2Blocked, 'actual_synthetic_rent_and_sai_zero_text_required'):
                    executor._rent_sai_preview()
                self.assertEqual(self.probe.events, [])

    def test_editor_dismissal_requires_actual_declared_editor_footer(self):
        for missing in ('خيارات المسودة', 'إرسال للمراجعة', 'السابق'):
            with self.subTest(missing=missing):
                executor = self.preview_executor()
                self.probe.surface = [row for row in self.probe.surface if row['text'] != missing]
                dismissal = self.dismissal_row()
                dismissal['class'] = 'android.view.View'
                self.probe.surface.append(dismissal)
                with self.assertRaisesRegex(c2.C2Blocked, 'actual_standard_editor_step4_required'):
                    executor._rent_sai_preview()
        executor = self.preview_executor()
        executor.entry_mode = 'completed_review'
        with self.assertRaisesRegex(c2.C2Blocked, 'actual_completed_review_editor_required'):
            executor._rent_sai_preview()

    def test_submit_fallback_keeps_its_separate_acceptance_protection(self):
        for label in ('قبول', 'رفض'):
            with self.subTest(label=label):
                executor = self.preview_executor(extra=(label,))
                with self.assertRaisesRegex(c2.C2Blocked, 'only_existing_platform_fallback_sai_allowed'):
                    executor._fallback(self.probe.surface)
        self.assertTrue(all(target[1] not in {'قبول', 'رفض', 'قبول ونشر', 'رفض نهائي وحظر'}
                            for target in c2.TARGETS.values()))

    def test_preview_diagnostic_identifies_each_guard_without_weakening_it(self):
        cases = [('wrong', '0', (), 'rent_matches_expected'),
                 ('50000', '1', (), 'sai_rate_is_zero'),
                 ('50000', '0', ('رمز التحقق',), 'auth_surface_absent'),
                 ('50000', '0', ('قبول',), 'accept_reject_absent'),
                 ('50000', '0', ('رفض',), 'accept_reject_absent')]
        guard_keys = {'rent_matches_expected', 'sai_rate_is_zero',
                      'auth_surface_absent', 'accept_reject_absent'}
        for rent, rate, extra, failed in cases:
            with self.subTest(failed=failed, extra=extra):
                executor = self.preview_executor(rent, rate, extra)
                with self.assertRaisesRegex(c2.C2Blocked, '^actual_synthetic_rent_and_sai_zero_text_required$'):
                    executor._rent_sai_preview()
                diagnostic = self.probe.report['c2_v2_rent_sai_readback_diagnostic']
                self.assertEqual({key: diagnostic[key] for key in guard_keys},
                                 {key: key != failed for key in guard_keys})
                self.assertEqual(self.probe.field.call_count, 2)
                self.assertEqual(self.probe.events, [])

    def test_preview_shapes_are_fixed_diagnostics_and_do_not_accept_empty_or_formatted_values(self):
        cases = [('', '0', 'EMPTY', 'EXPECTED'),
                 ('50000', '', 'EXPECTED', 'EMPTY'),
                 ('50000', '0.0', 'EXPECTED', 'ZERO_DECIMAL'),
                 ('50000', '٠٫٠٠', 'EXPECTED', 'ZERO_DECIMAL'),
                 ('50,000', '0', 'GROUPED_EXPECTED', 'EXPECTED'),
                 ('٥٠٬٠٠٠', '0', 'GROUPED_EXPECTED', 'EXPECTED'),
                 ('50000', 'PRIVATE_VALUE', 'EXPECTED', 'OTHER')]
        for rent, rate, rent_shape, rate_shape in cases:
            with self.subTest(rent_shape=rent_shape, rate_shape=rate_shape):
                executor = self.preview_executor(rent, rate)
                with self.assertRaises(c2.C2Blocked):
                    executor._rent_sai_preview()
                diagnostic = self.probe.report['c2_v2_rent_sai_readback_diagnostic']
                self.assertEqual((diagnostic['rent_shape'], diagnostic['rate_shape']),
                                 (rent_shape, rate_shape))

    def test_preview_diagnostic_never_exports_arbitrary_values_contact_rows_or_hashes(self):
        executor = self.preview_executor('PRIVATE_RENT_777888999', 'PRIVATE_RATE',
                                         ('PRIVATE_CONTACT_777888999',))
        with self.assertRaises(c2.C2Blocked):
            executor._rent_sai_preview()
        diagnostic = self.probe.report['c2_v2_rent_sai_readback_diagnostic']
        self.assertEqual(set(diagnostic), {'stage', 'fixture_key', 'fixture_tag', 'editor_chain',
            'rent_matches_expected', 'sai_rate_is_zero', 'auth_surface_absent',
            'accept_reject_absent', 'route_dismissal_only', 'custom_sai_sheet_absent',
            'rent_shape', 'rate_shape'})
        encoded = json.dumps(self.probe.report)
        for private in ('PRIVATE', '777888999', 'witness', 'sha256', 'hint', 'bounds'):
            self.assertNotIn(private, encoded)
        self.assertEqual(diagnostic['rent_shape'], 'OTHER')
        self.assertEqual(diagnostic['rate_shape'], 'OTHER')

    def test_passing_preview_is_unchanged_and_records_only_current_readback_outcomes(self):
        executor = self.preview_executor()
        self.assertEqual(executor._rent_sai_preview(), {
            'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'fixture_key': KEY,
            'fixture_tag': TAG, 'editor_chain': executor.editor_chain,
            'rent_text': '50000', 'sai_rate_text': '0',
            'fallback_notice': 'اختيار 0% يفعّل السعي الثابت 5% تلقائيًا.',
            'recording_stopped': True, 'custom_terms_visible': False,
            'policy_was_visually_reviewed': False, 'persisted_policy_configuration_proved': False})
        self.assertEqual(self.probe.report['c2_v2_rent_sai_readback_diagnostic'], {
            'stage': 'complete_rent', 'fixture_key': KEY, 'fixture_tag': TAG,
            'editor_chain': executor.editor_chain, 'rent_matches_expected': True,
            'sai_rate_is_zero': True, 'auth_surface_absent': True,
            'accept_reject_absent': True, 'route_dismissal_only': True,
            'custom_sai_sheet_absent': True, 'rent_shape': 'EXPECTED', 'rate_shape': 'EXPECTED'})
        self.assertEqual(self.probe.field.call_count, 2)
        self.assertEqual(self.probe.events, [])


if __name__ == '__main__': unittest.main()
