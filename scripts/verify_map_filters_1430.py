#!/usr/bin/env python3
"""Keep APK1430 components unchanged outside the owner's map/filter scope."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 'ae43f6e334093b51a86246f7230f684eea6a6a5a'
TREE = '414ac5e32d5c975887249e86078f42eaa7b0afb6'
ALLOWED = {
    'mobile_app/lib/features/discovery/data/marketplace_search_session.dart',
    'mobile_app/lib/features/discovery/presentation/marketplace_search_panel.dart',
    'mobile_app/lib/features/discovery/presentation/assisted_search_screen.dart',
    'mobile_app/lib/features/map/presentation/map_screen.dart',
}
PREFIXES = ('mobile_app/lib/', 'mobile_app/assets/', 'mobile_app/android/',
            'backend-api-runtime/app/', 'backend-api-runtime/database/',
            'backend-api-runtime/resources/', 'backend-api-runtime/routes/',
            'backend-api-runtime/config/')
EXACT = {'mobile_app/pubspec.yaml', 'mobile_app/pubspec.lock',
         'backend-api-runtime/composer.json', 'backend-api-runtime/composer.lock'}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    assert git('rev-parse', BASE + '^{tree}').decode().strip() == TREE, 'Wrong APK1430 source'
    baseline, count = set(), 0
    for entry in git('ls-tree', '-rz', BASE).split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        mode, kind, sha = metadata.decode().split()
        path = raw_path.decode()
        baseline.add(path)
        if kind != 'blob' or path in ALLOWED or not (path.startswith(PREFIXES) or path in EXACT):
            continue
        payload = (ROOT / path).read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(payload)).encode() + b'\0' + payload).hexdigest()
        assert actual == sha, 'Protected APK1430 component changed: ' + path
        count += 1
    for prefix in PREFIXES:
        for item in (ROOT / prefix).rglob('*'):
            if item.is_file():
                path = item.relative_to(ROOT).as_posix()
                assert path in baseline or path in ALLOWED, 'Unapproved new component: ' + path
    print(json.dumps({'baseline_source': BASE, 'baseline_tree': TREE,
                      'owner_build': 1430, 'unchanged_components': count,
                      'scope': sorted(ALLOWED), 'verified': True}))


if __name__ == '__main__':
    main()
