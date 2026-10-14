import json,re,time,urllib.error,urllib.request

BASE='https://real-estate-uat-api-frankfurt.onrender.com/api'
paths=['/health','/marketplace','/marketplace','/marketplace?type=apartment','/marketplace/locations','/health']
for index,path in enumerate(paths):
    started=time.monotonic();body=b'';status=0;kind='';error=None
    request=urllib.request.Request(BASE+path,headers={'Accept':'application/json','User-Agent':'RealEstate-UAT/startup-diagnosis'})
    try:
        with urllib.request.urlopen(request,timeout=70) as response:
            status=response.status;kind=response.headers.get('Content-Type','');body=response.read(2_000_000)
    except urllib.error.HTTPError as failure:
        status=failure.code;kind=failure.headers.get('Content-Type','');body=failure.read(50_000)
    except (OSError,TimeoutError) as failure:
        error=type(failure).__name__
    result={'index':index,'path':path,'status':status,'duration_ms':round((time.monotonic()-started)*1000),'mime':kind,'bytes':len(body),'transport_error':error}
    try:
        data=json.loads(body)
        result['json_object']=isinstance(data,dict)
        if isinstance(data,dict):
            result['health_ok']=data.get('ok') if isinstance(data.get('ok'),bool) else data.get('status')=='ok'
            payload=data.get('data')
            if isinstance(payload,dict) and isinstance(payload.get('sections'),dict):result['section_counts']={k:len(v) for k,v in payload['sections'].items() if isinstance(v,list)}
            if isinstance(payload,list):result['rows']=len(payload)
            if status>=400:
                message=str(data.get('message',''));sqlstate=re.search(r'SQLSTATE\[([A-Z0-9]+)\]',message)
                column=re.search(r'column [\"\']([A-Za-z_][A-Za-z_0-9.]*)[\"\'] does not exist',message)
                result['exception']=str(data.get('exception',''))[:120];result['sqlstate']=sqlstate.group(1) if sqlstate else None;result['missing_column']=column.group(1) if column else None
                result['server_error_generic']=message in ['Server Error','Service Unavailable']
    except (ValueError,TypeError):
        result['json_object']=False;result['render_startup_page']=any(v in body.lower() for v in [b'starting up',b'service is waking',b'spinning up'])
    print('UAT_HOME_PROBE '+json.dumps(result,sort_keys=True),flush=True)
