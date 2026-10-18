import json, os, re, urllib.request, urllib.parse
REPO='JJalal1/real-estate-uat-backend'
SOURCE='64c9ee9399eca21c370e2c67e0c2248467b8c5b5'
RUN=39176318725
class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        out=super().redirect_request(req, fp, code, msg, headers, newurl)
        if out is not None and urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            out.remove_header('Authorization')
        return out
root='https://api.github.com/repos/'+REPO
headers={'Authorization':'Bearer '+os.environ['LOG_READ_TOKEN'],'Accept':'application/vnd.github+json'}
opener=urllib.request.build_opener(SafeRedirect())
def get(path):
    with opener.open(urllib.request.Request(root+path,headers=headers), timeout=120) as r:
        data=r.read(100_000_001)
        assert len(data)<=100_000_000
        return data
assert os.environ['GITHUB_REPOSITORY']==REPO
assert json.loads(get(''))['private']
run=json.loads(get('/actions/runs/'+str(RUN)))
assert run['head_sha']==SOURCE and run['conclusion']=='failure'
jobs=json.loads(get('/actions/runs/'+str(RUN)+'/jobs?per_page=100'))['jobs']
job=next(j for j in jobs if j['name']=='Flutter broker experience and UAT APK')
assert job['head_sha']==SOURCE and job['run_id']==RUN
raw=get('/actions/jobs/'+str(job['id'])+'/logs').decode('utf-8-sig')
raw=re.split('CODEX_PREVIEW_BEGIN |CODEX_APK_BEGIN ',raw,maxsplit=1)[0]
lines=re.sub(r'\x1b\[[0-9;]*m','',raw).replace('\r','\n').splitlines()
indices=set()
for i,line in enumerate(lines):
    if re.search(r'EXCEPTION CAUGHT|Expected:|Actual:|Which:|test description was:|\[E\]|Failed assertion|Some tests failed|pumpAndSettle timed out|Error:',line):
        indices.update(range(max(0,i-3),min(len(lines),i+16)))
out='\n'.join(lines[i] for i in sorted(indices) if 'CHUNK' not in lines[i] and '✅' not in lines[i] and len(lines[i])<2000)
assert len(out)<100000
print('FAILED_SOURCE '+SOURCE+' RUN '+str(RUN))
print(out)
