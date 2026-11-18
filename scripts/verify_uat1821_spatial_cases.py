"""Verify the public reference for UAT1821 cases 10 and 11 on Frankfurt UAT."""

import argparse
from datetime import datetime, timezone
from getpass import getpass
import json
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, build_opener

from phase23_preflight import NoRedirect


API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
POLYGONS = {
    '10': '[[44.1,14.4],[44.4075,14.4],[44.4075,15.55],[44.1,15.55],[44.1,14.4]]',
    '11-on': '[[44.399,14.551],[44.4,14.551],[44.4,14.553],[44.399,14.553],[44.399,14.551]]',
    '11-out': '[[44.399,14.551],[44.3999,14.551],[44.3999,14.553],[44.399,14.553],[44.399,14.551]]',
}
FILTERS = {
    '10': {'area_polygon': POLYGONS['10']},
    '11-on': {'area_polygon': POLYGONS['11-on'], 'purpose': 'rent', 'governorate_code': 'DHAMAR'},
    '11-out': {'area_polygon': POLYGONS['11-out'], 'purpose': 'rent', 'governorate_code': 'DHAMAR'},
}
PAGES = (
    ([145, 144, 143, 140, 139, 138, 136, 135, 134, 133, 131, 130, 129, 128, 127, 126, 125, 124, 123, 122], []),
    (list(range(121, 105, -1)), [142, 147, 141, 146]),
    ([], [132, 137]),
)


def request(path, *, params=None, body=None, token=None, method=None):
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    if body is not None:
        headers['Content-Type'] = 'application/json'
    url = API + path + ('?' + urlencode(params) if params else '')
    start = datetime.now(timezone.utc).isoformat()
    req = Request(url, data=json.dumps(body).encode() if body is not None else None,
                  headers=headers, method=method)
    try:
        with build_opener(NoRedirect()).open(req, timeout=45) as reply:
            return json.load(reply), {
                'started_utc': start, 'http_status': reply.status,
                'request_id': reply.headers.get('X-Request-ID'),
                'ranked_contract': reply.headers.get('X-Aqer-Ranked-Contract'),
            }
    except HTTPError as error:
        raise RuntimeError(f'{path}: HTTP {error.code}, request {error.headers.get("X-Request-ID")}') from None


def expect(value, expected, name):
    if value != expected:
        raise RuntimeError(f'{name}: expected {expected}, found {value}')


def ranked(case, page):
    params = {**FILTERS[case], 'page': page, 'ranked_search': 1, 'per_page': 20, 'sort': 'latest'}
    reply, receipt = request('/properties', params=params)
    expect(receipt['ranked_contract'], '1', 'ranked contract')
    meta = reply['meta']
    expect((meta['current_page'], meta['per_page']), (page, 20), 'paging')
    rows = [{
        'id': r['id'], 'title': r['title'], 'kind': r['discovery_match']['kind'],
        'reasons': r['discovery_match']['reasons'], 'distance_m': r['discovery_match']['distance_m'],
    } for r in reply['data']]
    return {'case': case, 'request': params, **receipt, 'meta': meta, 'rows': rows}


def verify():
    results = []
    for page, (exact, nearby) in enumerate(PAGES, start=1):
        result = ranked('10', page)
        meta = result['meta']
        expect((meta['last_page'], meta['exact_total'], meta['alternative_total']), (3, 36, 6), 'case 10 totals')
        expect([(r['id'], r['kind']) for r in result['rows']],
               [(i, 'exact') for i in exact] + [(i, 'nearby') for i in nearby], f'case 10 page {page}')
        results.append(result)

    item, item_receipt = request('/properties/145')
    point = item['data']
    expect((point['id'], point['longitude'], point['latitude']), (145, 44.4, 14.552), 'case 11 point')
    for case, kind in [('11-on', 'exact'), ('11-out', 'nearby')]:
        result = ranked(case, 1)
        meta = result['meta']
        expect((meta['last_page'], meta['exact_total'], meta['alternative_total']),
               (1, 1, 9) if kind == 'exact' else (1, 0, 10), f'{case} totals')
        target = [r for r in result['rows'] if r['id'] == 145]
        expect([r['kind'] for r in target], [kind], f'{case} listing 145')
        if kind == 'nearby':
            expect([r['field'] for r in target[0]['reasons']], ['location'], f'{case} reason')
        results.append(result)
    return {'api': API, 'public_reference': results, 'boundary_listing': {
        'id': point['id'], 'latitude': point['latitude'], 'longitude': point['longitude'], **item_receipt,
    }}


