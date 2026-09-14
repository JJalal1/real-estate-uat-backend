#!/usr/bin/env python3
"""Capture the stable Flutter surface without changing application behavior.

This is a source index, not a substitute for journey or rendered-device review.
Run once against the verified stable source. Keep the captured baseline immutable.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/work-progress'
PATTERNS = {
    'declarations': r'^\s*(?:abstract\s+)?(?:final\s+)?(?:class|enum|mixin|extension)\s+\w+',
    'routes_and_navigation': r'GoRoute\(|path:|context\.(?:push|go|pop)|Navigator\.|MaterialPageRoute|AppNavDestination|_NavItemData',
    'actions': r'onPressed:|onTap:|onSelected:|onChanged:|onSubmitted:|onLongPress:|onDismissed:|onRefresh:|onStep',
    'forms_and_validation': r'TextEditingController|TextFormField|TextField\(|Dropdown|Form\(|validator:|validate\(|InputFormatter|labelText:|hintText:|helperText:|errorText:',
    'states': r'loading:|error:|data:|Async(?:Data|Loading|Error)|\.when\(|\.hasError|isLoading|\.isEmpty|_busy|CircularProgressIndicator|App(?:Loading|Error|Empty|Unavailable|Skeleton)|SnackBar\(',
    'dialogs_and_sheets': r'showDialog|showModalBottomSheet|AlertDialog|AppDialog|AppBottomSheet|Dialog\(|Sheet\(',
    'permissions_and_flags': r'hasPermission|hasRole|\.roles|isPlatformOwner|can[A-Z]\w+|requireActive|requireListingEligible|hasVerified|verificationFlag|capabilit|feature[_F]|enabled:|visible:',
    'providers_and_state': r'\b(?:ref\.(?:read|watch|invalidate|refresh)|\w*Provider\b|setState\(|initState\(|dispose\()',
    'api_calls': r'\.(?:get|post|put|patch|delete|request)(?:<[^;]*?>)?\(|requiredAuthOptions|optionalAuthOptions|MultipartFile|FormData|^\s*[\x27\x22]/',
}

def main():
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    files = []
    for path in sorted((ROOT / 'mobile_app/lib').rglob('*.dart')):
        source = path.read_text()
        lines = source.splitlines()
        records = {key: [{'line': i, 'source': line.strip()} for i, line in enumerate(lines, 1)
                         if re.search(pattern, line)] for key, pattern in PATTERNS.items()}
        files.append({'path': str(path.relative_to(ROOT)), 'lines': len(lines),
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), **records})
    tests = [str(p.relative_to(ROOT)) for base in ('mobile_app/test', 'backend-api-runtime/tests')
             for p in sorted((ROOT / base).rglob('*')) if p.is_file()]
    OUT.mkdir(parents=True, exist_ok=True)
    payload = {'source_sha': sha, 'scope': 'All tracked mobile_app/lib Dart files',
               'limitation': 'Static source anchors; multi-line callbacks and runtime states require manual review.',
               'files': files, 'tests': tests}
    (OUT / 'EBROKER_UI_SOURCE_INVENTORY.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    locked = {}
    for name in subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines():
        path = ROOT / name
        if (name.startswith('backend-api-runtime/') or
            (name.startswith('mobile_app/lib/') and any(segment in name for segment in
             ('/domain/', '/data/', '/router/', '/core/network/', '/core/local/', '/core/platform/')))):
            locked[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    (OUT / 'EBROKER_UI_LOCKED_SOURCE.json').write_text(json.dumps({'source_sha': sha, 'files': locked}, indent=2) + '\n')
    print(json.dumps({'dart_files': len(files), 'presentation_files': sum('/presentation/' in f['path'] for f in files),
                      'tests_and_fixtures': len(tests), 'locked_files': len(locked),
                      'anchors': {k: sum(len(f[k]) for f in files) for k in PATTERNS}}, indent=2))

if __name__ == '__main__':
    main()
