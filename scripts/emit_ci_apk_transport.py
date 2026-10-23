#!/usr/bin/env python3
"""Transport a tested APK through private CI logs if artifact storage is full.

Read-only: no repository mutation, secrets, network requests or release rights.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--part', type=int, required=True)
    parser.add_argument('--parts', type=int, default=3)
    args = parser.parse_args()
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if event.get('repository', {}).get('private') is not True:
        raise SystemExit('APK fallback transport is restricted to the private UAT repository.')
    if not 0 <= args.part < args.parts <= 10:
        raise SystemExit('Invalid transport part.')
    files = list(Path('dist').glob('real-estate-broker-uat-*.apk'))
    if len(files) != 1:
        raise SystemExit('Exactly one tested APK is required.')
    data = files[0].read_bytes()
    if not data.startswith(b'PK') or not 1_000_000 <= len(data) <= 80_000_000:
        raise SystemExit('APK size or container is invalid.')
    evidence = (Path('dist') / 'BUILD_INFO.txt').read_text()
    for gate in ('stage1_ui=success', 'flutter_regression=success', 'source_commit=' + os.environ['SOURCE_COMMIT']):
        if gate not in evidence.splitlines():
            raise SystemExit('Tested build evidence is required.')
    digest = hashlib.sha256(data).hexdigest()
    line_size = 6144
    count = (len(data) + line_size - 1) // line_size
    start, end = count * args.part // args.parts, count * (args.part + 1) // args.parts
    print('CODEX_APK_BEGIN ' + json.dumps({'part': args.part, 'parts': args.parts, 'chunks': count,
        'first': start, 'end': end, 'bytes': len(data), 'sha256': digest, 'file': files[0].name,
        'source_commit': os.environ['SOURCE_COMMIT']}, sort_keys=True), flush=True)
    for index in range(start, end):
        encoded = base64.b64encode(data[index * line_size:(index + 1) * line_size]).decode('ascii')
        print('CODEX_APK_DATA ' + str(index) + ' ' + encoded)
    print('CODEX_APK_END ' + str(args.part), flush=True)


if __name__ == '__main__':
    main()
