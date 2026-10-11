#!/usr/bin/env python3
"""Verify the isolated build only completes url_launcher entries missing in Golden.

The original pubspec declares url_launcher, but its committed lock has no entries
for it. Keep that original file intact in Git; build with separately pinned missing
entries, preserve all original package records and record the effective build lock.
"""

import argparse
import re
import subprocess
from pathlib import Path

GOLDEN_SHA = "dc2805c9215dcd500fc7034effa953a4c3751761"
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolved", required=True, type=Path)
    args = parser.parse_args()
    original = subprocess.check_output(
        ["git", "show", GOLDEN_SHA + ":mobile_app/pubspec.lock"], text=True,
    )
    try:
        count = verify(original, args.resolved.read_text(encoding="utf-8"))
    except ValueError as error:
        print("Dependency guard FAILED: " + str(error))
        return 1
    print(f"Original {count} locked package records and SDK constraints preserved.")
    print("Only original url_launcher completion plus five pinned SVG-renderer packages added.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
