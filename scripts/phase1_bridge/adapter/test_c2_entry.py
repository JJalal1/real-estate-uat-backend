"""Synthetic C2-only setup contracts; no native acceptance is produced."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, call, patch

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
CONTACT_PROOF = dict.fromkeys(('native_contact_readback_matches_fixture', 'contact_policy_valid',
                               'optional_contact_empty', 'contact_policy_observed_in_ui'), True)


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
        preview = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'rent_text': '50000', 'sai_rate_text': '0', **CONTACT_PROOF}
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
        preview = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW', 'rent_text': '50000', 'sai_rate_text': '0', **CONTACT_PROOF}
        executor.rent_sai_readback = executor.rent_sai_recheck = preview
        executor._rent_sai_preview = Mock(return_value=preview)
        executor._contact_readback = Mock(return_value=dict(CONTACT_PROOF))
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
        executor._nonimage_field = self.probe.field
        executor._contact_readback = Mock(return_value=dict(CONTACT_PROOF))
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
                executor.cursor = c2.STAGES.index('submit_confirm')
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
            'policy_was_visually_reviewed': False, 'persisted_policy_configuration_proved': False,
            **CONTACT_PROOF})
        self.assertEqual(self.probe.report['c2_v2_rent_sai_readback_diagnostic'], {
            'stage': 'complete_rent', 'fixture_key': KEY, 'fixture_tag': TAG,
            'editor_chain': executor.editor_chain, 'rent_matches_expected': True,
            'sai_rate_is_zero': True, 'auth_surface_absent': True,
            'accept_reject_absent': True, 'route_dismissal_only': True,
            'custom_sai_sheet_absent': True, 'rent_shape': 'EXPECTED', 'rate_shape': 'EXPECTED'})
        self.assertEqual(self.probe.field.call_count, 2)
        self.assertEqual(self.probe.events, [])

    def contact_executor(self, original='PRIVATE_INVALID_DEFAULT', alternate=''):
        executor = self.executor()
        values = {'رقم الاتصال *': original, 'رقم اتصال آخر (اختياري)': alternate}
        executor._nonimage_field = Mock(side_effect=lambda label: {'text': values[label]})
        def native(kind, label, value=None):
            if kind == 'set': values[label] = value
        executor._nonimage_input = Mock(side_effect=native)
        self.probe.surface += rows('أدخل رقم جوال يمني من 9 أرقام يبدأ بـ 70، 71، 73، 77، 78.')
        return executor, values

    def test_contact_uses_actual_local_validation_policy_before_fixed_native_set(self):
        executor, values = self.contact_executor()
        policy_rows = list(self.probe.surface)
        self.probe.nodes = Mock(side_effect=[policy_rows, rows('معاينة'), policy_rows])
        executor._complete_fixture_contact()
        self.assertEqual(executor._nonimage_input.call_args_list, [
            call('click', 'خيارات المسودة'), call('click', 'معاينة'),
            call('set', 'رقم الاتصال *', executor.fixture_contact)])
        self.assertEqual(executor._contact_readback(), CONTACT_PROOF)
        self.assertIn(executor.fixture_contact, self.probe.private_values)
        self.assertEqual(executor.contact_policy_prefixes, frozenset(('70', '71', '73', '77', '78')))
        self.assertEqual(self.probe.report, {})

    def test_contact_readback_precedes_rent_sai_so_checkpoint_keeps_policy_viewport(self):
        executor = self.preview_executor()
        observed = []
        executor._contact_readback.side_effect = lambda: (observed.append('contact') or dict(CONTACT_PROOF))
        self.probe.field.side_effect = lambda label: (observed.append(label) or
            {'text': '50000' if label == 'الإيجار الشهري بالريال اليمني *' else '0'})
        result = executor._rent_sai_preview()
        self.assertEqual(observed, ['contact', 'الإيجار الشهري بالريال اليمني *', 'نسبة السعي %'])
        self.assertTrue(all(result[key] for key in CONTACT_PROOF))

    def test_contact_refuses_valid_default_nonempty_alternate_or_unapproved_prefix_before_set(self):
        for original, alternate in [('710000001', ''), ('PRIVATE_INVALID_DEFAULT', 'PRIVATE_ALTERNATE')]:
            executor, _ = self.contact_executor(original, alternate)
            with self.assertRaisesRegex(c2.C2Blocked, 'actual_invalid_default_contact'):
                executor._complete_fixture_contact()
            executor._nonimage_input.assert_not_called()
        for text in ('أدخل رقم جوال يمني من 9 أرقام يبدأ بـ 70، 71.',
                     'أدخل رقم جوال يمني من 9 أرقام يبدأ بـ 77، 77.'):
            executor, _ = self.contact_executor()
            self.probe.surface = rows('خيارات المسودة', 'إرسال للمراجعة', 'السابق', text)
            with self.assertRaisesRegex(c2.C2Blocked, 'fixture_contact_prefix_not_in_loaded_policy'):
                executor._complete_fixture_contact()
            self.assertEqual(executor._nonimage_input.call_count, 2)
            self.assertIsNone(executor.contact_policy_prefixes)
        executor, _ = self.contact_executor()
        self.probe.surface += rows('أدخل رقم جوال يمني من 9 أرقام يبدأ بـ 77.')
        with self.assertRaisesRegex(c2.C2Blocked, 'unique_loaded_contact_policy_required'):
            executor._complete_fixture_contact()

    def test_contact_readback_rejects_any_drift_without_exporting_values(self):
        for phone, alternate, prefixes in [('PRIVATE_CONTACT', '', frozenset({'77'})),
             ('770000028', 'PRIVATE_ALTERNATE', frozenset({'77'})),
             ('770000028', '', None), ('770000028', '', frozenset({'71'})),
             ('٧٧٠٠٠٠٠٢٨', '', frozenset({'77'}))]:
            executor, _ = self.contact_executor(phone, alternate)
            executor.contact_policy_prefixes = prefixes
            with self.assertRaises(c2.C2Blocked): executor._contact_readback()
            self.assertEqual(self.probe.report, {})
            executor._nonimage_input.assert_not_called()
        self.assertEqual(c2.C2Executor._normalize_contact(' (+967) ٧٧٠-٠٠٠-٠٢٨ '), '770000028')

    def test_contact_native_delivery_is_count_only_and_policy_gated(self):
        executor = self.executor()
        executor._nonimage_field = Mock(return_value={'path': '0.5', 'witness': 'f'*64})
        self.probe.instrument = Mock(return_value={'account_action_delivered': 'true',
            'set_text_delivered': 'true', 'semantic_action_used': 'true'})
        self.probe.adb = Mock()
        with self.assertRaisesRegex(c2.C2Blocked, 'observed_listing_contact_policy_required'):
            executor._nonimage_input('set', 'رقم الاتصال *', executor.fixture_contact)
        self.probe.instrument.assert_not_called()
        executor.contact_policy_prefixes = frozenset({'77'})
        executor._nonimage_input('set', 'رقم الاتصال *', executor.fixture_contact)
        self.assertEqual(self.probe.report, {'c2_v2_nonimage_input_operations_delivered': 1})
        self.probe.adb.assert_called_once_with('shell', 'input', 'keyevent', '4')
        self.assertNotIn(executor.fixture_contact, json.dumps(self.probe.report))

    def test_nonimage_seeking_uses_actual_scroll_receiver_without_persisted_hash(self):
        executor = self.executor()
        scroll = dict(path='0.1', witness='f'*64, package=c2.roles.APP, visible=True,
                      enabled=True, scrollable=True, bounds=[0, 100, 600, 900])
        field = dict(path='0.2', witness='e'*64, package=c2.roles.APP, visible=True,
                     enabled=True, editable=True, text='PRIVATE_CONTACT', hint='رقم الاتصال *')
        self.probe.nodes = Mock(side_effect=[[scroll], [scroll, field]])
        self.probe.matching = lambda value, label: [r for r in value if label in c2.policy.names(r)]
        self.probe.field = Mock(return_value=field)
        self.probe.instrument = Mock(return_value={'account_action_delivered': 'true',
                                                 'semantic_action_used': 'true'})
        self.assertIs(executor._nonimage_field('رقم الاتصال *'), field)
        self.probe.instrument.assert_called_once_with('account-scroll', node_path='0.1',
                                                      node_witness='f'*64, direction='forward')
        self.probe.field.assert_called_once_with('رقم الاتصال *', seek=False)
        self.assertEqual(self.probe.report, {'c2_v2_nonimage_input_operations_delivered': 1})
        for raw in ('PRIVATE', 'witness', 'f'*64, '0.1', 'bounds'):
            self.assertNotIn(raw, json.dumps(self.probe.report))

    def test_final_save_requires_fresh_valid_contact_and_reviewed_boolean_proof(self):
        executor, values = self.contact_executor('770000028')
        executor.contact_policy_prefixes = frozenset({'77'})
        executor.rent_sai_readback = executor.rent_sai_recheck = dict(CONTACT_PROOF)
        values['رقم اتصال آخر (اختياري)'] = 'PRIVATE_DRIFT'
        with self.assertRaisesRegex(c2.C2Blocked, 'actual_valid_fixture_contact_required'):
            executor._execute('full_save', True)
        executor._nonimage_input.assert_not_called()
        values['رقم اتصال آخر (اختياري)'] = ''
        executor.rent_sai_readback.pop('contact_policy_observed_in_ui')
        with self.assertRaisesRegex(c2.C2Blocked, 'reviewed_contact_changed_before_explicit_save'):
            executor._execute('full_save', True)
        executor._nonimage_input.assert_not_called()


class C2LoginLaunchTests(unittest.TestCase):
    def setUp(self):
        fixture = C2EntryTests()
        fixture.setUp()
        self.executor, self.probe = fixture.executor(), fixture.probe
        self.probe.authenticated, self.probe.active_native_role = False, None
        self.probe.native_auth_uncertain, self.probe.adapter = False, None
        self.probe.adb, self.probe.startup = Mock(), Mock()
        patcher = patch.object(c2.roles, 'native_login_role',
            return_value={'status': 'PASS_WITHIN_AUTH_UI_SCOPE'})
        self.login = patcher.start(); self.addCleanup(patcher.stop)
        self.order = Mock()
        for name, mocked in [('force_stop', self.probe.adb), ('startup', self.probe.startup), ('login', self.login)]:
            self.order.attach_mock(mocked, name)

    def test_closed_admission_establishes_cold_launch_before_all_four_login_stages(self):
        for stage, role in [('broker_login_for_submit', 'broker'), ('support_login', 'support'),
                            ('broker_login_for_reason', 'broker'), ('regular_login', 'regular')]:
            with self.subTest(stage=stage):
                self.order.reset_mock()
                self.executor._execute(stage, True)
                self.assertEqual(self.order.mock_calls, [
                    call.force_stop('shell', 'am', 'force-stop', c2.roles.APP),
                    call.startup(), call.login(self.probe, role)])
        self.assertEqual(self.executor.regular_cycle, 1)

    def test_live_admission_keeps_existing_app_and_uses_normal_role_login(self):
        self.probe.adapter = object()
        self.executor._login('support')
        self.assertEqual(self.order.mock_calls, [call.login(self.probe, 'support')])

    def test_non_guest_or_uncertain_actor_is_refused_before_any_launch_or_login(self):
        for change in ({'authenticated': True}, {'active_native_role': 'broker'},
                       {'native_auth_uncertain': True}, {'recorder': object()}):
            with self.subTest(change=change):
                originals = {key: getattr(self.probe, key) for key in change}
                for key, value in change.items(): setattr(self.probe, key, value)
                with self.assertRaisesRegex(c2.C2Blocked, 'normal_native_guest'):
                    self.executor._login('support')
                for key, value in originals.items(): setattr(self.probe, key, value)
        self.assertEqual(self.order.mock_calls, [])

    def test_startup_failure_does_not_enter_role_login_or_repeat_launch(self):
        self.probe.startup.side_effect = RuntimeError('synthetic startup failure')
        with self.assertRaises(RuntimeError): self.executor._login('support')
        self.assertEqual(self.order.mock_calls, [
            call.force_stop('shell', 'am', 'force-stop', c2.roles.APP), call.startup()])
        self.login.assert_not_called()


class SaiSheetFallbackTests(unittest.TestCase):
    def setUp(self):
        fixture = C2EntryTests()
        fixture.setUp()
        self.executor, self.probe = fixture.executor(), fixture.probe
        self.executor.cursor = c2.STAGES.index('submit_sai_setup')
        self.executor.inflight = True
        self.clock = 0
        for name, fn in [('monotonic', lambda: self.clock), ('sleep', self.sleep)]:
            patcher = patch.object(c2.time, name, fn)
            patcher.start(); self.addCleanup(patcher.stop)
        for name in ('field', 'seek', 'scroll', 'act', 'instrument'):
            setattr(self.probe, name, Mock(side_effect=AssertionError('fallback must only observe')))

    def sleep(self, seconds): self.clock += seconds

    def sheet(self, *, value='0', dismissal=True, notice='اختيار 0% يفعّل السعي الثابت 20% تلقائيًا.'):
        result = rows('تحديد السعي قبل إرسال الإعلان', 'نسبة مئوية %', 'نسبة السعي %',
                      'العودة بدون إرسال', 'تأكيد السعي والمتابعة')
        for i, row in enumerate(result):
            row.update(path='0.' + str(i+1), bounds=[20, 100+i*60, 370, 150+i*60], editable=False)
        result[2].update(text=value, description='نسبة السعي %', hint='0', editable=True,
                         **{'class': 'android.widget.EditText'})
        if notice is not None:
            result += rows(notice)
            result[-1].update(path='0.8', editable=False)
        if dismissal:
            result.append(dict(text='', description='رفض', hint='', path='0.9',
                package=c2.roles.APP, visible=True, enabled=True, editable=False,
                clickable=True, witness='d'*64, bounds=[180, 40, 228, 88],
                **{'class': 'android.view.View'}))
        return result

    def test_real_zero_fallback_allows_only_source_drag_handle_in_setup_and_confirmation(self):
        for stage, inflight in [('submit_sai_setup', True), ('submit_confirm', False), ('submit_confirm', True)]:
            for dismissal in (False, True):
                with self.subTest(stage=stage, inflight=inflight, dismissal=dismissal):
                    self.executor.cursor, self.executor.inflight = c2.STAGES.index(stage), inflight
                    self.executor._fallback(self.sheet(dismissal=dismissal))
                    d = self.probe.report['c2_v2_sai_sheet_fallback_diagnostic']
                    self.assertEqual((d['state'], d['rate_shape'], d['visible_anchor_count']), ('READY', 'ZERO', 5))
                    self.assertEqual(d['source_dismissal_count'], int(dismissal))
                    self.assertFalse(d['hashes_recorded'])
        self.probe.field.assert_not_called(); self.probe.seek.assert_not_called()
        self.probe.act.assert_not_called(); self.probe.instrument.assert_not_called()

    def test_arabic_zero_is_actual_text_not_only_the_hint(self):
        self.executor._fallback(self.sheet(value='٠'))
        for value in ('', '7', '0.0', 'PRIVATE_VALUE'):
            with self.subTest(value=value):
                self.probe.nodes = Mock(return_value=self.sheet(value=value))
                with self.assertRaisesRegex(c2.C2Blocked, 'fallback_not_ready'):
                    self.executor._fallback(self.sheet(value=value))
                self.assertNotEqual(self.probe.report['c2_v2_sai_sheet_fallback_diagnostic']['rate_shape'], 'ZERO')
                self.assertNotIn('PRIVATE_VALUE', json.dumps(self.probe.report))

    def test_real_custom_decisions_and_invalid_dismissal_shapes_refuse_without_waiting(self):
        for change in ({'class': 'android.widget.Button'}, {'editable': True}, {'editable': None},
                       {'class': 'android.widget.EditText'}, {'package': 'foreign.app'},
                       {'visible': False}, {'enabled': False}, {'description': 'رفض\nPRIVATE_LABEL'},
                       {'text': 'قبول'}, {'class': 'unknown'}):
            with self.subTest(change=change):
                observed = self.sheet(); observed[-1].update(change)
                with self.assertRaisesRegex(c2.C2Blocked, 'only_existing_platform_fallback'):
                    self.executor._fallback(observed, settle=True)
                self.assertEqual(self.clock, 0)
                self.assertNotIn('PRIVATE_LABEL', json.dumps(self.probe.report))
        for label in ('قبول', 'رفض'):
            with self.assertRaisesRegex(c2.C2Blocked, 'only_existing_platform_fallback'):
                self.executor._fallback(self.sheet(dismissal=False) + rows(label), settle=True)

    def test_multiple_dismissals_or_actual_fields_are_never_collapsed(self):
        observed = self.sheet()
        observed.append(dict(observed[-1], path='0.10'))
        with self.assertRaisesRegex(c2.C2Blocked, 'only_existing_platform_fallback'):
            self.executor._fallback(observed, settle=True)
        observed = self.sheet()
        observed.append(dict(observed[2], path='0.11'))
        with self.assertRaisesRegex(c2.C2Blocked, 'unique_actual_sai_sheet'):
            self.executor._fallback(observed, settle=True)
        self.assertEqual(self.clock, 0)

    def test_exact_numeric_notice_is_required_and_two_different_notices_are_ambiguous(self):
        for notice in (None, 'اختيار 0 يفعّل السعي الثابت 20% تلقائيًا.',
                       'اختيار 0% يفعّل السعي الثابت 20% تلقائيًا. PRIVATE_SUFFIX',
                       'اختيار 0% يفعّل السعي الثابت غير محدد% تلقائيًا.'):
            with self.subTest(notice=notice), self.assertRaisesRegex(c2.C2Blocked, 'fallback_not_ready'):
                self.executor._fallback(self.sheet(notice=notice))
        with self.assertRaisesRegex(c2.C2Blocked, 'unique_actual_sai_sheet'):
            self.executor._fallback(self.sheet() + rows('اختيار 0% يفعّل السعي الثابت 15% تلقائيًا.'))
        self.assertNotIn('PRIVATE_SUFFIX', json.dumps(self.probe.report))

    def test_all_five_real_sheet_anchors_are_required(self):
        for index in range(5):
            with self.subTest(index=index):
                observed = self.sheet(); observed.pop(index)
                with self.assertRaisesRegex(c2.C2Blocked, 'fallback_not_ready'):
                    self.executor._fallback(observed)
                self.assertEqual(self.probe.report['c2_v2_sai_sheet_fallback_diagnostic']['visible_anchor_count'], 4)

    def test_bounded_post_ime_settlement_only_reads_fresh_observations(self):
        before = self.sheet(notice=None)
        after = self.sheet()
        self.probe.nodes = Mock(side_effect=[before, after])
        self.executor._fallback(before, settle=True)
        self.assertEqual(self.clock, .5)
        self.assertEqual(self.probe.nodes.call_count, 2)
        self.assertEqual(self.probe.report['c2_v2_sai_sheet_fallback_diagnostic']['observations'], 3)
        self.probe.seek.assert_not_called(); self.probe.scroll.assert_not_called()
        self.probe.field.assert_not_called(); self.probe.act.assert_not_called()

    def test_missing_notice_expires_at_eight_seconds_without_input(self):
        observed = self.sheet(notice=None)
        self.probe.nodes = Mock(return_value=observed)
        with self.assertRaisesRegex(c2.C2Blocked, 'fallback_not_ready'):
            self.executor._fallback(observed, settle=True)
        self.assertEqual(self.clock, 8)
        self.probe.act.assert_not_called(); self.probe.instrument.assert_not_called()

    def test_separate_label_uses_same_snapshot_unique_editable_field(self):
        observed = self.sheet()
        observed[2].update(text='نسبة السعي %', description='', hint='', editable=False,
                           **{'class': 'android.widget.TextView'})
        observed.append(dict(observed[2], text='0', path='0.12', editable=True,
                             **{'class': 'android.widget.EditText'}))
        self.executor._fallback(observed)
        self.probe.field.assert_not_called(); self.probe.seek.assert_not_called()

    def test_stage17_is_one_readonly_validation_and_never_enters_settling(self):
        self.executor.cursor, self.executor.inflight = c2.STAGES.index('submit_confirm'), False
        self.probe.nodes = Mock(side_effect=AssertionError('already supplied fresh rows'))
        self.executor._fallback(self.sheet())
        with self.assertRaisesRegex(c2.C2Blocked, 'reserved_sai_sheet_context'):
            self.executor._fallback(self.sheet(), settle=True)
        with self.assertRaisesRegex(c2.C2Blocked, 'fallback_not_ready'):
            self.executor._fallback(self.sheet(notice=None))
        self.probe.nodes.assert_not_called(); self.assertEqual(self.clock, 0)

    def test_wrong_context_auth_or_actor_refuses_before_settlement(self):
        self.executor.inflight = False
        with self.assertRaisesRegex(c2.C2Blocked, 'reserved_sai_sheet_context'):
            self.executor._fallback(self.sheet())
        self.executor.inflight = True
        with self.assertRaisesRegex(c2.C2Blocked, 'auth_surface'):
            self.executor._fallback(self.sheet() + rows('رمز التحقق'), settle=True)
        self.probe.active_native_role = 'support'
        with self.assertRaisesRegex(c2.C2Blocked, 'known_normal_native_actor'):
            self.executor._fallback(self.sheet(), settle=True)
        self.assertEqual(self.clock, 0)

    def test_setup_input_is_not_repeated_while_notice_settles(self):
        self.probe.set = Mock()
        self.probe.nodes = Mock(side_effect=[self.sheet(notice=None), self.sheet()])
        self.executor._execute('submit_sai_setup', True)
        self.assertEqual([e for e in self.probe.events if e[0] == 'tap'], [('tap', 'نسبة مئوية %')])
        self.probe.set.assert_called_once_with('نسبة السعي %', '0')
        self.assertEqual(self.probe.nodes.call_count, 2)


class NonimageClickReadinessTests(unittest.TestCase):
    def setUp(self):
        fixture = C2EntryTests()
        fixture.setUp()
        self.executor, self.probe = fixture.executor(), fixture.probe
        self.executor.cursor = c2.STAGES.index('navigate_previous_to_specs')
        self.executor.inflight, self.executor.failed = True, False
        self.executor.rent_sai_readback = {'kind': 'NATIVE_NONIMAGE_RENT_SAI_PREVIEW'}
        self.probe.instrument = Mock(return_value={'account_action_delivered': 'true'})
        self.probe.act = Mock(side_effect=AssertionError('private hash ledger forbidden'))
        self.probe.scroll = Mock(side_effect=AssertionError('readiness is observation only'))
        self.clock = 0
        for name, fn in [('monotonic', lambda: self.clock), ('sleep', self.sleep)]:
            patcher = patch.object(c2.time, name, fn)
            patcher.start(); self.addCleanup(patcher.stop)

    def sleep(self, seconds): self.clock += seconds

    def node(self, label='السابق', path='0.4', **changes):
        return dict(rows(label)[0], **{'path': path, 'bounds': [20, 600, 170, 650], **changes})

    def surface(self, *controls):
        return rows('خيارات المسودة', 'إرسال للمراجعة') + list(controls)

    def snapshots(self, *observations):
        pending = iter(observations)
        last = observations[-1]
        self.probe.nodes = Mock(side_effect=lambda: next(pending, last))

    def click(self): self.executor._nonimage_input('click', 'السابق')

    def test_ready_named_button_delivers_once_without_private_hashes(self):
        self.snapshots(self.surface(self.node(clickable=False)))
        self.click()
        self.probe.instrument.assert_called_once_with('account-click', node_path='0.4', node_witness='c'*64)
        self.assertEqual(self.probe.report['c2_v2_nonimage_click_readiness']['previous']['state'], 'direct_ready')
        self.assertEqual(self.probe.report['c2_v2_nonimage_input_operations_delivered'], 1)
        self.probe.act.assert_not_called(); self.probe.scroll.assert_not_called()

    def test_absent_then_disabled_then_nested_label_waits_before_one_click(self):
        leaf = self.node(path='0.4.1', clickable=False, **{'class': 'android.widget.TextView'})
        parent = self.node('', clickable=True, **{'class': 'android.view.View'})
        self.snapshots(self.surface(), self.surface(self.node(enabled=False)), self.surface(parent, leaf))
        self.click()
        self.probe.instrument.assert_called_once_with('account-click', node_path='0.4', node_witness='c'*64)
        diagnostic = self.probe.report['c2_v2_nonimage_click_readiness']['previous']
        self.assertEqual((diagnostic['observations'], diagnostic['state']), (3, 'ancestor_ready'))
        self.assertFalse(diagnostic['hashes_recorded'])
        self.assertEqual(set(diagnostic), {'observations', 'visible_label_paths', 'enabled_exact_label_paths',
                         'direct_control_paths', 'ancestor_control_paths', 'state', 'hashes_recorded'})
        self.assertNotIn('c'*64, json.dumps(self.probe.report))
        self.probe.act.assert_not_called(); self.probe.scroll.assert_not_called()

    def test_distinct_direct_or_label_candidates_are_not_collapsed_or_waited(self):
        for fields in ({}, {'clickable': False, 'class': 'android.widget.TextView'}):
            with self.subTest(fields=fields):
                self.snapshots(self.surface(self.node(**fields), self.node(path='0.5', **fields)))
                with self.assertRaisesRegex(c2.C2Blocked, 'exact_normal_control'): self.click()
                self.assertEqual(self.probe.nodes.call_count, 1)
                self.assertEqual(self.probe.report['c2_v2_nonimage_click_readiness']['previous']['state'], 'ambiguous')
        self.probe.instrument.assert_not_called()

    def test_invalid_ancestors_never_become_pointer_targets(self):
        leaf = self.node(path='0.4.1', clickable=False, **{'class': 'android.widget.TextView'})
        for changes in ({'package': 'foreign.app'}, {'visible': False}, {'enabled': False},
                        {'scrollable': True}, {'editable': True}, {'bounds': [180, 600, 300, 650]},
                        {'description': 'إرسال للمراجعة'}, {'path': '0'},
                        {'clickable': False, 'class': 'android.widget.Button'}):
            with self.subTest(changes=changes):
                self.clock = 0
                parent = self.node('', **{'class': 'android.view.View', **changes})
                self.snapshots(self.surface(parent, leaf))
                with self.assertRaisesRegex(c2.C2Blocked, 'nonimage_click_control_not_ready'): self.click()
                self.assertEqual(self.clock, 15)
        self.probe.instrument.assert_not_called()
        self.probe.act.assert_not_called(); self.probe.scroll.assert_not_called()

    def test_disabled_nearest_button_cannot_be_skipped_for_wider_clickable_ancestor(self):
        outer = self.node('', path='0.4', **{'class': 'android.view.View'})
        disabled = self.node('', path='0.4.1', enabled=False, clickable=False)
        leaf = self.node(path='0.4.1.1', clickable=False, **{'class': 'android.widget.TextView'})
        self.snapshots(self.surface(outer, disabled, leaf))
        with self.assertRaisesRegex(c2.C2Blocked, 'nonimage_click_control_not_ready'): self.click()
        self.probe.instrument.assert_not_called()

    def test_composite_label_and_wrong_editor_footer_cannot_authorize_click(self):
        for observed in (self.surface(self.node(description='إرسال للمراجعة')),
                         [self.node()], rows('العودة إلى النواقص') + [self.node()]):
            with self.subTest(observed=observed):
                self.clock = 0
                self.snapshots(observed)
                with self.assertRaisesRegex(c2.C2Blocked, 'nonimage_click_control_not_ready'): self.click()
        self.probe.instrument.assert_not_called()

    def test_auth_surface_or_wrong_reserved_stage_blocks_before_input(self):
        self.snapshots(self.surface(self.node()) + rows('رمز التحقق'))
        with self.assertRaisesRegex(c2.C2Blocked, 'auth_surface'): self.click()
        self.executor.cursor = c2.STAGES.index('full_save')
        with self.assertRaisesRegex(c2.C2Blocked, 'reserved_editor_stage'): self.click()
        self.probe.instrument.assert_not_called()

    def test_uncertain_instrument_delivery_is_never_retried(self):
        self.snapshots(self.surface(self.node()))
        self.probe.instrument.return_value = {'account_action_delivered': 'false'}
        with self.assertRaisesRegex(c2.C2Blocked, 'input_not_confirmed'): self.click()
        self.probe.instrument.assert_called_once()
        self.assertEqual(self.probe.nodes.call_count, 1)
        self.assertNotIn('c2_v2_nonimage_input_operations_delivered', self.probe.report)

    def footer(self, mode='standard_editor', *, target='خيارات المسودة'):
        primary = 'إرسال للمراجعة' if mode == 'standard_editor' else 'معاينة الإعلان'
        return [self.node(label, path='0.' + str(i)) for i, label in
                enumerate(('السابق', primary), 1)] + [self.node(target)]

    def popup(self, target, *, nested=True):
        other = 'حفظ مسودة' if target == 'معاينة' else 'معاينة'
        result = [self.node(other, path='0.8')]
        if nested:
            return result + [self.node('', path='0.7', **{'class': 'android.view.View'}),
                self.node(target, path='0.7.1', clickable=False, **{'class': 'android.view.View'})]
        return result + [self.node(target, path='0.7')]

    def test_delayed_nested_preview_uses_delivered_menu_and_does_not_require_obscured_footer(self):
        self.executor.cursor = c2.STAGES.index('complete_rent')
        self.snapshots(self.footer())
        self.executor._nonimage_input('click', 'خيارات المسودة')
        self.assertEqual(self.clock, .25)
        self.snapshots(self.footer(), [self.node('حفظ مسودة')], self.popup('معاينة'))
        self.executor._nonimage_input('click', 'معاينة')
        self.assertEqual(self.probe.instrument.call_args_list, [
            call('account-click', node_path='0.4', node_witness='c'*64),
            call('account-click', node_path='0.7', node_witness='c'*64)])
        preview = self.probe.report['c2_v2_nonimage_click_readiness']['validation_preview']
        self.assertEqual((preview['observations'], preview['state']), (3, 'ancestor_ready'))
        self.assertIsNone(self.executor._nonimage_draft_menu_stage)
        self.probe.act.assert_not_called(); self.probe.scroll.assert_not_called()

    def test_delayed_save_popup_supports_both_source_completion_modes(self):
        for mode in ('standard_editor', 'completed_review'):
            with self.subTest(mode=mode):
                self.executor.cursor = c2.STAGES.index('full_save')
                self.executor.entry_mode = mode
                self.probe.instrument.reset_mock()
                self.snapshots(self.footer(mode))
                self.executor._nonimage_input('click', 'خيارات المسودة')
                self.snapshots([], self.popup('حفظ مسودة'))
                self.executor._nonimage_input('click', 'حفظ مسودة')
                self.assertEqual(self.probe.instrument.call_args_list, [
                    call('account-click', node_path='0.4', node_witness='c'*64),
                    call('account-click', node_path='0.7', node_witness='c'*64)])
                self.assertIsNone(self.executor._nonimage_draft_menu_stage)

    def test_sai_and_completed_return_use_their_own_source_surfaces(self):
        for label, stage, mode, observed in [
            ('نسبة مئوية %', 'complete_rent', 'standard_editor',
             self.footer() + [self.node('نسبة مئوية %', path='0.7')]),
            ('نسبة مئوية %', 'complete_rent', 'completed_review',
             [self.node('العودة إلى النواقص'), self.node('نسبة مئوية %', path='0.7')]),
            ('العودة إلى النواقص', 'back_gaps_to_completion', 'completed_review',
             [self.node('العودة إلى النواقص', path='0.7')]),
        ]:
            with self.subTest(label=label, mode=mode):
                self.executor.cursor, self.executor.entry_mode = c2.STAGES.index(stage), mode
                self.probe.instrument.reset_mock()
                self.snapshots([], observed)
                self.executor._nonimage_input('click', label)
                self.probe.instrument.assert_called_once_with('account-click', node_path='0.7', node_witness='c'*64)

    def test_popup_items_require_current_stage_delivered_opening_and_both_exact_labels(self):
        for label, stage in [('معاينة', 'complete_rent'), ('حفظ مسودة', 'full_save')]:
            with self.subTest(label=label):
                self.executor.cursor = c2.STAGES.index(stage)
                self.snapshots(self.popup(label))
                for opening in (None, self.executor.cursor - 1):
                    self.executor._nonimage_draft_menu_stage = opening
                    with self.assertRaisesRegex(c2.C2Blocked, 'same_stage_delivered_draft_menu'):
                        self.executor._nonimage_input('click', label)
                self.executor._nonimage_draft_menu_stage = self.executor.cursor
                self.clock = 0
                self.snapshots([self.node(label)])
                with self.assertRaisesRegex(c2.C2Blocked, 'click_control_not_ready'):
                    self.executor._nonimage_input('click', label)
        self.probe.instrument.assert_not_called()

    def test_popup_ambiguity_fails_immediately_without_selecting_smallest_target(self):
        self.executor.cursor = c2.STAGES.index('complete_rent')
        self.executor._nonimage_draft_menu_stage = self.executor.cursor
        self.snapshots(self.popup('معاينة', nested=False) + [self.node('معاينة', path='0.9')])
        with self.assertRaisesRegex(c2.C2Blocked, 'exact_normal_control'):
            self.executor._nonimage_input('click', 'معاينة')
        self.assertEqual(self.probe.nodes.call_count, 1)
        self.assertEqual(self.clock, 0)
        self.probe.instrument.assert_not_called()

    def test_uncertain_menu_action_consumes_opening_and_cannot_repeat_input(self):
        self.executor.cursor = c2.STAGES.index('full_save')
        self.executor._nonimage_draft_menu_stage = self.executor.cursor
        self.snapshots(self.popup('حفظ مسودة'))
        self.probe.instrument.side_effect = TimeoutError('synthetic receiver timeout')
        with self.assertRaises(TimeoutError): self.executor._nonimage_input('click', 'حفظ مسودة')
        with self.assertRaisesRegex(c2.C2Blocked, 'same_stage_delivered_draft_menu'):
            self.executor._nonimage_input('click', 'حفظ مسودة')
        self.probe.instrument.assert_called_once()
        self.assertNotIn('c2_v2_nonimage_input_operations_delivered', self.probe.report)

    def test_controls_reject_wrong_stage_or_completion_mode_before_observation(self):
        cases = [('حفظ مسودة', 'complete_rent', 'standard_editor'),
                 ('معاينة', 'full_save', 'standard_editor'),
                 ('نسبة مئوية %', 'full_save', 'standard_editor'),
                 ('خيارات المسودة', 'navigate_previous_to_specs', 'standard_editor'),
                 ('العودة إلى النواقص', 'back_gaps_to_completion', 'standard_editor'),
                 ('خيارات المسودة', 'complete_rent', 'completed_review')]
        self.probe.nodes = Mock()
        for label, stage, mode in cases:
            with self.subTest(label=label, stage=stage, mode=mode):
                self.executor.cursor, self.executor.entry_mode = c2.STAGES.index(stage), mode
                with self.assertRaises(c2.C2Blocked): self.executor._nonimage_input('click', label)
        self.probe.nodes.assert_not_called(); self.probe.instrument.assert_not_called()


if __name__ == '__main__': unittest.main()
