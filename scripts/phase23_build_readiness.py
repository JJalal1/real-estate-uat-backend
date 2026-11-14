#!/usr/bin/env python3
"""Report declared CI-secret presence only, never consume signing material."""
import json
import os

SIGNING_NAMES = ('AQER_RELEASE_STORE_FILE', 'AQER_RELEASE_STORE_PASSWORD',
                 'AQER_RELEASE_KEY_ALIAS', 'AQER_RELEASE_KEY_PASSWORD')
FIREBASE_NAME = 'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64'


def readiness(env):
    def present(name):
        value = env.get('PHASE23_HAS_' + name, 'false')
        if value not in {'true', 'false'}:
            raise ValueError('presence_input_must_be_boolean_text')
        return value == 'true'
    signing = {name: present(name) for name in SIGNING_NAMES}
    return {'scope': 'declared_ci_secret_presence_only',
            'firebase_client_secret_present': present(FIREBASE_NAME),
            'signing_variable_presence': signing,
            'all_signing_names_present': all(signing.values()),
            'signing_key_material_verified': False,
            'stable_signing_used_for_build': False,
            'real_fcm_delivery_tested': False}


if __name__ == '__main__':
    try:
        print(json.dumps(readiness(os.environ), sort_keys=True))
    except ValueError:
        raise SystemExit('PHASE23_BUILD_READINESS_INPUT_REJECTED') from None
