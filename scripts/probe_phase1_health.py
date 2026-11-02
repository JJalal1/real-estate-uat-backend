#!/usr/bin/env python3
"""Bounded public timing only. Keep the original25s diagnostic limit and failure."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import prepare_phase1_followup as build


def main():
    build.guard(os.environ)
    out=Path('phase1-followup-health'); out.mkdir()
    rows=[]
    # A longer diagnostic is separately labeled; it never replaces the first failed case.
    for number,limit in [(1,25),(2,90)]:
        with tempfile.TemporaryDirectory(prefix='aqer-health-') as directory:
            body=Path(directory)/'body'
            started=datetime.datetime.now(datetime.timezone.utc).isoformat()
            clock=time.monotonic()
            result=subprocess.run(['curl','--silent','--show-error','--proto','=https','--max-time',str(limit),
                '--output',str(body),'--write-out',
                '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}',
                '--header','Accept: application/json',build.API+'/health'],capture_output=True,text=True,timeout=limit+5)
            fields=result.stdout.strip().split()
            row={'attempt':number,'limit_seconds':limit,'started_utc':started,
                 'elapsed_ms':round((time.monotonic()-clock)*1000),'curl_exit':result.returncode,
                 'status':'FAIL','diagnostic_followup_of':1 if number==2 else None,
                 'warms_server_before_android':True}
            if len(fields)==6 and fields[0].isdigit():
                row.update(http_status=int(fields[0]),**{name:float(value) for name,value in zip(
                    ['dns_seconds','tcp_seconds','tls_seconds','first_byte_seconds','total_seconds'],fields[1:])})
            if result.returncode==0 and row.get('http_status')==200:
                try: row['database_ready']=json.loads(body.read_bytes()).get('database') is True
                except Exception: row['database_ready']=False
                row['status']='PASS' if row['database_ready'] else 'FAIL'
            elif result.returncode==28: row['reason']='curl_timeout'
            else: row['reason']='request_or_response_failed'
            rows.append(row)
            (out/'report.json').write_text(json.dumps({'source_commit':os.environ['SOURCE_COMMIT'],
                'api':build.API,'original_limit_seconds':25,'first_failure_preserved':True,
                'source_unchanged_no_server_fix_claim':True,'attempts':rows},indent=2)+'\n')
        if number==1 and row['status']=='PASS': break
    print('AQER_PHASE1_HEALTH_TIMING_RECORDED')
    # This step collects diagnostics; the report retains FAIL and is not release acceptance.
    return 0


if __name__=='__main__': raise SystemExit(main())
