#!/usr/bin/env python3
"""Recipient-encrypted read-only delivery of the exact green listing-flow UAT installer."""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
import urllib.parse
import urllib.request

REPOSITORY = 'JJalal1/real-estate-uat-backend'
SOURCE = 'fb16ace018911953eaa12c5a3243ce7f1b6dc806'
RUN = 39318522976
RUN_NUMBER = 95
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            redirected.remove_header('Authorization')
        return redirected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--part', type=int, default=0)
    parser.add_argument('--parts', type=int, default=32)
    parser.add_argument('--evidence-only', action='store_true')
    args = parser.parse_args()
    assert 0 <= args.part < args.parts == 32
    assert os.environ['GITHUB_REPOSITORY'] == REPOSITORY
    root = 'https://api.github.com/repos/' + REPOSITORY
    headers = {'Authorization': 'Bearer ' + os.environ['APK_READ_TOKEN'],
               'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
    opener = urllib.request.build_opener(SafeRedirect())

    def get(path):
        with opener.open(urllib.request.Request(root + path, headers=headers), timeout=120) as response:
            return response.read()

    # Keep the original private-only delivery reader unchanged. This separate
    # relay publishes CMS ciphertext only, pinned to the task recipient.
    assert json.loads(get(''))['full_name'] == REPOSITORY
    recipient = Path('.github/apk1095-recipient.pem')
    assert hashlib.sha256(recipient.read_bytes()).hexdigest() == '12f6a686d39cef1b63f90011b979ebaef0a25f431d9f4eb1aa4d114a19c0f5e2'
    run = json.loads(get('/actions/runs/' + str(RUN)))
    assert run['head_sha'] == SOURCE and run['conclusion'] == 'success' and run['run_number'] == RUN_NUMBER
    jobs = json.loads(get('/actions/runs/' + str(RUN) + '/jobs?per_page=100'))['jobs']
    assert len(jobs) == 5 and all(j['conclusion'] == 'success' for j in jobs)
    job = next(j for j in jobs if j['name'] == 'Flutter broker experience and UAT APK')
    assert job['head_sha'] == SOURCE and job['run_id'] == RUN
    raw = get('/actions/jobs/' + str(job['id']) + '/logs').decode('utf-8-sig')
    metas = [json.loads(value) for value in re.findall(r'CODEX_APK_BEGIN (\{[^\r\n]+\})', raw)]
    assert len(metas) == 3
    meta = metas[0]
    assert meta['source_commit'] == SOURCE and meta['parts'] == 3 and 1000000 <= meta['bytes'] <= 80000000
    assert all(m['source_commit'] == SOURCE and m['sha256'] == meta['sha256'] and m['bytes'] == meta['bytes'] and m['chunks'] == meta['chunks'] for m in metas)
    found = re.findall(r'CODEX_APK_DATA (\d+) ([A-Za-z0-9+/=]+)', raw)
    chunks = {int(index): value for index, value in found}
    assert len(found) == len(chunks) == meta['chunks'] and set(chunks) == set(range(meta['chunks']))
    data = b''.join(base64.b64decode(chunks[i], validate=True) for i in range(meta['chunks']))
    assert len(data) == meta['bytes'] and hashlib.sha256(data).hexdigest() == meta['sha256'] and data.startswith(b'PK')
    prefix = raw[:raw.index('CODEX_APK_BEGIN ')]
    proof = [json.loads(value) for value in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})', prefix)]
    assert len(proof) == 1
    proof = proof[0]
    assert proof['source_commit'] == SOURCE and proof['version_code'] == 1000 + RUN_NUMBER
    assert proof['sha256'] == meta['sha256'] and proof['bytes'] == meta['bytes']
    assert proof['apksigner'] == 'passed' and proof['zip_crc'] == 'passed' and proof['fonts_match'] == 5
    assert set(proof['architectures']) == {'armeabi-v7a', 'arm64-v8a', 'x86_64'}
    assert proof['package'] == 'com.example.real_estate_mobile' and proof['api'] == API
    assert re.fullmatch('[0-9a-f]{64}', proof['certificate_sha256'])
    if args.evidence_only:
        print('CODEX_APK_VERIFICATION ' + json.dumps(proof, sort_keys=True))
        clean = re.sub(r'\x1b\[[0-9;]*m', '', prefix)
        summaries = [line for line in clean.splitlines() if 'All tests passed!' in line or 'tests passed.' in line]
        print('CODEX_TEST_SUMMARIES ' + json.dumps(summaries[-3:]))
        print('CODEX_RECIPIENT_SHA256 12f6a686d39cef1b63f90011b979ebaef0a25f431d9f4eb1aa4d114a19c0f5e2')
        return
    start = meta['chunks'] * args.part // args.parts
    end = meta['chunks'] * (args.part + 1) // args.parts
    payload = b''.join(base64.b64decode(chunks[index], validate=True) for index in range(start, end))
    result = subprocess.run([
        'openssl', 'cms', '-encrypt', '-binary', '-aes-256-gcm',
        '-outform', 'DER', '-recip', str(recipient),
        '-keyopt', 'rsa_padding_mode:oaep',
        '-keyopt', 'rsa_oaep_md:sha256',
    ], input=payload, capture_output=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError('Recipient encryption failed; no payload is emitted')
    encrypted = result.stdout
    assert encrypted and encrypted[0] == 0x30 and not encrypted.startswith(b'PK')
    blocks = [encrypted[index:index + 12000] for index in range(0, len(encrypted), 12000)]
    transport = {
        'native_meta': meta, 'proof': proof,
        'delivery_part': args.part, 'delivery_parts': args.parts,
        'first': start, 'end': end,
        'recipient_sha256': '12f6a686d39cef1b63f90011b979ebaef0a25f431d9f4eb1aa4d114a19c0f5e2',
        'cipher': 'CMS-AES256GCM-RSAOAEP-SHA256',
        'cipher_bytes': len(encrypted),
        'cipher_sha256': hashlib.sha256(encrypted).hexdigest(),
        'cipher_chunks': len(blocks),
        'payload_bytes': len(payload),
        'payload_sha256': hashlib.sha256(payload).hexdigest(),
    }
    print('CODEX_CMS_BEGIN ' + json.dumps(transport, sort_keys=True), flush=True)
    for index, block in enumerate(blocks):
        print('CODEX_CMS_DATA ' + str(index) + ' ' + base64.b64encode(block).decode('ascii'))
    print('CODEX_CMS_END ' + str(args.part), flush=True)


if __name__ == '__main__':
    main()

