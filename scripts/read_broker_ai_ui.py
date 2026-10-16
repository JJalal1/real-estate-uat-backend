#!/usr/bin/env python3
"""Read one synthetic UI image from one pinned private CI run; never accept an APK."""
import argparse, base64, hashlib, json, os, re, urllib.parse, urllib.request
REPO='JJalal1/real-estate-uat-backend'
SOURCE='2b955f18ea15946d462c1a3c111cda525e724377'
RUN=38844830294
FILES=('assistant-completion.png','assistant-review-1.0.png','assistant-copy-1.0.png','assistant-copy-2.4.png')
class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        target=super().redirect_request(req,fp,code,msg,headers,newurl)
        if target is not None and urllib.parse.urlsplit(req.full_url).netloc!=urllib.parse.urlsplit(newurl).netloc:
            target.remove_header('Authorization')
        return target
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--file',required=True,choices=FILES);args=parser.parse_args()
    assert os.environ['GITHUB_REPOSITORY']==REPO
    root='https://api.github.com/repos/'+REPO
    headers={'Authorization':'Bearer '+os.environ['UI_READ_TOKEN'],'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
    opener=urllib.request.build_opener(SafeRedirect())
    def request(path):return opener.open(urllib.request.Request(root+path,headers=headers),timeout=60)
    def get(path):
        with request(path) as response:return json.load(response)
    assert get('')['private'] is True
    run=get('/actions/runs/'+str(RUN));assert run['head_sha']==SOURCE and run['run_number']==58
    assert run['status'] in ('in_progress','completed') and run['conclusion'] in (None,'success')
    jobs=get('/actions/runs/'+str(RUN)+'/jobs?per_page=100')['jobs'];assert len(jobs)==5
    job=next(j for j in jobs if j['name']=='Flutter broker experience and UAT APK')
    assert job['head_sha']==SOURCE and job['run_id']==RUN and job['status'] in ('in_progress','completed')
    assert all(j['conclusion']=='success' for j in jobs if j['id']!=job['id'])
    steps={s['name']:s for s in job['steps']}
    assert steps['Broker journeys, template components and navigation acceptance']['conclusion']=='success'
    prefix=bytearray();marker=('CODEX_PREVIEW_END '+args.file).encode()
    with request('/actions/jobs/'+str(job['id'])+'/logs') as response:
        while len(prefix)<16*1024*1024 and marker not in prefix:
            block=response.read(65536)
            if not block:break
            prefix.extend(block)
    assert marker in prefix
    raw=bytes(prefix[:prefix.index(marker)+len(marker)]).decode('utf-8')
    metas=[json.loads(m) for m in re.findall(r'CODEX_PREVIEW_BEGIN (\{[^\r\n]+\})',raw)]
    meta=next(m for m in metas if m['file']==args.file)
    assert meta['source_commit']==SOURCE and 0<meta['bytes']<=4000000
    found=re.findall(r'CODEX_PREVIEW_DATA '+re.escape(args.file)+r' (\d+) ([A-Za-z0-9+/=]+)',raw)
    chunks={int(i):v for i,v in found};assert len(found)==len(chunks) and set(chunks)==set(range(len(chunks)))
    data=base64.b64decode(''.join(chunks[i] for i in range(len(chunks))),validate=True)
    assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data)==meta['bytes'] and hashlib.sha256(data).hexdigest()==meta['sha256']
    print('CODEX_PREVIEW_BEGIN '+json.dumps(meta,sort_keys=True))
    for i in range(len(chunks)):print('CODEX_PREVIEW_DATA '+args.file+' '+str(i)+' '+chunks[i])
    print('CODEX_PREVIEW_END '+args.file)
if __name__=='__main__':main()
