#!/usr/bin/env python3
"""Relay one bounded ciphertext-only segment from the current exact-source build."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            result.remove_header('Authorization')
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--part', required=True, type=int)
    args = parser.parse_args()
    assert 0 <= args.part < 32
    policy = json.loads(Path('docs/PUBLIC_UAT_DELIVERY.json').read_text())
    assert policy['repository'] == os.environ['GITHUB_REPOSITORY']
    source, run = os.environ['GITHUB_SHA'], int(os.environ['GITHUB_RUN_ID'])
    root = 'https://api.github.com/repos/' + policy['repository']
    opener = urllib.request.build_opener(SafeRedirect())
    headers = {'Authorization': 'Bearer ' + os.environ['APK_READ_TOKEN'], 'Accept': 'application/vnd.github+json'}
    def get(path):
        with opener.open(urllib.request.Request(root + path, headers=headers), timeout=120) as response:
            return response.read()
    jobs = json.loads(get(f'/actions/runs/{run}/jobs?per_page=100'))['jobs']
    required = ['Tracked source checkpoint', 'Laravel original regression', 'Disposable PostgreSQL 17 and PostGIS',
                'UAT Docker PNG runtime', 'Flutter broker experience and UAT APK']
    for name in required:
        match = next(j for j in jobs if j['name'] == name)
        assert match['conclusion'] == 'success' and match['head_sha'] == source and match['run_id'] == run
    build = next(j for j in jobs if j['name'] == required[-1])
    raw = get(f"/actions/jobs/{build['id']}/logs").decode('utf-8-sig')
    groups = list(re.finditer(r'CODEX_CMS_BEGIN (\{[^\r\n]+\})\r?\n(.*?)CODEX_CMS_END (\d+)', raw, re.S))
    assert len(groups) == 32
    group = groups[args.part]
    meta = json.loads(group[1])
    assert meta['delivery_part'] == int(group[3]) == args.part and meta['delivery_parts'] == 32
    assert meta['native_meta']['source_commit'] == meta['proof']['source_commit'] == source
    assert meta['recipient_sha256'] == policy['recipient_sha256']
    assert meta['proof']['apksigner'] == meta['proof']['zip_crc'] == 'passed'
    data = [(int(i), value) for i, value in re.findall(r'CODEX_CMS_DATA (\d+) ([A-Za-z0-9+/=]+)', group[2])]
    assert [i for i, _ in data] == list(range(meta['cipher_chunks']))
    encrypted = b''.join(base64.b64decode(value, validate=True) for _, value in data)
    assert len(encrypted) == meta['cipher_bytes'] <= 3_000_000
    assert hashlib.sha256(encrypted).hexdigest() == meta['cipher_sha256']
    assert encrypted[:1] == b'\x30' and meta['cipher'] == 'CMS-AES256GCM-RSAOAEP-SHA256'
    print('CODEX_CMS_BEGIN ' + json.dumps(meta, sort_keys=True))
    for i, value in data:
        print(f'CODEX_CMS_DATA {i} {value}')
    print('CODEX_CMS_END ' + str(args.part))


if __name__ == '__main__':
    main()
