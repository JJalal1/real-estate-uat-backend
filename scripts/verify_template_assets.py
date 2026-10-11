#!/usr/bin/env python3
"""Check every bundled template asset against its recorded source checksum."""

import hashlib
import json
from pathlib import Path

REFERENCE = "425f019070db73253ff77181c77623d28225cc25"


def verify(root, manifest):
    if manifest.get("template_reference_commit") != REFERENCE:
        raise ValueError("Template reference changed")
    recorded = set()
    for asset in manifest["assets"]:
        path = Path(asset["target"])
        if path.is_absolute() or ".." in path.parts or not str(path).startswith("mobile_app/assets/ebroker/"):
            raise ValueError("Unsafe template asset path")
        if asset["target"] in recorded:
            raise ValueError("Duplicate template asset")
        recorded.add(asset["target"])
        file = root / path
        if file.is_symlink():
            raise ValueError("Template asset symlink")
        content = file.read_bytes()
        if len(content) != asset["bytes"] or hashlib.sha256(content).hexdigest() != asset["sha256"]:
            raise ValueError("Template source checksum mismatch: " + str(path))
    actual = {str(p.relative_to(root)) for p in (root / "mobile_app/assets/ebroker").rglob("*") if p.is_file()}
    if actual != recorded:
        raise ValueError("Template asset inventory mismatch")
    return len(recorded)


if __name__ == "__main__":
    root = Path.cwd()
    manifest = json.loads((root / "docs/ui-transplant-v3/TEMPLATE_ASSETS.json").read_text())
    print(f"Verified {verify(root, manifest)} byte-identical purchased template assets.")
