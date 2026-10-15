#!/usr/bin/env python3
"""Read-only transport of selected synthetic UI previews in private CI logs."""
import base64
import hashlib
import json
import os
from pathlib import Path


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if event.get('repository', {}).get('private') is not True:
        raise SystemExit('UI preview transport requires the private repository.')
    selected = ['build/v3-preview/home-top.png', 'build/v3-preview/home-properties.png',
                'build/broker-preview/dashboard.png', 'build/broker-preview/refinement-smart-filters.png',
                'build/broker-preview/voice-home-listening.png', 'build/broker-preview/voice-home-large-text.png',
                'build/broker-preview/refinement-inline-sai.png', 'build/broker-preview/refinement-wave4-specifications.png',
                'build/broker-preview/refinement-wave4-specifications-content.png', 'build/broker-preview/wave4-customer-management.png']
    for path in selected:
        file = Path('mobile_app') / path
        if not file.is_file():
            continue
        data = file.read_bytes()
        if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data) > 4_000_000:
            raise SystemExit('Unexpected UI preview type or size.')
        print('CODEX_PREVIEW_BEGIN ' + json.dumps({'file': file.name, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'source_commit': os.environ['SOURCE_COMMIT']}, sort_keys=True))
        for index, start in enumerate(range(0, len(data), 6144)):
            print('CODEX_PREVIEW_DATA ' + file.name + ' ' + str(index) + ' ' + base64.b64encode(data[start:start + 6144]).decode('ascii'))
        print('CODEX_PREVIEW_END ' + file.name, flush=True)


if __name__ == '__main__':
    main()
