#!/usr/bin/env python3
"""Load the public, explicitly approved durable UAT signing identity."""
import argparse
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
IDENTITY_FILE = ROOT / 'docs/uat-signing-identity.json'
PACKAGE = 'com.aqer.yemen.uat.offline'
APP_NAME = 'عقار أوفلاين اختبار'
PRESENCE_NAMES = ('keystore', 'store_password', 'key_alias', 'key_password', 'certificate_pin')
BOOLEAN_FIELDS = (
    'approved_for_delivery', 'github_secret_storage_verified',
    'first_install_device_verified', 'future_update_pair_verified',
    'private_key_disclosed_in_artifacts',
)
PUBLIC_FIELDS = {
    'schema', 'package', 'application_name', 'certificate_sha256',
    'key_algorithm', 'signature_algorithm', 'first_durable_version',
    'previous_1815_certificate_sha256', 'transition_from_1815',
    'local_data_owner_statement', *BOOLEAN_FIELDS,
}


class IdentityError(ValueError):
    """Fixed public error codes only; no signing material is read here."""


def approval_ready(identity):
    return (identity['approved_for_delivery'] is True and
            identity['github_secret_storage_verified'] is True)


def require_delivery_approval(identity):
    if not approval_ready(identity):
        raise IdentityError('durable_uat_delivery_approval_or_secret_storage_pending')


def load_public_identity(path=IDENTITY_FILE, *, require_approval=False):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise IdentityError('public_uat_identity_file_required')
    try:
        identity = json.loads(path.read_text(encoding='utf-8'))
    except (ValueError, OSError):
        raise IdentityError('invalid_public_uat_identity') from None
    if not isinstance(identity, dict) or set(identity) != PUBLIC_FIELDS:
        raise IdentityError('public_uat_identity_fields_mismatch')
    if (type(identity['schema']) is not int or identity['schema'] != 1 or
            identity['package'] != PACKAGE or identity['application_name'] != APP_NAME or
            identity['key_algorithm'] != 'RSA4096' or identity['signature_algorithm'] != 'SHA256withRSA' or
            type(identity['first_durable_version']) is not int or identity['first_durable_version'] != 1816 or
            identity['transition_from_1815'] != 'one_time_clean_install_required'):
        raise IdentityError('public_uat_identity_contract_mismatch')
    for field in ('certificate_sha256', 'previous_1815_certificate_sha256'):
        if not isinstance(identity[field], str) or not re.fullmatch(r'[0-9a-f]{64}', identity[field]):
            raise IdentityError('invalid_public_uat_certificate_pin')
    if identity['certificate_sha256'] == identity['previous_1815_certificate_sha256']:
        raise IdentityError('clean_install_transition_requires_distinct_certificate')
    if any(type(identity[field]) is not bool for field in BOOLEAN_FIELDS):
        raise IdentityError('public_uat_approval_flags_must_be_boolean')
    if identity['private_key_disclosed_in_artifacts'] is not False:
        raise IdentityError('private_signing_material_must_not_be_disclosed')
    if not isinstance(identity['local_data_owner_statement'], str):
        raise IdentityError('owner_local_data_statement_required')
    if require_approval:
        require_delivery_approval(identity)
    return identity


def signing_readiness(identity, present, pin_matches):
    if set(present) != set(PRESENCE_NAMES) or any(type(value) is not bool for value in present.values()):
        raise IdentityError('presence_checks_must_be_boolean_only')
    if type(pin_matches) is not bool:
        raise IdentityError('certificate_match_check_must_be_boolean_only')
    approved = approval_ready(identity)
    compatible = approved and all(present.values()) and pin_matches
    if not approved:
        status = 'blocked_pending_delivery_approval_or_verified_secret_storage'
    elif not all(present.values()):
        status = 'blocked_missing_signing_configuration'
    elif not pin_matches:
        status = 'blocked_public_policy_pin_mismatch'
    else:
        status = 'configuration_present_pending_private_key_validation'
    return {
        'present': present, 'approved_certificate_pin_matches': pin_matches,
        'approved_for_delivery': identity['approved_for_delivery'],
        'github_secret_storage_verified': identity['github_secret_storage_verified'],
        'certificate_sha256': identity['certificate_sha256'],
        'package': identity['package'], 'compatible': compatible, 'status': status,
        'signing_material_verified': False, 'apk_built': False,
        'transition_from_1815': identity['transition_from_1815'],
        'upgrade_from_1815_compatible': False, 'installed_device_upgrade_tested': False,
    }


def verify_imported_environment(identity, env):
    require_delivery_approval(identity)
    if not (env.get('AQER_SIGNING_ENVIRONMENT') == 'uat' and
            env.get('AQER_UAT_SIGNING_CONFIGURED') == 'true' and
            env.get('AQER_ALLOW_DEBUG_RELEASE_SIGNING') == 'false' and
            env.get('AQER_UAT_SIGNING_CERT_SHA256') == identity['certificate_sha256']):
        raise IdentityError('imported_signer_does_not_match_approved_public_identity')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-delivery-approval', action='store_true')
    parser.add_argument('--verify-imported-environment', action='store_true')
    parser.add_argument('--github-output', action='store_true')
    args = parser.parse_args()
    identity = load_public_identity(require_approval=args.require_delivery_approval)
    if args.verify_imported_environment:
        verify_imported_environment(identity, os.environ)
    if args.github_output:
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('certificate_sha256=' + identity['certificate_sha256'] + '\n')
            output.write('package=' + identity['package'] + '\n')
            output.write('delivery_approved=' + str(approval_ready(identity)).lower() + '\n')
    print(json.dumps({key: identity[key] for key in (
        'package', 'certificate_sha256', 'approved_for_delivery',
        'github_secret_storage_verified', 'transition_from_1815',
    )}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, IdentityError) else 'public_uat_identity_validation_failed',
              file=sys.stderr)
        raise SystemExit(1) from None
