"""Read-only UAT measurements. Only the existing synthetic public fixtures.

Response bodies stay in memory and are never printed or saved. A controlled
reader rate is reported separately from unthrottled end-to-end measurements.
"""
import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = 'https://real-estate-uat-api-frankfurt.onrender.com'


def read(url, rate=0, headers=None):
    target = urllib.parse.urlsplit(url)
    if target.scheme != 'https' or target.netloc != urllib.parse.urlsplit(ORIGIN).netloc:
        raise RuntimeError('Unexpected UAT origin')
    started = time.monotonic()
    request = urllib.request.Request(url, headers={'Accept': 'application/json', **(headers or {})})
    try:
        response = urllib.request.urlopen(request, timeout=80)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        chunks = []
        while True:
            chunk = response.read(16384)
            if not chunk:
                break
            if sum(map(len, chunks)) + len(chunk) > 8 * 1024 * 1024:
                raise RuntimeError('Unexpected media size')
            chunks.append(chunk)
            if rate:
                time.sleep(len(chunk) / rate)
        body = b''.join(chunks)
        return body, {'status': response.status, 'bytes': len(body),
                      'elapsed_ms': round((time.monotonic() - started) * 1000),
                      'etag': response.headers.get('ETag'),
                      'cache_control': response.headers.get('Cache-Control'),
                      'variant': response.headers.get('X-Aqer-Image-Variant')}


def variant(url, name):
    parsed = urllib.parse.urlsplit(url)
    query = dict(urllib.parse.parse_qsl(parsed.query))
    query['variant'] = name
    return urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(query)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='adaptive-image-uat-metrics.json')
    parser.add_argument('--slow-rate', type=int, default=65536)
    args = parser.parse_args()
    _, health = read(ORIGIN + '/api/health')
    assert health['status'] == 200
    report = {'fixture_property_ids': [60, 61, 62], 'health': health,
              'note': 'Unthrottled wall time includes API/storage latency. Controlled reader is not OS network emulation.',
              'samples': []}
    for property_id in [60, 61, 62]:
        body, metadata = read(f'{ORIGIN}/api/properties/{property_id}')
        assert metadata['status'] == 200
        data = json.loads(body)['data']
        assert data['status'] == 'published' and data['images']
        url = data['images'][0]['url']
        assert urllib.parse.urlsplit(url).path.startswith('/api/property-media/')
        row = {'fixture_property_id': property_id}
        for name in ['gallery', 'card', 'thumb']:
            _, row[name] = read(variant(url, name))
        assert row['gallery']['status'] == row['card']['status'] == 200
        assert row['thumb']['status'] in [200, 422]
        if row['thumb']['status'] == 200:
            assert row['thumb']['variant'] == 'thumb'
            assert row['thumb']['bytes'] < row['card']['bytes']
            etag = row['thumb']['etag']
            assert etag
            _, row['conditional'] = read(variant(url, 'thumb'), headers={'If-None-Match': etag})
            assert row['conditional']['status'] == 304 and row['conditional']['bytes'] == 0
        if property_id == 60:
            _, row['slow_gallery'] = read(variant(url, 'gallery'), rate=args.slow_rate)
            after = 'thumb' if row['thumb']['status'] == 200 else 'card'
            _, row['slow_selected'] = read(variant(url, after), rate=args.slow_rate)
            row['controlled_reader_bytes_per_second'] = args.slow_rate
            row['slow_selected_variant'] = after
        report['samples'].append(row)
    rows = report['samples']
    report['adaptive_available'] = all(row['thumb']['status'] == 200 for row in rows)
    report['detail_before_bytes'] = sum(row['gallery']['bytes'] for row in rows)
    report['detail_metered_after_bytes'] = sum(row['card']['bytes'] for row in rows)
    report['detail_saving_percent'] = round(100 * (1 - report['detail_metered_after_bytes'] / report['detail_before_bytes']), 2)
    assert report['detail_saving_percent'] > 0
    if report['adaptive_available']:
        report['card_before_bytes'] = sum(row['card']['bytes'] for row in rows)
        report['card_metered_after_bytes'] = sum(row['thumb']['bytes'] for row in rows)
        report['card_saving_percent'] = round(100 * (1 - report['card_metered_after_bytes'] / report['card_before_bytes']), 2)
    with open(args.output, 'w', encoding='utf-8') as handle:
        json.dump(report, handle, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
