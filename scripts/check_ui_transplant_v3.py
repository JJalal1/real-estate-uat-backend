#!/usr/bin/env python3
"""Reject changes outside the approved UI transplant scope.

The immutable commit is the authority, not the editable inventory JSON.
This guard detects source drift; it does not prove behavioral parity.
"""

import argparse
import subprocess
from pathlib import Path

GOLDEN_SHA = "dc2805c9215dcd500fc7034effa953a4c3751761"
SETUP_FILES = frozenset({
    ".github/workflows/ui-transplant-v3-ci.yml",
    "scripts/check_ui_transplant_v3.py",
    "scripts/test_ui_transplant_v3_guard.py",
    "scripts/verify_v3_dependency_lock.py",
    "scripts/test_v3_dependency_lock.py",
    "scripts/check_v3_analysis.py",
    "scripts/test_v3_analysis.py",
})
PINNED_PRESENTATION = frozenset({
    "mobile_app/lib/features/account/presentation/auth_gate.dart",
})


def git(root, *args):
    result = subprocess.run(
        ["git", "-C", str(root), *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout


def paths(raw):
    return {item.decode("utf-8") for item in raw.split(b"\0") if item}


def allowed(path, baseline_paths):
    if path in PINNED_PRESENTATION:
        return False
    if path in SETUP_FILES or path.startswith("docs/ui-transplant-v3/"):
        return True
    if path.startswith(("mobile_app/lib/core/theme/", "mobile_app/lib/core/widgets/")):
        return True
    if path == "mobile_app/lib/router/app_router.dart":
        # Home is the sole approved navigation exception. Review/tests must
        # still preserve every existing route and authorization wrapper.
        return True
    if path.startswith("mobile_app/lib/features/") and "/presentation/" in path:
        return True
    if path.startswith("mobile_app/assets/"):
        return True
    if path.startswith("mobile_app/test/") and path.endswith("_test.dart"):
        # Add meaningful UI acceptance coverage without weakening old tests.
        return path not in baseline_paths
    return False


def violations(root, baseline=GOLDEN_SHA, setup=False):
    git(root, "cat-file", "-e", baseline + "^{commit}")
    git(root, "merge-base", "--is-ancestor", baseline, "HEAD")
    baseline_paths = paths(git(root, "ls-tree", "-r", "--name-only", "-z", baseline))
    changed = paths(git(root, "diff", "--name-only", "--no-renames", "-z", baseline, "--"))
    changed |= paths(git(root, "ls-files", "--others", "--exclude-standard", "-z"))
    failures = []
    for path in sorted(changed):
        if path in baseline_paths and not (root / path).exists():
            failures.append(path + " (original file removed before parity gate)")
        elif (root / path).is_symlink():
            failures.append(path + " (source symlink replacement is not UI transplant)")
        elif setup and path in baseline_paths:
            failures.append(path + " (setup must preserve every original file)")
        elif not allowed(path, baseline_paths):
            failures.append(path + " (outside UI transplant scope)")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--setup", action="store_true", help="Also reject all edits to original files")
    parser.add_argument("--verify-reference-refs", action="store_true", help="Require both frozen remote branches")
    args = parser.parse_args()
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip())
    try:
        if args.verify_reference_refs:
            for ref in ("origin/audit/system-stabilization", "origin/reference/golden-dc2805"):
                actual = git(root, "rev-parse", ref + "^{commit}").decode().strip()
                if actual != GOLDEN_SHA:
                    raise RuntimeError("Frozen reference moved: " + ref)
        failed = violations(root, setup=args.setup)
        if failed:
            print("UI transplant guard FAILED:")
            for failure in failed:
                print("- " + failure)
            return 1
        print("UI transplant scope OK; original backend/data/domain/auth/deployment sources preserved.")
        print("Source equality is one gate. Journey tests and device acceptance remain required.")
        return 0
    except (subprocess.CalledProcessError, RuntimeError) as error:
        print("Cannot verify the immutable baseline/reference refs: " + str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