class SavedSearchPreparationError(RuntimeError):
    pass


def check_preparation(condition, reason):
    if not condition:
        raise SavedSearchPreparationError(reason)


def prepare_broker_saved_searches(token, receipt, transport=request):
    check_preparation(bool(token), 'broker_session_required')
    body, identity = transport('/auth/me', token=token)
    user = body.get('data', {}).get('user', {})
    check_preparation(identity['http_status'] == 200 and type(user.get('id')) is int and user['id'] == 28
                      and user.get('account_type') == 'broker' and user.get('account_status') == 'active',
                      'expected_active_test_broker_28_required')
    receipt.update(actor_id=28, account_type='broker', auth_me_http=200, auth_me_request_id=identity['request_id'])

    def owned_searches():
        listing, trace = transport('/saved-searches', token=token)
        check_preparation(trace['http_status'] == 200 and isinstance(listing.get('data'), list),
                          'owned_saved_search_read_failed')
        return {row['id']: row for row in listing['data']}, trace['request_id']

    items = receipt['saved_searches'] = []
    for case, filters in FILTERS.items():
        payload = {'name': f'UAT1822 {case}', 'filters': filters, 'alert_frequency': 'off'}
        reply, saved_response = transport('/saved-searches', body=payload, token=token)
        saved = reply['data']
        save_http = saved_response['http_status']
        check_preparation(save_http in (200, 201) and type(saved.get('id')) is int and saved['id'] > 0
                          and saved.get('filters') == filters, 'unexpected_saved_search_response')
        saved_id = saved['id']
        check_preparation(all(item['id'] != saved_id for item in items), 'saved_search_ids_must_be_distinct')
        item = {'case': case, 'id': saved_id, 'save_http': save_http, 'created': save_http == 201,
                'save_request_id': saved_response['request_id']}
        items.append(item)

        owned, _ = owned_searches()
        row = owned.get(saved_id, {})
        check_preparation(row.get('filters') == filters, 'saved_search_not_owned_with_expected_filters')
        before = row.get('alert_frequency')
        check_preparation(before in ('instant', 'daily', 'off'), 'unrecognized_saved_search_alert_frequency')
        item.update(ownership_verified=True, alerts_before=before)
        if before != 'off':
            _, updated = transport(f'/saved-searches/{saved_id}', method='PATCH',
                                   body={'alert_frequency': 'off'}, token=token)
            item.update(alert_patch_http=updated['http_status'], alert_patch_request_id=updated['request_id'])
            check_preparation(updated['http_status'] == 200, 'saved_search_alert_update_failed')

    final, readback_id = owned_searches()
    for item in items:
        row = final.get(item['id'], {})
        check_preparation(row.get('filters') == FILTERS[item['case']] and row.get('alert_frequency') == 'off',
                          'saved_search_scope_or_alert_readback_mismatch')
        item.update(filters=row['filters'], alert_frequency='off', active=row.get('is_active'),
                    name=row.get('name'), readback_verified=True)
    receipt['owned_searches_readback_request_id'] = readback_id


def create_saved_searches():
    token = getpass('Bearer token for the signed-in UAT broker account 28: ').strip()
    receipt = {}
    prepare_broker_saved_searches(token, receipt)
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create-saved-searches', action='store_true',
                        help='After public checks pass, save these filters with alerts off for the UAT test account.')
    args = parser.parse_args()
    output = verify()
    if args.create_saved_searches:
        output['saved_searches'] = create_saved_searches()
    print(json.dumps(output, ensure_ascii=False, indent=2))
