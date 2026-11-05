"""Role login delegates to the existing bounded native Account helper."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1]))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


roles = module('_login_readiness_roles', HERE / 'variants/C2_SOURCE_PROPOSAL/c2_native_roles.py')
native = module('_login_readiness_native', HERE.parents[1] / 'probe_phase1_native_account.py')


def rows(*labels, scrollable=False):
    result = [{'text': value, 'description': '', 'hint': '', 'package': roles.APP,
               'visible': True, 'enabled': True} for value in labels]
    if scrollable:
        result.append({'text': '', 'package': roles.APP, 'visible': True,
                       'enabled': True, 'scrollable': True})
    return result


class Clock:
    def __init__(self): self.value = 0
    def monotonic(self): return self.value
    def sleep(self, seconds): self.value += seconds


class Probe:
    # Use the actual source helper, not a replacement that assumes success.
    wait_account_logout_control = native.NativeAccount.wait_account_logout_control

    def __init__(self, role, *, reveal=True, navigation=True, fail_set=False):
        self.role, self.reveal, self.navigation, self.fail_set = role, reveal, navigation, fail_set
        self.authenticated, self.active_native_role = False, None
        self.native_auth_uncertain, self.recorder = False, None
        self.report, self.private_values, self.inputs = {}, set(), []
        self.state, self.scrolls = 'guest', 0
        self._known_role_memory = roles.KnownRoleMemory({'otp': '123456',
            'phones': {'broker': '15550000001', 'support': '15550000002', 'regular': '15550000003'}})

    def nodes(self):
        if self.state == 'guest': return rows('حسابي', 'تسجيل الدخول أو إنشاء حساب')
        if self.state == 'account_bottom': return rows('تسجيل الخروج')
        if self.state == 'account_top': return rows('الأمان والخصوصية', 'الملف الشخصي', scrollable=True)
        return rows(*(roles.ROLE_NAV[self.role] if self.navigation else {'حسابي'}))

    def matching(self, observed, label):
        return [row for row in observed if label in roles.row_labels(row)]

    def _input(self, kind, label):
        assert self.authenticated is False and self.active_native_role is None
        assert self.native_auth_uncertain is True
        self.inputs.append((kind, label))
        self.report['auth_input_operations_delivered'] = self.report.get('auth_input_operations_delivered', 0) + 1

    def tap(self, label, **kwargs):
        self._input('tap', label)
        if label == 'تأكيد والدخول': self.state = 'role_home'
        elif label == 'حسابي' and self.state != 'guest': self.state = 'account_top'

    def set(self, label, value):
        if self.fail_set: raise ValueError('PRIVATE_PHONE PRIVATE_OTP')
        self._input('set', label)  # Never retain the synthetic credential value.

    def wait(self, label, **kwargs):
        if label == 'تسجيل الخروج': raise native.Blocked('visible_only_wait_cannot_reveal_logout')
        assert label in {'مرحبًا بعودتك', 'تأكيد والدخول'}

    def scroll(self, direction):
        self._input('scroll', direction)
        self.scrolls += 1
        if self.reveal: self.state = 'account_bottom'

    def save(self): pass


class RoleLoginReadinessTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.stack = [patch.object(roles.time, 'monotonic', self.clock.monotonic),
                      patch.object(roles.time, 'sleep', self.clock.sleep)]
        for item in self.stack: item.start(); self.addCleanup(item.stop)

    def test_all_roles_reveal_actual_logout_before_authentication_is_confirmed(self):
        for role in ('broker', 'support', 'regular'):
            with self.subTest(role=role):
                probe = Probe(role)
                result = roles.native_login_role(probe, role)
                self.assertEqual((result['status'], result['auth_stage']), ('PASS_WITHIN_AUTH_UI_SCOPE', 'complete'))
                self.assertTrue(probe.authenticated)
                self.assertEqual(probe.active_native_role, role)
                self.assertFalse(probe.native_auth_uncertain)
                self.assertEqual(probe.scrolls, 1)
                self.assertEqual(probe.inputs.count(('tap', 'تأكيد والدخول')), 1)
                self.assertEqual(probe.inputs.count(('tap', 'حسابي')), 2)  # One initial and one post-auth.
                self.assertEqual(result['auth_input_operations_delivered'], 8)
                self.assertFalse(result['authentication_captures'])
                self.assertFalse(result['auth_hashes_recorded'])

    def test_missing_logout_stops_after_four_scrolls_without_repeating_login_or_extending_wait(self):
        probe = Probe('broker', reveal=False)
        result = roles.native_login_role(probe, 'broker')
        self.assertEqual((result['status'], result['auth_stage']), ('BLOCKED', 'post_auth_logout_control'))
        self.assertEqual(probe.scrolls, 4)
        self.assertGreaterEqual(self.clock.value, 60)
        self.assertLess(self.clock.value, 61)
        self.assertFalse(probe.authenticated)
        self.assertIsNone(probe.active_native_role)
        self.assertTrue(probe.native_auth_uncertain)
        before = list(probe.inputs)
        with self.assertRaises(roles.RouteBlocked): roles.native_login_role(probe, 'broker')
        self.assertEqual(probe.inputs, before)
        self.assertEqual(probe.inputs.count(('tap', 'تأكيد والدخول')), 1)

    def test_returning_from_helper_without_logout_is_not_authentication_proof(self):
        probe = Probe('regular')
        probe.wait_account_logout_control = lambda **kwargs: None
        result = roles.native_login_role(probe, 'regular')
        self.assertEqual((result['status'], result['reason'], result['auth_stage']),
            ('BLOCKED', 'post_auth_account_not_observed', 'post_auth_account_verify'))
        self.assertFalse(probe.authenticated)
        self.assertTrue(probe.native_auth_uncertain)

    def test_fixed_failure_stage_never_exports_exception_credentials_or_node_data(self):
        probe = Probe('broker', fail_set=True)
        result = roles.native_login_role(probe, 'broker')
        self.assertEqual((result['status'], result['reason'], result['auth_stage']),
                         ('BLOCKED', 'controller_operation_blocked', 'phone_entry'))
        encoded = json.dumps(probe.report)
        for private in ('PRIVATE', '15550000001', '123456', 'witness', 'node_path', 'sha256'):
            self.assertNotIn(private, encoded)
        self.assertFalse(probe.authenticated)
        self.assertTrue(probe.native_auth_uncertain)


if __name__ == '__main__': unittest.main()
