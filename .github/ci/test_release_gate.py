"""Behavioral regressions for skip accounting and the fail-closed aggregate."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("gate", Path(__file__).with_name("verify-test-results.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class GateResultsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def backend(self, cases, events=""):
        junit = self.root / "junit.xml"
        event_path = self.root / "events.txt"
        junit.write_text("<testsuites><testsuite>" + cases + "</testsuite></testsuites>")
        event_path.write_text(events)
        return gate.verify_backend(junit, event_path)

    def known_skip(self):
        return f'<testcase classname="{gate.KNOWN_SKIP_JUNIT_CLASS}" name="{gate.KNOWN_SKIP_NAME}"><skipped/></testcase>'

    def known_event(self, reason=None):
        return f"Test Skipped ({gate.KNOWN_SKIP_CLASS}::{gate.KNOWN_SKIP_NAME})\n{reason or gate.KNOWN_SKIP_REASON}\n"

    def test_backend_accepts_no_skips(self):
        self.backend('<testcase classname="Tests\\Feature\\Normal" name="test_passes"/>')

    def test_backend_accounts_only_for_the_exact_sqlite_skip(self):
        self.backend(self.known_skip(), self.known_event())

    def test_backend_rejects_new_skip(self):
        with self.assertRaises(ValueError):
            self.backend('<testcase classname="Tests\\Feature\\Other" name="test_new"><skipped/></testcase>', "Test Skipped (Tests\\Feature\\Other::test_new)\nNo database\n")

    def test_backend_rejects_extra_known_skip(self):
        with self.assertRaises(ValueError):
            self.backend(self.known_skip() * 2, self.known_event() * 2)

    def test_backend_rejects_changed_or_missing_reason(self):
        for events in [self.known_event("Unexpected reason"), ""]:
            with self.subTest(events=events), self.assertRaises(ValueError):
                self.backend(self.known_skip(), events)

    def test_backend_rejects_empty_and_failed_report(self):
        for cases in ["", '<testcase name="test_failed"><failure/></testcase>', '<testcase name="test_errored"><error/></testcase>']:
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                self.backend(cases)

    def flutter(self, events):
        path = self.root / "flutter.jsonl"
        path.write_text("\n".join(json.dumps(event) for event in events))
        return gate.verify_flutter(path)

    def test_flutter_requires_completed_success_with_zero_skips(self):
        self.flutter([{"type": "testDone", "result": "success", "skipped": False}, {"type": "done", "success": True}])
        invalid = [
            [], [{"type": "done", "success": True}],
            [{"type": "testDone", "result": "success", "skipped": True}, {"type": "done", "success": True}],
            [{"type": "testStart", "test": {"metadata": {"skip": True}}}],
            [{"type": "testDone", "result": "failure"}, {"type": "done", "success": False}],
            [{"type": "error"}],
        ]
        for events in invalid:
            with self.subTest(events=events), self.assertRaises(ValueError):
                self.flutter(events)

    def test_flutter_accepts_its_real_process_start_notification(self):
        self.flutter([
            [{"event": "test.startedProcess", "params": {"vmServiceUri": None, "observatoryUri": None}}],
            {"type": "testDone", "result": "success", "skipped": False},
            {"type": "done", "success": True},
        ])

    def test_flutter_never_hides_results_in_unknown_or_malformed_batches(self):
        invalid = [
            [], [{"type": "error"}],
            [{"event": "test.failed", "params": {}}],
            [{"event": "test.startedProcess", "params": {"error": "failed"}}],
            [{"event": "test.startedProcess", "params": None}],
            [{"event": "test.startedProcess", "params": {"vmServiceUri": 1, "observatoryUri": None}}],
            "unexpected text",
        ]
        for event in invalid:
            with self.subTest(event=event), self.assertRaises(ValueError):
                self.flutter([event, {"type": "testDone", "result": "success", "skipped": False}, {"type": "done", "success": True}])

    def test_aggregate_accepts_only_all_required_successes(self):
        gate.verify_aggregate({name: {"result": "success"} for name in gate.REQUIRED_JOBS})
        for name in gate.REQUIRED_JOBS:
            for result in ["failure", "cancelled", "skipped", "timed_out", None, "pending"]:
                needs = {job: {"result": "success"} for job in gate.REQUIRED_JOBS}
                needs[name] = {"result": result}
                with self.subTest(name=name, result=result), self.assertRaises(ValueError):
                    gate.verify_aggregate(needs)

    def test_aggregate_rejects_missing_and_extra_jobs(self):
        needs = {name: {"result": "success"} for name in gate.REQUIRED_JOBS}
        for name in gate.REQUIRED_JOBS:
            with self.subTest(name=name), self.assertRaises(ValueError):
                gate.verify_aggregate({job: state for job, state in needs.items() if job != name})
        with self.assertRaises(ValueError):
            gate.verify_aggregate({**needs, "unexpected": {"result": "success"}})


if __name__ == "__main__":
    unittest.main()
