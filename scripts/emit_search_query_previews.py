#!/usr/bin/env python3
"""Bounded read-only transport of four synthetic test previews in private CI."""
import base64
import hashlib
import json
import os
from pathlib import Path


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if event.get('repository', {}).get('private') is not True:
        raise SystemExit('Synthetic preview transport requires the private repository.')
    for screen in ['summary', 'followup']:
        for scale in ['1.0', '2.4']:
            file = Path(f'mobile_app/build/broker-preview/search-query-{screen}-{scale}.png')
            if not file.is_file():
                continue
            data = file.read_bytes()
            if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data) > 4_000_000:
                raise SystemExit('Unexpected synthetic preview type or size.')
            print('CODEX_PREVIEW_BEGIN ' + json.dumps({
                'file': file.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                'source_commit': os.environ['SOURCE_COMMIT'],
            }, sort_keys=True))
            for index, start in enumerate(range(0, len(data), 6144)):
                print('CODEX_PREVIEW_DATA ' + file.name + ' ' + str(index) + ' ' +
                      base64.b64encode(data[start:start + 6144]).decode('ascii'))
            print('CODEX_PREVIEW_END ' + file.name, flush=True)


if __name__ == '__main__':
    main()
