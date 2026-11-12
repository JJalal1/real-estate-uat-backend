#!/usr/bin/env python3
"""Pinned, normal-login readiness for existing synthetic Phase23 actors only.

This does not create/reactivate accounts, grant roles, read private inboxes or
delete an account. A fresh effective UAT allowlist attestation must be supplied
before any OTP request, so a missing test route cannot fall through to a paid
delivery provider. The shared OTP stays in memory and never enters receipts.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from phase1_native_account_readiness import SECRET_NAME, validate_access
from phase23_preflight import API, GateError, guard, http

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'ipxsgxsqzthpgthwvdno'
ATTESTATION_NAME = 'AQER_PHASE23_ACTOR_ALLOWLIST_ATTESTATION'
SOURCE = 'backend-api-runtime/app/Console/Commands/UatOwnerAcceptancePreflight.php'
# These IDs and memberships were read from the current UAT inventory. The old
# capsule's "support" means manager; Phase23's "support" continues to mean6.
ACTORS = {
    'advertiser': {'id': 25, 'source_alias': 'advertiser',
                   'source_email': 'wave3-owner@example.invalid',
                   'source_role': 'registered_user', 'account_type': 'regular',
                   'roles': ['registered_user'], 'owner': False},
    'manager': {'id': 8, 'source_alias': 'support',
                'source_email': 'uat-support-manager@example.invalid',
                'source_role': 'support_manager', 'account_type': 'regular',
                'roles': ['registered_user', 'support_manager'], 'owner': False},
    'admin': {'id': 9, 'source_alias': 'admin',
              'source_email': 'uat-general-manager@example.invalid',
              'source_role': 'super_admin', 'account_type': 'regular',
              'roles': ['registered_user', 'super_admin'], 'owner': True},
    'erasure': {'id': 66, 'account_type': 'regular',
                'roles': ['registered_user'], 'owner': False},
}
REASONS = frozenset({
    'effective_otp_allowlist_attestation_required', 'allowlist_attestation_invalid',
    'allowlist_attestation_stale', 'allowlist_actor_not_confirmed',
    'pinned_fixture_source_invalid', 'normal_login_start_failed',
    'normal_login_verify_failed', 'expected_actor_identity_mismatch',
    'expected_actor_roles_mismatch', 'test_session_cleanup_unconfirmed',
    'uat_health_not_ready', 'secure_test_access_missing',
    'secure_test_access_invalid',
})


def validate_attestation(raw, now=None):
    """Accept only reviewed, current effective server test-OTP configuration."""
    if not raw:
        raise GateError('effective_otp_allowlist_attestation_required')
    now = now or datetime.datetime.now(datetime.timezone.utc)
    try:
        value = json.loads(raw)
        if not isinstance(value, dict) or set(value) != {
            'schema', 'api', 'project_id', 'source', 'environment',
            'test_otp_enabled', 'verified_at_utc', 'actors',
        }:
            raise ValueError
        if (type(value['schema']) is not int or value['schema'] != 1
                or value['api'] != API or value['project_id'] != PROJECT
                or value['source'] != 'render_effective_otp_allowlist'
                or value['environment'] not in {'uat', 'staging'}
                or value['test_otp_enabled'] is not True):
            raise ValueError
        verified = datetime.datetime.fromisoformat(value['verified_at_utc'].replace('Z', '+00:00'))
        if verified.tzinfo is None:
            raise ValueError
        age = (now - verified).total_seconds()
        if age < -60 or age > 24 * 60 * 60:
            raise GateError('allowlist_attestation_stale')
        actors = value['actors']
        if not isinstance(actors, dict) or set(actors) != set(ACTORS):
            raise ValueError
        for alias, expected in ACTORS.items():
            row = actors[alias]
            if (not isinstance(row, dict) or set(row) != {'user_id', 'allowlisted'}
                    or type(row['user_id']) is not int
                    or row['user_id'] != expected['id'] or row['allowlisted'] is not True):
                raise GateError('allowlist_actor_not_confirmed')
        return {'verified_at_utc': verified.isoformat(), 'source': value['source']}
    except GateError:
        raise
    except (ValueError, TypeError, KeyError, AttributeError):
        raise GateError('allowlist_attestation_invalid') from None


def fixture_phones(source_text):
    """Reuse the public, existing synthetic roster; never guess a new number."""
    result = {}
    for alias, actor in ACTORS.items():
        if alias == 'erasure':
            pattern = r"public const ERASURE_PHONE\s*=\s*'([+0-9]+)'\s*;"
        else:
            pattern = (r"'" + re.escape(actor['source_alias']) + r"'\s*=>\s*\[\s*'"
                       + re.escape(actor['source_email']) + r"'\s*,\s*'([+0-9]+)'\s*,\s*'"
                       + re.escape(actor['source_role']) + r"'\s*\]")
        matches = re.findall(pattern, source_text)
        if len(matches) != 1 or not re.fullmatch(r'\+?[0-9]{7,20}', matches[0]):
            raise GateError('pinned_fixture_source_invalid')
        result[alias] = matches[0]
    if len(set(result.values())) != len(result):
        raise GateError('pinned_fixture_source_invalid')
    return result


def identity_matches(user, expected):
    if (not isinstance(user, dict) or type(user.get('id')) is not int
            or user['id'] != expected['id']
            or user.get('account_type') != expected['account_type']
            or user.get('is_platform_owner') is not expected['owner']
            or user.get('account_status') != 'active'
            or not isinstance(user.get('phone_verified_at'), str)
            or not user['phone_verified_at']
            or not isinstance(user.get('profile_completed_at'), str)
            or not user['profile_completed_at']):
        raise GateError('expected_actor_identity_mismatch')
    roles = user.get('roles')
    if (not isinstance(roles, list) or any(not isinstance(r, str) for r in roles)
            or len(roles) != len(set(roles)) or sorted(roles) != expected['roles']):
        raise GateError('expected_actor_roles_mismatch')


def check_pinned_actor(alias, phone, otp, transport=http):
    expected = ACTORS[alias]
    receipt = {'alias': alias, 'expected_actor_id': expected['id'], 'status': 'BLOCKED',
               'scope': 'normal API login/identity/logout only; no native acceptance'}
    token = None
    try:
        code, _ = transport('POST', '/auth/whatsapp/start', {'phone': phone, 'intent': 'login'})
        receipt['otp_start_http'] = code
        if code != 200:
            raise GateError('normal_login_start_failed')
        code, body = transport('POST', '/auth/whatsapp/verify', {'phone': phone, 'code': otp})
        data = body.get('data', {}) if isinstance(body, dict) else {}
        token = data.get('token') if isinstance(data, dict) else None
        receipt['otp_verify_http'] = code
        if code != 200 or not isinstance(token, str) or not token:
            raise GateError('normal_login_verify_failed')
        identity_matches(data.get('user'), expected)
        code, body = transport('GET', '/auth/me', token=token)
        receipt['auth_me_http'] = code
        if code != 200 or not isinstance(body, dict):
            raise GateError('expected_actor_identity_mismatch')
        data = body.get('data', {})
        user = data.get('user') if isinstance(data, dict) else None
        identity_matches(user, expected)
        receipt.update(status='PASS', actor_id=user['id'], roles=user['roles'],
                       account_type=user['account_type'], is_platform_owner=user['is_platform_owner'])
    except Exception as error:
        receipt['reason'] = str(error) if str(error) in REASONS else type(error).__name__
    finally:
        if isinstance(token, str) and token:
            try:
                code, _ = transport('POST', '/auth/logout', {}, token=token)
                revoked, _ = transport('GET', '/auth/me', token=token)
                receipt.update(logout_http=code, revoked_auth_me_http=revoked,
                               session_closed=code == 200 and revoked == 401)
            except Exception as error:
                receipt.update(session_closed=False, cleanup_error=type(error).__name__)
            token = None
            if not receipt.get('session_closed'):
                receipt.update(status='BLOCKED', reason='test_session_cleanup_unconfirmed')
    return receipt


def run_readiness(env, source_text, transport=http, now=None):
    receipt = {'scope': 'existing pinned synthetic additional actors only',
               'status': 'BLOCKED', 'actors': [], 'fixtures_created': False,
               'roles_changed': False, 'account_deleted': False,
               'native_executed': False, 'acceptance_items_closed': False}
    try:
        # Must precede even /health and credential parsing; no OTP request can
        # escape the explicit effective-configuration gate.
        attestation = validate_attestation(env.get(ATTESTATION_NAME, ''), now=now)
        access = validate_access(env.get(SECRET_NAME, ''))
        phones = fixture_phones(source_text)
        receipt['allowlist_attestation'] = attestation
        code, body = transport('GET', '/health')
        if (code != 200 or not isinstance(body, dict)
                or body.get('database') is not True or body.get('postgis') is not True):
            raise GateError('uat_health_not_ready')
        for alias in ACTORS:
            result = check_pinned_actor(alias, phones[alias], access['otp'], transport)
            receipt['actors'].append(result)
            # Never chain additional logins after a failure/rate limit/unknown
            # session cleanup; diagnose it without automated replays.
            if result['status'] != 'PASS':
                break
        del access, phones
        if len(receipt['actors']) == len(ACTORS) and all(r['status'] == 'PASS' for r in receipt['actors']):
            receipt['status'] = 'AVAILABLE_NOT_NATIVE_ACCEPTED'
    except Exception as error:
        receipt['reason'] = str(error) if str(error) in REASONS else type(error).__name__
    return receipt


def write_sealed(receipt, root=ROOT):
    out = root / 'phase23-pinned-actors-sealed'
    out.mkdir(mode=0o700)
    cipher = out / 'EVIDENCE.cms'
    with tempfile.TemporaryDirectory(prefix='phase23-actors-', dir=os.environ.get('RUNNER_TEMP')) as temp:
        plain = Path(temp) / 'readiness.json'
        plain.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
        plain.chmod(0o600)
        subprocess.run(['openssl', 'cms', '-encrypt', '-aes-256-cbc', '-binary', '-outform', 'DER',
                        '-in', str(plain), '-out', str(cipher), str(root / 'scripts/phase23_recipient.pem')],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    public = {'source_sha': receipt['source_sha'], 'run_id': receipt['run_id'],
              'status': receipt['status'], 'cipher_sha256': hashlib.sha256(cipher.read_bytes()).hexdigest(),
              'plaintext_exported': False, 'native_executed': False,
              'actors': [{'alias': r['alias'], 'status': r['status'],
                          'session_closed': r.get('session_closed', False),
                          **({'reason': r['reason']} if 'reason' in r else {})} for r in receipt['actors']]}
    if 'reason' in receipt:
        public['reason'] = receipt['reason']
    (out / 'PUBLIC_RECEIPT.json').write_text(json.dumps(public, indent=2) + '\n')
    return public


def main():
    guard(os.environ)
    receipt = run_readiness(os.environ, (ROOT / SOURCE).read_text())
    receipt.update(source_sha=os.environ['GITHUB_SHA'], run_id=os.environ['GITHUB_RUN_ID'],
                   utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    public = write_sealed(receipt)
    print('AQER_PHASE23_PINNED_ACTOR_READINESS ' + json.dumps(public, sort_keys=True))
    return 0 if receipt['status'] == 'AVAILABLE_NOT_NATIVE_ACCEPTED' else 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('AQER_PHASE23_PINNED_ACTOR_EXECUTION_BLOCKED ' + type(error).__name__)
        sys.exit(2)
