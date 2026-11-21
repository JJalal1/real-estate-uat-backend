#!/usr/bin/env python3
"""Optional CI import; absent config keeps client push OFF, wrong config fails closed."""
import argparse
import base64
import json
import os
from pathlib import Path
from prepare_uat_firebase import OFFLINE_PACKAGE, PACKAGE, PROJECT, SENDER, validate, write_properties

CONFIG_ENV = {
    PACKAGE: 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64',
    OFFLINE_PACKAGE: 'AQER_UAT_OFFLINE_GOOGLE_SERVICES_JSON_BASE64',
}


def main(package=PACKAGE):
    output = Path(__file__).resolve().parents[1] / 'mobile_app/android/firebase-uat.properties'
    encoded = os.environ.get(CONFIG_ENV[package], '')
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
        config = validate(raw, package=package)
        write_properties(config, output, True)
    except (ValueError, OSError):
        print('UAT Firebase configuration rejected; no credentials are logged.')
        return 1
    print(json.dumps({'firebase_client_configured': True, 'client_push_enabled': True,
                      'package': package, 'project': PROJECT, 'sender': SENDER}))
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', choices=CONFIG_ENV, default=PACKAGE)
    raise SystemExit(main(parser.parse_args().package))
