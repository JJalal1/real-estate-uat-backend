"""Host-file capture through the official emulator console; no guest codec.

Usage: class Attempt2(HostConsoleCaptureMixin, base.NativeAccount).
Optionally set HOST_CAPTURE_ERROR = base.Blocked on Attempt2 for its report policy.
Only authenticated editor frames may be exported. Captures are actual PNG/WebM.
"""
import base64
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time
import zlib

AUTH_LABELS = frozenset({'مرحبًا بعودتك', 'رقم واتساب', 'رمز التحقق',
    'رمز التحقق عبر واتساب', 'تأكيد والدخول', 'إرسال رمز واتساب',
    'تسجيل الدخول أو إنشاء حساب'})
PRIVATE_CONTEXT_LABELS = frozenset({'الإيجار والتواصل', 'السعر والتواصل',
    'حدد الإيجار الشهري ووسائل التواصل.',
    'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
    'رقم الاتصال *', 'رقم اتصال آخر (اختياري)',
    'الإيجار الشهري بالريال اليمني *', 'سعر البيع بالريال اليمني *',
    'الملف الشخصي', 'تعديل الملف الشخصي', 'الأمان والخصوصية', 'تسجيل الخروج'})
CONTACT_CONTEXT_LABELS = PRIVATE_CONTEXT_LABELS - {'الملف الشخصي', 'تعديل الملف الشخصي', 'الأمان والخصوصية', 'تسجيل الخروج'}
PROFILE_CONTEXT_LABELS = PRIVATE_CONTEXT_LABELS - CONTACT_CONTEXT_LABELS
EDITOR_LABELS = frozenset({'عنوان الإعلان *', 'المواصفات', 'غرف النوم *',
    'الحمامات *', 'المحافظة *', 'تأكيد الموقع على الخريطة',
    'تم تحديد موقع العقار على الخريطة', 'تأكيد هذا الموقع'})


def _labels(row):
    return {s.strip() for k in ('text', 'description', 'hint')
            for s in str(row.get(k, '')).splitlines() if s.strip()}


