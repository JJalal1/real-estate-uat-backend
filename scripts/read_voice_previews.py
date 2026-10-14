import base64,hashlib,json,os,re,urllib.parse,urllib.request

REPO='JJalal1/real-estate-uat-backend'
SOURCE='998f3456d5dd74b493052376cf0091737c1eaf21'
RUN=38619452813
JOB=116044482247

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        result=super().redirect_request(req,fp,code,msg,headers,newurl)
        if result is not None and urllib.parse.urlsplit(req.full_url).netloc!=urllib.parse.urlsplit(newurl).netloc:
            result.remove_header('Authorization')
        return result

def main():
    assert os.environ['GITHUB_REPOSITORY']==REPO
    headers={'Authorization':'Bearer '+os.environ['PREVIEW_READ_TOKEN'],'Accept':'application/vnd.github+json'}
    opener=urllib.request.build_opener(SafeRedirect())
    def get(path):
        with opener.open(urllib.request.Request('https://api.github.com/repos/'+REPO+path,headers=headers),timeout=120) as response:return response.read()
    assert json.loads(get(''))['private'] is True
    run=json.loads(get('/actions/runs/'+str(RUN)));assert run['head_sha']==SOURCE and run['conclusion']=='success'
    text=get('/actions/jobs/'+str(JOB)+'/logs').decode('utf-8')
    # Only synthetic PNGs and a small verification summary leave this reader.
    # Installer payload, original log, prompts, environment and tokens are never emitted.
    prefix=text.split('CODEX_APK_BEGIN ',1)[0]
    proof=[json.loads(value) for value in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})',prefix)]
    assert len(proof)==1 and proof[0]['version_code']==1039 and proof[0]['source_commit']==SOURCE
    print('VOICE_BUILD_EVIDENCE '+json.dumps({k:proof[0][k] for k in ('source_commit','version_code','sha256','bytes')},sort_keys=True))
    metas=[json.loads(value) for value in re.findall(r'CODEX_PREVIEW_BEGIN (\{[^\r\n]+\})',prefix)]
    for name in ('voice-home-listening.png','voice-home-large-text.png'):
        matches=[m for m in metas if m['file']==name];assert len(matches)==1
        meta=matches[0];assert meta['source_commit']==SOURCE and meta['bytes']<=2_000_000
        pieces=re.findall(r'CODEX_PREVIEW_DATA '+re.escape(name)+r' (\d+) ([A-Za-z0-9+/=]+)',prefix)
        assert [int(i) for i,_ in pieces]==list(range(len(pieces)))
        data=base64.b64decode(''.join(value for _,value in pieces),validate=True)
        assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data)==meta['bytes'] and hashlib.sha256(data).hexdigest()==meta['sha256']
        print('CODEX_PREVIEW_BEGIN '+json.dumps(meta,sort_keys=True))
        for index,value in pieces:print('CODEX_PREVIEW_DATA '+name+' '+index+' '+value)
        print('CODEX_PREVIEW_END '+name)

if __name__=='__main__':main()
