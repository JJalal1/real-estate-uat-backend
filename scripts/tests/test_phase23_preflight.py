import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('phase23_preflight', Path(__file__).parents[1] / 'phase23_preflight.py')
import sys
sys.path.insert(0, str(Path(__file__).parents[1]))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PreflightSafetyTest(unittest.TestCase):
    def test_normal_session_is_revoked_and_secrets_are_not_in_receipt(self):
        calls = []
        def transport(method, path, body=None, token=None):
            calls.append((method, path))
            if path.endswith('/start'): return 200, {}
            if path.endswith('/verify'): return 200, {'data': {'token': 'private-token'}}
            if path.endswith('/logout'): return 200, {}
            if len(calls) == 3: return 200, {'data': {'user': {'id': 28, 'account_type': 'broker', 'roles': ['broker'], 'permissions': []}}}
            return 401, {}
        result = probe.check_actor('broker', '+123456789', '123456', transport)
        self.assertEqual(result['status'], 'PASS')
        self.assertTrue(result['session_closed'])
        for secret in ['+123456789', '123456', 'private-token']:
            self.assertNotIn(secret, str(result))

    def test_unexpected_identity_still_revokes_session(self):
        def transport(method, path, body=None, token=None):
            if path.endswith('/start'): return 200, {}
            if path.endswith('/verify'): return 200, {'data': {'token': 'private-token'}}
            if path.endswith('/logout'): return 200, {}
            return (200, {'data': {'user': {'id': 999, 'account_type': 'broker'}}}) if not getattr(transport, 'closed', False) else (401, {})
        def tracked(method, path, body=None, token=None):
            result = transport(method, path, body, token)
            if path.endswith('/logout'): transport.closed = True
            return result
        result = probe.check_actor('broker', '+123456789', '123456', tracked)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(result['reason'], 'expected_broker_identity_mismatch')
        self.assertTrue(result['session_closed'])

    def test_unconfirmed_logout_cannot_be_green(self):
        def transport(method, path, body=None, token=None):
            if path.endswith('/start'): return 200, {}
            if path.endswith('/verify'): return 200, {'data': {'token': 'private-token'}}
            if path.endswith('/logout'): return 500, {}
            return 200, {'data': {'user': {'id': 28, 'account_type': 'broker'}}}
        result = probe.check_actor('broker', '+123456789', '123456', transport)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertFalse(result['session_closed'])


if __name__ == '__main__':
    unittest.main()
