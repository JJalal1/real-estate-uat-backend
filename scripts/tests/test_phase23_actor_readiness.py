import copy
import datetime
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import phase23_actor_readiness as probe

NOW = datetime.datetime(2026, 11, 13, tzinfo=datetime.timezone.utc)


def attestation():
    return {'schema': 1, 'api': probe.API, 'project_id': probe.PROJECT,
            'source': 'render_effective_otp_allowlist', 'environment': 'staging',
            'test_otp_enabled': True, 'verified_at_utc': NOW.isoformat(),
            'actors': {alias: {'user_id': actor['id'], 'allowlisted': True}
                       for alias, actor in probe.ACTORS.items()}}


def environment():
    return {probe.ATTESTATION_NAME: json.dumps(attestation()),
            probe.SECRET_NAME: json.dumps({'otp': '123456', 'phones': {'broker': '+15550000001'}})}


def source_text():
    lines = ['public const ERASURE_PHONE=\'+15550000009\';']
    for i, (alias, actor) in enumerate(probe.ACTORS.items()):
        if alias == 'erasure':
            continue
        lines.append("'%s'=>['%s','+1555000000%d','%s']," %
                     (actor['source_alias'], actor['source_email'], i + 2, actor['source_role']))
    return '\n'.join(lines)


def identity(alias):
    actor = probe.ACTORS[alias]
    return {'id': actor['id'], 'account_type': actor['account_type'],
            'is_platform_owner': actor['owner'], 'account_status': 'active',
            'phone_verified_at': '2026-10-26T12:00:00Z',
            'profile_completed_at': '2026-10-26T12:00:00Z', 'roles': list(actor['roles']),
            'phone': 'NEVER_EXPORT_PHONE', 'private_document': 'NEVER_EXPORT_DOCUMENT'}


class NormalTransport:
    def __init__(self, alias='manager'):
        self.alias = alias
        self.closed = False
        self.calls = []
        self.user = identity(alias)
        self.start_status = 200
        self.logout_status = 200
        self.revoked_status = 401
        self.me_status = 200

    def __call__(self, method, path, body=None, token=None):
        self.calls.append((method, path, body, token))
        if path == '/health':
            return 200, {'database': True, 'postgis': True}
        if path.endswith('/start'):
            self.closed = False
            return self.start_status, {'message': 'NEVER_EXPORT_PROVIDER_BODY'}
        if path.endswith('/verify'):
            return 200, {'data': {'token': 'NEVER_EXPORT_TOKEN', 'user': copy.deepcopy(self.user)}}
        if path.endswith('/logout'):
            self.closed = True
            return self.logout_status, {}
        return (self.revoked_status, {}) if self.closed else (self.me_status, {'data': {'user': copy.deepcopy(self.user)}})


class AttestationSafetyTests(unittest.TestCase):
    def assert_no_network(self, env):
        calls = []
        result = probe.run_readiness(env, source_text(), lambda *a, **k: calls.append(a), now=NOW)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(calls, [])
        return result

    def test_missing_gate_blocks_before_even_health_or_secret_read(self):
        result = self.assert_no_network({})
        self.assertEqual(result['reason'], 'effective_otp_allowlist_attestation_required')

    def test_production_or_non_test_route_never_sends_otp(self):
        for field, value in [('environment', 'production'), ('test_otp_enabled', False),
                             ('api', 'https://other.invalid/api'), ('project_id', 'other'),
                             ('source', 'historical_capsule')]:
            with self.subTest(field=field):
                env = environment(); gate = attestation(); gate[field] = value
                env[probe.ATTESTATION_NAME] = json.dumps(gate)
                self.assert_no_network(env)

    def test_each_actor_needs_explicit_current_allowlist_confirmation(self):
        for alias in probe.ACTORS:
            for field, value in [('allowlisted', False), ('user_id', 999), ('user_id', True)]:
                with self.subTest(alias=alias, field=field):
                    env = environment(); gate = attestation(); gate['actors'][alias][field] = value
                    env[probe.ATTESTATION_NAME] = json.dumps(gate)
                    self.assert_no_network(env)

    def test_stale_future_or_timezone_free_attestation_is_refused(self):
        for timestamp in [NOW - datetime.timedelta(days=2), NOW + datetime.timedelta(minutes=2), NOW.replace(tzinfo=None)]:
            env = environment(); gate = attestation(); gate['verified_at_utc'] = timestamp.isoformat()
            env[probe.ATTESTATION_NAME] = json.dumps(gate)
            self.assert_no_network(env)

    def test_invalid_secret_and_unrecognized_actor_cannot_start(self):
        env = environment(); env[probe.SECRET_NAME] = '{}'
        self.assert_no_network(env)
        env = environment(); gate = attestation(); gate['actors']['unknown'] = {'user_id': 100, 'allowlisted': True}
        env[probe.ATTESTATION_NAME] = json.dumps(gate)
        self.assert_no_network(env)

    def test_valid_attestation_contains_no_phone_or_otp(self):
        result = probe.validate_attestation(json.dumps(attestation()), now=NOW)
        self.assertEqual(set(result), {'verified_at_utc', 'source'})


class FixtureMappingTests(unittest.TestCase):
    def test_current_roster_is_parsed_without_copying_old_capsule_aliases(self):
        phones = probe.fixture_phones(source_text())
        self.assertEqual(set(phones), {'advertiser', 'manager', 'admin', 'erasure'})
        self.assertEqual(probe.ACTORS['manager']['source_alias'], 'support')
        self.assertEqual(len(set(phones.values())), 4)

    def test_missing_duplicated_or_wrong_roster_definition_is_rejected(self):
        for value in ['', source_text() + '\n' + source_text(), source_text().replace('support_manager', 'super_admin')]:
            with self.assertRaisesRegex(probe.GateError, 'pinned_fixture_source_invalid'):
                probe.fixture_phones(value)


