import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from phase23_build_readiness import FIREBASE_NAME, SIGNING_NAMES, readiness


class BuildReadinessTest(unittest.TestCase):
    def test_no_names_configured_does_not_claim_stable_signing_or_push(self):
        receipt = readiness({})
        self.assertFalse(receipt['firebase_client_secret_present'])
        self.assertFalse(receipt['all_signing_names_present'])
        self.assertEqual(receipt['signing_variable_presence'], dict.fromkeys(SIGNING_NAMES, False))
        self.assertFalse(receipt['stable_signing_used_for_build'])
        self.assertFalse(receipt['signing_key_material_verified'])
        self.assertFalse(receipt['real_fcm_delivery_tested'])

    def test_all_names_present_is_not_valid_key_material_or_an_enabled_build(self):
        env = {'PHASE23_HAS_' + name: 'true' for name in (*SIGNING_NAMES, FIREBASE_NAME)}
        receipt = readiness(env)
        self.assertTrue(receipt['all_signing_names_present'])
        self.assertTrue(receipt['firebase_client_secret_present'])
        self.assertFalse(receipt['signing_key_material_verified'])
        self.assertFalse(receipt['stable_signing_used_for_build'])
        self.assertFalse(receipt['real_fcm_delivery_tested'])
        for missing in SIGNING_NAMES:
            self.assertFalse(readiness(dict(env, **{'PHASE23_HAS_' + missing: 'false'}))['all_signing_names_present'])

    def test_raw_signing_values_are_never_consumed_or_exposed(self):
        env = {name: 'SENSITIVE_SENTINEL' for name in (*SIGNING_NAMES, FIREBASE_NAME)}
        receipt = readiness(env)
        self.assertEqual(receipt, readiness({}))
        self.assertNotIn('SENSITIVE_SENTINEL', json.dumps(receipt))
        for value in ['SENSITIVE_SENTINEL', 'TRUE', '1', True, '']:
            with self.subTest(type=type(value).__name__), self.assertRaisesRegex(ValueError, '^presence_input_must_be_boolean_text$'):
                readiness({'PHASE23_HAS_' + FIREBASE_NAME: value})


if __name__ == '__main__':
    unittest.main()
