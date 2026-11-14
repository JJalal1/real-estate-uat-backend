import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import phase23_visual_revision as revision
from phase23_preflight import GateError, TREES as BASELINE_TREES


class VisualRevisionGateTest(unittest.TestCase):
    def setUp(self):
        self.env = {'GITHUB_ACTIONS': 'true',
                    'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
                    'GITHUB_REF': revision.BRANCH, 'GITHUB_EVENT_NAME': 'push',
                    'PHASE23_VISUAL_REVISION': 'true',
                    'GITHUB_SHA': 'a' * 40, 'SOURCE_COMMIT': 'a' * 40,
                    'GITHUB_RUN_ID': '12345'}
        self.responses = {
            ('rev-parse', 'HEAD'): self.env['GITHUB_SHA'],
            **{('rev-parse', 'HEAD:' + k): v for k, v in revision.TREES.items()},
            ('diff', '--name-status', '--no-renames', revision.BASE_MOBILE_TREE,
             revision.TREES['mobile_app']): '\n'.join(sorted(revision.MOBILE_DELTA)),
            ('diff', '--name-only', 'HEAD', '--', 'mobile_app', 'backend-api-runtime'): '',
        }

    def evaluate(self, env=None):
        with patch.object(revision, '_git', side_effect=lambda root, *args: self.responses[args]):
            return revision.guard(self.env if env is None else env)

    def test_reviewed_delta_returns_both_trees_without_changing_legacy_gate(self):
        receipt = self.evaluate()
        self.assertEqual(receipt['product_trees'], revision.TREES)
        self.assertEqual(receipt['prior_mobile_tree'], BASELINE_TREES['mobile_app'])
        self.assertNotEqual(revision.TREES['mobile_app'], BASELINE_TREES['mobile_app'])
        self.assertEqual(revision.TREES['backend-api-runtime'], BASELINE_TREES['backend-api-runtime'])
        self.assertFalse(receipt['live_preflight_rerun'])
        self.assertEqual(receipt['reviewed_mobile_changes'], sorted(revision.MOBILE_DELTA))

    def test_wrong_context_rejected_before_any_git_or_network_work(self):
        for key, value in [('GITHUB_ACTIONS', 'false'), ('GITHUB_REPOSITORY', 'other/repo'),
                           ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'),
                           ('PHASE23_VISUAL_REVISION', ''), ('GITHUB_SHA', 'a' * 39),
                           ('SOURCE_COMMIT', 'b' * 40), ('GITHUB_RUN_ID', '0'),
                           ('GITHUB_RUN_ID', True)]:
            with self.subTest(key=key, value=value), patch.object(revision, '_git') as git:
                with self.assertRaisesRegex(GateError, 'explicit_visual_revision_ci_context_required'):
                    revision.guard(dict(self.env, **{key: value}))
                git.assert_not_called()

    def test_mismatched_checkout_or_either_component_is_rejected(self):
        for key in [('rev-parse', 'HEAD'), ('rev-parse', 'HEAD:mobile_app'),
                    ('rev-parse', 'HEAD:backend-api-runtime')]:
            original = self.responses[key]
            self.responses[key] = 'b' * 40
            with self.subTest(key=key), self.assertRaises(GateError):
                self.evaluate()
            self.responses[key] = original

    def test_unrelated_file_rename_or_missing_test_cannot_extend_scope(self):
        key = ('diff', '--name-status', '--no-renames', revision.BASE_MOBILE_TREE,
               revision.TREES['mobile_app'])
        allowed = self.responses[key]
        for changes in ['', 'M\tlib/core/widgets/app_components.dart',
                        allowed + '\nM\tlib/main.dart',
                        allowed.replace('A\ttest/', 'M\ttest/'),
                        allowed + '\nD\tassets/icon.png']:
            self.responses[key] = changes
            with self.subTest(changes=changes), self.assertRaisesRegex(GateError, 'reviewed_delta'):
                self.evaluate()

    def test_dirty_product_file_rejected_after_exact_head_matches(self):
        self.responses[('diff', '--name-only', 'HEAD', '--', 'mobile_app', 'backend-api-runtime')] = 'mobile_app/lib/main.dart'
        with self.assertRaisesRegex(GateError, 'product_worktree_dirty'):
            self.evaluate()


if __name__ == '__main__':
    unittest.main()
