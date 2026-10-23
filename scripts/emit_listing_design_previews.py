#!/usr/bin/env python3
"""Transport only named synthetic test renders, with hashes and exact source."""
import base64
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = list((root / 'mobile_app/build/listing-design-preview').glob('*.png'))
files += list((root / 'mobile_app/build/broker-preview').glob('assistant-complete-*.png'))
files += list((root / 'mobile_app/build/compact-cards-preview').glob('*.png'))
files += list((root / 'mobile_app/build/broker-preview').glob('new-wave-*.png'))
if '--new-wave-only' in sys.argv:
    files = list((root / 'mobile_app/build/broker-preview').glob('new-wave-*.png'))
total = 0
for path in sorted(files):
    payload = path.read_bytes()
    total += len(payload)
    if len(payload) > 2_000_000 or total > 20_000_000:
        raise SystemExit('Synthetic preview transport limit exceeded')
    digest = hashlib.sha256(payload).hexdigest()
    print('LISTING_PREVIEW_META ' + json.dumps({'name': path.name, 'bytes': len(payload), 'sha256': digest,
        'source_commit': os.environ.get('GITHUB_SHA'), 'synthetic': True}))
    encoded = base64.b64encode(payload).decode()
    for index in range(0, len(encoded), 12000):
        print('LISTING_PREVIEW_CHUNK ' + json.dumps({'name': path.name, 'offset': index, 'data': encoded[index:index+12000]}))
    print('LISTING_PREVIEW_END ' + path.name)
print('LISTING_PREVIEW_TOTAL ' + str(len(files)))

