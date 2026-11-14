import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'phase23_local_media_guard.py'
spec = importlib.util.spec_from_file_location('local_media_guard', SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class LocalMediaBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.env = dict(guard.EXACT, GITHUB_ACTIONS='true',
            GITHUB_REPOSITORY='JJalal1/real-estate-uat-backend',
            GITHUB_REF='refs/heads/work/phase23-acceptance-20261111',
            GITHUB_EVENT_NAME='push', GITHUB_SHA='a'*40,
            SOURCE_COMMIT='a'*40, GITHUB_RUN_ID='123')

    def test_exact_disposable_context_is_accepted(self):
        self.assertTrue(guard.environment_guard(self.env))

    def test_each_required_boundary_cannot_be_removed_or_replaced(self):
        for key in guard.EXACT:
            for value in (None, 'unsafe'):
                with self.subTest(key=key, value=value):
                    changed = dict(self.env)
                    if value is None:
                        changed.pop(key)
                    else:
                        changed[key] = value
                    with self.assertRaises(ValueError):
                        guard.environment_guard(changed)

    def test_external_credentials_and_overriding_database_urls_are_rejected(self):
        for key in guard.EMPTY:
            with self.subTest(key=key), self.assertRaises(ValueError):
                guard.environment_guard(dict(self.env, **{key: 'forbidden'}))

    def test_mismatched_source_or_non_ci_invocation_is_rejected(self):
        for key in ('GITHUB_ACTIONS', 'GITHUB_REF', 'GITHUB_EVENT_NAME', 'GITHUB_SHA',
                    'GITHUB_RUN_ID', 'GITHUB_REPOSITORY', 'SOURCE_COMMIT'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                guard.environment_guard(dict(self.env, **{key: 'invalid'}))

    def test_worktree_change_is_rejected_before_runtime_access(self):
        replies = [self.env['GITHUB_SHA'], *guard.TREES.values(), 'mobile_app/lib/main.dart']
        with patch.object(guard.subprocess, 'check_output', side_effect=replies):
            with self.assertRaisesRegex(ValueError, 'product_worktree_changed'):
                guard.guard(self.env)

    def test_unreviewed_product_tree_is_rejected(self):
        with patch.object(guard.subprocess, 'check_output', side_effect=[self.env['GITHUB_SHA'], 'f'*40]):
            with self.assertRaisesRegex(ValueError, 'reviewed_product_tree_changed'):
                guard.guard(self.env)


if __name__ == '__main__':
    unittest.main()
