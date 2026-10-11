"""Exercise real Git changes that must be blocked during the transplant."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from check_ui_transplant_v3 import violations


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
