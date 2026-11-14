#!/usr/bin/env python3
"""Measure only the new synthetic large-image fixture through normal UAT accounts."""
import datetime,hashlib,io,json,os,subprocess,urllib.error,urllib.request
from pathlib import Path
from PIL import Image
from phase1_native_account_readiness import SECRET_NAME,validate_access
from phase23_preflight import API,NoRedirect,GateError,http
from run_phase23_native import Session
DRAFT='ad008330-99d5-4a51-b844-ae62886d8803'
IMAGE='47ec03d3-2128-4d55-b44c-f3daa7d0bd86'
PATH='/listing-editor-drafts/'+DRAFT+'/images/'+IMAGE
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'phase23-private-media-evidence/RECEIPT.json'

def media(path,token=None):
    headers={'Accept':'image/jpeg','User-Agent':'AQER-Phase23-New-Large-Fixture'}
    if token:headers['Authorization']='Bearer '+token
    request=urllib.request.Request(API+path,headers=headers,method='GET')
    try:
        with urllib.request.build_opener(NoRedirect()).open(request,timeout=45) as response:
            raw=response.read(8*1024*1024+1)
            assert len(raw)<=8*1024*1024,'bounded_variant_required'
            return response.status,dict(response.headers),raw
    except urllib.error.HTTPError as error:
        return error.code,{},b''

def main():
    assert os.environ.get('GITHUB_REPOSITORY')=='JJalal1/real-estate-uat-backend'
    assert os.environ.get('GITHUB_REF')=='refs/heads/work/phase23-acceptance-20261111'
    assert os.environ.get('GITHUB_EVENT_NAME')=='push'
    assert subprocess.check_output(['git','rev-parse','HEAD:mobile_app'],cwd=ROOT,text=True).strip()=='3e181f4e32969a18bf302093a2a3d09288ee1ac9'
    assert subprocess.check_output(['git','rev-parse','HEAD:backend-api-runtime'],cwd=ROOT,text=True).strip()=='e36417aca4233488220a6c8e2951ea0709f601a0'
    receipt={'run_id':os.environ['GITHUB_RUN_ID'],'source_sha':os.environ['GITHUB_SHA'],
        'native_source_run':42986038827,'native_steps':[24,25,28],
        'draft_key':DRAFT,'image_key':IMAGE,'scope':'normal UAT fixture-media GET only, not a direct database verification',
        'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'BLOCKED',
        'input':{'bytes':2952430,'width':2048,'height':1536,'sha256':'94edbd4529a2f025ad83cfc9e7dc5790ef20fa48ab9ef6d5975bca1fc17afa6b'},
        'variants':[],'cleanup':{}}
    sessions={}
    try:
        access=validate_access(os.environ.pop(SECRET_NAME,''))
        for alias in ('broker','regular'):
            sessions[alias]=Session(alias,access);sessions[alias].login()
        del access
        code,body=http('GET','/listing-editor-drafts/'+DRAFT,token=sessions['broker'].token)
        assert code==200 and any(row.get('key')==IMAGE for row in body.get('data',{}).get('images',[])),'owned_fixture_required'
        guest,_,_=media(PATH+'?variant=card')
        other,_,_=media(PATH+'?variant=card',sessions['regular'].token)
        receipt['guest_http']=guest;receipt['other_actor_http']=other
        assert guest==401 and other==404,'private_fixture_boundary_required'
        for variant,max_side in [('thumb',320),('card',640),('preview',960),('detail',1280),('gallery',1920),('zoom',3072)]:
            code,headers,raw=media(PATH+'?variant='+variant,sessions['broker'].token)
            assert code==200,'variant_unavailable'
            normalized={k.lower():v for k,v in headers.items()}
            with Image.open(io.BytesIO(raw)) as im:
                im.load();width,height=im.size;exif=len(im.getexif());fmt=im.format
            row={'variant':variant,'http':code,'bytes':len(raw),'width':width,'height':height,
                'sha256':hashlib.sha256(raw).hexdigest(),'exif_tags':exif,'format':fmt,
                'cache_control':normalized.get('cache-control'),'served_variant':normalized.get('x-aqer-image-variant')}
            receipt['variants'].append(row)
            assert fmt=='JPEG' and exif==0 and max(width,height)<=min(max_side,2048),'bounded_sanitized_variant_required'
            assert row['served_variant']==variant and 'no-store' in (row['cache_control'] or ''),'private_response_required'
        assert receipt['variants'][1]['bytes']<receipt['input']['bytes'],'card_compression_required'
        receipt['status']='PASS'
    except Exception as error:
        receipt['reason']=str(error) if isinstance(error,(AssertionError,GateError)) else type(error).__name__
    finally:
        for alias,session in sessions.items():
            try:receipt['cleanup'][alias]=session.close()
            except Exception:receipt['cleanup'][alias]=False
        if not all(receipt['cleanup'].values()) or len(receipt['cleanup'])!=2:receipt['status']='BLOCKED'
        OUT.parent.mkdir(exist_ok=True)
        OUT.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'variants':len(receipt['variants']),'cleanup':receipt['cleanup']}))
    if receipt['status']!='PASS':raise SystemExit(1)

if __name__=='__main__':main()