class PinnedLoginTests(unittest.TestCase):
    def check(self, transport):
        return probe.check_pinned_actor(transport.alias, 'NEVER_EXPORT_PHONE', 'NEVER_EXPORT_OTP', transport)

    def test_all_pinned_identities_login_normally_and_revoke_the_test_session(self):
        for alias in probe.ACTORS:
            with self.subTest(alias=alias):
                transport = NormalTransport(alias)
                result = self.check(transport)
                self.assertEqual(result['status'], 'PASS')
                self.assertTrue(result['session_closed'])
                self.assertEqual([(r[0], r[1]) for r in transport.calls], [
                    ('POST', '/auth/whatsapp/start'), ('POST', '/auth/whatsapp/verify'),
                    ('GET', '/auth/me'), ('POST', '/auth/logout'), ('GET', '/auth/me')])
                self.assertEqual(transport.calls[0][2]['intent'], 'login')
                self.assertNotIn('NEVER_EXPORT', json.dumps(result))

    def test_wrong_id_type_owner_status_or_profile_still_revokes_issued_token(self):
        for field, value in [('id', 999), ('id', True), ('account_type', 'broker'),
                             ('is_platform_owner', True), ('account_status', 'suspended'),
                             ('phone_verified_at', None),
                             ('profile_completed_at', None)]:
            with self.subTest(field=field):
                transport = NormalTransport(); transport.user[field] = value
                result = self.check(transport)
                self.assertEqual(result['reason'], 'expected_actor_identity_mismatch')
                self.assertTrue(result['session_closed'])

    def test_extra_missing_or_duplicate_roles_are_not_accepted_as_manager(self):
        for roles in [['registered_user'], ['registered_user', 'support_manager', 'super_admin'],
                      ['registered_user', 'support_manager', 'support_manager'], ['registered_user', 1]]:
            transport = NormalTransport(); transport.user['roles'] = roles
            result = self.check(transport)
            self.assertEqual(result['reason'], 'expected_actor_roles_mismatch')
            self.assertTrue(result['session_closed'])

    def test_me_identity_is_checked_independently_from_verify_response(self):
        transport = NormalTransport()
        def switch_after_verify(*args, **kwargs):
            result = transport(*args, **kwargs)
            if args[1].endswith('/verify'):
                transport.user['id'] = 999
            return result
        result = probe.check_pinned_actor('manager', 'NEVER_EXPORT_PHONE', 'NEVER_EXPORT_OTP', switch_after_verify)
        self.assertEqual(result['reason'], 'expected_actor_identity_mismatch')
        self.assertTrue(result['session_closed'])

    def test_login_failure_does_not_replay_or_try_another_endpoint(self):
        transport = NormalTransport(); transport.start_status = 429
        result = self.check(transport)
        self.assertEqual(result['reason'], 'normal_login_start_failed')
        self.assertEqual(len(transport.calls), 1)

    def test_logout_failure_or_live_token_prevents_ready_result(self):
        for field in ['logout_status', 'revoked_status']:
            transport = NormalTransport(); setattr(transport, field, 200 if field == 'revoked_status' else 500)
            result = self.check(transport)
            self.assertEqual(result['reason'], 'test_session_cleanup_unconfirmed')
            self.assertFalse(result['session_closed'])

    def test_exception_body_is_never_published_and_cleanup_is_attempted(self):
        transport = NormalTransport()
        def fail_me(*args, **kwargs):
            if args[1] == '/auth/me' and not transport.closed:
                raise RuntimeError('NEVER_EXPORT_TOKEN NEVER_EXPORT_PHONE')
            return transport(*args, **kwargs)
        result = probe.check_pinned_actor('manager', 'NEVER_EXPORT_PHONE', 'NEVER_EXPORT_OTP', fail_me)
        self.assertEqual(result['reason'], 'RuntimeError')
        self.assertTrue(result['session_closed'])
        self.assertNotIn('NEVER_EXPORT', json.dumps(result))


class BoundedReadinessTests(unittest.TestCase):
    def test_success_is_readiness_only_and_never_native_or_acceptance(self):
        phones = probe.fixture_phones(source_text())
        by_phone = {phone: NormalTransport(alias) for alias, phone in phones.items()}
        active = None
        def transport(method, path, body=None, token=None):
            nonlocal active
            if path == '/health':
                return 200, {'database': True, 'postgis': True}
            if path.endswith('/start'):
                active = by_phone[body['phone']]
            return active(method, path, body, token)
        result = probe.run_readiness(environment(), source_text(), transport, now=NOW)
        self.assertEqual(result['status'], 'AVAILABLE_NOT_NATIVE_ACCEPTED')
        self.assertEqual(len(result['actors']), 4)
        for key in ['fixtures_created', 'roles_changed', 'account_deleted', 'native_executed', 'acceptance_items_closed']:
            self.assertFalse(result[key])
        self.assertNotIn('NEVER_EXPORT', json.dumps(result))
        self.assertNotIn('123456', json.dumps(result))

    def test_actor_failure_stops_remaining_logins(self):
        transport = NormalTransport(); transport.start_status = 429
        result = probe.run_readiness(environment(), source_text(), transport, now=NOW)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(len(result['actors']), 1)
        self.assertEqual(len(transport.calls), 2)  # health + one start; no retry

    def test_failed_health_never_attempts_login(self):
        calls = []
        def transport(*args, **kwargs):
            calls.append(args)
            return 503, {}
        result = probe.run_readiness(environment(), source_text(), transport, now=NOW)
        self.assertEqual(result['reason'], 'uat_health_not_ready')
        self.assertEqual(calls, [('GET', '/health')])


if __name__ == '__main__':
    unittest.main()
