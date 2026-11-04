#!/usr/bin/env python3
"""Credential-channel preflight only. Does not log in or claim native acceptance."""
import datetime
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
SECRET_NAME = 'AQER_PHASE1_TEST_ACCESS_JSON'
ROLES = {'broker', 'support', 'regular', 'manager', 'advertiser'}
REQUIRED_ROLES = {'broker'}
PHONE_PATTERN = r'\+?[0-9]{7,20}'


def validate_access(raw):
    """Return ephemeral data to the caller; never put it in diagnostics or files."""
    if not raw:
        raise ValueError('secure_test_access_missing')
    if len(raw) > 4096:
        raise ValueError('secure_test_access_invalid')
    try:
        value = json.loads(raw)
        if not isinstance(value, dict) or set(value) != {'otp', 'phones'}:
            raise ValueError
        if not isinstance(value['otp'], str) or not re.fullmatch(r'[0-9]{6}', value['otp']):
            raise ValueError
        phones = value['phones']
        if not isinstance(phones, dict) or not REQUIRED_ROLES <= set(phones) or set(phones) - ROLES:
            raise ValueError
        # Match the existing authentication contract; account-fixture numbers
        # are not restricted to a country or a mobile contact-field format.
        if any(not isinstance(v, str) or not re.fullmatch(PHONE_PATTERN, v.strip())
               for v in phones.values()):
            raise ValueError
        normalized = {role: phone.strip() for role, phone in phones.items()}
        # The backend also treats an international 00 prefix as +. This is only
        # a duplicate-actor guard; the supplied phone is otherwise preserved.
        identities = {(('+' + v[2:]) if v.startswith('00') else v).lstrip('+')
                      for v in normalized.values()}
        if len(identities) != len(phones):
            raise ValueError
        return {'otp': value['otp'], 'phones': normalized}
    except (ValueError, TypeError, KeyError):
        raise ValueError('secure_test_access_invalid') from None


def preflight(env):
    if not (env.get('GITHUB_ACTIONS') == 'true'
            and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend'
            and env.get('GITHUB_REF') == 'refs/heads/work/phase1-completion-20261105'
            and env.get('GITHUB_EVENT_NAME') == 'push'
            and re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', ''))):
        raise ValueError('explicit_phase1_account_context_required')
    receipt = {'scope': 'secure channel preflight only; no Android or UAT action',
               'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'source_commit': env['GITHUB_SHA'], 'api': API,
               'secret_name': SECRET_NAME, 'native_journey_executed': False,
               'uat_login_executed': False, 'fixture_created': False,
               'phase1_accepted': False}
    try:
        access = validate_access(env.get(SECRET_NAME, ''))
        del access
        receipt.update(status='READY_FOR_REVIEWED_NATIVE_HARNESS',
                       secure_channel_configured=True)
    except ValueError as error:
        receipt.update(status='BLOCKED', reason=str(error),
                       secure_channel_configured=False)
    return receipt


def main():
    try:
        receipt = preflight(os.environ)
    except ValueError:
        print('AQER_PHASE1_NATIVE_ACCOUNT_CONTEXT_REJECTED')
        return 2
    out = ROOT / 'phase1-native-account-readiness'
    out.mkdir(mode=0o700, exist_ok=True)
    path = out / 'readiness.json'
    path.write_text(json.dumps(receipt, indent=2) + '\n')
    print('AQER_PHASE1_NATIVE_ACCOUNT_' + receipt['status'])
    # A missing secure channel is a real blocked gate, never a green native run.
    return 2 if receipt['status'] == 'BLOCKED' else 0


if __name__ == '__main__':
    sys.exit(main())
