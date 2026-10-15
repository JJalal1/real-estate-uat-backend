#!/usr/bin/env python3
"""Read only bounded verification metadata for the tested private Wave4 build."""
import json, os, re, urllib.parse, urllib.request
REPO = 'JJalal1/real-estate-uat-backend'
SOURCE = 'db378214ade105a7046a2d1069095070ac76f7a4'
RUN = 38751111886
JOB = 116479222681
class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = super().redirect_request(req, fp, code, msg, headers, newurl)
        if target is not None and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            target.remove_header('Authorization')
        return target

def main():
    assert os.environ['GITHUB_REPOSITORY'] == REPO
    root = 'https://api.github.com/repos/' + REPO
    headers = {'Authorization': 'Bearer ' + os.environ['APK_READ_TOKEN'], 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
    opener = urllib.request.build_opener(SafeRedirect())
    def request(path):
        return opener.open(urllib.request.Request(root + path, headers=headers), timeout=60)
    def get(path):
        with request(path) as response:
            return json.load(response)
    assert get('')['private'] is True
    run = get('/actions/runs/' + str(RUN))
    assert run['head_sha'] == SOURCE and run['run_number'] == 49 and run['conclusion'] == 'success'
    jobs = get('/actions/runs/' + str(RUN) + '/jobs?per_page=100')['jobs']
    assert len(jobs) == 5 and all(j['conclusion'] == 'success' for j in jobs)
    job = next(j for j in jobs if j['id'] == JOB)
    assert job['head_sha'] == SOURCE
    prefix = bytearray()
    with request('/actions/jobs/' + str(JOB) + '/logs') as response:
        while len(prefix) < 10 * 1024 * 1024:
            block = response.read(65536)
            if not block:
                break
            prefix.extend(block)
            if b'CODEX_APK_BEGIN ' in prefix:
                break
    assert b'CODEX_APK_BEGIN ' in prefix
    raw = bytes(prefix).split(b'CODEX_APK_BEGIN ', 1)[0].decode('utf-8')
    proofs = [json.loads(v) for v in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})', raw)]
    assert len(proofs) == 1
    proof = proofs[0]
    assert proof['source_commit'] == SOURCE and proof['version_code'] == 1049
    assert proof['package'] == 'com.example.real_estate_mobile'
    assert proof['api'] == 'https://real-estate-uat-api-frankfurt.onrender.com/api'
    assert proof['apksigner'] == proof['zip_crc'] == 'passed'
    assert proof['fonts_match'] == 5 and re.fullmatch('[a-f0-9]{64}', proof['sha256'])
    assert 40_000_000 < proof['bytes'] < 60_000_000
    print('WAVE4_APK_EVIDENCE ' + json.dumps(proof, sort_keys=True))
    print('WAVE4_CI_EVIDENCE ' + json.dumps({'run': RUN, 'source': SOURCE, 'jobs': [{'id': j['id'], 'name': j['name'], 'conclusion': j['conclusion']} for j in jobs]}, sort_keys=True))
    clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', raw)
    counts = re.findall(r'\+(\d+):\s*All tests passed!', clean)
    print('WAVE4_FLUTTER_COUNTS ' + json.dumps(counts))
if __name__ == '__main__':
    main()
