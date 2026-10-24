"""Bounded read-only UAT diagnostic. Never logs response bodies or credentials.

The first external request is reported separately (possibly asleep, not an
asserted cold start). Warm p95 is a nearest-rank descriptive 20-sample value,
not a production SLO or population estimate. Maximum three in-flight requests.
"""
import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time

ORIGIN = 'https://real-estate-uat-api-frankfurt.onrender.com'


def read(path, group, headers=None):
    assert path.startswith('/api/') and not path.startswith('//')
    with tempfile.TemporaryDirectory() as folder:
        body = Path(folder) / 'body'
        response_headers = Path(folder) / 'headers'
        command = ['curl', '--silent', '--show-error', '--connect-timeout', '10',
                   '--max-time', '80' if group == 'first_request' else '20',
                   '--max-filesize', '2097152', '--proto', '=https',
                   '--header', 'Accept: application/json', '--header',
                   'User-Agent: Aqer-UAT-109-bounded-probe/1.0', '--header',
                   'X-Aqer-Diagnostics: perf-109', '--dump-header', str(response_headers),
                   '--output', str(body), '--write-out', '%{json}']
        for name, value in (headers or {}).items():
            assert name == 'If-None-Match' and '\n' not in value and '\r' not in value
            command += ['--header', name + ': ' + value]
        result = subprocess.run(command + [ORIGIN + path], capture_output=True, text=True, timeout=85)
        timing = json.loads(result.stdout) if result.stdout else {}
        content = body.read_bytes() if body.exists() else b''
        safe_headers = {}
        if response_headers.exists():
            for line in response_headers.read_text(errors='replace').splitlines():
                name, sep, value = line.partition(':')
                if sep and name.lower() in ['server-timing', 'x-request-id', 'etag',
                                             'x-aqer-db-queries', 'x-aqer-storage-requests',
                                             'content-type', 'cache-control']:
                    safe_headers[name.lower()] = value.strip()
        row = {'group': group, 'path': path, 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
               'status': timing.get('http_code', 0), 'curl_exit': result.returncode,
               'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest(),
               'headers': safe_headers}
        for key in ['time_namelookup', 'time_connect', 'time_appconnect', 'time_pretransfer',
                    'time_starttransfer', 'time_total']:
            row[key + '_ms'] = round(float(timing.get(key, 0)) * 1000, 1)
        row['waiting_after_tls_ms'] = round(row['time_starttransfer_ms'] - row['time_pretransfer_ms'], 1)
        return row, content


def summarize(rows):
    times = sorted(row['time_total_ms'] for row in rows)
    return {'n': len(rows), 'p50_ms': times[math.ceil(len(times) * .5) - 1],
            'p95_ms': times[math.ceil(len(times) * .95) - 1], 'max_ms': max(times),
            'errors': sum(row['status'] != 200 or row['curl_exit'] != 0 for row in rows),
            'bytes': sum(row['bytes'] for row in rows)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='uat-performance-metrics.json')
    args = parser.parse_args()
    report = {'source_sha': os.environ.get('GITHUB_SHA'), 'origin': ORIGIN,
              'started_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'scope': 'Controlled UAT n=20 per warm endpoint; concurrency<=3; no production capacity claim.',
              'samples': [], 'summaries': {}, 'completed': False}
    def save():
        Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    try:
        row, content = read('/api/health', 'first_request')
        report['samples'].append(row)
        save()
        assert row['status'] == 200 and row['curl_exit'] == 0
        assert json.loads(content)['database'] is True
        row, content = read('/api/properties/60', 'synthetic_fixture_lookup')
        report['samples'].append(row)
        data = json.loads(content)['data']
        assert row['status'] == 200 and data['status'] == 'published'
        # Only the already documented synthetic fixture. Never crawl user media.
        from urllib.parse import urlsplit, parse_qsl, urlencode
        target = urlsplit(data['images'][0]['url'])
        assert target.netloc == urlsplit(ORIGIN).netloc and target.path.startswith('/api/property-media/')
        query = dict(parse_qsl(target.query)); query['variant'] = 'thumb'
        image_path = target.path + '?' + urlencode(query)
        for label, path, concurrency in [('warm_health', '/api/health', 3),
                                          ('warm_thumb', image_path, 3),
                                          ('warm_marketplace', '/api/marketplace?governorate=%D8%A5%D8%A8', 2)]:
            rows = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                # Submit at most one wave. Stop before submitting another wave
                # on any failure or warm response exceeding six seconds.
                for offset in range(0, 20, concurrency):
                    wave = list(pool.map(lambda _: read(path, label), range(min(concurrency, 20 - offset))))
                    for sample, body in wave:
                        rows.append(sample); report['samples'].append(sample)
                        assert sample['curl_exit'] == 0 and sample['status'] == 200
                        if label == 'warm_thumb':
                            assert body.startswith(b'\xff\xd8') and b'Exif\x00\x00' not in body
                        else:
                            assert isinstance(json.loads(body), dict)
                    report['summaries'][label] = dict(summarize(rows), concurrency=concurrency)
                    save()
                    assert max(r['time_total_ms'] for r, _ in wave) <= 6000, 'Warm safety latency ceiling exceeded'
                    time.sleep(.25)
        row, _ = read('/api/health', 'final_health')
        report['samples'].append(row)
        assert row['status'] == 200
        report['completed'] = True
    finally:
        save()
        print('AQER_UAT_PERFORMANCE ' + json.dumps({k: v for k, v in report.items() if k != 'samples'}))


if __name__ == '__main__':
    main()
