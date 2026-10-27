#!/usr/bin/env python3
"""Optional CI import; absent config keeps client push OFF, wrong config fails closed."""
import base64
import json
import os
from pathlib import Path
from prepare_uat_firebase import PACKAGE, PROJECT, SENDER, validate, write_properties


def main():
    output = Path(__file__).resolve().parents[1] / 'mobile_app/android/firebase-uat.properties'
    encoded = os.environ.get('AQER_UAT_GOOGLE_SERVICES_JSON_BASE64', '')
    if not encoded:
        if output.exists():
            output.unlink()
        print(json.dumps({'firebase_client_configured': False, 'client_push_enabled': False,
                          'reason': 'owner Android configuration not supplied'}))
        return 0
    try:
        if len(encoded) > 90000:
            raise ValueError('Configuration too large')
        raw = base64.b64decode(encoded, validate=True)
        config = validate(raw)
        write_properties(config, output, True)
    except (ValueError, OSError):
        print('UAT Firebase configuration rejected; no credentials are logged.')
        return 1
    print(json.dumps({'firebase_client_configured': True, 'client_push_enabled': True,
                      'package': PACKAGE, 'project': PROJECT, 'sender': SENDER}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
