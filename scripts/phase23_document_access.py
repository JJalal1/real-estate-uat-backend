#!/usr/bin/env python3
"""Check headers of two existing synthetic UAT documents; never read a body."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

from phase23_preflight import API, NoRedirect, guard
from run_phase23_native import Session, native_access

KINDS = ('identity_document', 'selfie')
ROOT = Path(__file__).resolve().parents[1]


def head_document(kind, token=None, opener=None):
    if kind not in KINDS:
        raise ValueError('fixed_synthetic_document_required')
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(
        API + '/account-verification/users/25/documents/' + kind,
        headers=headers, method='HEAD')
    transport = opener or urllib.request.build_opener(NoRedirect())
    try:
        response = transport.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        # Deliberately never call read(), even for errors or unexpected redirects.
        return {'http': response.code,
                'content_type': response.headers.get_content_type(),
                'cache_control': response.headers.get('Cache-Control', ''),
                'nosniff': response.headers.get('X-Content-Type-Options', '').lower() == 'nosniff',
                'redirect_received': 300 <= response.code < 400,
                'body_read': False}


def accepted(row, expected):
    if row['http'] != expected or row['redirect_received']:
        return False
    if expected == 200:
        cache = {value.strip().lower() for value in row['cache_control'].split(',')}
        return row['content_type'] == 'image/png' and {'private', 'no-store'} <= cache
    return True


def run():
    guard(os.environ)
    access = native_access(os.environ)
    os.environ.pop('AQER_PHASE1_TEST_ACCESS_JSON', None)
    os.environ.pop('AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION', None)
    rows = []
    cleanup = []
    for kind in KINDS:
        row = head_document(kind)
        rows.append({'actor': 'guest', 'kind': kind, 'expected': 401,
                     **row, 'pass': accepted(row, 401)})
    for alias, expected in [('advertiser', 200), ('admin', 200), ('erasure', 403)]:
        session = Session(alias, access)
        try:
            session.login()
            for kind in KINDS:
                row = head_document(kind, session.token)
                rows.append({'actor': alias, 'actor_id': session.identity['id'],
                             'kind': kind, 'expected': expected,
                             **row, 'pass': accepted(row, expected)})
        finally:
            cleanup.append({'actor': alias, 'session_closed': session.close()})
    access.clear()
    return {'scope': 'Existing synthetic user25 document HEAD only; no file contents, no URLs from responses, no native acceptance',
            'source_sha': os.environ['GITHUB_SHA'], 'run_id': os.environ['GITHUB_RUN_ID'],
            'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'checks': rows, 'cleanup': cleanup,
            'pass': len(rows) == 8 and all(r['pass'] for r in rows)
                    and all(r['session_closed'] for r in cleanup)}


def main():
    receipt = run()
    out = ROOT / 'phase23-document-access-sealed'
    out.mkdir(mode=0o700)
    cipher = out / 'EVIDENCE.cms'
    with tempfile.TemporaryDirectory(prefix='phase23-doc-head-', dir=os.environ.get('RUNNER_TEMP')) as temp:
        plain = Path(temp) / 'headers.json'
        plain.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
        plain.chmod(0o600)
        subprocess.run(['openssl', 'cms', '-encrypt', '-aes-256-cbc', '-binary', '-outform', 'DER',
                        '-in', str(plain), '-out', str(cipher), str(ROOT / 'scripts/phase23_recipient.pem')],
                       check=True, capture_output=True, timeout=30)
    public = {'source_sha': receipt['source_sha'], 'run_id': receipt['run_id'],
              'pass': receipt['pass'], 'checks': len(receipt['checks']),
              'all_sessions_closed': all(r['session_closed'] for r in receipt['cleanup']),
              'cipher_sha256': hashlib.sha256(cipher.read_bytes()).hexdigest(),
              'file_contents_exported': False, 'native_acceptance': False}
    (out / 'PUBLIC_RECEIPT.json').write_text(json.dumps(public, indent=2) + '\n')
    print('AQER_DOCUMENT_HEADERS ' + json.dumps(public, sort_keys=True))
    return 0 if receipt['pass'] else 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('AQER_DOCUMENT_HEADERS_BLOCKED ' + type(error).__name__)
        sys.exit(2)
