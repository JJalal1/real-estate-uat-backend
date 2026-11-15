#!/usr/bin/env python3
"""Describe the known UAT account's contact format without exporting a number."""
import datetime,json,os,re
from pathlib import Path
from phase1_native_account_readiness import SECRET_NAME,validate_access
from phase23_preflight import http
from run_phase23_native import Session
def normalize(s):
    s=s.translate(str.maketrans('٠١٢٣٤٥٦٧٨٩','0123456789'))
    s=re.sub(r'[\s()\-]','',s.strip())
    return s[4:] if s.startswith('+967') else s[5:] if s.startswith('00967') else s
def valid(s):
    return bool(re.fullmatch(r'7[0-9]{8}',s)) and s[:2] in {'70','71','73','77','78'}
def main():
    assert os.environ.get('GITHUB_REPOSITORY')=='JJalal1/real-estate-uat-backend'
    assert os.environ.get('GITHUB_REF')=='refs/heads/work/phase23-acceptance-20261111'
    access=validate_access(os.environ.pop(SECRET_NAME,''))
    session=Session('broker',access);del access
    out={'run_id':os.environ['GITHUB_RUN_ID'],'source_sha':os.environ['GITHUB_SHA'],'scope':'synthetic actor28 contact-format metadata only; no number exported','status':'BLOCKED'}
    try:
        session.login()
        code,body=http('GET','/auth/me',token=session.token)
        assert code==200
        user=body.get('data',{}).get('user',{})
        raw=user.get('phone') or ''
        current=normalize(raw)
        candidate=current[3:] if len(current)==12 and current.startswith('967') else current
        out.update(account_phone_present=bool(raw),account_phone_characters=len(raw),
            account_prefix_mode='plus967' if raw.startswith('+967') else '00967' if raw.startswith('00967') else 'plain967' if raw.startswith('967') else 'other',
            current_listing_normalizer_valid=valid(current),bare_country_normalizer_valid=valid(candidate))
        code,body=http('GET','/properties/106/contact',token=session.token)
        known=body.get('data',{}).get('phone') or ''
        out.update(existing_fixture_contact_http=code,existing_fixture_contact_valid=valid(normalize(known)),
            same_as_account_after_country_normalization=normalize(known)==candidate)
        raw=current=candidate=known=None;out['status']='OBSERVED'
    except Exception as error:out['reason']=type(error).__name__
    finally:
        out['session_closed']=session.close()
        if not out['session_closed']:out['status']='BLOCKED'
        folder=Path('phase23-contact-shape-evidence');folder.mkdir(exist_ok=True)
        (folder/'RECEIPT.json').write_text(json.dumps(out,indent=2)+'\n')
    print(json.dumps(out))
    if out['status']=='BLOCKED':raise SystemExit(1)
if __name__=='__main__':main()

