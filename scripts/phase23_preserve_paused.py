#!/usr/bin/env python3
"""Preserve only the original encrypted checkpoints of paused Native run1574."""
import hashlib,io,json,os,re,urllib.error,urllib.request,zipfile
from pathlib import Path
REPO='JJalal1/real-estate-uat-backend'
RUN=43087697204
SOURCE='77017f226f1867ac46b1bb09650ef9b442809f3a'
API='https://api.github.com/repos/'+REPO
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):return None
def main():
    assert os.environ.get('GITHUB_REPOSITORY')==REPO
    assert os.environ.get('GITHUB_REF')=='refs/heads/work/phase23-acceptance-20261111'
    assert os.environ.get('GITHUB_EVENT_NAME')=='push'
    token=os.environ.pop('GH_TOKEN')
    def read(path):
        request=urllib.request.Request(API+path,headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','User-Agent':'AQER-Phase23-Preserve-Sealed'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(request,timeout=45) as r:return r.read(10000001)
        except urllib.error.HTTPError as error:
            if error.code!=302:raise
            location=error.headers['Location']
            assert location.startswith('https://')
            # Do not forward GitHub authorization to the artifact storage host.
            with urllib.request.urlopen(location,timeout=45) as r:return r.read(10000001)
    run=json.loads(read('/actions/runs/'+str(RUN)))
    assert run['status']=='completed' and run['head_sha']==SOURCE
    rows=json.loads(read('/actions/runs/'+str(RUN)+'/artifacts?per_page=100'))['artifacts']
    out=Path('phase23-paused-sealed-originals');out.mkdir(exist_ok=True)
    receipt={'source_run':RUN,'source_sha':SOURCE,'copied_without_decryption':True,'private_key_used':False,'checkpoints':[]}
    for a in rows:
        match=re.fullmatch('aqer-bridge-'+str(RUN)+'-1-([0-9]{6})',a['name'])
        if not match:continue
        assert not a['expired'] and a['workflow_run']['head_sha']==SOURCE
        raw=read('/actions/artifacts/'+str(a['id'])+'/zip')
        digest=hashlib.sha256(raw).hexdigest()
        assert len(raw)<=10000000 and digest==a['digest'].removeprefix('sha256:')
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            assert not any(n.endswith(('.key','.pem','.apk','.png','.mp4')) for n in z.namelist())
            public=json.loads(z.read(next(n for n in z.namelist() if n.endswith('PUBLIC_RECEIPT.json'))))
            cipher=z.read(next(n for n in z.namelist() if n.endswith('checkpoint.cms')))
        seq=int(match[1])
        assert str(public['run_id'])==str(RUN) and public['source_sha']==SOURCE and public['seq']==seq
        assert hashlib.sha256(cipher).hexdigest()==public['cipher_sha'] and len(cipher)==public['cipher_bytes']
        (out/(match[1]+'.zip')).write_bytes(raw)
        receipt['checkpoints'].append({'seq':seq,'artifact_id':a['id'],'bytes':len(raw),'sha256':digest})
    receipt['checkpoints'].sort(key=lambda r:r['seq'])
    assert [r['seq'] for r in receipt['checkpoints']]==list(range(9))
    (out/'PRESERVATION_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'preserved':len(receipt['checkpoints']),'source_run':RUN,'decrypted':False}))
if __name__=='__main__':main()
