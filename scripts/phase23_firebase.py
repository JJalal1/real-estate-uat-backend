"""Verify the optional UAT client in memory; never return client credentials."""
import hashlib
import json
from pathlib import Path
import re

from phase23_preflight import GateError
from prepare_uat_firebase import PACKAGE, validate

_PREFIX = 'aqer.uat.firebase.'
_FIELDS = {'projectId', 'senderId', 'appId', 'apiKey'}
_BOOL_FIELDS = {'configuration_present', 'client_configured', 'client_push_enabled',
                'compiled_configuration_verified', 'real_fcm_delivery_tested'}


def disabled_receipt():
    return {**{key: False for key in sorted(_BOOL_FIELDS)}, 'config_fingerprint': None}


def validate_receipt(receipt):
    if (not isinstance(receipt, dict) or
            set(receipt) != _BOOL_FIELDS | {'config_fingerprint'} or
            any(type(receipt[key]) is not bool for key in _BOOL_FIELDS) or
            receipt['real_fcm_delivery_tested'] is not False):
        raise GateError('uat_firebase_receipt_invalid')
    configured = receipt['client_configured']
    if (receipt['client_push_enabled'] != configured or
            receipt['compiled_configuration_verified'] != configured or
            (configured and not receipt['configuration_present'])):
        raise GateError('uat_firebase_receipt_inconsistent')
    fingerprint = receipt['config_fingerprint']
    if receipt['configuration_present']:
        if not isinstance(fingerprint, str) or not re.fullmatch('[a-f0-9]{64}', fingerprint):
            raise GateError('uat_firebase_fingerprint_required')
    elif fingerprint is not None:
        raise GateError('uat_firebase_absent_configuration_fingerprint')


def verify_compiled_configuration(archive, properties):
    """Return safe configuration evidence, not a provider-delivery claim.

    ``properties`` is the fixed local output of import_ci_uat_firebase.py.
    Disabled configuration remains OFF. A requested client must match the
    approved UAT identity, its recomputed fingerprint and the actual APK DEX.
    """
    receipt = disabled_receipt()
    dex = [archive.read(name) for name in archive.namelist()
           if re.fullmatch(r'classes[0-9]*\.dex', name)]
    if not dex:
        raise GateError('uat_apk_dex_required')
    if any(b'-----BEGIN PRIVATE KEY-----' in part or
           b'-----BEGIN RSA PRIVATE KEY-----' in part or
           b'-----BEGIN EC PRIVATE KEY-----' in part for part in dex):
        raise GateError('server_private_key_forbidden_in_android')
    properties = Path(properties)
    if not properties.exists():
        return receipt
    try:
        if not 0 < properties.stat().st_size <= 65536:
            raise ValueError()
        entries = [line.split('=', 1) for line in properties.read_text(encoding='ascii').splitlines()]
        if any(len(pair) != 2 for pair in entries):
            raise ValueError()
        values = dict(entries)
        if (len(values) != len(entries) or
                set(values) != {_PREFIX + key for key in _FIELDS | {'fingerprint', 'enabled'}} or
                values[_PREFIX + 'enabled'] not in {'true', 'false'}):
            raise ValueError()
        config = validate(json.dumps({
            'project_info': {'project_id': values[_PREFIX + 'projectId'],
                             'project_number': values[_PREFIX + 'senderId']},
            'client': [{'client_info': {
                'mobilesdk_app_id': values[_PREFIX + 'appId'],
                'android_client_info': {'package_name': PACKAGE}},
                'api_key': [{'current_key': values[_PREFIX + 'apiKey']}]}],
        }).encode())
        fingerprint = hashlib.sha256(json.dumps(config, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        if values[_PREFIX + 'fingerprint'] != fingerprint:
            raise ValueError()
        enabled = values[_PREFIX + 'enabled'] == 'true'
    except (OSError, UnicodeError, ValueError):
        # Paths, client values and raw parser errors never cross this boundary.
        raise GateError('uat_firebase_properties_invalid') from None
    if enabled and not all(any(config[field].encode() in part for part in dex) for field in _FIELDS):
        raise GateError('compiled_uat_firebase_configuration_mismatch')
    receipt.update(configuration_present=True, config_fingerprint=fingerprint,
                   client_configured=enabled, client_push_enabled=enabled,
                   compiled_configuration_verified=enabled)
    validate_receipt(receipt)
    return receipt
