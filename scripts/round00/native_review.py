"""ADB interaction with real release Flutter rendering; no Widget test or fake map.

Each case records actual evidence, including blocked controls. A successful
evidence collection job is not a claim that all user journeys passed.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'round00-out'
PACKAGE = 'com.aqer.yemen.uat'
ACTIVITY = PACKAGE + '/com.example.real_estate_mobile.MainActivity'
assert os.environ.get('AQER_ROUND00_DISPOSABLE') == '20261030'
report = {'kind':'actual-Android-APK-ADB-navigation','synthetic_widgets':False,
    'offline_fallback':os.environ.get('ROUND00_OFFLINE_FALLBACK')=='true',
    'product_source':'03f77c1233776ef89868392b8afc0201a1dccdf5','cases':[],
    'data':'synthetic disposable matching Laravel/PostGIS and actual JPEG bytes',
    'limits':['x86_64 release rebuild; not original UAT1443 signature/bytes',
        'Runner CPU/GPU and local network are not owner handset or Render/Storage performance',
        'Android gfxinfo is not a complete Flutter raster/decode timing measurement'],
    'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
if report['offline_fallback']:
    report['data']='Offline environment; all Android outbound traffic rejected. No backend acceptance.'

def adb(*args, timeout=25, check=True, binary=False):
    r = subprocess.run(['adb',*args],capture_output=True,text=not binary,timeout=timeout)
    if check and r.returncode:
        raise RuntimeError('adb '+str(args[:3])+': '+str(r.stderr)[:200])
    return r.stdout

def save():
    (OUT/'REVIEW.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')

def screenshot(name):
    path = OUT / (name+'.png')
    path.write_bytes(adb('exec-out','screencap','-p',binary=True))
    assert path.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
    return path.name

def tree(name):
    adb('shell','rm','-f','/sdcard/round00.xml',check=False)
    raw = adb('shell','uiautomator','dump','/sdcard/round00.xml',timeout=20,check=False)
    xml = adb('shell','cat','/sdcard/round00.xml',check=False)
    (OUT/(name+'.xml')).write_text(xml)
    try:
        nodes = list(ET.fromstring(xml).iter('node'))
    except ET.ParseError:
        nodes = []
    return nodes

def label(node):
    return (node.get('text','')+' '+node.get('content-desc','')).strip()

def bounds(node):
    values = [int(x) for x in re.findall(r'\d+',node.get('bounds',''))]
    return values if len(values)==4 else [0,0,0,0]

def tap_text(text, name, *, exact=False):
    nodes = tree(name)
    matches = [node for node in nodes if (label(node)==text if exact else text in label(node))
        and bounds(node)[2]>bounds(node)[0] and bounds(node)[3]>bounds(node)[1]]
    if not matches:
        return False
    node = min(matches,key=lambda n:(bounds(n)[2]-bounds(n)[0])*(bounds(n)[3]-bounds(n)[1]))
    left,top,right,bottom = bounds(node)
    adb('shell','input','tap',str((left+right)//2),str((top+bottom)//2))
    time.sleep(1.2)
    return True

def snapshot(name):
    nodes = tree(name)
    time.sleep(.5)
    image = screenshot(name)
    return {'screen':image,'tree':name+'.xml','labels':[label(n) for n in nodes if label(n)][:120]}

def case(key, status, actual, expected, evidence=None):
    report['cases'].append({'id':key,'status':status,'actual':actual,'expected':expected,'evidence':evidence or []})
    save()

def swipe(up=True):
    adb('shell','input','swipe','780','1600' if up else '480','780','480' if up else '1600','650')
    time.sleep(.8)

def api_rows():
    p=OUT/'http.jsonl'
    return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []

def home():
    if tap_text('العقارات','seek-home-tab',exact=True):
        return True
    adb('shell','input','keyevent','4');time.sleep(1)
    return tap_text('العقارات','seek-home-tab-back',exact=True)

recording = None
try:
    report['android_api'] = adb('shell','getprop','ro.build.version.sdk').strip()
    report['device_model'] = adb('shell','getprop','ro.product.model').strip()
    report['device_size'] = adb('shell','wm','size').strip()
    report['device_density'] = adb('shell','wm','density').strip()
    report['kernel_page_bytes'] = adb('shell','getconf','PAGESIZE').strip()
    adb('logcat','-c')
    adb('shell','cmd','uimode','night','no')
    adb('shell','am','force-stop',PACKAGE)
    adb('shell','dumpsys','gfxinfo',PACKAGE,'reset',check=False)
    started=time.perf_counter()
    launch = adb('shell','am','start','-W','-n',ACTIVITY,timeout=60)
    report['launch_am_start_W'] = launch
    (OUT/'launch-am-start.txt').write_text(launch)
    frames=[]
    for seconds in [.3,1,2,4,7,10]:
        delay=seconds-(time.perf_counter()-started)
        if delay>0: time.sleep(delay)
        name=f'01-cold-start-{seconds:g}s'
        file=screenshot(name)
        frames.append({'file':file,'capture_completed_ms_after_launch_command':round((time.perf_counter()-started)*1000,1)})
    report['startup_screenshot_samples']=frames
    before=snapshot('02-home-initial')
    # OS location permission is intentionally denied; no real GPS/user location.
    for permission in ["Don't allow",'عدم السماح','Not now','لاحقًا']:
        if tap_text(permission,'permission-dialog'):
            time.sleep(2)
    region_choice = tap_text('المتابعة الآن','initial-region-continue')
    if region_choice:
        time.sleep(3)
    report['initial_region_choice_continued'] = region_choice
    initial=snapshot('03-home-after-permission')
    pid=adb('shell','pidof',PACKAGE,check=False).strip()
    case('R00-01','passed' if pid else 'failed',{'process_pid':pid,'launch':launch},
         'APK starts and stays running',[before['screen'],initial['screen'],'launch-am-start.txt'])
    initial_api=api_rows()
    homes=[r for r in initial_api if r['path'].startswith('/api/marketplace')]
    case('R00-02','executed_needs_visual_review' if any(r['status']==200 for r in homes) else 'blocked',
         {'marketplace_requests':homes,'visible_labels':initial['labels']},
         'Real matching Laravel returns feed and actual rendered Home exposes sections/cards',[initial['screen'],initial['tree'],'http.jsonl'])

    recording = subprocess.Popen(['adb','shell','screenrecord','--bit-rate','3000000','--time-limit','150','/sdcard/round00-navigation.mp4'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    time.sleep(.5)
    before_count=len([r for r in api_rows() if r['path'].startswith('/api/property-media/')])
    for index in range(3):
        swipe(True)
        snapshot(f'04-scroll-down-{index+1}')
    for index in range(3):
        swipe(False)
        snapshot(f'05-scroll-up-{index+1}')
    after_count=len([r for r in api_rows() if r['path'].startswith('/api/property-media/')])
    scroll=snapshot('06-home-after-return-scroll')
    case('R00-03','executed_needs_visual_review',
         {'down_swipes':3,'up_swipes':3,'image_requests_before':before_count,'image_requests_after':after_count},
         'Scroll down/up, retained images reappear and no crash/freeze',['04-scroll-down-3.png',scroll['screen'],'http.jsonl'])

    # Prefer the actual card tap; record deep-link fallback separately.
    opened=tap_text('عقار اختبار محاكاة','find-property-card')
    route='card_tap'
    if not opened:
        for _ in range(2): swipe(True)
        opened=tap_text('عقار اختبار محاكاة','find-property-card-after-scroll')
    if not opened:
        route='deep_link_fallback_card_tap_blocked'
        adb('shell','am','start','-W','-a','android.intent.action.VIEW','-d','realestate://app/properties/1',PACKAGE)
    time.sleep(3)
    details=snapshot('07-property-details')
    detail_requests=[r for r in api_rows() if re.match(r'^/api/properties/\d+(\?|$)',r['path'])]
    case('R00-04','executed_needs_visual_review' if any(r['status']==200 for r in detail_requests) else 'blocked',
         {'entry':route,'detail_requests':detail_requests,'visible_labels':details['labels']},
         'Tap real property card, view details, then back to retained list',[details['screen'],details['tree']])
    adb('shell','input','keyevent','4');time.sleep(1.5)
    returned=snapshot('08-return-from-details')
    case('R00-05','executed_needs_visual_review',{'visible_labels':returned['labels']},
         'Back returns to previous listing feed',[returned['screen']])

    home()
    for _ in range(4): swipe(False)
    map_open=tap_text('الخريطة','find-map-entry')
    if map_open:
        time.sleep(6)
        map_before=snapshot('09-map-before-pan')
        # Collapse the existing panel when needed, then pan an exposed map area.
        tap_text('تصغير الفلاتر','collapse-map-panel')
        rows_before=api_rows()
        adb('shell','input','swipe','780','750','330','1000','900');time.sleep(3)
        map_after=snapshot('10-map-after-pan')
        map_queries=[r for r in api_rows()[len(rows_before):] if '/api/properties/nearby' in r['path']]
        case('R00-06','executed_needs_visual_review',{'pan_gesture':True,'new_viewport_requests':map_queries,
             'before_screen_sha256':hashlib.sha256((OUT/map_before['screen']).read_bytes()).hexdigest(),
             'after_screen_sha256':hashlib.sha256((OUT/map_after['screen']).read_bytes()).hexdigest()},
             'Actual MapLibre basemap loads and pans, with matching local property API',[map_before['screen'],map_after['screen'],'isolated-dns.txt','http.jsonl'])
        adb('shell','input','keyevent','4');time.sleep(1)
    else:
        case('R00-06','blocked','Map entry not located in Android accessibility tree','Open and pan the real map',['find-map-entry.xml'])

    home()
    tabs=[]
    for text,name in [('الرسائل','11-messages-tab'),('إعلاناتي','12-listings-tab'),('حسابي','13-account-tab')]:
        clicked=tap_text(text,'find-'+name,exact=True)
        evidence=snapshot(name)
        tabs.append({'label':text,'clicked':clicked,'evidence':evidence['screen'],'visible_labels':evidence['labels']})
    case('R00-07','executed_needs_visual_review' if all(t['clicked'] for t in tabs) else 'blocked',tabs,
         'Main guest tabs navigate or show the expected sign-in gate',[t['evidence'] for t in tabs])
    theme=tap_text('المظهر','find-theme-row')
    dark=theme and tap_text('داكن','find-dark-mode')
    time.sleep(1)
    dark_account=snapshot('14-dark-account')
    home();time.sleep(1)
    dark_home=snapshot('15-dark-home')
    if dark:
        tap_text('حسابي','revisit-dark-account',exact=True)
        time.sleep(2)
        snapshot('16-dark-account-revisited')
    case('R00-08','executed_needs_visual_review' if dark else 'blocked',{'theme_row_opened':theme,'dark_selected':dark,
         'visible_labels':dark_home['labels']},'Switch to dark using actual account UI; check RTL/text/buttons',
         [dark_account['screen'],dark_home['screen']])
    report['final_process_alive']=bool(adb('shell','pidof',PACKAGE,check=False).strip())
    report['app_http_errors']=[r for r in api_rows() if r['status']>=400]
    report['api_environment_confirmed_local']=not report['offline_fallback'] and (OUT/'isolated-dns.txt').exists() and '(127.0.0.1)' in (OUT/'isolated-dns.txt').read_text()
    report['app_reached_matching_local_api']=any(r['path'].startswith('/api/marketplace') and
        r['status']==200 and r.get('contract')=='2' for r in api_rows())
except Exception as error:
    report['probe_error']={'type':type(error).__name__,'message':str(error)[:800]}
    try: screenshot('99-probe-error')
    except Exception: pass
finally:
    if recording is not None:
        adb('shell','pkill','-2','screenrecord',check=False)
        try: recording.wait(timeout=15)
        except subprocess.TimeoutExpired: recording.kill()
        adb('pull','/sdcard/round00-navigation.mp4',str(OUT/'round00-navigation.mp4'),check=False,timeout=40)
    for command,name in [(['logcat','-d','-b','crash'],'crash-buffer.txt'),
        (['shell','dumpsys','gfxinfo',PACKAGE,'framestats'],'gfxinfo-final.txt'),
        (['shell','dumpsys','meminfo',PACKAGE],'meminfo-final.txt')]:
        try: (OUT/name).write_text(adb(*command,check=False))
        except Exception: pass
    try:
        pid=adb('shell','pidof',PACKAGE,check=False).strip().split()[0]
        (OUT/'app-logcat.txt').write_text(adb('logcat','-d','--pid='+pid,check=False))
    except Exception: pass
    report['ended_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    report['evidence_collection_complete']=not bool(report.get('probe_error'))
    report['release_acceptance']=False
    save()
    print(json.dumps({'cases':[(x['id'],x['status']) for x in report['cases']],
        'probe_error':report.get('probe_error'),'collection_complete':report['evidence_collection_complete']},ensure_ascii=False))
    if not report.get('final_process_alive'): raise SystemExit(1)
