"""Exercise real Git changes that must be blocked during the transplant."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from check_ui_transplant_v3 import approved_auth_gate, approved_pubspec, approved_viewing_test, CANONICAL_VIEWING_TEST, approved_comments_test, COMMENTS_RENDER_FRAME_TEST, violations


class ScopeGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_git("init", "-q")
        self.run_git("config", "user.name", "Guard fixture")
        self.run_git("config", "user.email", "fixture@example.invalid")
        self.original = {
            "backend-api-runtime/routes/api.php": "original-api\n",
            "mobile_app/lib/features/account/data/auth_repository.dart": "original-auth\n",
            "mobile_app/lib/features/account/presentation/auth_gate.dart": "original-gate\n",
            "mobile_app/lib/features/messages/domain/message_models.dart": "original-model\n",
            "mobile_app/lib/features/messages/presentation/conversation_screen.dart": "original-ui\n",
            "mobile_app/lib/router/app_deep_links.dart": "original-links\n",
            "mobile_app/lib/router/app_router.dart": "original-router\n",
            "mobile_app/test/contract_test.dart": "original-test\n",
            "mobile_app/pubspec.yaml": "name: fixture\nenvironment:\n  sdk: \">=3.4.0 <4.0.0\"\ndependencies:\n  cupertino_icons: ^1.0.8\nflutter:\n  assets:\n    - assets/payments/\n",
            "mobile_app/pubspec.lock": "original-dependencies\n",
            "render.yaml": "original-runtime\n",
            ".github/workflows/build-uat-apk.yml": "original-workflow\n",
        }
        for path, content in self.original.items():
            self.write(path, content)
        self.run_git("add", ".")
        self.run_git("commit", "-qm", "baseline fixture")
        self.baseline = self.run_git("rev-parse", "HEAD").strip()

    def run_git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def check(self, setup=False):
        return violations(self.root, baseline=self.baseline, setup=setup)

    def test_only_exact_renderer_and_template_declarations_pass(self):
        original = self.original["mobile_app/pubspec.yaml"]
        self.write("mobile_app/pubspec.yaml", approved_pubspec(original))
        self.assertEqual(self.check(), [])
        self.assertEqual(len(self.check(setup=True)), 1)

    def test_dependency_sdk_and_asset_tampering_fail(self):
        approved = approved_pubspec(self.original["mobile_app/pubspec.yaml"])
        for changed in (approved.replace("^1.0.8", "^2.0.0"),
                        approved.replace(">=3.4.0", ">=3.10.0"),
                        approved.replace("2.0.10+1", "2.3.0"),
                        approved.replace("Manrope-Regular.ttf", "FakeFont.ttf")):
            self.write("mobile_app/pubspec.yaml", changed)
            self.assertEqual(len(self.check()), 1)

    def test_gate_renderers_preserve_authorization(self):
        path = "mobile_app/lib/features/account/presentation/auth_gate.dart"
        self.write(path, approved_auth_gate(self.original[path]))
        self.assertEqual(self.check(), [])
        self.write(path, approved_auth_gate(self.original[path]) + "unapproved-condition-change\n")
        self.assertEqual(len(self.check()), 1)

    def test_unchanged_original_passes(self):
        self.assertEqual(self.check(), [])

    def test_ui_and_home_edits_allowed_but_not_during_setup(self):
        for path in ("mobile_app/lib/features/messages/presentation/conversation_screen.dart",
                     "mobile_app/lib/router/app_router.dart"):
            self.write(path, "new-ui\n")
        self.assertEqual(self.check(), [])
        self.assertEqual(len(self.check(setup=True)), 2)

    def test_all_authoritative_layers_and_old_tests_are_rejected(self):
        ui_paths = {"mobile_app/lib/features/messages/presentation/conversation_screen.dart",
                    "mobile_app/lib/router/app_router.dart"}
        expected = set(self.original) - ui_paths
        for path in expected:
            self.write(path, "unapproved-change\n")
        rejected = {item.split(" (")[0] for item in self.check()}
        self.assertEqual(rejected, expected)

    def test_obsolete_viewing_source_guard_has_a_narrow_exception(self):
        original = """viewing request opens its linked conversation after creation
      expect(details, contains('booking.messageThreadId'));
      expect(details, contains("context.push('/messages/\\$threadId')"));
      expect(conversation, contains('unchanged-confirm-contract'));
