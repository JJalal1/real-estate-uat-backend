#!/usr/bin/env python3
"""Fail when an experimental UI change modifies a locked source boundary."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
baseline = json.loads((root / 'docs/work-progress/EBROKER_UI_LOCKED_SOURCE.json').read_text())
changed = []
for name, expected in baseline['files'].items():
    path = root / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        changed.append(name)
if changed:
    raise SystemExit('Locked source changed; review required:\n' + '\n'.join(changed))
print(f"Locked source unchanged: {len(baseline['files'])} files from {baseline['source_sha']}")
