#!/usr/bin/env python3
"""Audit the actual locked hosted Dart dependency graph against OSV.

No app credentials or user data are read. Incomplete/network/error responses
fail the check rather than being interpreted as an empty advisory list.
"""
import datetime
import json
import os
from pathlib import Path
import sys
import urllib.request


def request_json(path, payload=None):
    request = urllib.request.Request('https://api.osv.dev' + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'Content-Type': 'application/json', 'User-Agent': 'Aqer-dependency-audit/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def audit(graph, fetch=request_json):
    packages = sorted(({'name': item['name'], 'version': item['version']}
        for item in graph['packages'] if item.get('source') == 'hosted'), key=lambda item: item['name'])
    if len(packages) < 20 or not {'dio', 'maplibre_gl', 'flutter_riverpod'} <= {p['name'] for p in packages}:
        raise ValueError('Incomplete resolved hosted dependency inventory.')
    pending = [(index, {'package': {'name': item['name'], 'ecosystem': 'Pub'}, 'version': item['version']})
        for index, item in enumerate(packages)]
    findings = set()
    page_count = 0
    while pending:
        page_count += 1
        if page_count > 10:
            raise ValueError('Advisory pagination did not complete.')
        response = fetch('/v1/querybatch', {'queries': [query for _, query in pending]})
        results = response.get('results')
        if not isinstance(results, list) or len(results) != len(pending):
            raise ValueError('Incomplete advisory response.')
        following = []
        for (index, query), result in zip(pending, results):
            if not isinstance(result, dict) or result.get('error'):
                raise ValueError('Failed advisory result.')
            for vulnerability in result.get('vulns', []):
                identifier = vulnerability.get('id')
                if not isinstance(identifier, str) or not identifier or '/' in identifier:
                    raise ValueError('Malformed advisory identifier.')
                findings.add((index, identifier))
            if result.get('next_page_token'):
                following.append((index, {**query, 'page_token': result['next_page_token']}))
        pending = following
    details = {}
    for _, identifier in sorted(findings):
        if identifier not in details:
            entry = fetch('/v1/vulns/' + identifier)
            if entry.get('id') != identifier:
                raise ValueError('Advisory identity mismatch.')
            details[identifier] = {'id': identifier, 'summary': entry.get('summary'),
                'aliases': entry.get('aliases', []), 'affected': entry.get('affected', []),
                'references': entry.get('references', [])}
    return {'status': 'failed' if findings else 'passed', 'source_sha': os.environ.get('GITHUB_SHA'),
        'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'provider': 'https://api.osv.dev/v1/querybatch', 'ecosystem': 'Pub',
        'inventory': packages, 'hosted_packages_checked': len(packages), 'query_pages': page_count,
        'findings': [{**packages[index], 'advisory': identifier} for index, identifier in sorted(findings)],
        'advisories': list(details.values()),
        'limits': ['Known published advisories only.', 'Flutter/Android/native SDK binaries require separate verification.']}


def main():
    output = Path('pub-security-audit.json')
    try:
        report = audit(json.loads(Path('mobile_app/build/resolved-dependencies.json').read_text()))
    except Exception as error:
        output.write_text(json.dumps({'status': 'error', 'error_type': type(error).__name__}, indent=2) + '\n')
        raise
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ['inventory', 'advisories']}))
    return 1 if report['findings'] else 0


if __name__ == '__main__':
    sys.exit(main())
