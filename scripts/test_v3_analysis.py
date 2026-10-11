import unittest

from check_v3_analysis import BASELINE_FILE, BASELINE_CODE, assess


def diagnostic(severity="info", line=543, column=24, code=BASELINE_CODE):
    return f"   {severity} • Use interpolation • {BASELINE_FILE}:{line}:{column} • {code}\n"


class AnalysisBaselineTests(unittest.TestCase):
    def test_four_exact_original_infos_are_visible_and_accepted(self):
        output = "".join(diagnostic(line=line, column=column) for line, column in
                         ((543, 24), (544, 24), (545, 24), (547, 26)))
        self.assertEqual(assess(output + "4 issues found.\n", 0, True), 4)

    def test_new_info_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unaccepted"):
            assess(diagnostic(code="unused_import"), 0, True)

    def test_warnings_and_errors_are_always_rejected(self):
        for severity in ("warning", "error"):
            with self.subTest(severity=severity), self.assertRaises(ValueError):
                assess(diagnostic(severity=severity), 0, True)

    def test_original_info_cannot_be_waived_after_file_changes(self):
        with self.assertRaisesRegex(ValueError, "Unaccepted"):
            assess(diagnostic(), 0, False)

    def test_changed_location_and_incomplete_output_are_rejected(self):
        with self.assertRaises(ValueError):
            assess(diagnostic(line=548), 0, True)
        with self.assertRaisesRegex(ValueError, "count mismatch"):
            assess("4 issues found.\n", 0, True)

    def test_command_failure_is_rejected_even_without_diagnostics(self):
        with self.assertRaisesRegex(ValueError, "command failed"):
            assess("Analyzer crashed\n", 1, True)

    def test_clean_changed_ui_passes_without_any_waivers(self):
        self.assertEqual(assess("No issues found!\n", 0, False), 0)


if __name__ == "__main__":
    unittest.main()
