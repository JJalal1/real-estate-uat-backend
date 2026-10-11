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
    "scripts/verify_template_assets.py",
    "scripts/test_v3_template_assets.py",
    "scripts/check_v3_analysis.py",
    "scripts/test_v3_analysis.py",
})
VISUAL_TEST_UPDATES = frozenset({
    "mobile_app/test/app_components_test.dart",
    "mobile_app/test/app_theme_test.dart",
    "mobile_app/test/app_tokens_test.dart",
    "mobile_app/test/uat_three_role_workspaces_test.dart",
    "mobile_app/test/uat_services_hub_navigation_test.dart",
})

CANONICAL_VIEWING_TEST = 'mobile_app/test/uat_listing_publish_viewing_flow_test.dart'

PINNED_PRESENTATION = frozenset({
    "mobile_app/lib/features/account/presentation/auth_gate.dart",
})


ASSET_ADDITIONS = '    - assets/ebroker/svg/\n    - assets/ebroker/svg/agent/\n    - assets/ebroker/svg/MultiColorSvg/\n    - assets/ebroker/svg/Fallback/\n    - assets/ebroker/chat_background/\n    - assets/ebroker/images/\n    - assets/fonts/OFL-Manrope.txt\n'
FONT_ADDITION = '\n    - family: PrimaryFont\n      fonts:\n        - asset: assets/ebroker/fonts/Manrope-Regular.ttf\n          weight: 400\n        - asset: assets/ebroker/fonts/Manrope-Medium.ttf\n          weight: 500\n        - asset: assets/ebroker/fonts/Manrope-SemiBold.ttf\n          weight: 600\n        - asset: assets/ebroker/fonts/Manrope-Bold.ttf\n          weight: 700\n        - asset: assets/ebroker/fonts/Manrope-ExtraBold.ttf\n          weight: 800\n'

def approved_pubspec(original):
    """Permit the purchased fonts/assets and the single SVG renderer only."""
    return (original.replace(
        "  cupertino_icons: ^1.0.8\n",
        "  cupertino_icons: ^1.0.8\n  flutter_svg: 2.0.10+1\n",
    ).replace("    - assets/payments/\n",
              "    - assets/payments/\n" + ASSET_ADDITIONS) + FONT_ADDITION)


def approved_viewing_test(original):
    """Correct only the obsolete source location, keeping all other checks.

    Golden opens/reuses the property conversation first. Linked viewing actions
    are rendered there; the old literal refers to a removed details-screen path.
    """
    return (original.replace(
        'viewing request opens its linked conversation after creation',
        'property conversation entry preserves its linked viewing actions',
    ).replace(
        "      expect(details, contains('booking.messageThreadId'));",
        "      expect(details, contains('startForProperty(property.id)'));",
    ).replace(
        "      expect(details, contains(\"context.push('/messages/\\$threadId')\"));",
        "      expect(details, contains(\"context.push('/messages/\\${thread.id}')\"));\n"
        "      expect(conversation, contains('booking.messageThreadId == widget.threadId'));",
    ))


def approved_auth_gate(original):
    return (original.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../../../core/widgets/ebroker_widgets.dart';",
    ).replace("FilledButton(", "EbrokerFilledButton(")
     .replace("FilledButton.icon(", "EbrokerFilledButton.icon(")
     .replace("Icon(", "EbrokerIcon(")
     .replace("FontWeight.w900", "FontWeight.w600"))


def git(root, *args):
    result = subprocess.run(
        ["git", "-C", str(root), *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout


def paths(raw):
    return {item.decode("utf-8") for item in raw.split(b"\0") if item}


def allowed(path, baseline_paths):
    if path == CANONICAL_VIEWING_TEST:
        return True
    if path == "mobile_app/pubspec.yaml" or path in VISUAL_TEST_UPDATES:
        return True
    if path in PINNED_PRESENTATION:
        return True
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
    if "mobile_app/pubspec.yaml" in changed and (root / "mobile_app/pubspec.yaml").is_file():
        original = git(root, "show", baseline + ":mobile_app/pubspec.yaml").decode("utf-8")
        if (root / "mobile_app/pubspec.yaml").read_text(encoding="utf-8") != approved_pubspec(original):
            failures.append("mobile_app/pubspec.yaml (original declaration changed beyond pinned SVG/assets/fonts)")
    if CANONICAL_VIEWING_TEST in changed and (root / CANONICAL_VIEWING_TEST).is_file():
        original = git(root, "show", baseline + ":" + CANONICAL_VIEWING_TEST).decode("utf-8")
        if (root / CANONICAL_VIEWING_TEST).read_text(encoding="utf-8") != approved_viewing_test(original):
            failures.append(CANONICAL_VIEWING_TEST + " (changes beyond the proven obsolete source-location check)")
    for path in PINNED_PRESENTATION & changed:
        if (root / path).is_file():
            original = git(root, "show", baseline + ":" + path).decode("utf-8")
            if (root / path).read_text(encoding="utf-8") != approved_auth_gate(original):
                failures.append(path + " (authorization gate changed beyond exact template renderer substitutions)")
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
