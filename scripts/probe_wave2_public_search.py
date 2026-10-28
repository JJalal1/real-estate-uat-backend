#!/usr/bin/env python3
"""Bounded read-only checks of the existing UAT public search API, not handset metrics."""
import json
import math
import os
from pathlib import Path
import statistics
import time
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = 'https://real-estate-uat-api-frankfurt.onrender.com'
measurements = []

def get(path, params=None):
    url = ORIGIN + '/api' + path + ('?' + urllib.parse.urlencode(params) if params else '')
    started = time.perf_counter()
    request = urllib.request.Request(url, headers={'Accept': 'application/json'})
    try:
        response = urllib.request.urlopen(request, timeout=85)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read(512 * 1024 + 1)
        assert len(data) <= 512 * 1024, 'Unexpectedly large bounded public response'
        status = response.status
    measurements.append({'path': path, 'status': status, 'bytes': len(data),
                         'ms': round((time.perf_counter() - started) * 1000, 1)})
    time.sleep(.25)
    return status, json.loads(data)

def listings(params):
    status, body = get('/properties', {'per_page': 6, 'page': 1, 'sort': 'latest', **params})
    assert status == 200
    rows = body['data']
    assert isinstance(rows, list) and len(rows) <= 6
    assert len({row['id'] for row in rows}) == len(rows)
    for row in rows:
        assert all(key in row for key in ('id', 'title', 'price', 'currency', 'purpose', 'type', 'main_image'))
        assert not any(key in row for key in ('contact_phone', 'contact_whatsapp', 'documents', 'proof_documents', 'owner_key', 'user_email'))
        if 'purpose' in params:
            assert row['purpose'] == params['purpose']
        if params.get('type') == 'apartment':
            assert row['type'] in ('apartment', 'floor')
    return rows

def main():
    report = {'source_sha': os.environ.get('GITHUB_SHA'), 'origin': ORIGIN,
              'scope': 'Real UAT GET only, no token, fixtures, database writes or phone performance claim',
              'physical_android_tested': False, 'application_runtime_deployed': False}
    try:
        counts = {}
        for query in ('ش', 'ج'):
            counts[query] = len(listings({'search': query, 'governorate': 'صنعاء'}))
        a = listings({'search': 'شقة'}); b = listings({'search': 'شَقَه'})
        assert [r['id'] for r in a] == [r['id'] for r in b]
        for purpose in ('sale', 'rent'):
            listings({'search': 'ش', 'purpose': purpose, 'type': 'apartment'})
        assert listings({'search': 'ظظلاتوجدنتيجةبهذاالاسم'}) == []
        listings({})  # Empty text remains a six-row page, never an unbounded fetch.
        for row in listings({'search': 'ش', 'south': 15.25, 'west': 44.0, 'north': 15.6, 'east': 44.5}):
            assert 15.25 <= float(row['latitude']) <= 15.6 and 44.0 <= float(row['longitude']) <= 44.5
        for path in ('/properties/mine/list', '/listing-editor-drafts'):
            status, _ = get(path)
            assert status == 401
        times = sorted(m['ms'] for m in measurements)
        report.update({'passed': True, 'requests': len(measurements), 'first_character_counts': counts,
                       'p50_ms': statistics.median(times), 'p95_ms': times[math.ceil(.95*len(times))-1],
                       'bytes': sum(m['bytes'] for m in measurements), 'measurements': measurements,
                       'interpretation': 'Descriptive HTTP samples including cold/network latency; not a device baseline or production capacity result'})
    except Exception as error:
        report.update({'passed': False, 'failure_type': type(error).__name__, 'measurements': measurements})
        raise
    finally:
        Path('wave2-public-search-uat.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        print(json.dumps(report, ensure_ascii=False))

if __name__ == '__main__':
    main()
