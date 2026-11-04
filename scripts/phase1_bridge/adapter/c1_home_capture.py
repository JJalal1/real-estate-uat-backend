"""C1-only broker Home diagnostic through the official emulator console.

This dedicated hook never overrides or broadens the editor safe_capture path.
It creates no Root approval and is not C1/C4/C2 acceptance media.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import stat
import struct
import tempfile


HOME_NAMES = {'C1-photo-save': 'C1-before-add-home',
              'C1-force-stop-restore': 'C1-restore-before-add-home'}
HOME_LABELS = ('ماذا تبحث عنه؟', 'ابحث عن عقار أو منطقة…',
               'الرئيسية', 'عملي', 'العملاء', 'حسابي')
HOME_SCOPE = 'authenticated_broker_marketplace_before_add'
HOST_PNG = 'official_emulator_console_host_png'
PATH = re.compile(r'0(?:\.[0-9]{1,4}){0,40}\Z')
SHA = re.compile(r'[a-f0-9]{64}\Z')


def labels(row):
    return {line.strip() for key in ('text', 'description', 'hint')
            for line in str(row.get(key, '')).splitlines() if line.strip()}


class C1HomeConsoleCaptureMixin:
    def _c1_home_need(self, condition, code):
        if not condition: self._capture_fail(code)

    def _c1_home_binding(self):
        self._healthy()
        case = getattr(self, '_active_case', None)
        self._c1_home_need(case in HOME_NAMES and self.authenticated is True
            and self.recorder is None, 'fixed_initial_c1_home_scope_required')
        authority = self._authority('tap')  # Validate the existing lease; no UI input.
        self._c1_home_need(authority.authority_kind == 'SOURCE_PLAN_ONLY',
                           'initial_source_home_capture_only')
        rows = self._capture_full_rows()  # Full APP tree, never just viewport.
        self._c1_home_need(not self._capture_rows_private(rows), 'private_c1_home_capture_refused')
        self._c1_home_need(self.broker_home_ready(rows) is True, 'actual_broker_home_required')
        visible = [row for row in rows if row.get('package') == 'com.aqer.yemen.uat'
                   and row.get('visible') is True]
        binding = []
        for name in HOME_LABELS:
            matches = [row for row in visible if name in labels(row)]
            # Parent/child semantics can repeat one label; independent leaves
            # remain ambiguous. This binds fixed public Home anchors only.
            leaves = [row for row in matches if not any(type(row.get('path')) is str
                and type(other.get('path')) is str and other['path'].startswith(row['path'] + '.')
                for other in matches)]
            self._c1_home_need(len(leaves) == 1, 'unique_visible_broker_home_anchor_required')
            row = leaves[0]
            path, witness, bounds = row.get('path'), row.get('witness'), row.get('bounds')
            self._c1_home_need(type(path) is str and PATH.fullmatch(path) is not None
                and type(witness) is str and SHA.fullmatch(witness) is not None
                and type(bounds) is list and len(bounds) == 4 and all(type(v) is int for v in bounds)
                and row.get('enabled') is True, 'actual_home_anchor_identity_required')
            a, b, c, d = bounds
            self._c1_home_need(0 <= a < c <= 540 and 0 <= b < d <= 960,
                               'visible_home_anchor_bounds_required')
            binding.append((name, path, witness, tuple(bounds), row.get('clickable') is True))
        return case, tuple(binding)

    def capture_initial_broker_home(self):
        name = self.initial_home_capture_name()  # Reviewed Base Fix5 scope/name API.
        before_case, before = self._c1_home_binding()
        self._c1_home_need(name == HOME_NAMES[before_case], 'fixed_initial_home_capture_name_required')
        destination = Path(self.out) / (name + '.png')
        self._c1_home_need(not destination.exists() and not destination.is_symlink()
            and not any(row.get('file') == destination.name for row in self.report['frames']),
            'initial_home_capture_already_exists')
        self._c1_home_need(Path(self.out).is_dir() and not Path(self.out).is_symlink(),
                           'owned_home_capture_directory_required')
        with tempfile.TemporaryDirectory(prefix='c1-home-png-', dir=self._host_capture_root()) as directory:
            folder = Path(directory)
            self._console('screenshot', folder)  # Original official console API.
            files = list(folder.iterdir())
            self._c1_home_need(len(files) == 1 and files[0].is_file() and not files[0].is_symlink()
                and files[0].suffix.lower() == '.png' and files[0].stat().st_nlink == 1
                and 32 <= files[0].stat().st_size <= 32 * 1024 * 1024,
                'unique_actual_home_console_png_required')
            data = files[0].read_bytes()
            if len(data) >= 24 and data.startswith(b'\x89PNG\r\n\x1a\n') and data[12:16] == b'IHDR':
                width, height = struct.unpack('>II', data[16:24])
                if 0 < width <= 16384 and 0 < height <= 16384:
                    self.report.setdefault('home_console_observed_dimensions', {})[name] = {
                        'width': width, 'height': height, 'acceptance_claimed': False}
            dimensions = self._validate_png(data)  # Unchanged frozen CRC/540x960 validator.
            after_case, after = self._c1_home_binding()  # Full privacy + Home again.
            self._c1_home_need(before_case == after_case, 'fixed_initial_c1_home_scope_required')
            if before != after:
                # This Home PNG is an optional diagnostic, excluded from C1
                # acceptance media. Both complete privacy/Home checks passed,
                # but its changed binding means no image may be exported.
                # The subsequent Add still has its own unchanged fresh stable
                # target checks. Never retry this capture or any UI input here.
                self.report.setdefault('home_console_diagnostic_skipped', {})[name] = {
                    'reason': 'home_binding_changed_no_media_exported',
                    'privacy_before_and_after': True, 'acceptance_claimed': False}
                self.save()
                return False
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
            try:
                fd = os.open(destination, flags, 0o600)
            except OSError:
                self._capture_fail('home_png_destination_write_refused')
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        info = destination.stat()
        self._c1_home_need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
            and stat.S_IMODE(info.st_mode) == 0o600, 'private_home_png_write_unconfirmed')
        self.report['frames'].append({'file': destination.name, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'width': dimensions[0], 'height': dimensions[1],
            'capture': HOST_PNG, 'authenticated_editor_only': False,
            'authenticated_broker_home_only': True, 'capture_scope': HOME_SCOPE,
            'privacy_before_and_after': True, 'home_binding_unchanged': True})
        self.save()
