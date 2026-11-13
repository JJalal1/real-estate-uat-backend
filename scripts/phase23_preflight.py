#!/usr/bin/env python3
"""Bounded UAT readiness: normal OTP, server identity, logout; no fixtures."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

from phase1_native_account_readiness import SECRET_NAME, validate_access

API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
BRANCH = 'refs/heads/work/phase23-acceptance-20261111'
TREES = {'mobile_app': '3db0f5c725a58202ccf10d4170d85f0cca62778c',
         'backend-api-runtime': '76dcc5b61ed2bf55d05935289d09885182fef96e'}


class GateError(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http(method, path, body=None, token=None):
    if method not in {'GET', 'POST'} or not path.startswith('/') or path.startswith('//'):
        raise GateError('invalid_preflight_request')
    headers = {'Accept': 'application/json', 'User-Agent': 'AQER-Phase23-Preflight'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    data = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    request = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=25) as response:
            code, raw = response.status, response.read(2000001)
    except urllib.error.HTTPError as error:
        code, raw = error.code, error.read(2000001)
    if len(raw) > 2000000:
        raise GateError('response_too_large')
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        raise GateError('non_json_response') from None
    if not isinstance(value, dict):
        raise GateError('unexpected_response_shape')
    return code, value


def check_actor(alias, phone, otp, transport=http):
    receipt = {'alias': alias, 'status': 'BLOCKED', 'scope': 'API login only; no Android acceptance'}
    token = None
    try:
        code, _ = transport('POST', '/auth/whatsapp/start', {'phone': phone, 'intent': 'login'})
        receipt['otp_start_http'] = code
        if code != 200:
            raise GateError('normal_login_start_failed')
        code, body = transport('POST', '/auth/whatsapp/verify', {'phone': phone, 'code': otp})
        data = body.get('data', {})
        token = data.get('token') if isinstance(data, dict) else None
        receipt['otp_verify_http'] = code
        if not isinstance(token, str) or not token or code != 200:
            raise GateError('normal_login_verify_failed')
        code, body = transport('GET', '/auth/me', token=token)
        data = body.get('data', {})
        user = data.get('user', {}) if isinstance(data, dict) else {}
        receipt['auth_me_http'] = code
        if code != 200 or not isinstance(user, dict) or not isinstance(user.get('id'), int):
            raise GateError('normal_identity_not_verified')
        if alias == 'broker' and (user['id'] != 28 or user.get('account_type') != 'broker'):
            raise GateError('expected_broker_identity_mismatch')
        receipt.update(actor_id=user['id'], account_type=user.get('account_type'),
                       roles=user.get('roles', []), permission_count=len(user.get('permissions', [])))
        receipt['status'] = 'PASS'
    except Exception as error:
        receipt['reason'] = str(error) if isinstance(error, GateError) else type(error).__name__
    finally:
        if isinstance(token, str) and token:
            try:
                code, _ = transport('POST', '/auth/logout', {}, token=token)
                receipt['logout_http'] = code
                revoked, _ = transport('GET', '/auth/me', token=token)
                receipt['revoked_auth_me_http'] = revoked
                receipt['session_closed'] = code == 200 and revoked == 401
            except Exception as error:
                receipt['session_closed'] = False
                receipt['cleanup_error'] = type(error).__name__
            token = None
            if not receipt.get('session_closed'):
                receipt.update(status='BLOCKED', reason='test_session_cleanup_unconfirmed')
    return receipt


def guard(env):
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and env.get('GITHUB_EVENT_NAME') == 'push' and
            re.fullmatch('[0-9a-f]{40}', env.get('GITHUB_SHA', ''))):
        raise GateError('explicit_phase23_ci_context_required')
    root = Path(__file__).resolve().parents[1]
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
    if git('rev-parse', 'HEAD') != env['GITHUB_SHA']:
        raise GateError('source_checkout_mismatch')
    for component, expected in TREES.items():
        if git('rev-parse', 'HEAD:' + component) != expected:
            raise GateError('unreviewed_product_tree')


def main():
    guard(os.environ)
    receipt = {'scope': 'Phase23 preflight, not acceptance', 'status': 'BLOCKED',
               'source_sha': os.environ['GITHUB_SHA'], 'product_trees': TREES,
               'run_id': os.environ['GITHUB_RUN_ID'], 'api': API,
               'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'fixtures_created': False, 'native_executed': False, 'actors': []}
    try:
        raw = os.environ.pop(SECRET_NAME, '')
        access = validate_access(raw)
        del raw
        receipt['configured_aliases'] = sorted(access['phones'])
        receipt['missing_aliases'] = sorted({'broker', 'support', 'regular'} - set(access['phones']))
        code, body = http('GET', '/health')
        receipt['health'] = {'http': code, 'database': body.get('database'), 'postgis': body.get('postgis')}
        if code != 200 or body.get('database') is not True or body.get('postgis') is not True:
            raise GateError('uat_health_not_ready')
        for alias, phone in access['phones'].items():
            receipt['actors'].append(check_actor(alias, phone, access['otp']))
        del access
        receipt['status'] = ('PASS' if not receipt['missing_aliases'] and
                             all(a['status'] == 'PASS' for a in receipt['actors']) else 'BLOCKED')
    except Exception as error:
        receipt['reason'] = str(error) if isinstance(error, GateError) else type(error).__name__
    out = Path('phase23-public')
    out.mkdir(mode=0o700, exist_ok=True)
    (out / 'PREFLIGHT.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print('AQER_PHASE23_PREFLIGHT ' + json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except GateError as error:
        print('AQER_PHASE23_CONTEXT_REJECTED ' + str(error))
        sys.exit(2)
