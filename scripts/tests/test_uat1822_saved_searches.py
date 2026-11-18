import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_uat1821_spatial_cases import (FILTERS, SavedSearchPreparationError,
                                         prepare_broker_saved_searches)


class BrokerSavedSearchesTests(unittest.TestCase):
    def setUp(self):
        self.actor = 28
        self.accept_patch = True
        self.rows = {7: {'id': 7, 'name': 'Existing polygon', 'filters': FILTERS['10'],
                         'alert_frequency': 'daily', 'is_active': True}}
        self.mutations = []

    def api(self, path, *, body=None, token=None, method=None):
        self.assertEqual(token, 'synthetic-broker-session')
        code = 200
        if path == '/auth/me':
            data = {'user': {'id': self.actor, 'account_type': 'broker', 'account_status': 'active'}}
        elif path == '/saved-searches' and body is None:
            data = list(self.rows.values())
        else:
            self.mutations.append((path, method, body))
            if path == '/saved-searches':
                self.assertEqual(body['alert_frequency'], 'off')
                data = next((r for r in self.rows.values() if r['filters'] == body['filters']), None)
                if data is None:
                    key = max(self.rows) + 1
                    data = self.rows[key] = {'id': key, **body, 'is_active': True}
                    code = 201
            else:
                self.assertEqual((path, method, body), ('/saved-searches/7', 'PATCH', {'alert_frequency': 'off'}))
                if self.accept_patch:
                    self.rows[7]['alert_frequency'] = 'off'
                data = self.rows[7]
        return {'data': copy.deepcopy(data)}, {'http_status': code, 'request_id': 'fixture'}

    def test_reused_search_is_patched_and_read_back_off(self):
        receipt = {}
        prepare_broker_saved_searches('synthetic-broker-session', receipt, self.api)
        self.assertEqual(receipt['actor_id'], 28)
        records = receipt['saved_searches']
        self.assertEqual([(r['id'], r['save_http'], r['alert_frequency'], r['readback_verified']) for r in records],
                         [(7, 200, 'off', True), (8, 201, 'off', True), (9, 201, 'off', True)])
        self.assertTrue(all(r['ownership_verified'] for r in records))
        self.assertEqual(records[0]['alert_patch_http'], 200)
        self.assertEqual(self.rows[7]['name'], 'Existing polygon')
        self.assertTrue(self.rows[7]['is_active'])

    def test_wrong_account_blocks_every_write(self):
        self.actor = 26
        with self.assertRaisesRegex(SavedSearchPreparationError, 'expected_active_test_broker_28_required'):
            prepare_broker_saved_searches('synthetic-broker-session', {}, self.api)
        self.assertEqual(self.mutations, [])

    def test_patch_response_without_off_readback_fails(self):
        self.accept_patch = False
        with self.assertRaisesRegex(SavedSearchPreparationError, 'saved_search_scope_or_alert_readback_mismatch'):
            prepare_broker_saved_searches('synthetic-broker-session', {}, self.api)


if __name__ == '__main__':
    unittest.main()
