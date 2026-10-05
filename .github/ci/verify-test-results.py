"""Fail closed on missing results, unexpected skips, or incomplete prerequisites."""

import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


KNOWN_SKIP_CLASS = "Tests\\Feature\\Stage8RegionsBrokerApiTest"
KNOWN_SKIP_JUNIT_CLASS = KNOWN_SKIP_CLASS.replace("\\", ".")
KNOWN_SKIP_NAME = "test_postgis_rejects_interior_overlap_but_allows_touching_borders"
KNOWN_SKIP_REASON = (
    "PostGIS overlap trigger requires PostgreSQL; "
    "required in the disposable CI PostGIS job."
)
REQUIRED_JOBS = {
    "source-provenance", "backend-tests", "postgres-audit",
    "flutter-validation", "build-uat-apk",
}


def verify_backend(junit_path, events_path):
    root = ET.parse(junit_path).getroot()
    cases = root.findall(".//testcase")
    if not cases:
        raise ValueError("Missing backend test cases")
    if root.findall(".//failure") or root.findall(".//error"):
        raise ValueError("Backend report contains failures/errors")
    skipped = [case for case in cases if case.find("skipped") is not None]
    if len(skipped) > 1:
        raise ValueError("More than the one explicitly permitted SQLite skip")
    events = Path(events_path).read_text(encoding="utf-8")
    skip_events = [line for line in events.splitlines() if line.startswith("Test Skipped (")]
    if len(skip_events) != len(skipped):
        raise ValueError("Skip report/event mismatch")
    for case in skipped:
        if (case.get("classname"), case.get("name")) != (KNOWN_SKIP_JUNIT_CLASS, KNOWN_SKIP_NAME):
            raise ValueError("Unexpected backend skip: " + str(case.attrib))
        expected_event = f"Test Skipped ({KNOWN_SKIP_CLASS}::{KNOWN_SKIP_NAME})\n{KNOWN_SKIP_REASON}"
        if expected_event not in events:
            raise ValueError("Known skipped test has a missing/unexpected reason")
    print(f"Backend result verified: {len(cases)} tests; {len(skipped)} narrowly accounted SQLite skip")
    if skipped:
        print(f"Exception: {KNOWN_SKIP_CLASS}::{KNOWN_SKIP_NAME}: {KNOWN_SKIP_REASON}")
        print("This exact test must pass without skips in the required PostgreSQL job.")


def verify_flutter(machine_path):
    events = [json.loads(line) for line in Path(machine_path).read_text(encoding="utf-8").splitlines() if line.strip()]
    completed = 0
    done = []
    for event in events:
        # Flutter 3.27.3 also emits a daemon-protocol start notification.
        # It is separate from package:test results; reject every other batch.
        if isinstance(event, list):
            if not event:
                raise ValueError("Empty Flutter daemon event batch")
            for notification in event:
                if (
                    not isinstance(notification, dict)
                    or set(notification) != {"event", "params"}
                    or notification["event"] != "test.startedProcess"
                    or not isinstance(notification["params"], dict)
                    or set(notification["params"]) != {"vmServiceUri", "observatoryUri"}
                    or any(value is not None and not isinstance(value, str)
                           for value in notification["params"].values())
                ):
                    raise ValueError("Unexpected Flutter daemon event batch")
            continue
        if not isinstance(event, dict):
            raise ValueError("Unexpected Flutter machine result type")
        kind = event.get("type")
        if kind == "error":
            raise ValueError("Flutter emitted an error event")
        if kind == "testStart" and event.get("test", {}).get("metadata", {}).get("skip"):
            raise ValueError("Flutter test marked skipped")
        if kind == "testDone":
            if event.get("skipped") or event.get("result") != "success":
                raise ValueError("Flutter test failed/errored/skipped")
            if not event.get("hidden", False):
                completed += 1
        if kind == "done":
            done.append(event.get("success"))
    if not completed or done != [True]:
        raise ValueError("Missing/incomplete/unsuccessful Flutter test results")
    print(f"Flutter result verified: {completed} completed tests, zero skipped")


def verify_aggregate(needs):
    if set(needs) != REQUIRED_JOBS:
        raise ValueError("Missing/unexpected required jobs: " + str(sorted(needs)))
    for name in sorted(REQUIRED_JOBS):
        result = needs[name].get("result")
        print(f"{name}={result}")
        if result != "success":
            raise ValueError(f"Required job {name} is {result}, not success")
    print("Unified UAT Gate: SUCCESS — candidate pre-deploy qualification only")


def main():
    mode = sys.argv[1]
    if mode == "backend":
        verify_backend(sys.argv[2], sys.argv[3])
    elif mode == "flutter":
        verify_flutter(sys.argv[2])
    elif mode == "aggregate":
        verify_aggregate(json.loads(os.environ["REQUIRED_JOB_RESULTS"]))
    else:
        raise ValueError("Unknown verification mode")


if __name__ == "__main__":
    main()
