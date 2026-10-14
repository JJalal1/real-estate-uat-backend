#!/usr/bin/env python3
"""Expose one bounded segment of an already verified private UAT installer.

Only reads GitHub. No releases, repository writes, credentials or public files.
"""
import argparse,base64,hashlib,json,os,re,urllib.parse,urllib.request

REPOSITORY='JJalal1/real-estate-uat-backend'
SOURCE='4296aa06f9735f9bc63d12f235155fbabf46d705'
RUN=38646662876
JOB=116136291234
EXPECTED_BYTES=49250885
EXPECTED_SHA='847ad17f84d77eeec2df2e473861ee1a1d6d062f76635fc807c32bb6041c9217'

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        redirected=super().redirect_request(req,fp,code,msg,headers,newurl)
        if redirected is not None and urllib.parse.urlsplit(req.full_url).netloc!=urllib.parse.urlsplit(newurl).netloc:
            redirected.remove_header('Authorization')
        return redirected

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--part',type=int,default=0);parser.add_argument('--parts',type=int,default=32);args=parser.parse_args()
    assert 0<=args.part<args.parts==32
    assert os.environ['GITHUB_REPOSITORY']==REPOSITORY
    root='https://api.github.com/repos/'+REPOSITORY
    headers={'Authorization':'Bearer '+os.environ['APK_READ_TOKEN'],'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
    opener=urllib.request.build_opener(SafeRedirect())
    def get(path):
        with opener.open(urllib.request.Request(root+path,headers=headers),timeout=120) as response:return response.read()
    assert json.loads(get(''))['private'] is True
    run=json.loads(get('/actions/runs/'+str(RUN)));assert run['head_sha']==SOURCE and run['conclusion']=='success'
    raw=get('/actions/jobs/'+str(JOB)+'/logs').decode('utf-8')
    metas=[json.loads(value) for value in re.findall(r'CODEX_APK_BEGIN (\{[^\r\n]+\})',raw)]
    assert len(metas)==3
    meta=metas[0];assert meta['source_commit']==SOURCE and meta['parts']==3 and meta['bytes']==EXPECTED_BYTES and meta['sha256']==EXPECTED_SHA
    assert all(m['source_commit']==SOURCE and m['sha256']==meta['sha256'] and m['bytes']==meta['bytes'] and m['chunks']==meta['chunks'] for m in metas)
    found=re.findall(r'CODEX_APK_DATA (\d+) ([A-Za-z0-9+/=]+)',raw)
    chunks={int(index):value for index,value in found};assert len(found)==len(chunks)==meta['chunks']
    assert set(chunks)==set(range(meta['chunks']))
    data=base64.b64decode(''.join(chunks[i] for i in range(meta['chunks'])),validate=True)
    assert len(data)==meta['bytes'] and hashlib.sha256(data).hexdigest()==meta['sha256'] and data.startswith(b'PK')
    prefix=raw[:raw.index('CODEX_APK_BEGIN ')]
    proof=[json.loads(value) for value in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})',prefix)]
    assert len(proof)==1 and proof[0]['version_code']==1043 and proof[0]['sha256']==meta['sha256'] and proof[0]['source_commit']==SOURCE
    assert proof[0]['apksigner']=='passed' and proof[0]['zip_crc']=='passed'
    print('CODEX_APK_VERIFICATION '+json.dumps(proof[0],sort_keys=True))
    start,end=meta['chunks']*args.part//args.parts,meta['chunks']*(args.part+1)//args.parts
    print('CODEX_APK_BEGIN '+json.dumps({**meta,'delivery_part':args.part,'delivery_parts':args.parts,'first':start,'end':end},sort_keys=True),flush=True)
    for i in range(start,end):print('CODEX_APK_DATA '+str(i)+' '+chunks[i])
    print('CODEX_APK_END '+str(args.part),flush=True)

if __name__=='__main__':main()
