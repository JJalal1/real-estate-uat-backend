"""Verify the public reference for UAT1821 cases 10 and 11 on Frankfurt UAT."""

import argparse
from datetime import datetime, timezone
from getpass import getpass
import json
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


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


def request(path, *, params=None, body=None, token=None):
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    if body is not None:
        headers['Content-Type'] = 'application/json'
    url = API + path + ('?' + urlencode(params) if params else '')
    start = datetime.now(timezone.utc).isoformat()
    req = Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urlopen(req, timeout=45) as reply:
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


def create_saved_searches():
    token = getpass('Bearer token for the signed-in regular UAT test account: ').strip()
    if not token:
        raise RuntimeError('A token for the UAT test account is required.')
    items = []
    for case, filters in FILTERS.items():
        payload = {'name': f'UAT1821 {case}', 'filters': filters, 'alert_frequency': 'off'}
        reply, receipt = request('/saved-searches', body=payload, token=token)
        saved = reply['data']
        expect(saved['filters'], filters, f'{case} saved filters')
        items.append({'case': case, 'id': saved['id'], 'name': saved['name'], 'filters': saved['filters'],
                      'created': receipt['http_status'] == 201, **receipt})
    reply, _ = request('/saved-searches', token=token)
    stored = {row['id']: row['filters'] for row in reply['data']}
    for item in items:
        expect(stored.get(item['id']), item['filters'], f"case {item['case']} persisted filters")
    return items


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create-saved-searches', action='store_true',
                        help='After public checks pass, save these filters with alerts off for the UAT test account.')
    args = parser.parse_args()
    output = verify()
    if args.create_saved_searches:
        output['saved_searches'] = create_saved_searches()
    print(json.dumps(output, ensure_ascii=False, indent=2))
