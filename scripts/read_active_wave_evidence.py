#!/usr/bin/env python3
"""Read bounded metadata or one synthetic preview from a pinned private CI run."""
import argparse
import base64
import hashlib
import json
import os
import re
import urllib.parse
import urllib.request

REPO = 'JJalal1/real-estate-uat-backend'
SOURCE = '526a87f10a63669c747e3ea967d0128e0e95547c'
RUN = 38958017457
JOB = 117167013226
RUN_NUMBER = 69
PREVIEWS = ('home-top.png', 'wave5-home-large.png', 'active-wave-details-1.0.png', 'active-wave-details-2.4.png', 'active-wave-advertiser-1.0.png', 'active-wave-advertiser-2.4.png', 'active-wave-compare-1.0.png', 'active-wave-compare-2.4.png', 'active-wave-save-1.0.png', 'active-wave-save-2.4.png', 'active-wave-directory-1.0.png', 'active-wave-directory-2.4.png')


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = super().redirect_request(req, fp, code, msg, headers, newurl)
        if target is not None and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            target.remove_header('Authorization')
        return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preview', choices=PREVIEWS)
    args = parser.parse_args()
    assert os.environ['GITHUB_REPOSITORY'] == REPO
    root = 'https://api.github.com/repos/' + REPO
    headers = {'Authorization': 'Bearer ' + os.environ['APK_READ_TOKEN'],
               'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
    opener = urllib.request.build_opener(SafeRedirect())

    def request(path):
        return opener.open(urllib.request.Request(root + path, headers=headers), timeout=60)

    def get(path):
        with request(path) as response:
            return json.load(response)

    assert get('')['private'] is True
    run = get('/actions/runs/' + str(RUN))
    assert run['head_sha'] == SOURCE and run['run_number'] == RUN_NUMBER and run['conclusion'] == 'success'
    jobs = get('/actions/runs/' + str(RUN) + '/jobs?per_page=100')['jobs']
    assert len(jobs) == 5 and all(j['conclusion'] == 'success' for j in jobs)
    job = next(j for j in jobs if j['id'] == JOB)
    assert job['head_sha'] == SOURCE and job['run_id'] == RUN
    prefix = bytearray()
    with request('/actions/jobs/' + str(JOB) + '/logs') as response:
        while len(prefix) < 16 * 1024 * 1024:
            block = response.read(65536)
            if not block:
                break
            prefix.extend(block)
            if b'CODEX_APK_BEGIN ' in prefix:
                break
    raw = bytes(prefix).split(b'CODEX_APK_BEGIN ', 1)[0].decode('utf-8')
    proofs = [json.loads(v) for v in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})', raw)]
    assert len(proofs) == 1
    proof = proofs[0]
    assert proof['source_commit'] == SOURCE and proof['version_code'] == 1000 + RUN_NUMBER
    assert proof['package'] == 'com.example.real_estate_mobile'
    assert proof['api'] == 'https://real-estate-uat-api-frankfurt.onrender.com/api'
    assert proof['apksigner'] == proof['zip_crc'] == 'passed'
    assert proof['fonts_match'] == 5 and re.fullmatch('[a-f0-9]{64}', proof['sha256'])
    assert re.fullmatch('[a-f0-9]{64}', proof['certificate_sha256'])
    assert set(proof['architectures']) == {'armeabi-v7a', 'arm64-v8a', 'x86_64'}
    assert 40_000_000 < proof['bytes'] < 60_000_000
    if args.preview:
        metas = [json.loads(v) for v in re.findall(r'CODEX_PREVIEW_BEGIN (\{[^\r\n]+\})', raw)]
        matching = [m for m in metas if m['file'] == args.preview]
        assert len(matching) == 1
        meta = matching[0]
        assert meta['source_commit'] == SOURCE and 0 < meta['bytes'] <= 4_000_000
        found = re.findall(r'CODEX_PREVIEW_DATA ' + re.escape(args.preview) + r' (\d+) ([A-Za-z0-9+/=]+)', raw)
        chunks = {int(i): value for i, value in found}
        assert len(found) == len(chunks) and set(chunks) == set(range(len(chunks)))
        data = base64.b64decode(''.join(chunks[i] for i in range(len(chunks))), validate=True)
        assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) == meta['bytes']
        assert hashlib.sha256(data).hexdigest() == meta['sha256']
        print('CODEX_PREVIEW_BEGIN ' + json.dumps(meta, sort_keys=True))
        for i in range(len(chunks)):
            print('CODEX_PREVIEW_DATA ' + args.preview + ' ' + str(i) + ' ' + chunks[i])
        print('CODEX_PREVIEW_END ' + args.preview)
    else:
        print('ACTIVE_WAVE_APK_EVIDENCE ' + json.dumps(proof, sort_keys=True))
        print('ACTIVE_WAVE_CI_EVIDENCE ' + json.dumps({'run': RUN, 'source': SOURCE, 'jobs': [
            {'id': j['id'], 'name': j['name'], 'conclusion': j['conclusion']} for j in jobs]}, sort_keys=True))
        clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', raw)
        counts = re.findall(r'(\d+) tests passed', clean)
        print('ACTIVE_WAVE_FLUTTER_COUNTS ' + json.dumps(counts))
        metas = [json.loads(v) for v in re.findall(r'CODEX_PREVIEW_BEGIN (\{[^\r\n]+\})', raw)]
        print('ACTIVE_WAVE_PREVIEW_HASHES ' + json.dumps([m for m in metas if m['file'] in PREVIEWS], sort_keys=True))


if __name__ == '__main__':
    main()
