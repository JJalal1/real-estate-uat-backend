#!/usr/bin/env python3
"""Read only known synthetic case9 and export an explicit metadata allowlist."""
import datetime,json,os,subprocess
from pathlib import Path
from phase1_native_account_readiness import SECRET_NAME,validate_access
from phase23_preflight import http
from run_phase23_native import Session

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'phase23-case9-metadata/RECEIPT.json'
STATUSES={'open','in_progress','waiting_user','resolved','closed','rejected','dismissed'}
EVENTS={'support.case_created','support.case_started','support.case_assigned',
        'support.status_changed','support.case_status_changed','support.case_resolved',
        'support.internal_note_added','support.reply_added','support.case_reopened',
        'support_case.created','support_case.started','support_case.status_changed'}

def main():
    assert os.environ.get('GITHUB_REPOSITORY')=='JJalal1/real-estate-uat-backend'
    assert os.environ.get('GITHUB_REF')=='refs/heads/work/phase23-acceptance-20261111'
    assert os.environ.get('GITHUB_EVENT_NAME')=='push'
    assert subprocess.check_output(['git','rev-parse','HEAD:backend-api-runtime'],cwd=ROOT,text=True).strip()=='e36417aca4233488220a6c8e2951ea0709f601a0'
    receipt={'run_id':os.environ['GITHUB_RUN_ID'],'source_sha':os.environ['GITHUB_SHA'],
        'scope':'Known synthetic case9/thread37/requester26 only. No inbox query or case content export.',
        'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'BLOCKED',
        'case_id':9,'target_id':37,'private_content_exported':False,'cleanup':{}}
    session=None
    try:
        access=validate_access(os.environ.pop(SECRET_NAME,''))
        session=Session('support',access);session.login();del access
        code,body=http('GET','/admin/support/cases/9',token=session.token)
        receipt['http']=code
        if code in (403,404):receipt['status']='ROLE_BOUNDARY';return
        assert code==200
        data=body.get('data',{})
        assert data.get('id')==9 and data.get('kind')=='report'
        assert data.get('target_type')=='conversation_thread' and data.get('target_id')==37
        assert data.get('requester',{}).get('id')==26
        state=data.get('status');assert state in STATUSES
        assigned=data.get('assigned_to_user_id');assert assigned in (None,6)
        receipt['case_status']=state;receipt['assigned_to_user_id']=assigned
        receipt['message_count']=len(data.get('messages',[]))
        receipt['events']=[{'id':row.get('id') if isinstance(row.get('id'),int) else None,
            'code':row.get('event') if row.get('event') in EVENTS else 'other_event',
            'from_status':row.get('from_status') if row.get('from_status') in STATUSES else None,
            'to_status':row.get('to_status') if row.get('to_status') in STATUSES else None}
            for row in data.get('events',[])[:100]]
        receipt['status']='OBSERVED_METADATA_ONLY'
        del body,data
    except Exception as error:
        receipt['error_type']=type(error).__name__
    finally:
        if session:
            try:receipt['cleanup']['support']=session.close()
            except Exception:receipt['cleanup']['support']=False
        if receipt['cleanup'].get('support') is not True:receipt['status']='BLOCKED'
        OUT.parent.mkdir(exist_ok=True);OUT.write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'status':receipt['status'],'cleanup':receipt['cleanup']}))
    if receipt['status']=='BLOCKED':raise SystemExit(1)

if __name__=='__main__':main()
