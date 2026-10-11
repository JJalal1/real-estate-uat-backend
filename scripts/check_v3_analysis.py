#!/usr/bin/env python3
"""Run Flutter analysis, permitting only four INFOs in one unchanged Golden file."""

import hashlib
import re
import subprocess
from pathlib import Path

BASELINE_FILE = "lib/features/support/presentation/support_tasks_screen.dart"
BASELINE_BLOB = "6a405e928a77b70584a74712c0bf1e7aeaea8932"
BASELINE_CODE = "prefer_interpolation_to_compose_strings"
BASELINE_INFOS = {(BASELINE_FILE, line, column, BASELINE_CODE)
                  for line, column in ((543, 24), (544, 24), (545, 24), (547, 26))}


def assess(output, returncode, file_unchanged):
    clean = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", output)
    records = []
    for line in clean.splitlines():
        match = re.match(r"\s*(info|warning|error)\s*•\s*.*?\s*•\s*(.*):(\d+):(\d+)\s*•\s*([a-z_0-9]+)\s*$", line)
        if match:
            severity, path, number, column, code = match.groups()
            records.append((severity, path, int(number), int(column), code))
        elif re.match(r"\s*(info|warning|error)\s*•", line):
            raise ValueError("Unrecognized analyzer diagnostic format")
    reported = re.search(r"(\d+) issues? found\.", clean)
    if reported and int(reported.group(1)) != len(records):
        raise ValueError("Analyzer diagnostic count mismatch")
    if returncode != 0:
        raise ValueError("Flutter analysis command failed")
    for severity, path, line, column, code in records:
        key = (path, line, column, code)
        if severity != "info" or not file_unchanged or key not in BASELINE_INFOS:
            raise ValueError(f"Unaccepted analyzer diagnostic: {severity} {path}:{line}:{column} {code}")
    return len(records)


def main():
    target = Path(BASELINE_FILE)
    payload = target.read_bytes()
    blob = hashlib.sha1(b"blob " + str(len(payload)).encode() + b"\0" + payload).hexdigest()
    result = subprocess.run(["flutter", "analyze", "--no-fatal-infos"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end="")
    try:
        count = assess(result.stdout, result.returncode, blob == BASELINE_BLOB)
    except ValueError as error:
        print("V3 analysis gate FAILED: " + str(error))
        return 1
    print(f"V3 analysis gate OK; {count} pre-existing INFOs retained on unchanged Golden file.")
    print("Errors, warnings, new INFOs and INFO waivers on a modified file remain forbidden.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
