"""Dependency-injected, offline-loadable one-shot NativeAccount integration.

The owner supplies exact classes and checked source identity/UTC preflight
callbacks. Constructing this class alone is neither native proof nor a grant.
"""
from __future__ import annotations

import calendar
from datetime import datetime, timedelta
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET

from oneshot_adapter import AdmissionError, OneShotAdmission, OneShotInstrumentAdapter
from c1_home_capture import C1HomeConsoleCaptureMixin
from c1_basics_capture import C1BasicsConsoleCaptureMixin


class BridgeRefused(RuntimeError):
    """Fixed diagnostics; never include arguments, output, nodes or exceptions."""


def need(ok, code):
    if not ok:
        raise BridgeRefused(code) from None


def exact_deadline_ms(authority):
    """Use the original signed whole-second UTC expiry, never a new lease."""
    expires = getattr(authority, 'expires_utc', None)
    need(type(expires) is datetime and expires.tzinfo is not None
         and expires.utcoffset() == timedelta(0) and expires.microsecond == 0,
         'exact_whole_second_utc_expiry_required')
    result = str(calendar.timegm(expires.utctimetuple()) * 1000)
    need(re.fullmatch(r'[0-9]{13}', result) is not None, 'guest_deadline_range_invalid')
    return result


def make_probe_class(*, base_class, host_capture_mixin, validate_access,
                     secret_name, install_known_roles, authority_types,
                     app, activity, helper):
    """Bind source classes once; no workspace-absolute or private imports.

    ``authority_types`` is the exact owner VerifiedGrant/SourcePlanLease classes
    (and optionally CleanupLease), not untrusted payload classes. ``install``
    must be from the SAME C2 variant module as its executor (type identity).
    The factory does not instantiate an emulator, probe, authority, or role.
    """
    need(type(authority_types) is tuple and authority_types
         and all(isinstance(t, type) for t in authority_types), 'owner_authority_types_required')
    need(all(callable(f) for f in (base_class, host_capture_mixin, validate_access,
                                  install_known_roles)), 'bridge_dependencies_required')

    class CIProbe(C1BasicsConsoleCaptureMixin, C1HomeConsoleCaptureMixin, host_capture_mixin, base_class):
        # C2 V2's operation selector remains the four supported account ops.
        # Actual click delivery is checked by the pinned Java/base receipts.
        explicit_pointer_mode = False
        HOST_CAPTURE_ERROR = BridgeRefused

        def __init__(self, private, env, *, authority_getter, context_getter,
                     verify_helper_identity, verify_guest_utc):
            need(all(callable(f) for f in (authority_getter, context_getter,
                  verify_helper_identity, verify_guest_utc)), 'owner_callbacks_required')
            retained = validate_access(env.get(secret_name, ''))
            need(type(retained) is dict and type(retained.get('phones')) is dict
                 and set(retained['phones']) == {'broker', 'support', 'regular'},
                 'all_three_known_roles_required')
            # Retain only the validated role pool in RAM before base discards
            # optional actors/removes the secret from its child-process env.
            retained = {'otp': retained['otp'], 'phones': dict(retained['phones'])}
            self._owner_authority = authority_getter
            self._owner_context = context_getter
            self._verify_helper_identity = verify_helper_identity
            self._verify_guest_utc = verify_guest_utc
            self._transport = threading.local()
            self._raw_lock = threading.RLock()
            self._admission = OneShotAdmission()
            self._one_shot = OneShotInstrumentAdapter(self._checked_driver, admission=self._admission)
            self._epoch = None
            self.adapter = None
            self._deadline_preflight = False
            self._pending_creation_clip = False
            super().__init__(private, env)
            self.access = retained
            install_known_roles(self, retained)
            # Full aliases, including 00/country format, join base redactions.
            for value in retained['phones'].values():
                digits = value.lstrip('+')
                self.private_values.update({value, digits, '+' + digits})
                if digits.startswith('00'):
                    self.private_values.update({digits[2:], '+' + digits[2:]})
            del retained

        def __repr__(self):
            return '<CIProbe one_shot_admission=' + self._admission.metrics['state'] + '>'

        @property
        def admission_metrics(self):
            return self._admission.metrics

        def _authority(self, category):
            try:
                authority = self._owner_authority()
                context = self._owner_context()
                need(type(authority) in authority_types, 'active_owner_authority_required')
                kind = authority.authority_kind
                need(kind in {'ROOT_VERIFIED', 'SOURCE_PLAN_ONLY', 'OWNER_CLEANUP'},
                     'fixed_owner_authority_kind_required')
                if kind == 'SOURCE_PLAN_ONLY':
                    need(context.phase == 'C1' and context.cursor == 'INITIAL_C1',
                         'initial_source_scope_required')
                if kind == 'OWNER_CLEANUP':
                    need(context.phase == 'C5' and context.cursor == 'OWNER_CLEANUP',
                         'fixed_cleanup_scope_required')
                need(authority.require_input(context, category) is True,
                     'owner_input_not_authorized')
                return authority
            except BaseException:
                raise BridgeRefused('owner_input_authority_refused') from None

        def _healthy(self):
            need(self._admission.metrics['state'] != 'uncertain', 'oneshot_runtime_uncertain')
            need(not getattr(self, '_host_stop_unconfirmed', False), 'host_recorder_stop_unconfirmed')

        def require_phase_scope(self, phase):
            """Source/cleanup leases never enter the generic phase executors."""
            need(phase in {'C4', 'C2'}, 'fixed_phase_required')
            authority = self._authority('tap')
            need(authority.authority_kind == 'ROOT_VERIFIED'
                 and self._owner_context().phase == phase, 'root_phase_authority_required')
            return True

        def start_session(self):
            self._healthy()
            need(self.adapter is None, 'admission_already_open')
            self._epoch = self._one_shot.start()
            self.adapter = self._one_shot
            # Admission is not a persistent UiAutomation/native-release fact.
            return self.admission_metrics

        def stop_session(self, reason=None):
            # Do not retain arbitrary human reasons in diagnostics.
            metrics = self._one_shot.stop()
            self.adapter, self._epoch = None, None
            return metrics

        def startup(self):
            if self.adapter is None:
                self.start_session()
            return base_class.startup(self)

        def preflight_deadline_helper(self):
            """Owner must bind actual installed SHA and measured guest UTC sync.

            Capability is a fresh nonmutating checked snapshot. A result after
            first input cannot substitute for the before-input identity proof.
            """
            self._healthy()
            need(self.adapter is not None, 'admission_must_be_open')
            self._deadline_preflight = False
            try:
                need(self._verify_helper_identity() is True and self._verify_guest_utc() is True,
                     'deadline_helper_identity_or_utc_unverified')
                result = self.instrument('account-snapshot')
                need(result.get('deadline_capable') == 'true', 'deadline_helper_capability_missing')
            except BaseException:
                raise BridgeRefused('deadline_helper_preflight_refused') from None
            self._deadline_preflight = True

        def _checked_driver(self, op, **extras):
            """Called only after the SAME admission has reserved this call."""
            with self._raw_lock:
                authority = None
                if op != 'account-snapshot':
                    category = {'account-click': 'tap', 'account-set': 'text',
                                'account-scroll': 'scroll', 'account-dismiss-ime': 'back'}[op]
                    authority = self._authority(category)
                    if authority.authority_kind != 'SOURCE_PLAN_ONLY':
                        need(self._deadline_preflight, 'deadline_helper_preflight_required')
                        extras = dict(extras, deadline_utc_ms=exact_deadline_ms(authority))
                self._transport.instrument_op = op
                try:
                    result = base_class.instrument(self, op, **extras)
                finally:
                    self._transport.instrument_op = None
                if authority is not None and authority.authority_kind != 'SOURCE_PLAN_ONLY':
                    need(type(result) is dict and result.get('deadline_capable') == 'true'
                         and result.get('deadline_enforced') == 'true',
                         'guest_deadline_enforcement_unconfirmed')
                return result

        def instrument(self, op, **extras):
            self._healthy()
            need(self.adapter is self._one_shot and self._epoch is not None,
                 'admission_must_be_open')
            # Foundation rejects unsolicited mode/deadline arguments. Its
            # checked-driver binding appends the original grant expiry itself.
            return self._one_shot.instrument(op, expected_epoch=self._epoch, **extras)

        def _dismiss_ime(self):
            self._healthy()
            need(self.adapter is self._one_shot and self._epoch is not None,
                 'admission_must_be_open')
            # New helper op, SAME reservation/latch, no fake selected-node data.
            reservation = self._admission._reserve(self._epoch)
            known, result = False, None
            try:
                result = self._checked_driver('account-dismiss-ime')
                visible, dismissed = result.get('ime_was_visible'), result.get('ime_dismissed')
                known = (result.get('passed') == 'true' and result.get('op') == 'account-dismiss-ime'
                         and (visible, dismissed) in {('true', 'true'), ('false', 'false')})
            except BaseException:
                pass
            finally:
                self._admission._complete(reservation, known=known)
            if not known:
                raise AdmissionError('instrumentation_completion_uncertain') from None
            return result

        def adb(self, *args, **kwargs):
            """Closed list of source transports; mutations checked at dispatch.

            Lifecycle adb has a host before-dispatch guarantee only. It cannot
            prove Android's eventual server execution happened before expiry.
            Root APP semantic/pointer/IME inputs use guest enforcement instead.
            """
            values = tuple(str(x) for x in args)
            if values == ('shell', 'input', 'keyevent', '4'):
                authority = self._authority('back')
                if authority.authority_kind != 'SOURCE_PLAN_ONLY':
                    return self._dismiss_ime()
            with self._raw_lock:
                op = getattr(self._transport, 'instrument_op', None)
                if values[:4] == ('shell', 'am', 'instrument', '-w'):
                    need(op is not None and values[4:7] == ('-e', 'op', op)
                         and values[-1] == helper, 'direct_instrumentation_refused')
                else:
                    category, source_only = self._classify_adb(values)
                    if category is not None:
                        authority = self._authority(category)
                        if source_only:
                            need(authority.authority_kind == 'SOURCE_PLAN_ONLY',
                                 'raw_input_initial_source_only')
                        if category not in {'app_stop', 'recorder_stop'}:
                            self._healthy()
                        # Stopping native/host processes may remain possible
                        # during uncertain cleanup; no new UI may be delivered.
                        need(self._admission.metrics['inflight'] == 0,
                             'native_transaction_inflight')
                self._transport.adb_dispatch = True
                try:
                    return base_class.adb(self, *args, **kwargs)
                finally:
                    self._transport.adb_dispatch = False

        def _classify_adb(self, args):
            if args == ('shell', 'am', 'start', '-W', '-n', activity):
                return 'app_start', False
            if args == ('shell', 'am', 'force-stop', app):
                return 'app_stop', False
            if args[:2] == ('emu', 'screenrecord'):
                need(len(args) >= 3, 'console_operation_required')
                if args[2] == 'start': return 'recorder_start', False
                if args[2] == 'stop': return 'recorder_stop', False
                if args[2] == 'screenshot':
                    self._healthy()
                    return None, False
            if args[:3] == ('shell', 'input', 'tap') and len(args) == 5:
                need(all(re.fullmatch(r'[0-9]{1,4}', v) for v in args[3:]), 'os_pointer_invalid')
                return 'os_picker', True
            if args == ('shell', 'input', 'keyevent', '4'):
                return 'back', True
            if args[:1] == ('install',): return 'media_write', True
            if args[:1] == ('push',) and len(args) == 3:
                need(args[2] == '/sdcard/Download/' + self.photo_name, 'fixed_owned_photo_path_required')
                return 'media_write', True
            if args == ('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                        '-d', 'file:///sdcard/Download/' + self.photo_name):
                return 'media_write', True
            if args in {('shell', 'wm', 'size', '540x960'), ('shell', 'wm', 'density', '210')}:
                return 'media_write', True
            if args in {('shell', 'wm', 'size'), ('shell', 'wm', 'density'), ('reverse', '--list'),
                        ('shell', 'service', 'check', 'package'), ('shell', 'pidof', 'system_server'),
                        ('shell', 'cat', '/etc/hosts')}:
                return None, False
            if args[:2] == ('shell', 'getprop') and len(args) == 3 and args[2] in {
                    'sys.boot_completed', 'sys.user.0.ce_available', 'ro.boot.qemu', 'ro.build.version.sdk'}:
                return None, False
            targets = {'/sdcard/phase1-startup-permission.xml', '/sdcard/phase1-os-picker.xml'}
            if ((args[:3] == ('shell', 'uiautomator', 'dump') and len(args) == 4 and args[3] in targets)
                or (args[:2] == ('exec-out', 'cat') and len(args) == 3 and args[2] in targets)
                or (args[:3] == ('shell', 'rm', '-f') and len(args) == 4 and args[3] in targets)):
                return 'os_picker', True
            raise BridgeRefused('unclassified_adb_operation_refused') from None

        def command(self, args, **kwargs):
            values = tuple(str(x) for x in args)
            if not getattr(self._transport, 'adb_dispatch', False):
                need(values == ('adb', 'devices') or
                     (len(values) == 2 and values[0].endswith('/emulator/emulator')
                      and values[1] == '-accel-check'), 'direct_transport_refused')
                need(self._authority('media_write').authority_kind == 'SOURCE_PLAN_ONLY',
                     'preinstall_source_authority_required')
            return base_class.command(self, args, **kwargs)

        def configure_host_display(self):
            self.adb('shell', 'wm', 'size', '540x960')
            self.adb('shell', 'wm', 'density', '210')
            def effective(output, label):
                lines = str(output).splitlines()
                override = [line.removeprefix('Override ' + label + ': ').strip()
                            for line in lines if line.startswith('Override ' + label + ': ')]
                physical = [line.removeprefix('Physical ' + label + ': ').strip()
                            for line in lines if line.startswith('Physical ' + label + ': ')]
                need(len(override) <= 1 and len(physical) == 1, 'display_readback_invalid')
                return override[0] if override else physical[0]
            need(effective(self.adb('shell', 'wm', 'size'), 'size') == '540x960'
                 and effective(self.adb('shell', 'wm', 'density'), 'density') == '210',
                 'host_capture_display_not_verified')
            return {'width': 540, 'height': 960, 'density_dpi': 210, 'actual_readback_checked': True}

        def record_start(self, name):
            if name == 'C1-create-photo':
                need(self._authority('recorder_start').authority_kind == 'SOURCE_PLAN_ONLY',
                     'initial_creation_clip_scope_required')
                need(not self._pending_creation_clip, 'creation_clip_already_pending')
                self._pending_creation_clip = True
                return
            return super().record_start(name)

        def photo_picker(self):
            need(self._pending_creation_clip, 'creation_clip_not_requested')
            self._pending_creation_clip = False
            # Specs now observed by base; actual photo selection remains within
            # the real <=120 second console clip. Never label this whole journey.
            super().record_start('C1-create-photo')
            self.report['create_clip_scope'] = 'actual_specs_photo_selection_only'
            try:
                return base_class.photo_picker(self)
            except Exception as failure:
                # Diagnose only a known source selection/return timeout, before
                # cleanup can move the UI. This is never C1 acceptance media.
                if failure.args in (('genuine_os_photo_selection_not_observed',),
                                     ('genuine_os_picker_return_not_observed',)):
                    try:
                        self.capture_initial_os_picker_diagnostic()
                    except Exception:
                        self.report['os_picker_diagnostic'] = {
                            'status': 'REFUSED', 'acceptance_claimed': False}
                        self.save()
                raise

        def _validate_webm(self, path):
            try:
                # Preserve the frozen single-stream path. The sole native
                # silent-Vorbis layout is checked explicitly below.
                return super()._validate_webm(path)
            except Exception as failure:
                # AOSP's console recorder unconditionally adds native Vorbis.
                # Keep one actual video stream and admit that sole audio track
                # only when full PCM decoding proves every sample is zero.
                if failure.args == ('host_webm_stream_or_duration_invalid',):
                    try:
                        return self._validate_native_silent_audio_webm(path)
                    except Exception:
                        pass  # Preserve the original refusal and diagnostics.
                try:
                    self._healthy()
                    need(self._authority('media_write').authority_kind == 'SOURCE_PLAN_ONLY'
                         and self._active_case in {'C1-photo-save','C1-force-stop-restore'}
                         and self.video_name in {'C1-create-photo','C1-restored-facts'}
                         and self.authenticated is True and self.recorder is None
                         and not getattr(self,'_host_stop_unconfirmed',False),
                         'initial_stopped_host_video_diagnostic_only')
                    path = Path(path)
                    need(path == self._host_video_path and path.name == 'capture.webm'
                         and path.parent.parent == Path(self.private)/'host_console_capture_tmp'
                         and not path.is_symlink(), 'owned_host_video_diagnostic_required')
                    codes = {'host_webm_file_invalid','host_webm_ebml_invalid',
                             'host_webm_probe_failed','host_webm_stream_or_duration_invalid'}
                    code = failure.args[0] if len(failure.args)==1 and failure.args[0] in codes else 'host_video_validation_refused'
                    facts = {'status':'OBSERVED','acceptance_claimed':False,'code':code,
                             'file':self.video_name+'.webm','file_present':path.is_file(),
                             'probe_status':'NOT_RUN'}
                    if path.is_file():
                        size = path.stat().st_size
                        facts['bytes'] = size if 0 <= size <= 64*1024*1024 else None
                        if 0 < size <= 64*1024*1024:
                            with path.open('rb') as stream:
                                facts['ebml_header_observed'] = stream.read(4)==b'\x1a\x45\xdf\xa3'
                            result = subprocess.run(['ffprobe','-v','error','-protocol_whitelist','file,pipe',
                                '-show_entries','format=format_name,duration:stream=codec_name,codec_type,width,height,avg_frame_rate',
                                '-of','json',str(path)],capture_output=True,stdin=subprocess.DEVNULL,timeout=5)
                            if result.returncode == 0 and len(result.stdout) <= 16384:
                                value = json.loads(result.stdout)
                                streams = value.get('streams',[])
                                need(type(streams) is list and len(streams)<=8,'bounded_video_stream_diagnostic_required')
                                facts['probe_status'] = 'READ'
                                facts['stream_count'] = len(streams)
                                facts['webm_format_observed'] = 'webm' in value.get('format',{}).get('format_name','')
                                duration = float(value.get('format',{}).get('duration','nan'))
                                facts['duration_s'] = round(duration,3) if math.isfinite(duration) and 0 <= duration <= 3600 else None
                                facts['streams'] = []
                                for item in streams:
                                    row = {'type':item.get('codec_type') if item.get('codec_type') in {'video','audio'} else 'OTHER',
                                           'codec':item.get('codec_name') if item.get('codec_name') in {'vp8','vp9','av1','h264','aac','vorbis','opus'} else 'OTHER'}
                                    for key in ('width','height'):
                                        number = item.get(key)
                                        row[key] = number if type(number) is int and 0 <= number <= 16384 else None
                                    rate = item.get('avg_frame_rate','')
                                    row['average_frame_rate'] = rate if type(rate) is str and re.fullmatch(r'[0-9]{1,10}/[0-9]{1,10}',rate) else None
                                    facts['streams'].append(row)
                            else:
                                facts['probe_status'] = 'UNAVAILABLE'
                    self.report['host_video_diagnostic'] = facts
                    self.save()
                except Exception:
                    self.report['host_video_diagnostic'] = {'status':'REFUSED','acceptance_claimed':False}
                    try: self.save()
                    except Exception: pass
                raise

        def _validate_native_silent_audio_webm(self, path):
            self._healthy()
            self._authority('media_write')
            need(self._owner_context().phase in {'C1','C4'} and self.authenticated is True
                 and self.recorder is None and not getattr(self,'_host_stop_unconfirmed',False),
                 'stopped_safe_native_video_required')
            path=Path(path)
            need(path==self._host_video_path and path.name=='capture.webm'
                 and path.parent.parent==Path(self.private)/'host_console_capture_tmp'
                 and not path.is_symlink() and path.is_file(), 'owned_native_video_required')
            before=path.stat()
            need(1024 <= before.st_size <= 64*1024*1024, 'bounded_native_video_required')
            with path.open('rb') as stream:
                need(stream.read(4)==b'\x1a\x45\xdf\xa3','native_webm_header_required')
            probe=subprocess.run(['ffprobe','-v','error','-protocol_whitelist','file,pipe',
                '-show_entries','format=format_name,duration:stream=codec_name,codec_type,width,height,avg_frame_rate,channels,sample_rate',
                '-of','json',str(path)],capture_output=True,stdin=subprocess.DEVNULL,timeout=25)
            need(probe.returncode==0 and len(probe.stdout)<=16384,'native_webm_probe_required')
            value=json.loads(probe.stdout);streams=value.get('streams',[])
            need(type(streams) is list and len(streams)==2 and all(type(s) is dict for s in streams),
                 'one_video_one_silent_native_audio_required')
            videos=[s for s in streams if s.get('codec_type')=='video']
            audios=[s for s in streams if s.get('codec_type')=='audio']
            need(len(videos)==len(audios)==1,'one_video_one_silent_native_audio_required')
            video,audio=videos[0],audios[0];duration=float(value.get('format',{}).get('duration','nan'))
            need(video.get('codec_name')=='vp9' and (video.get('width'),video.get('height'))==self.HOST_CAPTURE_SIZE
                 and 'webm' in value.get('format',{}).get('format_name','')
                 and math.isfinite(duration) and 0<duration<=self.HOST_VIDEO_SECONDS+5,
                 'native_video_codec_dimensions_duration_required')
            need(audio.get('codec_name')=='vorbis' and type(audio.get('channels')) is int
                 and audio['channels'] in {1,2} and audio.get('sample_rate') in {'44100','48000'},
                 'native_vorbis_layout_required')
            pcm=subprocess.run(['ffmpeg','-nostdin','-v','error','-protocol_whitelist','file,pipe',
                '-i',str(path),'-map','0:a:0','-vn','-c:a','pcm_f32le','-f','f32le','-fs','50000000','pipe:1'],
                capture_output=True,stdin=subprocess.DEVNULL,timeout=25)
            need(pcm.returncode==0 and 0<len(pcm.stdout)<50_000_000 and len(pcm.stdout)%4==0
                 and all(s[0]==0.0 for s in struct.iter_unpack('<f',pcm.stdout)),
                 'native_audio_exact_silence_required')
            after=path.stat()
            need((before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)==
                 (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns),'native_video_changed_during_read')
            self.report.setdefault('native_silent_audio_tracks',{})[self.video_name+'.webm']={
                'video_stream_count':1,'native_audio_stream_count':1,'audio_codec':'vorbis',
                'all_decoded_samples_zero':True,'original_file_unmodified':True}
            return {'duration_s':round(duration,3),'codec':video['codec_name'],
                    'width':video['width'],'height':video['height'],
                    'average_frame_rate':video.get('avg_frame_rate')}

        def _initial_os_picker_observation(self):
            target = '/sdcard/phase1-os-picker.xml'
            self.adb('shell', 'uiautomator', 'dump', target, timeout=20)
            try:
                raw = self.adb('exec-out', 'cat', target)
                need(type(raw) is str and 0 < len(raw) <= 512 * 1024,
                     'bounded_os_picker_tree_required')
                try:
                    nodes = list(ET.fromstring(raw).iter('node'))
                except ET.ParseError:
                    raise BridgeRefused('actual_os_picker_tree_required') from None
            finally:
                self.adb('shell', 'rm', '-f', target)
            allowed = {'com.google.android.documentsui', 'com.android.documentsui',
                       'com.google.android.providers.media.module', 'com.android.providers.media.module'}
            if not (0 < len(nodes) <= 1200 and nodes[0].get('package') in allowed):
                self.record_tainted = True
                raise BridgeRefused('actual_os_picker_foreground_required')
            rows = [{'package': n.get('package', ''), 'class': n.get('class', ''),
                     'text': n.get('text', ''), 'description': n.get('content-desc', ''),
                     'hint': n.get('hint', ''), 'bounds': n.get('bounds', ''),
                     'resource_id': n.get('resource-id', ''),
                     'visible': n.get('visible-to-user', 'true') == 'true',
                     'enabled': n.get('enabled', 'false') == 'true',
                     'clickable': n.get('clickable', 'false') == 'true',
                     'selected': n.get('selected', 'false') == 'true'} for n in nodes]
            # Reuse the unchanged full mounted-contact/auth/profile/private-
            # alias predicate. No APP-only snapshot or new UI input occurs.
            text = '\n'.join(row[key] for row in rows if row['visible']
                             for key in ('text', 'description', 'hint'))
            english_auth = {'sign in', 'sign-in', 'password', 'email or phone',
                            'email address', 'phone number', 'verify it\'s you', 'enter your email'}
            if (self._capture_rows_private(rows) or english_auth & {s.strip().casefold() for s in text.splitlines()}
                    or re.search(r'[^\s@]+@[^\s@]+\.[^\s@]+', text) is not None):
                self.record_tainted = True
                raise BridgeRefused('private_os_picker_diagnostic_refused')
            binding = hashlib.sha256(json.dumps(rows, sort_keys=True,
                separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
            facts = {'node_count': len(rows),
                     'exact_filename_matches': sum(self.photo_name in {row['text'],row['description']} for row in rows),
                     'filename_contains_matches': sum(self.photo_name in row['text'] or self.photo_name in row['description'] for row in rows),
                     'downloads_matches': sum(row['text'] in {'Downloads','التنزيلات'} for row in rows),
                     'drawer_matches': sum(row['description'] in {'Show roots','Open navigation drawer','عرض الجذور','فتح قائمة التنقل'} for row in rows)}
            return binding, facts

        def capture_initial_os_picker_diagnostic(self):
            self._healthy()
            need(self._authority('media_write').authority_kind == 'SOURCE_PLAN_ONLY'
                 and self._active_case == 'C1-photo-save' and self.authenticated is True
                 and self.recorder == 'official-host-console' and self.video_name == 'C1-create-photo',
                 'initial_source_picker_diagnostic_only')
            name = 'C1-os-picker-diagnostic.png'
            destination = Path(self.out) / name
            need(not destination.exists() and not destination.is_symlink(),
                 'unique_os_picker_diagnostic_required')
            before, facts = self._initial_os_picker_observation()
            with tempfile.TemporaryDirectory(prefix='picker-png-', dir=self._host_capture_root()) as directory:
                folder = Path(directory)
                self._console('screenshot', folder)
                files = list(folder.iterdir())
                need(len(files) == 1 and files[0].suffix.lower() == '.png'
                     and files[0].is_file() and not files[0].is_symlink(),
                     'unique_os_picker_console_png_required')
                data = files[0].read_bytes()
                dims = self._validate_png(data)
                after, _ = self._initial_os_picker_observation()
                if before != after:
                    self.record_tainted = True
                    raise BridgeRefused('os_picker_binding_changed_during_capture')
                destination.write_bytes(data)
                destination.chmod(0o600)
            self.report['os_picker_diagnostic'] = {'status': 'CAPTURED',
                'file': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                'width': dims[0], 'height': dims[1],
                'capture': 'official_emulator_console_host_png',
                'capture_scope': 'fresh_owned_os_picker_failure_diagnostic',
                'privacy_before_and_after': True, 'picker_binding_unchanged': True,
                'observed_controls': facts, 'acceptance_claimed': False}
            # Deliberately separate from accepted editor frames and clips.
            self.save()

        def execute(self):
            raise BridgeRefused('same_job_owner_stage_router_required') from None

        def hold_after_initial_c1(self):
            """Clear C1-only diagnostics after actual restore, never invent PASS."""
            need(any(row.get('id') == 'C1-force-stop-restore' and row.get('status') == 'PASS'
                     for row in self.report.get('cases', [])) and self.recorder is None,
                 'actual_c1_restore_required_before_hold')
            self._active_case, self._auth_phase = None, None
            self.report['held_after_c1_restore_for_root_review'] = True
            self.save()

        def cleanup(self):
            raise BridgeRefused('owner_promoted_property_first_cleanup_required') from None

        def clear_role_memory(self):
            # Owner invokes only after all work/cleanup; no secret is serialized.
            memory = getattr(self, '_known_role_memory', None)
            if memory is not None:
                memory.clear()
            self.access.get('phones', {}).clear()
            self.access['otp'] = ''
            self.private_values.clear()

    return CIProbe
