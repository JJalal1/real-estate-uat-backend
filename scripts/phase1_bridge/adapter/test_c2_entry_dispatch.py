"""Offline current-C1 entry proof checks; no device, API or acceptance claims."""
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('_c2_entry_dispatch',
    HERE / 'variants/ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py')
dispatch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatch)


class CurrentC1EntryDispatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = Path(self.tmp.name)
        key, tag = '4a953df4-9eca-4b87-b06b-664785de24d5', 'AQER-C1-' + 'a' * 12
        title = 'SYNTHETIC ' + tag
        frames = []
        for filename in ('C1-restored-title.png', 'C1-restored-complete-photo.png'):
            data = b'\x89PNG\r\n\x1a\n' + filename.encode()
            (self.out / filename).write_bytes(data)
            frames.append({'file': filename, 'sha256': hashlib.sha256(data).hexdigest(),
                           'authenticated_editor_only': True})
        state = {'key': key, 'tag': tag, 'actor_id': 28}
        report = {'fixture_key': key, 'fixture_tag': tag, 'phase1_accepted': False,
                  'c1_accepted': False, 'frames': frames,
                  'held_after_c1_restore_for_root_review': True,
                  'c1_monthly_rent_blank_checks': {'before_save': True, 'after_reopen': True},
                  'cases': [{'id': name, 'status': 'PASS'} for name in
                            ('C1-photo-save', 'C1-force-stop-restore')]}
        self.probe = SimpleNamespace(out=self.out, private_values={'SYNTHETIC_PRIVATE'},
            report=report, title=title, authenticated=True, recorder=None,
            _root_c2_entry_mode='c2_only', fixture_api=SimpleNamespace(state=state, _call=Mock()),
            access={'phones': {'broker': 'synthetic_b', 'support': 'synthetic_s', 'regular': 'synthetic_r'}})
        stamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        common = {'kind': 'ROOT_ACTUAL_FRAME_REVIEW', 'privacy_checked': True,
                  'manual_review_completed': True, 'fixture_key': key, 'fixture_tag': tag,
                  'monthly_rent_still_blank': True, 'review_completed_utc': stamp,
                  'restored_frame_sha256': frames[0]['sha256']}
        self.c1 = dict(common, phase='C1', c1_accepted=True, native_title=title)
        self.entry = dict(common, phase='C2', restored_title=title, property_id=None,
            same_unpromoted_uuid_verified=True, restored_editor_step=0,
            restored_photo_frame_sha256=frames[1]['sha256'], entry_mode='standard_editor',
            current_fixture_visually_verified=True)
        self.module = SimpleNamespace(configure_c2=Mock(return_value={'status': 'CONFIGURED'}))
        self.write_reviews()

    def write_reviews(self):
        for filename, value in ((dispatch.C1_FILE, self.c1), (dispatch.C2_ENTRY_FILE, self.entry)):
            p = self.out / filename
            p.write_text(json.dumps(value))
            p.chmod(0o600)

    def configure(self):
        return dispatch._configure(self.probe, self.module)

    def test_explicit_current_c1_entry_configures_without_any_c4_proof_or_claim(self):
        before = copy.deepcopy(self.probe.report)
        self.assertEqual(self.configure(), {'status': 'CONFIGURED'})
        args, kwargs = self.module.configure_c2.call_args
        self.assertIsNone(args[3])
        self.assertEqual(kwargs['entry_review'], self.entry)
        self.assertEqual(self.probe.report, before)
        self.assertNotIn('local_c4_executor', self.probe.report)
        self.assertFalse((self.out / dispatch.C4_FILE).exists())
        self.probe.fixture_api._call.assert_not_called()

    def test_standard_entry_requires_explicit_mode_and_rejects_current_c4_state(self):
        del self.probe._root_c2_entry_mode
        with self.assertRaisesRegex(dispatch.Hold, 'actual_root_review_file_missing'):
            self.configure()
        self.probe._root_c2_entry_mode = 'c2_only'
        self.probe.report['local_c4_executor'] = {'accepted': True}
        with self.assertRaisesRegex(dispatch.Hold, 'c2_only_current_c4_state_refused'):
            self.configure()
        self.module.configure_c2.assert_not_called()

    def test_false_or_missing_current_entry_proofs_refuse_before_configuration(self):
        original = dict(self.entry)
        for change in ({'privacy_checked': False}, {'manual_review_completed': False},
                       {'current_fixture_visually_verified': False}, {'property_id': 1},
                       {'same_unpromoted_uuid_verified': False}, {'restored_editor_step': True},
                       {'monthly_rent_still_blank': False}, {'entry_mode': 'completed_review'},
                       {'phase': 'C4'}, {'c4_accepted': True}):
            with self.subTest(change=change):
                self.entry = dict(original, **change); self.write_reviews()
                with self.assertRaises(dispatch.Hold): self.configure()
        self.entry = dict(original); del self.entry['restored_photo_frame_sha256']; self.write_reviews()
        with self.assertRaises(dispatch.Hold): self.configure()
        self.module.configure_c2.assert_not_called()

    def test_current_uuid_title_and_private_values_cannot_be_substituted(self):
        original = dict(self.entry)
        for change in ({'fixture_key': 'a7d53381-72a7-46d7-a2d2-b87cdf2c5f4d'},
                       {'fixture_tag': 'AQER-C1-' + 'b' * 12},
                       {'restored_title': 'OTHER SYNTHETIC TITLE'},
                       {'restored_title': 'SYNTHETIC_PRIVATE'}):
            with self.subTest(change=change):
                self.entry = dict(original, **change); self.write_reviews()
                with self.assertRaises(dispatch.Hold): self.configure()
        self.module.configure_c2.assert_not_called()

    def test_current_c1_cases_hold_and_blank_rent_receipts_are_required(self):
        original = copy.deepcopy(self.probe.report)
        for field, value in (('held_after_c1_restore_for_root_review', False),
                             ('c1_monthly_rent_blank_checks', {'before_save': True, 'after_reopen': False}),
                             ('cases', [{'id': 'C1-photo-save', 'status': 'PASS'}]),
                             ('cases', [{'id': 'C1-photo-save', 'status': 'PASS'},
                                        {'id': 'C1-force-stop-restore', 'status': 'FAIL'}])):
            self.probe.report = copy.deepcopy(original); self.probe.report[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(dispatch.Hold, 'actual_current_c1_restored_hold_required'):
                self.configure()
        self.module.configure_c2.assert_not_called()

    def test_frame_claims_require_actual_current_authenticated_files(self):
        original = copy.deepcopy(self.probe.report)
        self.entry['restored_photo_frame_sha256'] = 'f' * 64; self.write_reviews()
        with self.assertRaisesRegex(dispatch.Hold, 'recorded_frame_mismatch'): self.configure()
        self.entry['restored_photo_frame_sha256'] = original['frames'][1]['sha256']; self.write_reviews()
        self.probe.report['frames'][1]['authenticated_editor_only'] = False
        with self.assertRaisesRegex(dispatch.Hold, 'recorded_frame_mismatch'): self.configure()
        self.probe.report = original
        (self.out / 'C1-restored-complete-photo.png').write_bytes(b'\x89PNG\r\n\x1a\nCHANGED')
        with self.assertRaisesRegex(dispatch.Hold, 'actual_frame_mismatch'): self.configure()
        self.module.configure_c2.assert_not_called()

    def test_stale_entry_review_and_title_frame_disagreement_refuse(self):
        self.entry['review_completed_utc'] = '2000-01-01T00:00:00Z'; self.write_reviews()
        with self.assertRaisesRegex(dispatch.Hold, 'root_review_utc_expired'): self.configure()
        self.entry['review_completed_utc'] = self.c1['review_completed_utc']
        self.entry['restored_frame_sha256'] = 'e' * 64; self.write_reviews()
        with self.assertRaisesRegex(dispatch.Hold, 'current_c1_entry_title_frame_mismatch'): self.configure()
        self.module.configure_c2.assert_not_called()

    def test_photo_chain_uses_current_c1_title_only_in_standard_mode(self):
        rows = [{'path': '0', 'witness': 'a'*64, 'visible': True, 'enabled': True, 'text': ''},
                {'path': '0.1', 'witness': 'b'*64, 'visible': True, 'enabled': True, 'text': 'صور الإعلان (1/12)'},
                {'path': '0.2', 'witness': 'c'*64, 'visible': True, 'enabled': True, 'text': 'مكتمل'}]
        self.probe.active_native_role = 'broker'; self.probe.native_auth_uncertain = False
        self.probe._capture_full_rows = lambda: rows; self.probe._capture_rows_private = lambda unused: False
        policy = SimpleNamespace(names=lambda row: {row['text']}, sha=lambda value: isinstance(value, str) and len(value) == 64)
        module = SimpleNamespace(TARGETS={}, policy=policy, _names=lambda rows: {r['text'] for r in rows})
        executor = SimpleNamespace(key=self.entry['fixture_key'], tag=self.entry['fixture_tag'],
            editor_chain='C2-V2:' + self.entry['fixture_key'], entry_mode='standard_editor', c4=None,
            fixture_title_frame={'file':'C1-restored-title.png','sha256':self.entry['restored_frame_sha256']})
        binding = dispatch._capture_rows(self.probe, module, executor, 'review_photo_before_save')['serialized_identity_binding']
        self.assertEqual(binding['prior_fixture_tagged_title_frame'], executor.fixture_title_frame)
        self.assertNotIn('prior_c4_tagged_title_frame', binding)
        executor.entry_mode = 'completed_review'; executor.c4 = {'restored_frame_sha256':'d'*64}
        binding = dispatch._capture_rows(self.probe, module, executor, 'review_photo_before_save')['serialized_identity_binding']
        self.assertEqual(binding['prior_c4_tagged_title_frame'],
                         {'file':'C1-c4-restored-final-title.png','sha256':'d'*64})
        self.assertNotIn('prior_fixture_tagged_title_frame', binding)


if __name__ == '__main__':
    unittest.main()
