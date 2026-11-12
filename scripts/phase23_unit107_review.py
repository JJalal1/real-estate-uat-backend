#!/usr/bin/env python3
"""Normal support API actions for the one owner-authorized synthetic listing107.

Never query an inbox or export credentials, contacts, owners or private messages.
The image-only first stage allows actual review before the bounded decision.
"""
import datetime, hashlib, json, os, re, subprocess, urllib.request
from pathlib import Path
from phase1_native_account_readiness import SECRET_NAME, validate_access
from phase23_preflight import API, NoRedirect, http
from run_phase23_native import Session

STAGE = 'start_image'
REVIEWED_IMAGE_SHA256 = ''
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'phase23-unit107-review'
BASE = '/admin/listing-review/listings/107'
TITLE = 'شقة النور الغربية اختبار المرحلة23'

def require(value, reason):
    if not value: raise RuntimeError(reason)

def request(session, method, path, body=None, expected=200):
    code, data = http(method, path, body, token=session.token)
    require(code == expected, 'unexpected_http_'+str(code))
    return data.get('data', {})

def metadata(detail):
    return {k: detail.get(k) for k in ('id','status','review_status','submitted_at','published_at','likely_duplicate_count') } | {
        'asset_id':detail.get('property_asset',{}).get('id'),
        'images':[{'id':r.get('id'),'decision':r.get('relevance_review',{}).get('decision')} for r in detail.get('images',[])],
        'review_history':[{'id':r.get('id'),'action':r.get('action'),'from':r.get('from'),'to':r.get('to'),'created_at':r.get('created_at')} for r in detail.get('review_history',[])]}

def image_bytes(session):
    req=urllib.request.Request(API+'/property-media/176', headers={'Authorization':'Bearer '+session.token,'Accept':'image/*'})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=30) as response:
        require(response.status==200 and response.headers.get('Content-Type','').startswith('image/'),'image_response_invalid')
        content=response.read(12*1024*1024+1)
    require(0<len(content)<=12*1024*1024,'image_size_invalid')
    return content

def main():
    require(os.environ.get('GITHUB_REPOSITORY')=='JJalal1/real-estate-uat-backend','wrong_repo')
    require(os.environ.get('GITHUB_REF')=='refs/heads/work/phase23-acceptance-20261111','wrong_branch')
    require(os.environ.get('GITHUB_EVENT_NAME')=='push','wrong_event')
    require(subprocess.check_output(['git','rev-parse','HEAD:mobile_app'],cwd=ROOT,text=True).strip()=='9c60a4c704cd783352847363d737028f839f7813','product_tree_changed')
    require(subprocess.check_output(['git','rev-parse','HEAD:backend-api-runtime'],cwd=ROOT,text=True).strip()=='e36417aca4233488220a6c8e2951ea0709f601a0','backend_tree_changed')
    receipt={'run_id':os.environ['GITHUB_RUN_ID'],'source_sha':os.environ['GITHUB_SHA'],'stage':STAGE,
        'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'BLOCKED','listing_id':107,
        'scope':'Only synthetic listing107 belonging to configured broker28; normal support6 API; no inbox or private conversation query.',
        'native_acceptance_claimed':False,'cleanup':{}}
    session=None
    try:
        access=validate_access(os.environ.pop(SECRET_NAME,''));session=Session('support',access);session.login();del access
        detail=request(session,'GET',BASE)
        require(detail.get('id')==107 and detail.get('title')==TITLE and detail.get('owner',{}).get('id')==28,'fixture_identity_mismatch')
        require([r.get('id') for r in detail.get('images',[])]==[176],'fixture_media_changed')
        receipt['before']=metadata(detail)
        if STAGE=='start_image':
            require(detail.get('review_status')=='submitted' and detail.get('property_asset',{}).get('id')==101,'negative_fixture_not_ready')
            request(session,'POST',BASE+'/start')
            image=image_bytes(session);OUT.mkdir(exist_ok=True);(OUT/'REVIEW_IMAGE_176.jpg').write_bytes(image)
            receipt['image_sha256']=hashlib.sha256(image).hexdigest();receipt['image_bytes']=len(image)
            receipt['after']=metadata(request(session,'GET',BASE));receipt['status']='READY_FOR_IMAGE_REVIEW'
        elif STAGE=='negative_return':
            require(re.fullmatch('[a-f0-9]{64}',REVIEWED_IMAGE_SHA256) is not None,'explicit_review_hash_required')
            require(detail.get('review_status')=='under_review' and detail.get('property_asset',{}).get('id')==101,'negative_fixture_not_ready')
            require(hashlib.sha256(image_bytes(session)).hexdigest()==REVIEWED_IMAGE_SHA256,'reviewed_image_changed')
            media=detail['images'][0]
            reviewed=request(session,'POST',BASE+'/media-review',{'image_id':176,'image_token':media['relevance_token'],'decision':'relevant','reason':'صورة مبنى اصطناعية مناسبة؛ راجعت الصورة176 نفسها قبل قرار المراجعة في اختبار المرحلة23.'})
            receipt['media_review']={k:reviewed.get(k) for k in ('review_id','decision','checker')}
            code,body=http('POST',BASE+'/approve',{'reason':'محاولة سلبية متعمدة: الوحدة الشرقية نفسها المنشورة106؛ يجب منع النشر.'},token=session.token)
            require(code==409,'duplicate_approval_was_not_blocked_'+str(code))
            message=body.get('message','');require(any(x in message for x in ('منشور','مسجل','يطابق','تكرار','published')),'conflict_not_identified_as_duplicate')
            receipt['negative_approval']={'http':code,'duplicate_conflict':True};del body,message
            request(session,'POST',BASE+'/return',{'reason':'اختبار تكرار مؤكد مع الوحدة الشرقية في الإعلان106. صحح موضع الوحدة إلى غربية 2 مرحلة23 ثم أعد إرسال الإعلان107 نفسه.'})
            detail=request(session,'GET',BASE);require(detail.get('review_status')=='returned_for_correction' and detail.get('published_at') is None,'return_not_persisted')
            receipt['after']=metadata(detail);receipt['status']='PASS_DUPLICATE_BLOCK_AND_RETURN'
        else:
            raise RuntimeError('unreviewed_stage')
    except Exception as error:
        receipt['error_type']=type(error).__name__
        if isinstance(error,RuntimeError):receipt['reason_code']=str(error)
    finally:
        if session:
            try:receipt['cleanup']['support']=session.close()
            except Exception:receipt['cleanup']['support']=False
        if receipt['cleanup'].get('support') is not True:receipt['status']='BLOCKED'
        OUT.mkdir(exist_ok=True);(OUT/'RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps({'status':receipt['status'],'cleanup':receipt['cleanup']}))
    require(receipt['status']!='BLOCKED','review_stage_blocked')

if __name__=='__main__':main()
