"""Owner-fixture boundaries against an in-memory HTTP model; no network/accounts."""
import copy
import json
import re
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlsplit
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import phase1_native_fixture_api as fixture


def dummy_access():
    # Deliberately generated format-only values; never import task-private data.
    phone = '+' + ''.join(str((index * 3 + 1) % 10) for index in range(9))
    otp = ''.join(str((index * 7 + 2) % 10) for index in range(6))
    return phone, otp


class SyntheticTagSafety(unittest.TestCase):
    def test_synthetic_tag_avoids_otp_redaction_collision_without_weakening_labels(self):
        bad = uuid.UUID('a258147b-cdef-4abc-8def-abcdefabcdef')
        good = uuid.UUID('abcdefab-cdef-4abc-8def-abcdefabcdef')
        with patch.object(fixture.uuid, 'uuid4', side_effect=[bad, good]) as create:
            tag = fixture.new_fixture_tag()
        self.assertEqual(create.call_count, 2)
        self.assertRegex(tag, r'^AQER-C1-[a-f0-9]{12}$')
        self.assertIsNone(re.search(r'[0-9]{6}', tag))

    def test_tag_generation_is_bounded_and_never_adopts_ambiguous_fallback(self):
        bad = uuid.UUID('a258147b-cdef-4abc-8def-abcdefabcdef')
        with patch.object(fixture.uuid, 'uuid4', return_value=bad) as create:
            with self.assertRaisesRegex(fixture.FixtureError, 'synthetic_tag_unavailable'):
                fixture.new_fixture_tag()
        self.assertEqual(create.call_count, 8)

    def test_unavailable_safe_tag_creates_no_business_fixture_and_revokes_api_session(self):
        api = MemoryOwnerApi()
        probe = fixture.FixtureApi(*dummy_access(), '9001', transport=api)
        with patch.object(fixture, 'new_fixture_tag', side_effect=fixture.FixtureError('unambiguous_synthetic_tag_unavailable')):
            with self.assertRaises(fixture.FixtureError):
                probe.bootstrap()
        self.assertIsNone(probe.state)
        self.assertFalse(api.active)
        self.assertEqual((api.properties, api.drafts), api.original)
        self.assertFalse(any(method in {'PUT', 'DELETE'} for method, *_ in api.calls))


