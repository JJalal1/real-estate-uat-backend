"""Dedicated loaded-basics PNG; generic editor/title capture stays unchanged."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import tempfile

from c1_home_capture import labels


BASICS_LABELS = ('إضافة عقار', '1/4', 'نوع الإعلان والعقار', 'للبيع', 'للإيجار', 'شقة')
BASICS_SCOPE = 'authenticated_c1_loaded_basics_before_title'
PATH = re.compile(r'0(?:\.[0-9]{1,4}){0,40}\Z')
SHA = re.compile(r'[a-f0-9]{64}\Z')


class C1BasicsConsoleCaptureMixin:
    def _c1_basics_need(self, condition, code):
        if not condition: self._capture_fail(code)

    def _c1_basics_binding(self):
        self._healthy()
        self._c1_basics_need(getattr(self, '_active_case', None) == 'C1-photo-save'
            and self.authenticated is True and self.recorder is None,
            'fixed_initial_c1_basics_scope_required')
        authority = self._authority('tap')  # Lease validation only; never UI input.
        self._c1_basics_need(authority.authority_kind == 'SOURCE_PLAN_ONLY',
                            'initial_source_basics_capture_only')
        rows = self._capture_full_rows()
        self._c1_basics_need(not self._capture_rows_private(rows), 'private_c1_basics_capture_refused')
        visible = [row for row in rows if row.get('package') == 'com.aqer.yemen.uat'
                   and row.get('visible') is True]
        self._c1_basics_need(self.basic_editor_loaded(visible) is True,
                            'actual_visible_loaded_basics_required')
        binding = []
        for name in BASICS_LABELS:
            matches = [row for row in visible if name in labels(row)]
            leaves = [row for row in matches if not any(type(row.get('path')) is str
                and type(other.get('path')) is str and other['path'].startswith(row['path'] + '.')
                for other in matches)]
            self._c1_basics_need(len(leaves) == 1, 'unique_visible_basics_anchor_required')
            row = leaves[0]
            path, witness, bounds = row.get('path'), row.get('witness'), row.get('bounds')
            self._c1_basics_need(type(path) is str and PATH.fullmatch(path) is not None
                and type(witness) is str and SHA.fullmatch(witness) is not None
                and type(bounds) is list and len(bounds) == 4 and all(type(v) is int for v in bounds)
                and row.get('enabled') is True, 'actual_basics_anchor_identity_required')
            a, b, c, d = bounds
            self._c1_basics_need(0 <= a < c <= 540 and 0 <= b < d <= 960,
                                'visible_basics_anchor_bounds_required')
            binding.append((name, path, witness, tuple(bounds), row.get('clickable') is True))
        return tuple(binding)

    def capture_basic_editor(self, name, expected_title=None):
        if name != 'C1-basic-editor':
            # Includes C1-owned-editor-title: preserve the original visible-title
            # validation, sequencing and inherited safe_capture implementation.
            return super().capture_basic_editor(name, expected_title)
        before = self._c1_basics_binding()
        destination = Path(self.out) / 'C1-basic-editor.png'
        self._c1_basics_need(not destination.exists() and not destination.is_symlink()
            and not any(row.get('file') == destination.name for row in self.report['frames']),
            'initial_basics_capture_already_exists')
        self._c1_basics_need(Path(self.out).is_dir() and not Path(self.out).is_symlink(),
                            'owned_basics_capture_directory_required')
        with tempfile.TemporaryDirectory(prefix='c1-basics-png-', dir=self._host_capture_root()) as directory:
            folder = Path(directory)
            self._console('screenshot', folder)
            files = list(folder.iterdir())
            self._c1_basics_need(len(files) == 1 and files[0].is_file() and not files[0].is_symlink()
                and files[0].suffix.lower() == '.png' and files[0].stat().st_nlink == 1
                and 32 <= files[0].stat().st_size <= 32 * 1024 * 1024,
                'unique_actual_basics_console_png_required')
            data = files[0].read_bytes()
            dimensions = self._validate_png(data)
            after = self._c1_basics_binding()
            self._c1_basics_need(before == after, 'basics_binding_changed_during_capture')
            try:
                fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            except OSError:
                self._capture_fail('basics_png_destination_write_refused')
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        self.report['frames'].append({'file': destination.name, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'width': dimensions[0], 'height': dimensions[1],
            'capture': 'official_emulator_console_host_png', 'authenticated_editor_only': True,
            'capture_scope': BASICS_SCOPE, 'privacy_before_and_after': True,
            'basics_binding_unchanged': True, 'title_identity_proved': False,
            'fixture_uuid_identity_proved': False})
        self.save()
