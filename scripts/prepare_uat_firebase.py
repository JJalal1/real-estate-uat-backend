#!/usr/bin/env python3
"""Validate owner-supplied Android client config; never emit keys or server credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

PACKAGE = 'com.aqer.yemen.uat'
PROJECT = 'aqer-yemen'
SENDER = '982331876719'


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate configuration key')
        result[key] = value
    return result


def validate(raw):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= 65536:
        raise ValueError('Configuration must be a bounded JSON file')
    try:
        config = json.loads(raw.decode('utf-8'), object_pairs_hook=no_duplicate_keys)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError('Invalid Android configuration JSON') from exc
    if not isinstance(config, dict):
        raise ValueError('Expected Android configuration object')
    def reject_server_credentials(value):
        if isinstance(value, dict):
            if any(str(k).lower() in {'private_key', 'private_key_id', 'client_secret', 'refresh_token'} for k in value):
                raise ValueError('Server credentials are forbidden in Android configuration')
            for child in value.values():
                reject_server_credentials(child)
        elif isinstance(value, list):
            for child in value:
                reject_server_credentials(child)
    reject_server_credentials(config)
    info = config.get('project_info')
    if not isinstance(info, dict) or info.get('project_id') != PROJECT or str(info.get('project_number')) != SENDER:
        raise ValueError('Wrong approved Firebase project or sender')
    clients = config.get('client')
    if not isinstance(clients, list):
        raise ValueError('Android client list missing')
    matches = [c for c in clients if isinstance(c, dict) and isinstance(c.get('client_info'), dict)
               and isinstance(c['client_info'].get('android_client_info'), dict)
               and c['client_info']['android_client_info'].get('package_name') == PACKAGE]
    if len(matches) != 1:
        raise ValueError('Expected exactly one approved UAT Android client')
    client = matches[0]
    app_id = client['client_info'].get('mobilesdk_app_id')
    if not isinstance(app_id, str) or not re.fullmatch(r'1:' + SENDER + r':android:[a-fA-F0-9]{8,64}', app_id):
        raise ValueError('Android app ID does not match the approved sender')
    keys = client.get('api_key')
    if not isinstance(keys, list) or len(keys) != 1 or not isinstance(keys[0], dict):
        raise ValueError('Expected one Firebase Android client key')
    api_key = keys[0].get('current_key')
    if not isinstance(api_key, str) or not re.fullmatch(r'[A-Za-z0-9_-]{20,200}', api_key):
        raise ValueError('Invalid Firebase Android client key shape')
    return {'projectId': PROJECT, 'senderId': SENDER, 'appId': app_id, 'apiKey': api_key}


def write_properties(config, output, client_enabled):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.firebase-uat-', dir=output.parent)
    try:
        with os.fdopen(fd, 'w', encoding='ascii') as stream:
            os.fchmod(stream.fileno(), 0o600)
            for key, value in config.items():
                stream.write('aqer.uat.firebase.' + key + '=' + value + '\n')
            fingerprint = hashlib.sha256(json.dumps(config, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            stream.write('aqer.uat.firebase.fingerprint=' + fingerprint + '\n')
            stream.write('aqer.uat.firebase.enabled=' + str(client_enabled).lower() + '\n')
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=Path(__file__).resolve().parents[1] / 'mobile_app/android/firebase-uat.properties')
    parser.add_argument('--enable-client', action='store_true')
    args = parser.parse_args()
    try:
        if args.config.resolve() == args.out.resolve():
            raise ValueError('Input and output must differ')
        config = validate(args.config.read_bytes())
        write_properties(config, args.out, args.enable_client)
    except (ValueError, OSError) as exc:
        # Do not include JSON values or arbitrary paths in CI errors.
        print(json.dumps({'status': 'rejected', 'reason': str(exc) if isinstance(exc, ValueError) else 'Configuration file unavailable'}))
        return 1
    print(json.dumps({'status': 'validated', 'package': PACKAGE, 'project': PROJECT,
                      'sender': SENDER, 'client_enabled': args.enable_client}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
