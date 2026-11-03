import importlib.util
import json
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'phase1_native_account_readiness.py'
spec = importlib.util.spec_from_file_location('account_readiness', MODULE)
ready = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ready)


class AccountReadinessSafety(unittest.TestCase):
    def env(self, raw=None):
        env = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
               'GITHUB_REF': 'refs/heads/work/phase1-native-account-20261103',
               'GITHUB_EVENT_NAME': 'push', 'GITHUB_SHA': 'a' * 40}
        if raw is not None:
            env[ready.SECRET_NAME] = raw
        return env

    def fake(self):
        # Format-only synthetic placeholders, never usable fixture credentials.
        return {'otp': ''.join(str((index * 3 + 2) % 10) for index in range(6)),
                'phones': {'broker': '+967000000001',
                'support': '+967000000002', 'regular': '+967000000003'}}

    def test_missing_channel_is_blocked_without_native_claim(self):
        result = ready.preflight(self.env())
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(result['reason'], 'secure_test_access_missing')
        self.assertFalse(result['native_journey_executed'])
        self.assertFalse(result['phase1_accepted'])

    def test_ready_channel_does_not_serialize_values_or_claim_journey(self):
        value = self.fake()
        result = ready.preflight(self.env(json.dumps(value)))
        self.assertEqual(result['status'], 'READY_FOR_REVIEWED_NATIVE_HARNESS')
        for secret in [value['otp'], *value['phones'].values()]:
            self.assertNotIn(secret, json.dumps(result))
        self.assertFalse(result['uat_login_executed'])

    def test_minimal_broker_only_is_sufficient_for_c1(self):
        value = self.fake()
        value['phones'] = {'broker': value['phones']['broker']}
        result = ready.preflight(self.env(json.dumps(value)))
        self.assertEqual(result['status'], 'READY_FOR_REVIEWED_NATIVE_HARNESS')
        self.assertFalse(result['native_journey_executed'])

    def test_five_known_actors_are_accepted_without_expanding_c1_scope(self):
        value = self.fake()
        value['phones'].update(manager='+967000000004', advertiser='+967000000005')
        result = ready.preflight(self.env(json.dumps(value)))
        self.assertEqual(result['status'], 'READY_FOR_REVIEWED_NATIVE_HARNESS')
        self.assertFalse(result['uat_login_executed'])
        self.assertFalse(result['fixture_created'])
        for phone in value['phones'].values():
            self.assertNotIn(phone, json.dumps(result))

    def test_unknown_or_missing_required_actor_is_rejected(self):
        for name in ['other', 'production', 'BROKER']:
            value = self.fake(); value['phones'][name] = '+967000000004'
            with self.assertRaisesRegex(ValueError, '^secure_test_access_invalid$'):
                ready.validate_access(json.dumps(value))
        value = self.fake(); value['phones'].pop('broker')
        with self.assertRaisesRegex(ValueError, '^secure_test_access_invalid$'):
            ready.validate_access(json.dumps(value))

    def test_invalid_secret_errors_cannot_echo_arbitrary_input(self):
        marker = 'private-input-must-not-appear'
        for raw in [marker, json.dumps({'otp': marker}), 'null', '[]', 'x' * 5000]:
            with self.subTest(raw_type=type(raw).__name__):
                result = ready.preflight(self.env(raw))
                self.assertEqual(result['status'], 'BLOCKED')
                self.assertNotIn(marker, json.dumps(result))

    def test_other_destinations_and_actor_shapes_fail_closed(self):
        for replacement in ['+19990000000', '+967000000002', 123]:
            value = self.fake(); value['phones']['broker'] = replacement
            with self.assertRaisesRegex(ValueError, '^secure_test_access_invalid$'):
                ready.validate_access(json.dumps(value))
        value = self.fake(); value['extra'] = 'unapproved'
        with self.assertRaises(ValueError):
            ready.validate_access(json.dumps(value))

    def test_unrelated_repository_branch_or_event_is_rejected(self):
        for name, replacement in [('GITHUB_ACTIONS', 'false'), ('GITHUB_REPOSITORY', 'foreign/repo'),
                                  ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request')]:
            env = self.env(); env[name] = replacement
            with self.assertRaisesRegex(ValueError, '^explicit_phase1_account_context_required$'):
                ready.preflight(env)


if __name__ == '__main__':
    unittest.main()