class HostConsoleCaptureMixin:
    HOST_CAPTURE_SIZE = (540, 960)
    HOST_CAPTURE_ERROR = RuntimeError
    HOST_VIDEO_SECONDS = 120

    def _capture_fail(self, code):
        raise self.HOST_CAPTURE_ERROR(code)

    def _capture_name(self, name):
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', name):
            self._capture_fail('host_capture_name_rejected')
        return name

    def _host_capture_root(self):
        root = Path(self.private) / 'host_console_capture_tmp'
        if root.is_symlink():
            self._capture_fail('host_capture_directory_rejected')
        root.mkdir(mode=0o700, exist_ok=True)
        root.chmod(0o700)
        return root

    def _console(self, *args):
        output = self.adb('emu', 'screenrecord', *map(str, args), timeout=45)
        lines = [line.strip() for line in str(output).splitlines() if line.strip()]
        if not lines or lines[-1] != 'OK' or any(
                line.startswith(('KO:', 'ERROR:', 'Error:')) for line in lines):
            self._capture_fail('host_console_command_not_confirmed')

    def _capture_full_rows(self):
        # Full current APP tree also catches contact-Step4 fields below viewport.
        result = self.instrument('account-snapshot')
        try:
            rows = json.loads(base64.b64decode(result['tree_b64'], validate=True))
        except Exception:
            self._capture_fail('host_capture_fresh_tree_invalid')
        if not isinstance(rows, list) or len(rows) > 1200 or any(not isinstance(r, dict) for r in rows):
            self._capture_fail('host_capture_fresh_tree_invalid')
        return [r for r in rows if r.get('package') == 'com.aqer.yemen.uat']

    def _capture_rows_private(self, rows):
        # Step4 may be scrolled: its mounted contact fields are always forbidden.
        # Hidden underlying routes are not themselves captured pixels.
        all_labels = set().union(*(_labels(r) for r in rows)) if rows else set()
        visible = [r for r in rows if r.get('visible', True)]
        visible_labels = set().union(*(_labels(r) for r in visible)) if visible else set()
        text = '\n'.join(visible_labels)
        return bool(all_labels & CONTACT_CONTEXT_LABELS or
                    visible_labels & (AUTH_LABELS | PROFILE_CONTEXT_LABELS)) or any(
            isinstance(value, str) and value and value in text
            for value in getattr(self, 'private_values', ()))

    def nodes(self):
        try:
            rows = super().nodes()
            if getattr(self, 'recorder', None) is not None:
                full = self._capture_full_rows()
                if self._capture_rows_private(full):
                    self.record_tainted = True
                    self._capture_fail('private_transition_during_host_recording')
                # Return the newest snapshot that owns the current action lease.
                rows=[r for r in full if r.get('visible')]
            return rows
        except Exception:
            if getattr(self, 'recorder', None) is not None:
                self.record_tainted = True
            raise

    def _capture_guard(self):
        if not getattr(self, 'authenticated', False):
            self._capture_fail('authentication_capture_refused')
        if getattr(self, '_host_stop_unconfirmed', False):
            self._capture_fail('host_record_stop_unconfirmed_abort_ui')
        self.nodes()  # Fresh caller-compatible state plus existing taint guards.
        rows = self._capture_full_rows()
        if self._capture_rows_private(rows):
            if getattr(self, 'recorder', None) is not None:
                self.record_tainted = True
            self._capture_fail('private_or_contact_capture_refused')
        visible = [r for r in rows if r.get('visible', True)]
        labels = set().union(*(_labels(r) for r in visible)) if visible else set()
        if not (labels & EDITOR_LABELS or any(s.startswith('صور الإعلان (') for s in labels)):
            self._capture_fail('authenticated_editor_capture_required')

    def _validate_png(self, data):
        if not isinstance(data, bytes) or not (32 <= len(data) <= 32 * 1024 * 1024) or data[:8] != b'\x89PNG\r\n\x1a\n':
            self._capture_fail('host_png_invalid')
        offset, dims, image_chunks, ended = 8, None, 0, False
        while offset + 12 <= len(data):
            size = struct.unpack('>I', data[offset:offset + 4])[0]
            kind = data[offset + 4:offset + 8]
            end = offset + 8 + size
            if end + 4 > len(data) or size > 32 * 1024 * 1024:
                self._capture_fail('host_png_invalid')
            payload = data[offset + 8:end]
            if zlib.crc32(kind + payload) & 0xffffffff != struct.unpack('>I', data[end:end + 4])[0]:
                self._capture_fail('host_png_crc_invalid')
            if kind == b'IHDR':
                if dims is not None or size != 13:
                    self._capture_fail('host_png_invalid')
                dims = struct.unpack('>II', payload[:8])
            elif kind == b'IDAT':
                image_chunks += 1
            elif kind == b'IEND':
                ended = size == 0 and end + 4 == len(data)
                break
            offset = end + 4
        if dims != self.HOST_CAPTURE_SIZE or not image_chunks or not ended:
            self._capture_fail('host_png_dimensions_or_structure_invalid')
        return dims

    def safe_capture(self, name):
        name = self._capture_name(name)
        self._capture_guard()
        destination = Path(self.out) / (name + '.png')
        if destination.exists():
            self._capture_fail('host_capture_name_already_exists')
        with tempfile.TemporaryDirectory(prefix='png-', dir=self._host_capture_root()) as directory:
            folder = Path(directory)
            self._console('screenshot', folder)  # Official API takes a directory.
            files = list(folder.iterdir())
            if len(files) != 1 or files[0].is_symlink() or not files[0].is_file() or files[0].suffix.lower() != '.png':
                self._capture_fail('host_png_output_not_unique')
            data = files[0].read_bytes()
            dims = self._validate_png(data)
            self._capture_guard()  # Discard if UI changed into a private context.
            destination.write_bytes(data)
            destination.chmod(0o600)
        self.report['frames'].append({'file': destination.name, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'width': dims[0], 'height': dims[1],
            'authenticated_editor_only': True, 'capture': 'official_emulator_console_host_png'})
        self.save()

    def record_start(self, name):
        name = self._capture_name(name)
        if getattr(self, 'recorder', None) is not None or getattr(self, '_host_stop_unconfirmed', False):
            self._capture_fail('host_recorder_already_active_or_unconfirmed')
        self.safe_capture(name + '-start')
        folder = Path(tempfile.mkdtemp(prefix='webm-', dir=self._host_capture_root()))
        folder.chmod(0o700)
        self._host_video_folder = folder
        self._host_video_path = folder / 'capture.webm'
        self.video_name = name
        self.record_tainted = False
        self._host_stop_unconfirmed = False
        self.recorder = 'official-host-console'  # Preserves base.nodes taint checks.
        self._host_video_start = time.monotonic()
        try:
            self._console('start', '--size', '%dx%d' % self.HOST_CAPTURE_SIZE,
                          '--bit-rate', '1000000', '--time-limit', str(self.HOST_VIDEO_SECONDS),
                          '--fps', '10', '--display', '0', self._host_video_path)
        except Exception:
            self.record_tainted = True
            self.record_stop(export=False)
            raise

    def _validate_webm(self, path):
        if path.is_symlink() or not path.is_file() or not (1024 <= path.stat().st_size <= 64 * 1024 * 1024):
            self._capture_fail('host_webm_file_invalid')
        with path.open('rb') as stream:
            if stream.read(4) != b'\x1a\x45\xdf\xa3':
                self._capture_fail('host_webm_ebml_invalid')
        try:
            result = subprocess.run(['ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
                '-show_entries', 'format=format_name,duration:stream=codec_name,codec_type,width,height,avg_frame_rate',
                '-of', 'json', str(path)], capture_output=True, stdin=subprocess.DEVNULL, timeout=25)
            value = json.loads(result.stdout) if result.returncode == 0 else {}
            streams = value.get('streams', [])
            duration = float(value.get('format', {}).get('duration', 'nan'))
        except Exception:
            self._capture_fail('host_webm_probe_failed')
        if not (len(streams) == 1 and streams[0].get('codec_type') == 'video'
                and streams[0].get('codec_name') in {'vp8', 'vp9', 'av1'}
                and (streams[0].get('width'), streams[0].get('height')) == self.HOST_CAPTURE_SIZE
                and 'webm' in value.get('format', {}).get('format_name', '')
                and math.isfinite(duration) and 0 < duration <= self.HOST_VIDEO_SECONDS + 5):
            self._capture_fail('host_webm_stream_or_duration_invalid')
        return {'duration_s': round(duration, 3), 'codec': streams[0]['codec_name'],
                'width': streams[0]['width'], 'height': streams[0]['height'],
                'average_frame_rate': streams[0].get('avg_frame_rate')}

    def record_stop(self, export=False):
        if getattr(self, 'recorder', None) is None:
            return
        folder = getattr(self, '_host_video_folder', None)
        path = getattr(self, '_host_video_path', None)
        stopped = False
        try:
            self._console('stop')
            stopped = True
            self.recorder = None
            self._host_stop_unconfirmed = False
            if not export:
                return
            if self.record_tainted:
                self._capture_fail('tainted_host_video_discarded')
            self._capture_guard()
            facts = self._validate_webm(path)
            self.safe_capture(self.video_name + '-end')
            destination = Path(self.out) / (self.video_name + '.webm')
            if destination.exists():
                self._capture_fail('host_video_name_already_exists')
            data = path.read_bytes()
            destination.write_bytes(data)
            destination.chmod(0o600)
            self.report['videos'].append({'file': destination.name, 'bytes': len(data),
                'sha256': hashlib.sha256(data).hexdigest(), **facts,
                'capture': 'official_emulator_console_host_webm',
                'requested_time_limit_s': self.HOST_VIDEO_SECONDS, 'authentication_frames': False})
            self.save()
        finally:
            if stopped:
                if folder is not None:
                    shutil.rmtree(folder, ignore_errors=True)
                self._host_video_folder = None
                self._host_video_path = None
            else:
                self.record_tainted = True
                self._host_stop_unconfirmed = True
                self.report['host_record_stop_unconfirmed'] = True
                # Caller must abort UI/auth navigation and stop the emulator.
                # No private/failed clip is exported; it remains only in 0700 temp.
