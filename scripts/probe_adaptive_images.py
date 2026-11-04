"""Read-only UAT measurements. Only the existing synthetic public fixtures.

Response bodies are never printed. Only the known synthetic fixture60 gallery
is saved for watermark inspection. A controlled reader rate is reported
separately from unthrottled end-to-end measurements.
"""
import argparse
import hashlib
import json
from pathlib import Path
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
    report = {'fixture_property_ids': [60, 61, 62], 'completed': False,
              'note': 'Unthrottled wall time includes API/storage latency. Controlled reader is not OS network emulation.',
              'fixture_lookups': [], 'samples': []}
    try:
        _, health = read(ORIGIN + '/api/health')
        report['health'] = health
        assert health['status'] == 200, f"UAT health returned {health['status']}"
        for property_id in [60, 61, 62]:
            body, metadata = read(f'{ORIGIN}/api/properties/{property_id}')
            report['fixture_lookups'].append({'fixture_property_id': property_id, **metadata})
            assert metadata['status'] == 200, f"Synthetic fixture {property_id} returned {metadata['status']}; verify availability without changing probe limits"
            data = json.loads(body)['data']
            assert data['status'] == 'published' and data['images']
            url = data['images'][0]['url']
            assert urllib.parse.urlsplit(url).path.startswith('/api/property-media/')
            version = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query)).get('v', 'v1')
            assert version in ['v1', 'v2-wm-bf7611483e0689ad9ccd']
            row = {'fixture_property_id': property_id, 'display_version': version}
            report['samples'].append(row)
            for name in ['gallery', 'card', 'thumb']:
                encoded, row[name] = read(variant(url, name))
                if row[name]['status'] == 200:
                    assert encoded.startswith(b'\xff\xd8') and encoded.endswith(b'\xff\xd9')
                    assert b'Exif\x00\x00' not in encoded
                    row[name]['sha256'] = hashlib.sha256(encoded).hexdigest()
                    row[name]['exif_present'] = False
                    if property_id == 60 and name == 'gallery':
                        # This existing fixture is synthetic; never save arbitrary user media.
                        Path(f'synthetic-watermark-{version}.jpg').write_bytes(encoded)
            assert row['gallery']['status'] == row['card']['status'] == 200
            assert row['thumb']['status'] in [200, 422]
            if row['thumb']['status'] == 200:
                assert row['thumb']['variant'] == 'thumb'
                assert row['thumb']['bytes'] < row['card']['bytes']
                etag = row['thumb']['etag']
                assert etag
                _, row['conditional'] = read(variant(url, 'thumb'), headers={'If-None-Match': etag})
                assert row['conditional']['status'] == 304 and row['conditional']['bytes'] == 0
            _, row['original_variant'] = read(variant(url, 'original'))
            assert row['original_variant']['status'] == 422
            if property_id == 60:
                _, row['slow_gallery'] = read(variant(url, 'gallery'), rate=args.slow_rate)
                after = 'thumb' if row['thumb']['status'] == 200 else 'card'
                _, row['slow_selected'] = read(variant(url, after), rate=args.slow_rate)
                row['controlled_reader_bytes_per_second'] = args.slow_rate
                row['slow_selected_variant'] = after
        rows = report['samples']
        report['adaptive_available'] = all(row['thumb']['status'] == 200 for row in rows)
        report['watermark_active'] = all(row['display_version'].startswith('v2-wm-') for row in rows)
        report['detail_before_bytes'] = sum(row['gallery']['bytes'] for row in rows)
        report['detail_metered_after_bytes'] = sum(row['card']['bytes'] for row in rows)
        report['detail_saving_percent'] = round(100 * (1 - report['detail_metered_after_bytes'] / report['detail_before_bytes']), 2)
        assert report['detail_saving_percent'] > 0
        if report['adaptive_available']:
            report['card_before_bytes'] = sum(row['card']['bytes'] for row in rows)
            report['card_metered_after_bytes'] = sum(row['thumb']['bytes'] for row in rows)
            report['card_saving_percent'] = round(100 * (1 - report['card_metered_after_bytes'] / report['card_before_bytes']), 2)
        report['completed'] = True
    except Exception as error:
        report['error_type'] = type(error).__name__
        raise
    finally:
        Path(args.output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
