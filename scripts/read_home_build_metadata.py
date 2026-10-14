"""Read existing build verification; never print APK, previews, raw log or credentials."""
import json,os,re,urllib.parse,urllib.request

REPOSITORY='JJalal1/real-estate-uat-backend'
SOURCE='4296aa06f9735f9bc63d12f235155fbabf46d705'
RUN=38646662876
JOB=116136291234

class Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,request,*args):
        redirected=super().redirect_request(request,*args)
        if redirected is not None and urllib.parse.urlsplit(request.full_url).netloc!=urllib.parse.urlsplit(redirected.full_url).netloc:
            redirected.remove_header('Authorization')
        return redirected

assert os.environ['GITHUB_REPOSITORY']==REPOSITORY
root='https://api.github.com/repos/'+REPOSITORY
headers={'Authorization':'Bearer '+os.environ['BUILD_METADATA_READ_TOKEN'],'Accept':'application/vnd.github+json'}
opener=urllib.request.build_opener(Redirect())
def read(path):
    with opener.open(urllib.request.Request(root+path,headers=headers),timeout=90) as response:return response.read()
assert json.loads(read(''))['private'] is True
run=json.loads(read('/actions/runs/'+str(RUN)))
assert run['head_sha']==SOURCE and run['conclusion']=='success'
raw=read('/actions/jobs/'+str(JOB)+'/logs').decode('utf-8')
prefix=raw.split('CODEX_APK_BEGIN ',1)[0]
found=[json.loads(value) for value in re.findall(r'(\{[^\r\n]*"version_code"[^\r\n]*\})',prefix)]
assert len(found)==1
proof=found[0]
assert proof['version_code']==1043 and proof['source_commit']==SOURCE and proof['apksigner']=='passed' and proof['zip_crc']=='passed'
assert 1<=proof['bytes']<100_000_000 and re.fullmatch('[a-f0-9]{64}',proof['sha256'])
print('HOME_BUILD_EVIDENCE '+json.dumps({key:proof[key] for key in ('version_code','source_commit','bytes','sha256')},sort_keys=True))
