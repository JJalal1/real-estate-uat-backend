"""Strictly numeric callback-harness telemetry; never export arbitrary AX text."""
import json

MARKER = 'AQER_PHASE23_CALLBACK_HARNESS_V1'
FIELDS = frozenset(('v','actor','bLogin','bSeed','bEpoch','aiCapture','aiEpoch','aiRelease','aiComplete',
    'resultsCapture','resultsEpoch','resultsRelease','resultsComplete','gpsCapture','gpsEpoch',
    'gpsRelease','gpsComplete','cancelled','cacheClean','errors','forbidden'))
CONTROLS = frozenset(('CB controls','CB hide','CB AI start','CB results start','CB editor','CB seed B',
    'CB release AI','CB release results','CB release GPS', MARKER,
    *('CB '+kind+' '+state for kind in ('AI','results','GPS') for state in ('idle','held','PASS','FAIL'))))

def safe_callback_label(label):
    if label in CONTROLS:
        return label
    if not isinstance(label,str) or not label.startswith('CB-META:') or len(label)>600:
        return None
    try:
        value=json.loads(label[8:])
    except (ValueError,TypeError):
        return None
    if not isinstance(value,dict) or set(value)!=FIELDS or any(type(x) is not int or not -1<=x<=100000 for x in value.values()):
        return None
    if value['v']!=1 or value['actor'] not in (0,1,2) or value['cancelled'] not in (0,1):
        return None
    return 'CB-META:'+json.dumps(value,separators=(',',':'),sort_keys=True)


def completed_callback_proof(label):
    safe=safe_callback_label(label)
    if safe is None or not safe.startswith('CB-META:'):
        return False
    v=json.loads(safe[8:])
    if v['actor']!=2 or v['errors']!=0 or v['forbidden']!=0 or v['cancelled']!=1 or v['cacheClean']!=1:
        return False
    if not 0<v['bLogin']<v['bSeed'] or v['bEpoch']<0:
        return False
    for kind in ('ai','results','gps'):
        if not 0<v[kind+'Capture']<v['bLogin']<v['bSeed']<v[kind+'Release']<v[kind+'Complete']:
            return False
        if v[kind+'Epoch']<0 or v[kind+'Epoch']==v['bEpoch']:
            return False
    return True
