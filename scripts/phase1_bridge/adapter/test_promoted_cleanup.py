"""Actual response-projection contracts using synthetic in-memory API rows."""
import copy
import importlib.util
from pathlib import Path
import unittest
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('_tested_promoted_cleanup', HERE / 'variants/promoted_cleanup.py')
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)

KEY = '10000000-0000-4000-8000-000000000001'
TAG = 'AQER-C1-123456789abc'
TITLE = 'Synthetic native fixture ' + TAG


class ProjectionApi:
    def __init__(self):
        self.properties = [{'id': i, 'title': 'Existing '+str(i), 'status': 'draft',
                            'review_status': 'draft', 'images': []} for i in range(1, 26)]
        self.drafts = [{'key': str(uuid.UUID(int=i)), 'property_id': None, 'revision': 2,
                        'payload': {'fields': {'title': 'Existing draft '+str(i)}}, 'images': []}
                       for i in range(1, 8)]
        self.state = {'actor_id': 28, 'creation_request_sent': True, 'created_confirmed': True,
            'bootstrap_only_title_label': True, 'key': KEY, 'tag': TAG,
            'baseline': {
                'properties': {str(r['id']): cleanup.digest(cleanup.property_projection(r)) for r in self.properties},
                'drafts': {r['key']: cleanup.digest(cleanup.draft_projection(r)) for r in self.drafts}}}
        # PropertyController.mine() without view=workspace returns detailData:
        # advertiser.id is present, while is_owner is not part of that result.
        self.mine = {'id': 97, 'title': TITLE, 'status': 'draft', 'review_status': 'draft',
                     'type': 'apartment', 'purpose': 'rent', 'floor_number': '2', 'unit_number': None,
                     'advertiser': {'id': 28}, 'images': [{'id': 197}]}
        # PropertyController.show() adds is_owner to that same detailData.
        self.detail = dict(copy.deepcopy(self.mine), is_owner=True)
        self.draft = {'key': KEY, 'property_id': 97, 'revision': 24,
                      'payload': {'fields': {'title': TITLE}}, 'images': []}
        self.calls = []
        self.property_deleted = self.draft_deleted = False

    def __call__(self, method, path):
        self.calls.append((method, path))
        if (method, path) == ('GET', '/auth/me'):
            return 200, {'data': {'user': {'id': 28, 'account_type': 'broker'}}}
        if method == 'GET' and path.startswith('/properties/mine/list?'):
            return 200, {'data': copy.deepcopy(self.properties + ([] if self.property_deleted else [self.mine])), 'meta': {'last_page': 1}}
        if method == 'GET' and path.startswith('/listing-editor-drafts?'):
            return 200, {'data': copy.deepcopy(self.drafts + ([] if self.draft_deleted else [self.draft])), 'meta': {'last_page': 1}}
        if path == '/properties/97':
            if method == 'DELETE':
                self.property_deleted = True
                self.draft['property_id'] = None
                return 200, {}
            return (404, {}) if self.property_deleted else (200, {'data': copy.deepcopy(self.detail)})
        if path == '/listing-editor-drafts/' + KEY:
            if method == 'DELETE':
                self.draft_deleted = True
                return 200, {}
            return (404, {}) if self.draft_deleted else (200, {'data': copy.deepcopy(self.draft)})
        if (method, path) == ('GET', '/property-media/197') and self.property_deleted:
            return 404, {}
        raise AssertionError('Unexpected synthetic API route')


class PromotedCleanupProjectionTests(unittest.TestCase):
    def test_actual_mine_projection_without_owner_flag_pins_and_cleans_only_exact_pair(self):
        api = ProjectionApi()
        helper = cleanup.PromotedFixtureCleanup(api, api.state)
        self.assertNotIn('is_owner', api.mine)
        self.assertEqual(helper.pin_candidate(native_writers_stopped=True)['status'], 'READY')
        self.assertFalse(any(method == 'DELETE' for method, _ in api.calls))
        result = helper.cleanup(native_writers_stopped=True)
        self.assertEqual(result['status'], 'PASS')
        self.assertTrue(result['protected_baseline_restored'])
        self.assertEqual([path for method, path in api.calls if method == 'DELETE'],
                         ['/properties/97', '/listing-editor-drafts/' + KEY])
        self.assertEqual((len(api.properties), len(api.drafts)), (25, 7))

    def test_advertiser_and_detail_owner_proofs_are_both_mandatory(self):
        mutations = [lambda a: a.mine.pop('advertiser'),
            lambda a: a.mine.update(advertiser={'id': 29}),
            lambda a: a.mine.update(is_owner=False),
            lambda a: a.detail.pop('is_owner'),
            lambda a: a.detail.update(is_owner=False),
            lambda a: a.detail.update(is_owner=1),
            lambda a: a.detail.update(advertiser={'id': 29}),
            lambda a: a.detail.update(id=98)]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                api = ProjectionApi(); mutate(api)
                helper = cleanup.PromotedFixtureCleanup(api, api.state)
                result = helper.pin_candidate(native_writers_stopped=True)
                self.assertEqual((result['status'], result['reason']),
                                 ('BLOCKED', 'new_property_ownership_required'))
                self.assertFalse(any(method == 'DELETE' for method, _ in api.calls))

    def test_ownership_fix_keeps_baseline_status_and_pinned_revision_guards(self):
        api = ProjectionApi(); api.properties[0]['title'] = 'Unrelated edit'
        helper = cleanup.PromotedFixtureCleanup(api, api.state)
        self.assertEqual(helper.pin_candidate(native_writers_stopped=True)['reason'], 'preexisting_state_changed')
        api = ProjectionApi(); api.mine['review_status'] = api.detail['review_status'] = 'submitted'
        helper = cleanup.PromotedFixtureCleanup(api, api.state)
        self.assertEqual(helper.pin_candidate(native_writers_stopped=True)['reason'], 'new_property_not_deletable')
        api = ProjectionApi(); helper = cleanup.PromotedFixtureCleanup(api, api.state)
        self.assertEqual(helper.pin_candidate(native_writers_stopped=True)['status'], 'READY')
        api.draft['revision'] += 1
        self.assertEqual(helper.cleanup(native_writers_stopped=True)['reason'], 'pinned_fixture_changed')
        self.assertFalse(any(method == 'DELETE' for method, _ in api.calls))


if __name__ == '__main__':
    unittest.main()
