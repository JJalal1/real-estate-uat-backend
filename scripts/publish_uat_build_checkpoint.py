#!/usr/bin/env python3
"""Private Git-object fallback when Actions artifact storage is unavailable.

Runs only after the original tests and release APK build succeed. Does not move
any product branch or merge a PR. Credentials never enter files or log output.
"""
import base64
import json
import os
from pathlib import Path
import urllib.request

repository = os.environ['GITHUB_REPOSITORY']
source = os.environ['SOURCE_COMMIT']
run = os.environ['GITHUB_RUN_NUMBER']
checkpoint = f'delivery/uat-{run}-{source[:10]}'
api_root = f'https://api.github.com/repos/{repository}'


def request(endpoint, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(api_root + endpoint, data=body, method='POST', headers={
        'Authorization': 'Bearer ' + os.environ['BUILD_CHECKPOINT_TOKEN'],
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
    })
    with urllib.request.urlopen(req, timeout=120) as response:
        return json.load(response)


elements = []
for path in sorted(Path('dist').glob('*')):
    if not path.is_file():
        continue
    content = path.read_bytes()
    # Each ASCII blob remains small enough for the connected GitHub reader.
    for index, offset in enumerate(range(0, len(content), 180000)):
        name = f'{path.name}.part-{index:04d}.b64'
        encoded = base64.b64encode(content[offset:offset + 180000]).decode('ascii')
        blob = request('/git/blobs', {'content': encoded, 'encoding': 'utf-8'})
        elements.append({'path': name, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})
manifest = request('/git/blobs', {'content': json.dumps({
    'source_commit': source, 'run_number': int(run),
    'files': {p.name: p.stat().st_size for p in Path('dist').glob('*') if p.is_file()},
    'chunk_bytes': 180000,
}, indent=2), 'encoding': 'utf-8'})
elements.append({'path': 'MANIFEST.json', 'mode': '100644', 'type': 'blob', 'sha': manifest['sha']})
tree = request('/git/trees', {'tree': elements})
commit = request('/git/commits', {'message': f'Private UAT build {run} from {source}', 'tree': tree['sha'], 'parents': []})
request('/git/refs', {'ref': 'refs/heads/' + checkpoint, 'sha': commit['sha']})
print(json.dumps({'private_build_checkpoint': checkpoint, 'tree_sha': tree['sha'], 'files': len(elements)}))
