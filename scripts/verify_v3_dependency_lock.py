#!/usr/bin/env python3
"""Verify the isolated build only completes url_launcher entries missing in Golden.

The original pubspec declares url_launcher, but its committed lock has no entries
for it. Keep that original file intact in Git; build with separately pinned missing
entries, preserve all original package records and record the effective build lock.

The explicit Cleanup1818 mode additionally permits only the pinned, audited
SQLite dependency closure on its isolated branch or trusted internal PR. The
ordinary verification contract remains unchanged.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

GOLDEN_SHA = "dc2805c9215dcd500fc7034effa953a4c3751761"
CLEANUP_BASELINE_SHA = "76c3ef76b396e35dfa5659c1aa2158faecb94b78"
CLEANUP_REPOSITORY = "JJalal1/real-estate-uat-backend"
CLEANUP_BRANCH = "work/apk-cleanup-1817-20261117"
CLEANUP_PR_BASE = "work/fix-connectivity-1815-20261117"
# Inherit the audited finite cleanup on this explicitly authorized UX branch.
UX1820_BRANCH = "work/map-search-ux-1820-20261117"
UX1820_PR_BASE = CLEANUP_BRANCH
CLEANUP_REMOVALS = frozenset({
    "charcode", "cli_util", "drift", "drift_dev", "recase", "sqlite3",
    "sqlite3_flutter_libs", "sqlparser",
})
CLEANUP_ROOTS = frozenset({"drift", "drift_dev", "sqlite3_flutter_libs"})
ROOT = Path(__file__).resolve().parents[1]
MISSING_PACKAGES = {
    "flutter_svg": "2.0.10+1",
    "path_parsing": "1.0.1",
    "vector_graphics": "1.1.11+1",
    "vector_graphics_codec": "1.1.11+1",
    "vector_graphics_compiler": "1.1.11+1",
    "url_launcher": "6.3.2",
    "url_launcher_android": "6.3.17",
    "url_launcher_ios": "6.3.3",
    "url_launcher_linux": "3.2.1",
    "url_launcher_macos": "3.2.2",
    "url_launcher_platform_interface": "2.3.2",
    "url_launcher_web": "2.4.1",
    "url_launcher_windows": "3.1.4",
}


def canonical(block):
    # Pub lock records use scalar values only. Normalize scalar quote style;
    # retain field names, indentation, all values and archive checksums.
    return "\n".join(re.sub(r'["\']', '', line.rstrip())
                     for line in block.splitlines() if line.strip())


def parse_lock(content):
    if content.count("\nsdks:\n") != 1 or content.count("\npackages:\n") != 1:
        raise ValueError("Unexpected pub lock structure")
    package_section, sdks = content.split("\nsdks:\n")
    package_section = package_section.split("\npackages:\n", 1)[1]
    starts = list(re.finditer(r"^  ([a-zA-Z0-9_]+):\n", package_section, re.MULTILINE))
    packages = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(package_section)
        name = match.group(1)
        if name in packages:
            raise ValueError("Duplicate package record: " + name)
        packages[name] = canonical(package_section[match.start():end])
    if not packages:
        raise ValueError("Empty package lock")
    return packages, canonical(sdks)


def verify(original, resolved):
    before, original_sdks = parse_lock(original)
    after, resolved_sdks = parse_lock(resolved)
    changed = [name for name, record in before.items() if after.get(name) != record]
    if changed:
        raise ValueError("Original locked packages changed or removed: " + ", ".join(sorted(changed)))
    added = set(after) - set(before)
    if added != set(MISSING_PACKAGES):
        raise ValueError("Unexpected added dependency set: " + ", ".join(sorted(added)))
    if original_sdks != resolved_sdks:
        raise ValueError("Original Dart/Flutter SDK constraints changed")
    for name, expected in MISSING_PACKAGES.items():
        record = after[name]
        if not re.search(r"^    version: " + re.escape(expected) + r"$", record, re.MULTILINE):
            raise ValueError("Unexpected build-only package version: " + name)
        if not re.search(r"^      sha256: [a-f0-9]{64}$", record, re.MULTILINE):
            raise ValueError("Missing archive integrity checksum: " + name)
        if "      url: https://pub.dev" not in record or "    source: hosted" not in record:
            raise ValueError("Unexpected package source: " + name)
    return len(before)


def cleanup_context(env):
    """Read-only dependency checks may run on this branch or its internal PR.

    This does not authorize signing in pull requests. The signing importer keeps
    its independent push-only policy. PR head repository comes from the caller's
    GitHub event context, not from application or package contents.
    """
    common = (env.get("GITHUB_ACTIONS") == "true" and
              env.get("GITHUB_REPOSITORY") == CLEANUP_REPOSITORY)
    push = (env.get("GITHUB_EVENT_NAME") == "push" and
            env.get("GITHUB_REF") in {"refs/heads/" + CLEANUP_BRANCH, "refs/heads/" + UX1820_BRANCH})
    internal_pr = (
        env.get("GITHUB_EVENT_NAME") == "pull_request" and
        re.fullmatch(r"refs/pull/[1-9][0-9]*/merge", env.get("GITHUB_REF", "")) and
        (env.get("GITHUB_HEAD_REF"), env.get("GITHUB_BASE_REF")) in {
            (CLEANUP_BRANCH, CLEANUP_PR_BASE), (UX1820_BRANCH, UX1820_PR_BASE)} and
        env.get("AQER_CLEANUP_PR_HEAD_REPO") == CLEANUP_REPOSITORY
    )
    if not (common and (push or internal_pr)):
        raise ValueError("Cleanup1818 requires the explicit CI branch or internal PR")


def without_cleanup_packages(content):
    """Remove exactly the audited records while preserving every other byte."""
    starts = list(re.finditer(r"^  ([a-zA-Z0-9_]+):\n", content, re.MULTILINE))
    segments, cursor, removed = [], 0, set()
    sdk_start = content.index("\nsdks:\n")
    for index, match in enumerate(starts):
        if match.group(1) not in CLEANUP_REMOVALS:
            continue
        end = starts[index + 1].start() if index + 1 < len(starts) else sdk_start
        segments.append(content[cursor:match.start()])
        cursor = end
        removed.add(match.group(1))
    segments.append(content[cursor:])
    if removed != CLEANUP_REMOVALS:
        raise ValueError("Cleanup package set is absent from the pinned baseline")
    return "".join(segments)


def without_cleanup_roots(content):
    for name in sorted(CLEANUP_ROOTS):
        content, count = re.subn(r"^  " + re.escape(name) + r": [^\n]+\n", "", content,
                                 flags=re.MULTILINE)
        if count != 1:
            raise ValueError("Pinned baseline must declare every audited cleanup root once")
    return content


def verify_cleanup(original, resolved, *, policy, baseline_pubspec,
                   current_pubspec, committed_lock, env):
    """Opt-in bounded cleanup; the ordinary Golden verifier stays unchanged."""
    cleanup_context(env)
    fields = {"schema", "mode", "repository", "branch", "pr_base", "golden_source",
              "baseline_source", "baseline_pubspec_sha256", "baseline_lock_sha256",
              "removed_roots", "removed_packages"}
    if (not isinstance(policy, dict) or set(policy) != fields or
            type(policy["schema"]) is not int or policy["schema"] != 1 or
            policy["mode"] != "apk_cleanup_1818" or
            policy["repository"] != CLEANUP_REPOSITORY or
            policy["branch"] != CLEANUP_BRANCH or policy["pr_base"] != CLEANUP_PR_BASE or
            policy["golden_source"] != GOLDEN_SHA or
            policy["baseline_source"] != CLEANUP_BASELINE_SHA or
            policy["removed_roots"] != sorted(CLEANUP_ROOTS) or
            not isinstance(policy["removed_packages"], dict) or
            set(policy["removed_packages"]) != CLEANUP_REMOVALS):
        raise ValueError("Cleanup policy must equal the finite audited contract")
    if (hashlib.sha256(original.encode()).hexdigest() != policy["baseline_lock_sha256"] or
            hashlib.sha256(baseline_pubspec.encode()).hexdigest() != policy["baseline_pubspec_sha256"]):
        raise ValueError("Cleanup baseline file identity mismatch")
    before, _ = parse_lock(original)
    for name, entry in policy["removed_packages"].items():
        record = before.get(name, "")
        if (not isinstance(entry, dict) or
                set(entry) != {"version", "archive_sha256", "original_record_sha256", "pubspec_url"} or
                entry["original_record_sha256"] != hashlib.sha256(record.encode()).hexdigest() or
                not re.search(r"^    version: " + re.escape(str(entry["version"])) + r"$", record, re.MULTILINE) or
                not re.search(r"^      sha256: " + re.escape(str(entry["archive_sha256"])) + r"$", record, re.MULTILINE) or
                entry["pubspec_url"] != "https://pub.dev/api/packages/" + name + "/versions/" + str(entry["version"])):
            raise ValueError("Cleanup removal record does not match its pinned package")
    if current_pubspec != without_cleanup_roots(baseline_pubspec):
        raise ValueError("Cleanup may only remove the three audited pubspec roots")
    expected_committed = without_cleanup_packages(original)
    if parse_lock(committed_lock) != parse_lock(expected_committed):
        raise ValueError("Committed cleanup lock must contain exactly the retained baseline")
    # Reuse every ordinary version/source/archive checksum/SDK/addition check.
    # Pub must resolve to this exact retained set plus the original allowed SVG
    # and launcher completion; reintroducing a supposedly exclusive package fails.
    return verify(expected_committed, resolved)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolved", required=True, type=Path)
    parser.add_argument("--cleanup1818", action="store_true",
                        help="opt in to the finite approved cleanup on its exact CI branch")
    args = parser.parse_args()
    original = subprocess.check_output(
        ["git", "show", GOLDEN_SHA + ":mobile_app/pubspec.lock"], text=True,
    )
    try:
        if args.cleanup1818:
            policy_path = ROOT / "docs/apk-cleanup-dependency-policy.json"
            if policy_path.is_symlink() or not policy_path.is_file():
                raise ValueError("A regular committed cleanup policy is required")
            policy = json.loads(policy_path.read_text(encoding="utf-8"))
            baseline_pubspec = subprocess.check_output(
                ["git", "show", CLEANUP_BASELINE_SHA + ":mobile_app/pubspec.yaml"], text=True,
            )
            committed_lock = subprocess.check_output(
                ["git", "show", "HEAD:mobile_app/pubspec.lock"], text=True,
            )
            count = verify_cleanup(
                original, args.resolved.read_text(encoding="utf-8"), policy=policy,
                baseline_pubspec=baseline_pubspec,
                current_pubspec=(ROOT / "mobile_app/pubspec.yaml").read_text(encoding="utf-8"),
                committed_lock=committed_lock, env=os.environ,
            )
        else:
            count = verify(original, args.resolved.read_text(encoding="utf-8"))
    except ValueError as error:
        print("Dependency guard FAILED: " + str(error))
        return 1
    if args.cleanup1818:
        print("Cleanup1818 finite package removals verified; all retained records are unchanged.")
        print(f"Original {count} retained locked package records and SDK constraints preserved.")
    else:
        print(f"Original {count} locked package records and SDK constraints preserved.")
    print("Only original url_launcher completion plus five pinned SVG-renderer packages added.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