class MemoryOwnerApi:
    def __init__(self):
        self.properties = {str(index): {'id': index, 'title': 'protected row ' + str(index),
            'status': 'draft', 'review_status': 'draft', 'images': [], 'updated_at': 'stable'}
            for index in range(101, 126)}
        self.drafts = {}
        for index in range(7):
            key = str(uuid.uuid5(uuid.NAMESPACE_DNS, 'protected-draft-' + str(index)))
            self.drafts[key] = {'key': key, 'property_id': None, 'revision': index + 1,
                               'updated_at': 'stable', 'images': [],
                               'payload': {'fields': {'title': 'protected draft ' + str(index)}}}
        self.original = copy.deepcopy((self.properties, self.drafts))
        self.calls, self.active = [], False
        self.token = 'memory-only-token-private-marker'
        self.actor_id = 28
        self.verify_status = 200
        self.fail_after_put = False
        self.logout_status = 200

    def __call__(self, method, path, body=None, token=None):
        self.calls.append((method, path, copy.deepcopy(body)))
        parsed = urlsplit(path)
        route = parsed.path
        if route == '/auth/whatsapp/start':
            return 200, {'data': {}}, 1
        if route == '/auth/whatsapp/verify':
            self.active = True
            return self.verify_status, {'data': {'token': self.token}}, 1
        if route == '/auth/logout':
            self.active = False
            return self.logout_status, {}, 1
        if route == '/auth/me':
            if not self.active or token != self.token:
                return 401, {}, 1
            return 200, {'data': {'user': {'id': self.actor_id, 'account_type': 'broker'}}}, 1
        if not self.active or token != self.token:
            return 401, {}, 1
        if route in ['/properties/mine/list', '/listing-editor-drafts']:
            rows = list((self.properties if route.startswith('/properties') else self.drafts).values())
            # Smaller server pages prove the collector follows all metadata pages.
            page = int(parse_qs(parsed.query)['page'][0])
            last = max(1, (len(rows) + 9) // 10)
            data = rows[(page-1)*10:page*10]
            return 200, {'data': copy.deepcopy(data), 'meta': {'last_page': last}}, 1
        if route.startswith('/listing-editor-drafts/'):
            key = route.rsplit('/', 1)[1]
            if method == 'GET':
                return (200, {'data': copy.deepcopy(self.drafts[key])}, 1) if key in self.drafts else (404, {}, 1)
            if method == 'PUT':
                self.drafts[key] = {'key': key, 'property_id': None, 'revision': 1,
                    'updated_at': 'stable-new', 'images': [], 'payload': copy.deepcopy(body['payload'])}
                if self.fail_after_put:
                    self.fail_after_put = False
                    raise RuntimeError('arbitrary-private-transport-detail')
                return 200, {'data': copy.deepcopy(self.drafts[key])}, 1
            if method == 'DELETE':
                self.drafts.pop(key, None)
                return 200, {}, 1
        raise AssertionError('unexpected mocked route')

    def deletes(self):
        return [urlsplit(path).path for method, path, _ in self.calls if method == 'DELETE']


class NativeFixtureSafety(unittest.TestCase):
    def setUp(self):
        self.server = MemoryOwnerApi()
        self.phone, self.otp = dummy_access()
        self.api = fixture.FixtureApi(self.phone, self.otp, '9', transport=self.server)

    def assert_secret_free(self, value):
        output = json.dumps(value, ensure_ascii=False)
        for private in [self.phone, self.phone.lstrip('+'), self.otp, self.server.token,
                        'arbitrary-private-transport-detail']:
            self.assertNotIn(private, output)

    def test_construction_and_unknown_cleanup_perform_no_http(self):
        self.assertEqual(self.server.calls, [])
        with self.assertRaisesRegex(fixture.FixtureError, '^known_owner_fixture_state_required$'):
            self.api.cleanup()
        self.assertEqual(self.server.calls, [])

    def test_bootstrap_preserves_all_preexisting_rows_and_adds_only_a_title_label(self):
        receipt = self.api.bootstrap()
        self.assertEqual(receipt['status'], 'PASS')
        self.assertEqual(receipt['before']['properties']['count'], 25)
        self.assertEqual(receipt['before']['drafts']['count'], 7)
        self.assertEqual(len(self.api.state['baseline']['properties']), 25)
        self.assertEqual(len(self.api.state['baseline']['drafts']), 7)
        self.assertTrue(all(row['all_preexisting_unchanged'] for row in receipt['protected'].values()))
        self.assertFalse(receipt['native_journey_executed'])
        self.assertFalse(receipt['property_create_requested'])
        puts = [(path, body) for method, path, body in self.server.calls if method == 'PUT']
        self.assertEqual(len(puts), 1)
        self.assertEqual(puts[0][1]['payload']['fields'], {'title': self.api.state['title']})
        self.assertFalse(puts[0][1]['payload']['type_confirmed'])
        self.assertFalse(puts[0][1]['payload']['purpose_confirmed'])
        for field in ['type', 'purpose', 'latitude', 'longitude', 'property_id']:
            self.assertNotIn(field, puts[0][1]['payload'])
        self.assertEqual(self.server.deletes(), [])
        self.assertEqual(self.server.properties, self.server.original[0])
        for key, old in self.server.original[1].items():
            self.assertEqual(self.server.drafts[key], old)
        self.assertFalse(self.server.active)
        self.assertTrue(receipt['fresh_session_cleaned'])
        self.assertEqual(receipt['revoked_token_http'], 401)
        self.assert_secret_free(receipt)

    def test_cleanup_removes_only_new_unpromoted_tagged_draft_after_native_edits(self):
        self.api.bootstrap()
        key = self.api.state['key']
        self.server.drafts[key]['payload'].update(type='apartment', purpose='rent', step=3)
        self.server.drafts[key]['payload']['fields'].update(title='native edit ' + self.api.state['tag'], bedrooms=3)
        self.server.drafts[key]['images'] = [{'key': 'new-native-only-image'}]
        receipt = self.api.cleanup()
        self.assertEqual(receipt['status'], 'PASS')
        self.assertEqual(self.server.deletes(), ['/listing-editor-drafts/' + key])
        self.assertEqual((self.server.properties, self.server.drafts), self.server.original)
        self.assertFalse(self.api.has_pending_fixture)
        self.assertTrue(receipt['fresh_session_cleaned'])
        self.assert_secret_free(receipt)

    def test_original_uuid_refused_before_any_http(self):
        self.api.bootstrap()
        old = next(iter(self.api.state['baseline']['drafts']))
        self.api.state['key'] = old
        before = len(self.server.calls)
        with self.assertRaisesRegex(fixture.FixtureError, '^new_owned_uuid_required$'):
            self.api.cleanup()
        self.assertEqual(len(self.server.calls), before)
        self.assertEqual(self.server.deletes(), [])

    def test_caller_cannot_substitute_another_new_uuid_and_tag_for_cleanup(self):
        self.api.bootstrap()
        self.api.state.update(key=str(uuid.uuid4()), tag='AQER-C1-' + uuid.uuid4().hex[:12],
                              title='a concurrent new draft')
        before = len(self.server.calls)
        with self.assertRaisesRegex(fixture.FixtureError, '^known_fixture_identity_mismatch$'):
            self.api.cleanup()
        self.assertEqual(len(self.server.calls), before)
        self.assertEqual(self.server.deletes(), [])

    def test_caller_cannot_rewrite_the_protected_baseline(self):
        self.api.bootstrap()
        old = next(iter(self.api.state['baseline']['properties']))
        self.api.state['baseline']['properties'].pop(old)
        before = len(self.server.calls)
        with self.assertRaisesRegex(fixture.FixtureError, '^known_fixture_identity_mismatch$'):
            self.api.cleanup()
        self.assertEqual(len(self.server.calls), before)
        self.assertEqual(self.server.deletes(), [])

    def test_promoted_missing_property_guard_and_foreign_tags_are_never_deleted(self):
        for fault in ['promoted', 'missing', 'foreign-tag', 'promoted-images',
                      'payload-server-property', 'top-server-property']:
            with self.subTest(fault=fault):
                server = MemoryOwnerApi()
                api = fixture.FixtureApi(self.phone, self.otp, '9', transport=server)
                api.bootstrap(); key = api.state['key']; row = server.drafts[key]
                if fault == 'promoted': row['property_id'] = 123
                if fault == 'missing': del row['property_id']
                if fault == 'foreign-tag': row['payload']['fields']['title'] = 'unrelated work'
                if fault == 'promoted-images': row['payload']['promoted_image_keys'] = {'new': 'property-image'}
                if fault == 'payload-server-property': row['payload']['server_property_id'] = 123
                if fault == 'top-server-property': row['server_property_id'] = 123
                with self.assertRaises(fixture.FixtureError): api.cleanup()
                self.assertEqual(server.deletes(), [])
                self.assertFalse(server.active)
                self.assertTrue(api.last_receipt['fresh_session_cleaned'])
                self.assertTrue(api.has_pending_fixture)

    def test_partial_put_failure_keeps_known_cleanup_identity_and_revokes_api_session(self):
        self.server.fail_after_put = True
        with self.assertRaisesRegex(fixture.FixtureError, '^fixture_transport_or_runtime_failed$'):
            self.api.bootstrap()
        self.assertTrue(self.api.has_pending_fixture)
        self.assertTrue(self.api.last_receipt['fresh_session_cleaned'])
        self.assertFalse(self.server.active)
        key = self.api.state['key']
        self.assertIn(key, self.server.drafts)
        self.assert_secret_free(self.api.last_receipt)
        self.assertEqual(self.api.cleanup()['status'], 'PASS')
        self.assertEqual(self.server.deletes(), ['/listing-editor-drafts/' + key])
        self.assertEqual((self.server.properties, self.server.drafts), self.server.original)

    def test_implicit_bootstrap_facts_are_rejected_but_new_fixture_remains_cleanable(self):
        for key, fact in [('type', 'apartment'), ('purpose', 'rent'),
                          ('latitude', 1.25), ('longitude', 2.5), ('bedrooms', 3),
                          ('parking', True), ('sai_terms_accepted', True),
                          ('location_accuracy_m', 1.0), ('unknown_future_fact', 'invented')]:
            with self.subTest(implicit_fact=key):
                server = MemoryOwnerApi()
                def transport(method, path, body=None, token=None):
                    result = server(method, path, body, token)
                    if method == 'PUT':
                        new_key = urlsplit(path).path.rsplit('/', 1)[1]
                        server.drafts[new_key]['payload'][key] = fact
                        result[1]['data']['payload'][key] = fact
                    return result
                api = fixture.FixtureApi(self.phone, self.otp, '9', transport=transport)
                with self.assertRaisesRegex(fixture.FixtureError, '^bootstrap_must_not_fill_facts$'):
                    api.bootstrap()
                self.assertTrue(api.has_pending_fixture)
                self.assertTrue(api.last_receipt['fresh_session_cleaned'])
                self.assertFalse(server.active)
                new_key = api.state['key']
                self.assertEqual(api.cleanup()['status'], 'PASS')
                self.assertEqual(server.deletes(), ['/listing-editor-drafts/' + new_key])
                self.assertEqual((server.properties, server.drafts), server.original)

    def test_unrelated_concurrent_change_is_not_repaired_or_deleted(self):
        self.api.bootstrap(); key = self.api.state['key']
        old = next(iter(self.server.properties))
        self.server.properties[old]['title'] = 'concurrent owner edit'
        with self.assertRaisesRegex(fixture.FixtureError, '^protected_state_observation_inconclusive$'):
            self.api.cleanup()
        self.assertEqual(self.server.deletes(), ['/listing-editor-drafts/' + key])
        self.assertEqual(self.server.properties[old]['title'], 'concurrent owner edit')
        self.assertTrue(self.api.last_receipt['fixture_removed'])
        self.assertTrue(self.api.last_receipt['fresh_session_cleaned'])
        self.assertEqual(self.api.last_receipt['status'], 'BLOCKED')

    def test_wrong_identity_still_revokes_token_and_never_creates_fixture(self):
        self.server.actor_id = 29
        with self.assertRaisesRegex(fixture.FixtureError, '^fixture_expected_actor_required$'):
            self.api.bootstrap()
        self.assertIsNone(self.api.state)
        self.assertFalse(any(method in ['PUT', 'DELETE'] for method, _, _ in self.server.calls))
        self.assertTrue(self.api.last_receipt['fresh_session_cleaned'])
        self.assert_secret_free(self.api.last_receipt)

    def test_token_in_unusual_verify_response_is_also_revoked(self):
        self.server.verify_status = 500
        with self.assertRaisesRegex(fixture.FixtureError, '^fixture_normal_login_verify_failed$'):
            self.api.bootstrap()
        self.assertFalse(self.server.active)
        self.assertTrue(self.api.last_receipt['fresh_session_cleaned'])
        self.assertIsNone(self.api.state)

    def test_finally_revokes_token_even_for_base_exception(self):
        with patch.object(self.api, '_snapshot', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt): self.api.bootstrap()
        self.assertFalse(self.server.active)
        self.assertTrue(self.api.last_receipt['fresh_session_cleaned'])

    def test_unproven_logout_blocks_progress_and_stays_secret_free(self):
        self.server.logout_status = 500
        with self.assertRaisesRegex(fixture.FixtureError, '^fixture_session_cleanup_unproven$'):
            self.api.bootstrap()
        self.assertEqual(self.api.last_receipt['status'], 'BLOCKED')
        self.assertFalse(self.api.last_receipt['fresh_session_cleaned'])
        self.assertTrue(self.api.last_receipt['session_cleanup_unproven'])
        self.assert_secret_free(self.api.last_receipt)

    def test_existing_state_cannot_bootstrap_again(self):
        self.api.bootstrap(); count = len(self.server.calls)
        with self.assertRaisesRegex(fixture.FixtureError, '^existing_fixture_state_protected$'):
            self.api.bootstrap()
        self.assertEqual(len(self.server.calls), count)

    def test_absolute_paths_and_redirects_are_refused(self):
        for path in ['https://foreign.invalid/endpoint', '//foreign.invalid/endpoint', '/\\foreign']:
            with self.assertRaisesRegex(fixture.FixtureError, '^fixture_relative_api_request_required$'):
                self.api._call('GET', path)
        self.assertEqual(self.server.calls, [])
        self.assertIsNone(fixture.NoRedirect().redirect_request(None, None, 307, '', {}, 'https://foreign.invalid'))


class PublicReferenceSafety(unittest.TestCase):
    def test_reference_uses_one_current_unauthenticated_public_get_and_returns_only_ids_titles(self):
        calls = []
        def transport(method, path, body, token):
            calls.append((method, path, body, token))
            return 200, {'data': [{'id': 71, 'title': 'current published reference', 'status': 'published',
                                   'unused_private_marker': 'must not be retained'}]}, 1
        result = fixture.read_public_reference(transport)
        self.assertEqual(result, [{'id': 71, 'title': 'current published reference'}])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], 'GET')
        self.assertTrue(calls[0][1].startswith('/properties?per_page=24&sort=latest&_phase1='))
        self.assertIsNone(calls[0][2]); self.assertIsNone(calls[0][3])
        self.assertNotIn('must not be retained', json.dumps(result))

    def test_empty_error_unpublished_or_unbounded_references_are_not_valid_network_witnesses(self):
        samples = [(503, {'data': []}), (200, {'data': []}), (200, {'data': 'invalid'}),
                   (200, {'data': [{'id': 71, 'title': 'draft', 'status': 'draft'}]}),
                   (200, {'data': [{'id': 71, 'title': 'x'}] * 51}),
                   (200, {'data': [{'id': 71, 'title': 'first'}, {'id': 71, 'title': 'duplicate id'}]})]
        for code, value in samples:
            with self.subTest(code=code, shape=type(value.get('data')).__name__):
                with self.assertRaises(fixture.FixtureError):
                    fixture.read_public_reference(lambda *args: (code, value, 1))

    def test_transport_failure_cannot_supply_a_fallback_or_leak_raw_exception(self):
        def failed(*args):
            raise RuntimeError('private-transport-sentinel')
        with self.assertRaisesRegex(fixture.FixtureError, '^public_reference_transport_or_response_failed$') as result:
            fixture.read_public_reference(failed)
        self.assertNotIn('private-transport-sentinel', str(result.exception))


if __name__ == '__main__':
    unittest.main()
