#!/usr/bin/env python3
"""Prepare and verify exactly three saved searches for the UAT broker 28."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from phase1_native_account_readiness import SECRET_NAME, validate_access
from phase23_preflight import API, http
from verify_uat1821_spatial_cases import (SavedSearchPreparationError, check_preparation,
                                         prepare_broker_saved_searches)


ROOT = Path(__file__).resolve().parents[1]
BACKEND_TREE = 'bc0e96b8266f062b7fde166ba0451148ec2402f1'
BRANCH = 'refs/heads/work/map-search-ux-1820-20261117'
FIX = '647edc35f4957fbfc9e4895adf17685d9a6a41eb'


def guard(env):
    source = env.get('GITHUB_SHA', '')
    check_preparation(env.get('GITHUB_ACTIONS') == 'true'
                      and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend'
                      and env.get('GITHUB_EVENT_NAME') == 'push' and env.get('GITHUB_REF') == BRANCH
                      and re.fullmatch('[a-f0-9]{40}', source), 'private_pr193_push_context_required')
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    check_preparation(git('rev-parse', 'HEAD') == source and
                      git('rev-parse', 'HEAD:backend-api-runtime') == BACKEND_TREE,
                      'approved_source_or_frankfurt_backend_mismatch')
    git('merge-base', '--is-ancestor', FIX, source)


def run(receipt):
    token = None
    try:
        raw = os.environ.pop(SECRET_NAME, '')
        try:
            access = validate_access(raw)
        except ValueError as error:
            raise SavedSearchPreparationError(str(error)) from None
        del raw
        phone = access['phones']['broker'].lstrip('+')
        if phone.startswith('00'):
            phone = phone[2:]
        check_preparation(phone == '12025550104', 'approved_broker_contact_mismatch')
        code, _ = http('POST', '/auth/whatsapp/start', {'phone': '+' + phone, 'intent': 'login'})
        receipt['otp_start_http'] = code
        check_preparation(code == 200, 'normal_test_login_start_failed')
        code, body = http('POST', '/auth/whatsapp/verify', {'phone': '+' + phone, 'code': access['otp']})
        del access
        token = body.get('data', {}).get('token')
        receipt['otp_verify_http'] = code
        check_preparation(code == 200 and isinstance(token, str) and bool(token), 'normal_test_login_verify_failed')
        prepare_broker_saved_searches(token, receipt)
        receipt['status'] = 'PASS'
    except Exception as error:
        receipt.update(status='BLOCKED', reason=str(error) if isinstance(error, SavedSearchPreparationError)
                       else type(error).__name__)
    finally:
        if isinstance(token, str) and token:
            try:
                receipt['logout_http'], _ = http('POST', '/auth/logout', {}, token=token)
                receipt['revoked_auth_me_http'], _ = http('GET', '/auth/me', token=token)
                receipt['temporary_session_revoked'] = receipt['logout_http'] == 200 and receipt['revoked_auth_me_http'] == 401
            except Exception:
                receipt['temporary_session_revoked'] = False
            if not receipt['temporary_session_revoked']:
                receipt.update(status='BLOCKED', reason='temporary_session_cleanup_unconfirmed')


def main():
    guard(os.environ)
    receipt = {'status': 'BLOCKED', 'api': API, 'source_commit': os.environ['GITHUB_SHA'],
               'utc': datetime.now(timezone.utc).isoformat(), 'run_id': os.environ['GITHUB_RUN_ID']}
    run(receipt)
    path = ROOT / 'uat1822-broker-proof'
    path.mkdir(mode=0o700, exist_ok=True)
    (path / 'SAVED_SEARCHES.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    count = sum(item.get('readback_verified', False) for item in receipt.get('saved_searches', []))
    print(f"UAT1822_SAVED_SEARCHES status={receipt['status']} verified={count} reason={receipt.get('reason', '-')}")
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print('UAT1822_SAVED_SEARCH_CONTEXT_REJECTED', file=sys.stderr)
        sys.exit(2)
