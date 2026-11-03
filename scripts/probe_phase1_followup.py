#!/usr/bin/env python3
"""Only incomplete native Phase1 journeys; no credentials, owner sessions or account writes."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.parse
import urllib.request

import prepare_phase1_followup as build
import probe_phase1_android_ui as core
from probe_phase1_uat_guest import GuestProbe, Blocked, NoRedirect, node_bounds, node_labels, FIXTURE_TITLE

ROOT = Path(__file__).resolve().parents[1]
INPUT = 'com.aqer.phase1.input'
QUERY = 'شقة للإيجار'


def input_receipt(output, op):
    # Read only a strict result allowlist. Never retain instrumentation output.
    values = {}
    for key in ['passed', 'op', 'events', 'inter_tap_ms', 'inter_tap_lower_ms', 'inter_tap_upper_ms', 'event_ms', 'return_ms', 'text_matched','focused_set_text_handler','semantic_click_delivered']:
        rows = re.findall(r'^INSTRUMENTATION_RESULT: ' + key + r'=([^\r\n]+)', output, re.M)
        if len(rows) > 1:
            raise Blocked('ambiguous_input_receipt')
        if rows:
            values[key] = rows[0]
    if values.get('passed') != 'true' or values.get('op') != op or not re.search(r'^INSTRUMENTATION_CODE: -1\s*$', output, re.M):
        raise Blocked('native_input_not_delivered')
    receipt = {'op': op, 'passed': True}
    if op=='submit-query':
        if values.get('semantic_click_delivered')!='true': raise Blocked('semantic_submit_not_delivered')
        receipt['semantic_click_delivered']=True
    elif op in ['fixture-query', 'negative-query', 'clear-query']:
        if values.get('text_matched') != 'true' or values.get('focused_set_text_handler')!='true':
            raise Blocked('native_query_not_matched')
        receipt['text_matched'] = True
        receipt['focused_set_text_handler'] = True
    else:
        count = 4 if op == 'double-tap' else 19
        if values.get('events') != str(count):
            raise Blocked('native_input_event_count_mismatch')
        receipt['events'] = count
        for key in ['event_ms','return_ms']:
            raw=values.get(key,'')
            if not re.fullmatch('[0-9]+(?:,[0-9]+)*',raw): raise Blocked('native_event_timings_missing')
            times=[int(v) for v in raw.split(',')]
            if len(times)!=count or times!=sorted(times) or any(v>10000 for v in times):
                raise Blocked('native_event_timings_invalid')
            receipt[key]=times
        if any(a>b for a,b in zip(receipt['event_ms'],receipt['return_ms'])):
            raise Blocked('native_event_return_precedes_dispatch')
        if op == 'double-tap':
            interval = values.get('inter_tap_ms', '')
            if not interval.isdigit() or not 40 <= int(interval) <= 300:
                raise Blocked('native_double_tap_interval_unproven')
            receipt['inter_tap_ms'] = int(interval)
            for key in ['inter_tap_lower_ms','inter_tap_upper_ms']:
                value=values.get(key,'')
                if not value.isdigit() or not 40<=int(value)<=300:
                    raise Blocked('native_delivery_interval_unproven')
                receipt[key]=int(value)
    return receipt


def input_failure_diagnostic(output):
    result={}
    for key in ['stage','events','event_ms','return_ms']:
        rows=re.findall(r'^INSTRUMENTATION_RESULT: '+key+r'=([^\r\n]*)',output,re.M)
        if len(rows)!=1: continue
        value=rows[0]
        if key=='stage' and value in ['guard','automation','root_ready','query_focus','query_action','query_match','submit_action','double_tap','pinch','complete']:
            result[key]=value
        elif key=='events' and value.isdigit() and int(value)<=20: result[key]=int(value)
        elif key in ['event_ms','return_ms'] and re.fullmatch(r'[0-9]+(?:,[0-9]+){0,19}',value):
            values=[int(v) for v in value.split(',')]
            if all(v<=10000 for v in values): result[key]=values
    return result


def photo_difference(first, second):
    from PIL import Image, ImageChops, ImageStat
    # Inspect only the photo's central rectangle; exclude counters, hints and controls.
    with Image.open(first) as a, Image.open(second) as b:
        if a.size != b.size or a.size != (1080, 1920):
            raise Blocked('gallery_frame_geometry_changed')
        region = (216, 720, 864, 1200)
        difference = ImageChops.difference(a.convert('RGB').crop(region), b.convert('RGB').crop(region))
        mean = sum(ImageStat.Stat(difference).mean) / 3
        pixels = difference.getdata()
        changed = sum(max(pixel) > 20 for pixel in pixels) / (648 * 480)
    return {'mean_absolute_difference': round(mean, 3), 'changed_fraction': round(changed, 4),
            'region': list(region), 'photo_scale_requires_visual_review': True}


def visible_map_handle(path):
    """Locate the actually rendered centered42dp grip, not an oversized semantic rect."""
    from PIL import Image
    with Image.open(path) as source:
        if source.size!=(1080,1920): raise Blocked('map_frame_geometry_changed')
        pixels=source.convert('RGB').load()
        def grip(x,y): return all(abs(a-b)<=2 for a,b in zip(pixels[x,y],(227,234,241)))
        rows=[]
        for y in range(300,1810):
            if not grip(540,y): continue
            left=right=540
            while left>320 and grip(left-1,y): left-=1
            while right<760 and grip(right+1,y): right+=1
            if 80<=right-left+1<=150 and abs((left+right)/2-540)<=30: rows.append((y,left,right))
        groups=[]
        for row in rows:
            if not groups or row[0]!=groups[-1][-1][0]+1: groups.append([])
            groups[-1].append(row)
        candidates=[]
        for group in groups:
            if not 6<=len(group)<=20: continue
            top,bottom=group[0][0],group[-1][0]+1
            white=sum(min(pixels[x,y])>=250 for y in [top-12,bottom+12] for x in range(400,681))/562
            if white<.99: continue
            candidates.append([min(r[1] for r in group),top,max(r[2] for r in group)+1,bottom])
        if len(candidates)!=1: raise Blocked('unique_visible_map_handle_not_observed')
        return candidates[0]


class Followup(GuestProbe):
    def __init__(self, root, env, run=core.execute):
        self.version = build.guard(env)
        self.root, self.env, self.run = root, env, run
        self.serial = None
        self.out = root / 'phase1-followup-evidence'
        self.installed = False
        self.driver_installed = False
        self.recorder = None
        self.created = False
        self.live_fixture = False
        self.report = {'scope': 'actual-UAT-incomplete-journeys-only', 'cases': [], 'frames': [],
            'source_commit': env['SOURCE_COMMIT'], 'api': core.API,
            'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'ci_run_id': env['GITHUB_RUN_ID'], 'ci_run_number': int(env['GITHUB_RUN_NUMBER']),
            'product_baseline': build.BASE, 'reused_ci': 'CI457 / APK1457',
            'accounts': ['guest'], 'account_writes': False, 'fixture_ids': [60],
            'permitted_live_side_effects': ['normal synthetic listing60 view analytics'],
            'synthetic_widgets': False, 'phase1_accepted': False,
            'visual_review_required': True, 'host_oracle_is_not_mobile_network_trace': True,
            'limitations': ['Authenticated roles/drafts/review require approved existing login',
                            'FCM/audio/GPS physical acceptance not certified']}

    def validate_environment(self):
        receipt = build.source_receipt(self.env)
        private = self.root / 'phase1-followup-private'
        self.proof = json.loads((private / 'APK_VERIFICATION.json').read_text())
        self.apk = private / 'target.apk'
        # This pure validator expresses version=1000+series; the real workflow ID/number
        # are separately retained above and are never replaced or misattributed.
        core.validate_proof(self.proof, self.apk.read_bytes(), self.env['SOURCE_COMMIT'], self.version - 1000)
        if self.proof['product_trees'] != receipt['product_trees']:
            raise core.GateError('followup_product_tree_mismatch')
        sdk = Path(self.env['ANDROID_HOME'])
        if 'KVM' not in self.command([sdk / 'emulator/emulator', '-accel-check']):
            raise core.GateError('kvm_required')
        serials = re.findall(r'^(emulator-[0-9]+)\s+device\s*$', self.command(['adb', 'devices']), re.M)
        if len(serials) != 1:
            raise core.GateError('one_disposable_emulator_required')
        self.serial = serials[0]
        for key, expected in [('ro.boot.qemu', '1'), ('sys.boot_completed', '1'), ('ro.build.version.sdk', '36')]:
            if self.adb('shell', 'getprop', key) != expected:
                raise core.GateError('booted_disposable_api36_required')
        self.adb('root')
        self.adb('wait-for-device', timeout=30)
        for package in [core.PACKAGE, INPUT]:
            if self.adb('shell', 'pm', 'path', package, codes=(0, 1)):
                raise core.GateError('fresh_followup_install_required')
        if self.adb('reverse', '--list') or build.API.removeprefix('https://').split('/')[0] in self.adb('shell', 'cat', '/etc/hosts'):
            raise core.GateError('real_uat_route_override_refused')
        for tool in ['iptables', 'ip6tables']:
            for action in ['DROP', 'REJECT']:
                result = self.run(['adb', '-s', self.serial, 'shell', tool, '-C', 'OUTPUT', '-j', action])
                if result.returncode != 1:
                    raise core.GateError('preexisting_emulator_network_block_refused')
        self.report.update(android_api=36, version_code=self.version, apk_sha256=self.proof['sha256'],
                           certificate_sha256=self.proof['certificate_sha256'], product_trees=receipt['product_trees'])
        self.driver = private / 'input.apk'
        if hashlib.sha256(self.driver.read_bytes()).hexdigest() != self.proof['input_driver']['sha256']:
            raise core.GateError('input_driver_identity_mismatch')

    def native(self, op, point=None):
        before = self.adb('shell', 'pidof', core.PACKAGE)
        command = ['shell', 'am', 'instrument', '-w', '-r', '-e', 'op', op]
        if point is not None:
            command += ['-e', 'x', str(point[0]), '-e', 'y', str(point[1])]
        command += [INPUT + '/.Phase1Input']
        output=self.adb(*command,timeout=40)
        try: result=input_receipt(output,op)
        except Blocked:
            self.report.setdefault('input_failures',[]).append({'op':op,**input_failure_diagnostic(output)})
            self.save(); raise
        if self.adb('shell', 'pidof', core.PACKAGE) != before or not before:
            raise Blocked('input_driver_restarted_release_process')
        self.report.setdefault('native_input', []).append(result)
        self.save()
        return result

    def wait(self, text, seconds=35, prefix=False):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.has(text, prefix):
                return
            time.sleep(.7)
        raise Blocked('expected_destination_or_result_not_observed')

    def selected(self, nodes=None):
        nodes = self.nodes() if nodes is None else nodes
        return {text: any(n.get('selected') == 'true' or n.get('checked') == 'true'
                         for n in self.matches(nodes, text))
                for text in ['شقق', 'فلل', 'منازل', 'بيع', 'إيجار']}

    def public_oracle(self, purpose='rent'):
        if purpose not in {'rent','sale'}: raise Blocked('unsupported_public_oracle_purpose')
        query = urllib.parse.urlencode({'search': QUERY, 'type': 'apartment', 'purpose': purpose, 'per_page': 50})
        path = '/api/properties?' + query
        started = time.monotonic()
        request = urllib.request.Request(build.API.removesuffix('/api') + path,
            headers={'Accept': 'application/json', 'User-Agent': 'Aqer-Phase1-Followup/1.0'})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=25) as response:
            raw = response.read(2*1024*1024+1)
            if response.status != 200 or len(raw) > 2*1024*1024:
                raise Blocked('positive_host_oracle_unavailable')
            data = json.loads(raw)
        rows = data.get('data', [])
        if any(r.get('type') != 'apartment' or r.get('purpose') != purpose for r in rows):
            raise Blocked('positive_fixture_or_filter_oracle_failed')
        if purpose=='rent' and not any(r.get('id') == 60 and r.get('title') == FIXTURE_TITLE for r in rows):
            raise Blocked('positive_fixture_or_filter_oracle_failed')
        if purpose=='sale' and any(r.get('id')==60 for r in rows):
            raise Blocked('rental_fixture_in_sale_host_oracle')
        if purpose=='rent': self.live_fixture = True
        result = {'host_only': True, 'http_status': 200, 'elapsed_ms': round((time.monotonic()-started)*1000),
                  'ids': [r['id'] for r in rows], 'all_apartment_requested_purpose': True,'purpose':purpose,
                  'response_sha256': hashlib.sha256(raw).hexdigest()}
        self.report['positive_host_oracle' if purpose=='rent' else 'sale_host_oracle'] = result
        return result

    def positive_search(self):
        if not self.has('البحث عن عقار'):
            self.home()
            self.home_entry('search')
        self.wait('البحث عن عقار')
        self.native('fixture-query')
        self.frame('search-focused-query-before-submit')
        self.tap('تنفيذ')
        self.wait('نتائج «'+QUERY+'»')
        for text in ['شقق', 'إيجار']:
            if not self.selected()[text]: self.tap(text)
        self.wait(FIXTURE_TITLE, 60)
        flags = self.selected()
        if not flags['شقق'] or not flags['إيجار'] or flags['فلل'] or flags['بيع']:
            raise Blocked('positive_filter_selection_mismatch')
        self.frame('search-positive-apartment-rent')
        self.public_oracle()
        # Contradictory sale must exclude the exact rental fixture, then restore rent.
        sale=self.public_oracle('sale')
        self.tap('بيع')
        self.wait('لا توجد عقارات مطابقة الآن' if not sale['ids'] else 'للبيع', 40)
        if self.has(FIXTURE_TITLE):
            raise Blocked('rental_fixture_survived_sale_filter')
        self.frame('search-sale-excludes-rental')
        self.tap('إيجار')
        self.wait(FIXTURE_TITLE, 40)
        self.frame('search-rent-restored')
        self.tap(FIXTURE_TITLE)
        self.wait('تفاصيل العقار')
        self.wait(FIXTURE_TITLE)
        return {'positive_query_entered_via_native_accessibility': True, 'selected': flags,
                'sale_excluded_rental_fixture': True, 'entry': 'actual_result_card_tap',
                'fixture_id': 60, 'host_oracle_separate': True, 'deep_link_used': False}

    def timeout_recovery(self):
        # This is a new failure/retry journey, not a replay of CI457 startup.
        self.home(); self.home_entry('search'); self.wait('البحث عن عقار')
        added=[]
        restored=True
        started=time.monotonic()
        try:
            for tool in ['iptables','ip6tables']:
                self.adb('shell',tool,'-I','OUTPUT','1','-j','DROP'); added.append(tool)
            self.native('fixture-query'); self.tap('تنفيذ')
            self.frame('network-search-loading')
            observed=False
            deadline=time.monotonic()+88
            while time.monotonic()<deadline:
                if self.has('إعادة المحاولة'):
                    observed=True; break
                time.sleep(2)
            self.report['network_fault']={'scope':'disposable_API36_emulator_only','method':'temporary_ipv4_ipv6_DROP',
                'elapsed_until_observation_ms':round((time.monotonic()-started)*1000),
                'retry_control_observed':observed,'server_or_owner_network_modified':False}
            self.frame('network-search-error-before-restore')
        finally:
            for tool in reversed(added):
                try:
                    self.adb('shell',tool,'-D','OUTPUT','-j','DROP')
                    check=self.run(['adb','-s',self.serial,'shell',tool,'-C','OUTPUT','-j','DROP'])
                    if check.returncode!=1: restored=False
                except Exception: restored=False
            self.report.setdefault('network_fault',{})['block_removed']=restored
            self.save()
        if not restored: raise core.GateError('disposable_network_cleanup_failed')
        if not self.report['network_fault'].get('retry_control_observed'):
            raise Blocked('loading_did_not_settle_to_retry_within_observed_window')
        self.tap('إعادة المحاولة')
        self.wait(FIXTURE_TITLE,60)
        self.frame('network-search-retry-recovered')
        return {'failure_then_user_retry_recovered_actual_fixture':True,
                'fault_was_controlled_emulator_drop_not_natural_server_timeout':True,
                'block_removed':True,'login_or_server_state_changed':False}

    def gallery(self):
        self.tap('تكبير الصور')
        self.dismiss_immersive_tutorial()
        time.sleep(2)
        before = self.frame('gallery-before-zoom')
        image = self.fullscreen_gallery_image(self.report['frames'][-1])
        left, top, right, bottom = node_bounds(image)
        point = ((left+right)//2, (top+bottom)//2)
        self.native('double-tap', point)
        zoomed = self.frame('gallery-after-double-tap')
        zoom = photo_difference(self.out / before, self.out / zoomed)
        self.report['gallery_zoom_comparison'] = zoom; self.save()
        if zoom['changed_fraction'] < .15 or zoom['mean_absolute_difference'] < 5:
            raise Blocked('delivered_double_tap_has_no_photo_change')
        self.native('double-tap', point)
        reset = self.frame('gallery-after-reset')
        restored = photo_difference(self.out / before, self.out / reset)
        self.report['gallery_reset_comparison'] = restored; self.save()
        if restored['mean_absolute_difference'] > 12:
            raise Blocked('double_tap_reset_not_restored')
        self.native('pinch-out', point)
        pinch = self.frame('gallery-after-pinch-out')
        expanded = photo_difference(self.out / reset, self.out / pinch)
        self.report['gallery_pinch_out_comparison'] = expanded; self.save()
        if expanded['changed_fraction'] < .15:
            raise Blocked('delivered_pinch_has_no_photo_change')
        self.native('pinch-in', point)
        reduced = self.frame('gallery-after-pinch-in')
        reduction = photo_difference(self.out / pinch, self.out / reduced)
        self.report['gallery_pinch_in_comparison'] = reduction; self.save()
        if reduction['changed_fraction'] < .15:
            raise Blocked('delivered_pinch_in_has_no_photo_change')
        return {'double_tap_zoom_and_reset_frames_changed': True, 'two_pointer_pinch_out_and_in': True,
                'visual_scale_and_fixed_controls_review_required': True}

    def map(self):
        for _ in range(4):
            if self.has('ماذا تبحث عنه؟'): break
            self.back()
        self.home()
        self.home_entry('map')
        self.wait('البحث على الخريطة', 40)
        time.sleep(6)
        before = self.selected()
        self.frame('map-before-clear')
        nodes = self.nodes()
        fields = [n for n in nodes if n.get('package') == core.PACKAGE and
                  n.get('class') == 'android.widget.EditText' and node_bounds(n)]
        villas = self.matches(nodes, 'فلل')
        geometry = {'selected_before': before, 'unique_editable': len(fields)==1,
                    'clear_control_present': bool(self.matches(nodes, 'مسح النص'))}
        if len(fields)==1:
            left, top, right, bottom = node_bounds(fields[0])
            point = [(left+right)//2,(top+bottom)//2]
            geometry.update(old_center_point=point, editable_bounds=list(node_bounds(fields[0])))
            geometry['point_inside_villa_bounds'] = any(b[0]<=point[0]<b[2] and b[1]<=point[1]<b[3] for b in map(node_bounds,villas))
            geometry['villa_bounds'] = [list(node_bounds(n)) for n in villas]
        self.report['map_clear_geometry'] = geometry; self.save()
        # CI4 already proves clearing + explicit semantic submit and unchanged
        # list/map filters. Only previously unexecuted markers/pan are rerun.
        self.report['map_clear_reused']={'ci_run_id':41554064729,'apk_version':1461,
            'scope':'actual query cleared, explicit submit, apartment/rent and listing60 retained'}
        nodes = self.nodes()
        if not self.matches(nodes,'البحث على الخريطة') or self.matches(nodes,'شروط البحث'):
            raise Blocked('semantic_submit_did_not_leave_map_visible')
        flags = self.selected(nodes)
        if flags != before or not flags['شقق'] or not flags['إيجار'] or flags['فلل']:
            raise Blocked('map_filter_consistency_failed')
        fresh_fields = [n for n in nodes if n.get('package') == core.PACKAGE and n.get('class')=='android.widget.EditText']
        if not any(QUERY in node_labels(n) for n in fresh_fields):
            raise Blocked('map_pan_query_prerequisite_missing')
        self.frame('map-query-and-apartment-rent-before-pan')
        before_count=self.settled_map_count()
        if before_count<1: raise Blocked('no_actual_map_results_before_pan')
        self.collapse_map_panel_and_pan()
        self.frame('map-after-pan')
        after_count=self.settled_map_count()
        if after_count==before_count:
            # First300px pan did not move listings out of the viewport. A bounded
            # larger translation is a new observed camera test, not a blind repeat.
            y=self.fresh_map_pan_y()
            self.adb('shell','input','swipe','200',y,'880',y,'800')
            time.sleep(8)
            self.frame('map-after-larger-pan')
            after_count=self.settled_map_count()
        self.report['map_result_update']={'before':before_count,'after':after_count,
                                         'counter_changed':before_count!=after_count}; self.save()
        if before_count==after_count: raise Blocked('map_result_refresh_not_proven_by_changed_counter')
        left,top,right,bottom=self.map_handle_geometry('map-final-filter-context')
        if (top+bottom)//2>450:
            x=(left+right)//2
            self.adb('shell','input','swipe',x,(top+bottom)//2,x,350,'450');time.sleep(1)
        nodes=self.nodes()
        fields=[n for n in nodes if n.get('package')==core.PACKAGE and n.get('class')=='android.widget.EditText']
        if self.selected(nodes)!=before or not any(QUERY in node_labels(n) for n in fields):
            raise Blocked('map_query_or_filters_changed_after_pan')
        self.report['map_after_pan_criteria']={'query_retained':True,'selected':self.selected(nodes)}
        self.frame('map-after-pan-query-and-filters')
        return {'query_clear_reused_from_CI4_not_repeated': True,'pan_query_retained':QUERY,
                'selected_before': before, 'selected_after': flags,
                'pan_sent': True, 'native_marker_movement_and_result_refresh_require_visual_review': True}

    def map_count(self,nodes=None):
        nodes=self.nodes() if nodes is None else nodes
        counts={int(match[1]) for node in nodes if node.get('package')==core.PACKAGE
                for value in node_labels(node) if (match:=re.fullmatch(r'([0-9]+)\+? عقار في النطاق',value))}
        if len(counts)!=1: raise Blocked('unique_map_result_counter_not_observed')
        return counts.pop()

    def map_handle_geometry(self,name):
        nodes=self.nodes()
        label='اسحب لتوسيع الفلاتر والعقارات أو تصغيرها'
        handles=self.matches(nodes,label);titles=self.matches(nodes,'البحث على الخريطة')
        if len(handles)!=1 or len(titles)!=1 or self.matches(nodes,'شروط البحث'):
            raise Blocked('fresh_map_pan_context_missing')
        name=name+'-'+str(len(self.report.get('observed_map_geometry',[]))+1)
        frame=self.frame(name);bounds=visible_map_handle(self.out/frame)
        time.sleep(.15)
        confirmed=self.frame(name+'-confirmed');fresh=visible_map_handle(self.out/confirmed)
        if any(abs(a-b)>2 for a,b in zip(bounds,fresh)): raise Blocked('visible_map_handle_not_stable')
        self.report.setdefault('observed_map_geometry',[]).append({'frame':frame,'confirmation_frame':confirmed,'visible_handle_bounds':fresh,
            'semantic_handle_bounds':list(node_bounds(handles[0])),'semantic_title_bounds':list(node_bounds(titles[0])),
            'coordinates_derived_from_fresh_native_pixels':True})
        self.save();return fresh

    def fresh_map_pan_y(self):
        left,top,right,bottom=self.map_handle_geometry('map-current-handle')
        if top<1152:
            x=(left+right)//2
            self.adb('shell','input','swipe',x,(top+bottom)//2,x,1800,'450');time.sleep(1)
            left,top,right,bottom=self.map_handle_geometry('map-exposed-for-pan')
        if not 1152<=top<bottom<=1850: raise Blocked('fresh_map_area_not_exposed')
        return (300+top-60)//2

    def collapse_map_panel_and_pan(self):
        y=self.fresh_map_pan_y()
        self.frame('map-before-pan')
        self.adb('shell','input','swipe','390',y,'690',y,'500')
        self.report['map_pan_gesture']={'from':[390,y],'to':[690,y],
            'bounds_from_fresh_visible_handle':True,'visual_movement_review_required':True}
        time.sleep(4)

    def settled_map_count(self):
        deadline=time.monotonic()+50
        while time.monotonic()<deadline:
            nodes=self.nodes()
            count=self.map_count(nodes)
            loading=any(n.get('package')==core.PACKAGE and n.get('class')=='android.widget.ProgressBar' for n in nodes)
            loading=loading or bool(self.matches(nodes,'جارٍ تحديث النطاق… النتائج الظاهرة من آخر تحميل متاح.'))
            if self.matches(nodes,'إعادة المحاولة'):
                raise Blocked('map_viewport_request_error_visible')
            if not loading and count>0: return count
            empty='لا توجد عقارات مطابقة في هذا النطاق. حرّك الخريطة أو عدّل الفلاتر.'
            if not loading and count==0 and self.matches(nodes,empty): return 0
            if not loading and count==0:
                # Expand the actual panel so the success-empty/error state becomes
                # observable instead of promoting an intermediate zero counter.
                left,top,right,bottom=self.map_handle_geometry('map-zero-state-handle')
                if (top+bottom)//2>450:
                    x=(left+right)//2
                    self.adb('shell','input','swipe',x,(top+bottom)//2,x,350,'450')
            time.sleep(1)
        raise Blocked('settled_successful_map_result_not_observed')

    def ai_guest_gate(self):
        self.back(); self.home()
        self.tap('حسابي', bottom=True)
        self.tap('إضافة عقار')
        self.wait('ذكاء اصطناعي')
        self.frame('ai-existing-method-menu')
        self.tap('ذكاء اصطناعي')
        self.wait('سجّل الدخول أولاً')
        return {'ai_method_selected': True, 'actual_gate': 'authentication',
                'subscription_gate_proven': False, 'provider_called': False, 'purchase': False}

    def record_start(self, name):
        self.video_name = name
        self.adb('shell','rm','-f','/sdcard/aqer-followup.mp4')
        self.recorder = subprocess.Popen(['adb','-s',self.serial,'shell','screenrecord','--bit-rate','2500000',
            '--time-limit','180','/sdcard/aqer-followup.mp4'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

    def record_stop(self):
        if self.recorder is None: return
        try:
            self.adb('shell','pkill','-2','screenrecord',codes=(0,1))
            self.recorder.wait(timeout=15)
            self.adb('pull','/sdcard/aqer-followup.mp4',self.out/(self.video_name+'.mp4'),timeout=30)
            self.report.setdefault('videos',[]).append(self.video_name+'.mp4')
        except Exception:
            self.report.setdefault('video_failures',[]).append(self.video_name)
            self.recorder.kill()
        self.recorder=None; self.save()

    def execute(self):
        self.validate_environment()
        self.out.mkdir(); self.created=True; self.save()
        # Publish freshness immediately: timeout/SIGTERM must not hide captured evidence.
        if self.env.get('GITHUB_OUTPUT'):
            with open(self.env['GITHUB_OUTPUT'],'a') as stream: stream.write('followup_evidence=true\n')
        (self.out/'APK_VERIFICATION.json').write_text(json.dumps(self.proof,indent=2)+'\n')
        try:
            self.adb('install',str(self.apk),timeout=180); self.installed=True
            self.adb('install','-t',str(self.driver),timeout=60); self.driver_installed=True
            self.startup()  # prerequisite only; CI457 startup acceptance is reused.
            # CI2 already captured loading/error, removed the block and explicit
            # retry recovered real public rows. Its strict fixture assertion
            # failed because the unfocused text action did not submit a query.
            # Keep that raw BLOCKED receipt and reuse only the reviewed recovery.
            self.report['reused_followup_evidence']={
                'ci_run_id':41549748457,'apk_version':1459,
                'F04':'PASS actual AI method -> guest authentication gate',
                'F05':'Reviewed controlled loading/error/retry -> actual public rows; targeted query not proven'}
            self.report['reused_followup_evidence']['CI3']={
                'ci_run_id':41552246597,'apk_version':1460,
                'F01':'PASS actual Arabic query, apartment/rent, sale exclusion, restored rent and result card -> matching details',
                'F02':'PASS measured doubletap zoom/reset and two-pointer pinch out/in; original frames/video retained'}
            # Establish the shared list criteria as a prerequisite only. Do not
            # repeat sale contrast, details/card or gallery acceptance journeys.
            self.home(); self.home_entry('search'); self.wait('البحث عن عقار')
            self.native('fixture-query'); self.native('submit-query')
            self.wait('نتائج «'+QUERY+'»')
            for text in ['شقق','إيجار']:
                if not self.selected()[text]: self.tap(text)
            self.wait(FIXTURE_TITLE,60)
            self.frame('map-prerequisite-list-apartment-rent')
            self.report['map_list_prerequisite']={'query':QUERY,'selected':self.selected(),'fixture60_visible':True}
            self.record_start('map-and-filters')
            self.case('F03-map-markers-pan','Reuse CI4 clear; verify real price markers and viewport results while retaining the query and apartment/rent.',self.map)
            self.record_stop()
        finally:
            self.record_stop()
            clean=True
            for package, installed in [(core.PACKAGE,self.installed),(INPUT,self.driver_installed)]:
                if installed:
                    try:
                        self.adb('shell','am','force-stop',package); self.adb('uninstall',package)
                    except Exception: clean=False
            self.report['cleanup_passed']=clean
            if self.report.get('network_fault',{}).get('block_removed') is False:
                self.report['cleanup_passed']=False
            self.report['ended_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat(); self.save()
        return self.report


def main():
    probe=None
    try:
        probe=Followup(ROOT,os.environ)
        report=probe.execute()
        passed=report.get('cleanup_passed') and all(c['status']=='PASS' for c in report['cases'])
        print('AQER_PHASE1_FOLLOWUP_'+('COLLECTED' if passed else 'INCOMPLETE'))
        return 0 if passed else 1
    except Exception as error:
        if probe is not None and probe.created:
            probe.report.update(collection_failed=True,error_type=type(error).__name__); probe.save()
        print('AQER_PHASE1_FOLLOWUP_COLLECTION_FAILED'); return 1
    finally:
        if probe is not None and probe.created and os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'],'a') as stream: stream.write('followup_evidence=true\n')


if __name__=='__main__': raise SystemExit(main())
