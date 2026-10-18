"""Public read-only UAT smoke; protected listing preparation must reject anonymous calls."""
import json
import time
import urllib.error
import urllib.parse
import urllib.request

API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
DEPLOYED_SOURCE = '22a142666ad92b419eba7e41ea358b7e68199c82'
DEPLOY_ID = 'dep-dbalpk2jnfac73879qu0'


def request(path, payload=None):
    url = API + path
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
    headers = {'Accept': 'application/json', 'User-Agent': 'RealEstate-UAT-Listing-Smoke/1.0'}
    if data is not None:
        headers['Content-Type'] = 'application/json'
    start = time.monotonic()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=55) as response:
            return response.status, json.load(response), round((time.monotonic() - start) * 1000)
    except urllib.error.HTTPError as error:
        try:
            body = json.loads(error.read())
        except (ValueError, UnicodeError):
            body = {}
        return error.code, body, round((time.monotonic() - start) * 1000)


def main():
    assert DEPLOYED_SOURCE != 'SET_AFTER_LIVE' and DEPLOY_ID.startswith('dep-')
    checks = []
    code, body, ms = request('/health')
    assert code == 200 and body['status'] == 'ok' and body['database'] is True and body['postgis'] is True
    checks.append({'check': 'health/database/PostGIS', 'status': code, 'ms': ms})
    sample = None
    for city, first in [('صنعاء', 60), ('ذمار', 68), ('إب', 76)]:
        code, body, ms = request('/properties?' + urllib.parse.urlencode({'governorate': city, 'per_page': 100}))
        assert code == 200
        rows = body['data']
        assert isinstance(rows, list)
        ids = {row['id'] for row in rows}
        assert set(range(first, first + 8)).issubset(ids), (city, sorted(ids))
        assert all(row.get('status', 'published') == 'published' for row in rows)
        checks.append({'check': 'public city fixtures', 'city': city, 'expected_fixtures': 8, 'public_count': len(rows), 'status': code, 'ms': ms})
        if city == 'إب':
            sample = next(row for row in rows if row['id'] == 76)
    code, body, ms = request('/properties/76')
    assert code == 200 and body['data']['id'] == 76
    public = body['data']
    forbidden = {'phone', 'whatsapp', 'identity_number', 'document_owner_name', 'relationship_note', 'ownership_proof_path'}
    assert not forbidden.intersection(public)
    checks.append({'check': 'published property privacy', 'status': code, 'ms': ms})
    image = public.get('main_image') or sample.get('main_image')
    assert isinstance(image, str) and image.startswith('https://')
    parsed = urllib.parse.urlsplit(image)
    assert parsed.hostname in {'real-estate-uat-api-frankfurt.onrender.com', 'ipxsgxsqzthpgthwvdno.supabase.co'}
    with urllib.request.urlopen(image, timeout=30) as response:
        prefix = response.read(64)
        assert response.status == 200 and response.headers.get_content_type().startswith('image/')
        assert prefix.startswith(b'\x89PNG\r\n\x1a\n') or prefix.startswith(b'\xff\xd8')
    checks.append({'check': 'real public HTTPS photo bytes', 'status': 200})
    brief = 'شقة للايجار في اب شارع السبل ثلاث غرف واثنين حمامات ويوجد موقف سيارات السعر مئة الف ريال'
    for path, payload in [('/ai/listing-draft', {'mode': 'prepare', 'message': brief, 'facts': {}}),
                          ('/ai/listing-fields', {'message': brief, 'facts': {}}),
                          ('/properties/mine/list', None), ('/properties/76/contact', None)]:
        code, _, ms = request(path, payload)
        assert code == 401, (path, code)
        checks.append({'check': 'anonymous access denied', 'path': path, 'status': code, 'ms': ms})
    code, body, ms = request('/ai/search', {'message': 'ابحث لي عن عقارات في مدينة اب', 'filters': {}, 'revision': 1})
    if code == 200:
        filters = body['data']['filters']
        assert filters.get('search') == 'إب', filters
        ai = {'status': 200, 'ms': ms, 'city': filters['search'], 'passed': True}
    else:
        assert code in {429, 503}, code
        ai = {'status': code, 'ms': ms, 'passed': False, 'availability': 'open; honest provider failure retained'}
    print('LISTING_LIVE_SMOKE ' + json.dumps({'deployed_source': DEPLOYED_SOURCE, 'deploy': DEPLOY_ID,
        'checks': checks, 'real_ai_search': ai, 'protected_listing_provider': 'not exercised without an authorized user session',
        'handset_microphone': 'open', 'automatic_retries': 0}, ensure_ascii=False, sort_keys=True))


if __name__ == '__main__':
    main()