"""
        self.write(CANONICAL_VIEWING_TEST, original)
        self.run_git("add", CANONICAL_VIEWING_TEST)
        self.run_git("commit", "-qm", "canonical viewing fixture")
        self.baseline = self.run_git("rev-parse", "HEAD").strip()
        approved = approved_viewing_test(original)
        self.write(CANONICAL_VIEWING_TEST, approved)
        self.assertEqual(self.check(), [])
        self.write(CANONICAL_VIEWING_TEST, approved.replace('unchanged-confirm-contract', 'weakened-contract'))
        self.assertTrue(any(item.startswith(CANONICAL_VIEWING_TEST) for item in self.check()))

    def test_comment_render_waits_cannot_weaken_count_or_refresh_assertions(self):
        original = """    await tester.scrollUntilVisible(communityButton, 300);
    expect(find.text('0 comment'), findsOneWidget);
    expect(detailsCalls, greaterThanOrEqualTo(2));
    await tester.scrollUntilVisible(communityButton, 300);
    expect(find.text('3 comments'), findsOneWidget);
"""
        self.write(COMMENTS_RENDER_FRAME_TEST, original)
        self.run_git("add", COMMENTS_RENDER_FRAME_TEST)
        self.run_git("commit", "-qm", "comment render fixture")
        self.baseline = self.run_git("rev-parse", "HEAD").strip()
        approved = approved_comments_test(original)
        self.write(COMMENTS_RENDER_FRAME_TEST, approved)
        self.assertEqual(self.check(), [])
        self.assertEqual(approved.count('await tester.pumpAndSettle();'), 2)
        self.write(COMMENTS_RENDER_FRAME_TEST, approved.replace('greaterThanOrEqualTo(2)', 'greaterThanOrEqualTo(1)'))
        self.assertTrue(any(item.startswith(COMMENTS_RENDER_FRAME_TEST) for item in self.check()))
        self.write(COMMENTS_RENDER_FRAME_TEST, approved.replace('3 comments', '0 comment'))
        self.assertTrue(any(item.startswith(COMMENTS_RENDER_FRAME_TEST) for item in self.check()))

    def test_new_untracked_backend_and_data_files_are_rejected(self):
        self.write("backend-api-runtime/database/migrations/unapproved.php", "new-schema\n")
        self.write("mobile_app/lib/features/messages/data/template_repository.dart", "template-api\n")
        self.assertEqual(len(self.check()), 2)

    def test_new_ui_tests_and_documentation_are_allowed(self):
        self.write("mobile_app/test/transplant_contact_test.dart", "new-acceptance\n")
        self.write("docs/ui-transplant-v3/README_AR.md", "new-plan\n")
        self.write(".github/workflows/ui-transplant-v3-ci.yml", "new-ci\n")
        self.assertEqual(self.check(setup=True), [])

    def test_deleted_backend_file_is_rejected(self):
        (self.root / "backend-api-runtime/routes/api.php").unlink()
        self.assertEqual(len(self.check()), 1)

    def test_deleting_original_ui_file_is_rejected(self):
        (self.root / "mobile_app/lib/features/messages/presentation/conversation_screen.dart").unlink()
        self.assertEqual(len(self.check()), 1)

    def test_replacing_ui_with_a_symlink_is_rejected(self):
        target = self.root / "mobile_app/lib/features/messages/presentation/conversation_screen.dart"
        target.unlink()
        target.symlink_to("../../account/data/auth_repository.dart")
        self.assertEqual(len(self.check()), 1)

    def test_committed_drift_is_detected(self):
        self.write("render.yaml", "changed-runtime\n")
        self.run_git("add", "render.yaml")
        self.run_git("commit", "-qm", "unapproved runtime drift")
        self.assertEqual(len(self.check()), 1)

    def test_renaming_original_test_cannot_bypass_the_guard(self):
        self.run_git("mv", "mobile_app/test/contract_test.dart", "mobile_app/test/renamed_test.dart")
        self.assertTrue(any(item.startswith("mobile_app/test/contract_test.dart ") for item in self.check()))


if __name__ == "__main__":
    unittest.main()
