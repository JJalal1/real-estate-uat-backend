"""Bounded APK cleanup contracts using synthetic resolver completion records."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_v3_dependency_lock as subject


def complete_lock(committed):
    prefix, sdks = committed.split('\nsdks:\n')
    additions = []
    for name, version in sorted(subject.MISSING_PACKAGES.items()):
        kind = '"direct main"' if name in {'url_launcher', 'flutter_svg'} else 'transitive'
        additions.append(
            f'  {name}:\n    dependency: {kind}\n    description:\n'
            f'      name: {name}\n      sha256: {"a" * 64}\n'
            f'      url: "https://pub.dev"\n    source: hosted\n'
            f'    version: "{version}"\n'
        )
    return prefix.rstrip('\n') + '\n' + ''.join(additions) + '\nsdks:\n' + sdks


def drop_record(content, name):
    before, sdks = content.split('\nsdks:\n')
    import re
    before, count = re.subn(r'^  ' + re.escape(name) + r':\n.*?(?=^  [a-zA-Z0-9_]+:\n|\Z)',
                            '', before, flags=re.MULTILINE | re.DOTALL)
    if count != 1:
        raise AssertionError('fixture package missing')
    return before + '\nsdks:\n' + sdks


class ApkCleanupDependencyPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = subprocess.check_output(
            ['git', 'show', subject.CLEANUP_BASELINE_SHA + ':mobile_app/pubspec.lock'],
            cwd=ROOT, text=True,
        )
        cls.baseline_pubspec = subprocess.check_output(
            ['git', 'show', subject.CLEANUP_BASELINE_SHA + ':mobile_app/pubspec.yaml'],
            cwd=ROOT, text=True,
        )
        cls.policy = json.loads((ROOT / 'docs/apk-cleanup-dependency-policy.json').read_text())
        cls.current_pubspec = (ROOT / 'mobile_app/pubspec.yaml').read_text()
        cls.committed = (ROOT / 'mobile_app/pubspec.lock').read_text()
        cls.resolved = complete_lock(cls.committed)
        cls.env = {
            'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': subject.CLEANUP_REPOSITORY,
            'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/' + subject.CLEANUP_BRANCH,
        }

    def verify(self, **changes):
        values = dict(policy=self.policy, baseline_pubspec=self.baseline_pubspec,
                      current_pubspec=self.current_pubspec, committed_lock=self.committed,
                      env=self.env)
        values.update(changes)
        resolved = values.pop('resolved', self.resolved)
        return subject.verify_cleanup(self.original, resolved, **values)

    def test_exact_cleanup_retains_every_other_package_record(self):
        before, sdks_before = subject.parse_lock(self.original)
        after, sdks_after = subject.parse_lock(self.committed)
        self.assertEqual(set(before) - set(after), subject.CLEANUP_REMOVALS)
        self.assertEqual(set(after) - set(before), set())
        self.assertEqual(sdks_before, sdks_after)
        self.assertEqual({k: before[k] for k in after}, after)
        self.assertIn('fixnum', after)
        self.assertEqual(self.verify(), len(after))

    def test_default_golden_contract_remains_strict_and_unchanged(self):
        self.assertEqual(subject.verify(self.original, complete_lock(self.original)), 117)
        with self.assertRaises(ValueError):
            subject.verify(self.original, self.resolved)

    def test_only_three_audited_pubspec_lines_change(self):
        before = self.baseline_pubspec.splitlines()
        after = self.current_pubspec.splitlines()
        removed = [line for line in before if line not in after]
        self.assertEqual(len(removed), 3)
        self.assertEqual({line.split(':', 1)[0].strip() for line in removed}, subject.CLEANUP_ROOTS)
        for altered in [self.baseline_pubspec,
                        self.current_pubspec.replace('maplibre_gl: 0.22.0', 'maplibre_gl: 0.23.0'),
                        self.current_pubspec.replace('assets/brand/', 'assets/other/')]:
            with self.subTest(altered=altered[:20]), self.assertRaises(ValueError):
                self.verify(current_pubspec=altered)

    def test_wrong_push_repository_branch_event_or_runner_fails(self):
        for field, value in [('GITHUB_ACTIONS', 'false'), ('GITHUB_REPOSITORY', 'other/repo'),
                             ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'workflow_dispatch')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify(env={**self.env, field: value})

    def test_only_trusted_internal_pr_head_and_base_are_accepted(self):
        env = {**self.env, 'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF': 'refs/pull/192/merge',
               'GITHUB_HEAD_REF': subject.CLEANUP_BRANCH, 'GITHUB_BASE_REF': subject.CLEANUP_PR_BASE,
               'AQER_CLEANUP_PR_HEAD_REPO': subject.CLEANUP_REPOSITORY}
        self.verify(env=env)
        for field, value in [('GITHUB_HEAD_REF', 'other-branch'), ('GITHUB_BASE_REF', 'main'),
                             ('AQER_CLEANUP_PR_HEAD_REPO', 'fork/repository'),
                             ('GITHUB_REF', 'refs/heads/' + subject.CLEANUP_BRANCH)]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify(env={**env, field: value})

    def test_policy_cannot_expand_removal_set_or_change_baseline(self):
        cases = []
        expanded = copy.deepcopy(self.policy)
        expanded['removed_packages']['maplibre_gl'] = copy.deepcopy(expanded['removed_packages']['drift'])
        cases.append(expanded)
        fewer = copy.deepcopy(self.policy)
        del fewer['removed_packages']['charcode']
        cases.append(fewer)
        for field, value in [('schema', True), ('baseline_source', '0' * 40),
                             ('golden_source', '0' * 40), ('mode', 'other'),
                             ('baseline_pubspec_sha256', '0' * 64), ('baseline_lock_sha256', '0' * 64)]:
            changed = copy.deepcopy(self.policy)
            changed[field] = value
            cases.append(changed)
        for policy in cases:
            with self.subTest(policy=policy.get('mode')), self.assertRaises(ValueError):
                self.verify(policy=policy)

    def test_removed_versions_archive_checksums_and_record_hashes_are_pinned(self):
        for field, value in [('version', '9.9.9'), ('archive_sha256', '0' * 64),
                             ('original_record_sha256', '0' * 64), ('pubspec_url', 'https://other.invalid')]:
            changed = copy.deepcopy(self.policy)
            changed['removed_packages']['drift'][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify(policy=changed)

    def test_reintroduced_removed_package_fails_resolver_contract(self):
        before, _ = subject.parse_lock(self.original)
        for name in sorted(subject.CLEANUP_REMOVALS):
            prefix, sdks = self.resolved.split('\nsdks:\n')
            altered = prefix + '\n' + before[name] + '\n\nsdks:\n' + sdks
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify(resolved=altered)

    def test_shared_active_package_cannot_disappear(self):
        for name in ('fixnum', 'maplibre_gl', 'path_provider', 'flutter_riverpod'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify(resolved=drop_record(self.resolved, name))

    def test_retained_version_checksum_and_source_cannot_change(self):
        for old, new in [('version: "0.22.0"', 'version: "0.23.0"'),
                         ('source: hosted', 'source: other'),
                         ('sha256: da0d', 'sha256: 0000')]:
            self.assertIn(old, self.resolved)
            with self.subTest(old=old), self.assertRaises(ValueError):
                self.verify(resolved=self.resolved.replace(old, new, 1))

    def test_sdk_constraints_and_pinned_completion_versions_remain_protected(self):
        prefix = self.resolved.split('\nsdks:\n')[0]
        with self.assertRaises(ValueError):
            self.verify(resolved=prefix + '\nsdks:\n  dart: ">=3.0.0 <4.0.0"\n')
        with self.assertRaises(ValueError):
            self.verify(resolved=self.resolved.replace('version: "6.3.17"', 'version: "6.3.18"'))

    def test_committed_lock_has_no_hidden_changes_or_resolver_completion(self):
        for altered in (self.original, self.resolved, drop_record(self.committed, 'fixnum')):
            with self.subTest(length=len(altered)), self.assertRaises(ValueError):
                self.verify(committed_lock=altered)


if __name__ == '__main__':
    unittest.main()
