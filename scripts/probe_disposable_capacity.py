"""Bounded black-box API load against a fixed, empty disposable CI database.

Never contacts UAT, Storage or Production. Timings describe this runner only.
"""
import concurrent.futures
import json
import math
import os
from pathlib import Path
import time
import urllib.request

ORIGIN = 'http://127.0.0.1:8098'
TARGETS = {
    'first_page': '/api/properties?per_page=20&page=1',
    'deep_page': '/api/properties?per_page=20&page=500',
    'arabic_search': '/api/properties?per_page=20&search=%D9%85%D9%83%D8%AA%D8%A8',
    'marketplace': '/api/marketplace?governorate=%D8%A5%D8%A8',
    'nearby': '/api/properties/nearby?latitude=15.123456&longitude=44.654321&radius_km=5',
}


def php_resources():
    rss = cpu = workers = 0
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            if (proc / 'comm').read_text().strip() != 'php':
                continue
            values = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
            rss += int(values[21]) * os.sysconf('SC_PAGE_SIZE')
            cpu += (int(values[11]) + int(values[12])) / os.sysconf('SC_CLK_TCK')
            workers += 1
        except (OSError, ValueError, IndexError):
            continue
    return {'php_processes': workers, 'sum_rss_bytes': rss, 'cpu_seconds': cpu}


def read(label):
    request = urllib.request.Request(ORIGIN + TARGETS[label], headers={
        'Accept': 'application/json', 'X-Aqer-Diagnostics': 'perf-109'})
    start = time.perf_counter()
    with urllib.request.urlopen(request, timeout=10) as response:
        body = response.read(2 * 1024 * 1024 + 1)
        assert response.status == 200 and len(body) <= 2 * 1024 * 1024
        payload = json.loads(body)
        data = payload['data']
        if label in ('first_page', 'deep_page', 'arabic_search'):
            assert len(data) == 20 and payload['meta']['total'] == 10000
        elif label == 'nearby':
            assert 0 < len(data) <= 250
        else:
            assert len(data['sections']['latest']) == 6
        return {'ms': round((time.perf_counter() - start) * 1000, 2),
                'bytes': len(body), 'db_queries': int(response.headers['X-Aqer-DB-Queries']),
                'storage_requests': int(response.headers['X-Aqer-Storage-Requests'])}


def main():
    assert os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.environ.get('AQER_CAPACITY_DISPOSABLE') == '20261025'
    assert os.environ.get('DB_DATABASE') == 'aqer_capacity'
    report = {'source_sha': os.environ.get('GITHUB_SHA'), 'origin': ORIGIN,
              'fixture': json.loads(Path('capacity-fixture.json').read_text()),
              'requests_per_endpoint_per_level': 18, 'results': [], 'completed': False,
              'limits': {'p95_ms': 2000, 'response_bytes': 1048576},
              'interpretation': 'CI runner + PHP development server + local PostgreSQL; excludes Render/network/Storage/device.'}
    samples = [php_resources()]
    try:
        for label in TARGETS:
            read(label)
        for concurrency in (1, 3, 6):
            for label in TARGETS:
                rows = []
                started = time.perf_counter()
                with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                    for offset in range(0, 18, concurrency):
                        rows += list(pool.map(read, [label] * min(concurrency, 18 - offset)))
                        samples.append(php_resources())
                        assert max(row['ms'] for row in rows[-concurrency:]) <= 6000
                times = sorted(row['ms'] for row in rows)
                result = {'endpoint': label, 'concurrency': concurrency, 'n': len(rows),
                          'p50_ms': times[math.ceil(.5 * len(times)) - 1],
                          'p95_ms': times[math.ceil(.95 * len(times)) - 1],
                          'p99_ms': times[math.ceil(.99 * len(times)) - 1],
                          'requests_per_second': round(len(rows) / (time.perf_counter() - started), 2),
                          'bytes': sum(row['bytes'] for row in rows),
                          'max_bytes': max(row['bytes'] for row in rows),
                          'max_db_queries': max(row['db_queries'] for row in rows),
                          'storage_requests': sum(row['storage_requests'] for row in rows), 'errors': 0}
                report['results'].append(result)
                assert result['p95_ms'] <= 2000 and result['max_bytes'] <= 1048576
                assert result['storage_requests'] == 0
        report['completed'] = True
    finally:
        report['sampled_php_max_sum_rss_bytes'] = max(row['sum_rss_bytes'] for row in samples)
        report['php_cpu_seconds_delta'] = round(samples[-1]['cpu_seconds'] - samples[0]['cpu_seconds'], 2)
        Path('capacity-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('AQER_DISPOSABLE_CAPACITY ' + json.dumps(report))


if __name__ == '__main__':
    main()
