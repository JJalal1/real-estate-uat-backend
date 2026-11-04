"""Offline proposal: immutable, minimized recipient-encrypted CI checkpoints.

No credential discovery, network, device, acceptance, or key-generation action is
performed here. Only a supplied public certificate is read. Actual capture and
privacy guards remain mandatory in the reviewed producer adapter.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import uuid
import zipfile

from PIL import Image

REPO = 'JJalal1/real-estate-uat-backend'
MAX_MEDIA = 64 * 1024 * 1024
MAX_TOTAL = 200 * 1024 * 1024
MAX_CIPHER = 256 * 1024 * 1024
MAX_STAGE = 32 * 1024
HEX64 = re.compile(r'[0-9a-f]{64}\Z')
UTC = re.compile(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z')
MEDIA_NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}\.(?:png|webm|mp4)\Z')
STAGE_KEYS = frozenset({'required_review_kind', 'executor_cursor', 'context', 'bindings',
    'postconditions', 'requested_review_fields', 'report_scope'})
FORBIDDEN_KEYS = frozenset({'access', 'credentials', 'credential', 'private_values',
    'private_aliases', 'private_key', 'state', 'full_state', 'payload', 'original_rows',
    'business_rows', 'baseline_rows', 'env', 'environment', 'headers'})
AUTH_KEY = re.compile(r'(?:^|_)(?:password|otp|phone|phones|token|jwt|cookie|authorization|secret|secrets)(?:_|$)', re.I)
IDENTITY_KEYS = frozenset({'repo', 'run_id', 'run_attempt', 'source_sha', 'toolbundle_sha'})


class PackagerRefused(RuntimeError):
    """Fixed codes only: never interpolate a path, content, or exception."""


def require(value, code):
    if not value:
        raise PackagerRefused(code)


def canonical(value):
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(',', ':'), allow_nan=False).encode('utf-8')
    except (TypeError, ValueError, UnicodeError):
        raise PackagerRefused('checkpoint_json_invalid') from None


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'duplicate_checkpoint_key')
        result[key] = value
    return result


def json_bytes(data, maximum):
    require(type(data) is bytes and 0 < len(data) <= maximum, 'checkpoint_json_size_invalid')
    try:
        value = json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(PackagerRefused('nonfinite_checkpoint_json')))
    except PackagerRefused:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise PackagerRefused('checkpoint_json_invalid') from None
    require(type(value) is dict, 'checkpoint_json_object_required')
    return value


def open_dir(path):
    """Open every absolute path component with NOFOLLOW, anchoring final dirfd."""
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts, 'absolute_directory_required')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open('/', flags)
    try:
        for component in path.parts[1:]:
            child = os.open(component, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except OSError:
        os.close(fd)
        raise PackagerRefused('directory_unobserved') from None


def private_dir(fd):
    info = os.fstat(fd)
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid()
            and stat.S_IMODE(info.st_mode) == 0o700, 'private_owned_directory_required')


def regular_file(fd, maximum, *, private=True):
    info = os.fstat(fd)
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.geteuid()
            and 0 < info.st_size <= maximum, 'owned_single_link_file_required')
    if private:
        require(stat.S_IMODE(info.st_mode) == 0o600, 'private_file_mode_required')
    return info


def identity_shape(value):
    require(type(value) is dict and set(value) == IDENTITY_KEYS and value['repo'] == REPO,
            'fixed_checkpoint_identity_required')
    require(type(value['run_id']) is str and re.fullmatch(r'[1-9][0-9]{0,19}', value['run_id']), 'run_id_invalid')
    require(type(value['run_attempt']) is int and 1 <= value['run_attempt'] <= 1000, 'run_attempt_invalid')
    require(type(value['source_sha']) is str and re.fullmatch(r'[0-9a-f]{40}', value['source_sha']), 'source_sha_invalid')
    require(type(value['toolbundle_sha']) is str and HEX64.fullmatch(value['toolbundle_sha']), 'toolbundle_sha_invalid')


def timestamp(value):
    if value is None:
        return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    require(type(value) is str and UTC.fullmatch(value), 'checkpoint_utc_invalid')
    try:
        datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        raise PackagerRefused('checkpoint_utc_invalid') from None
    return value


def minimized_fixture(fixture, baseline, terminal):
    if terminal and fixture is None and baseline is None:
        return None, None
    require(type(fixture) is dict and set(fixture) == {'draft_uuid', 'tag', 'actor_id', 'property_id'},
            'minimal_fixture_identity_required')
    try:
        require(type(fixture['draft_uuid']) is str
                and str(uuid.UUID(fixture['draft_uuid'])) == fixture['draft_uuid'], 'fixture_uuid_invalid')
    except (ValueError, AttributeError):
        raise PackagerRefused('fixture_uuid_invalid') from None
    require(type(fixture['tag']) is str and re.fullmatch(r'AQER-C1-[0-9a-f]{12}', fixture['tag']), 'fixture_tag_invalid')
    require(type(fixture['actor_id']) is int and fixture['actor_id'] == 28, 'fixture_owner_invalid')
    require(fixture['property_id'] is None or (type(fixture['property_id']) is int
            and fixture['property_id'] > 0), 'fixture_property_identity_invalid')
    require(type(baseline) is dict and set(baseline) == {'properties', 'drafts'}, 'minimal_baseline_required')
    for kind in ['properties', 'drafts']:
        row = baseline[kind]
        require(type(row) is dict and set(row) == {'count', 'sha256'}
                and type(row['count']) is int and 0 <= row['count'] <= 100000
                and type(row['sha256']) is str and HEX64.fullmatch(row['sha256']), 'minimal_baseline_row_required')
    # Deep copies by canonical roundtrip prevent an asynchronous producer from
    # adding original rows or private aliases after schema validation.
    return json_bytes(canonical(fixture), 2048), json_bytes(canonical(baseline), 2048)


def stage_shape(stage, aliases):
    require(type(stage) is dict and set(stage) <= STAGE_KEYS, 'selected_stage_metadata_required')
    count = 0
    def visit(node, depth=0):
        nonlocal count
        count += 1
        require(count <= 1024 and depth <= 10, 'stage_structure_bound')
        if type(node) is dict:
            for name, child in node.items():
                require(type(name) is str and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,95}', name), 'stage_key_invalid')
                require(name.lower() not in FORBIDDEN_KEYS and AUTH_KEY.search(name) is None,
                        'private_stage_data_refused')
                require(name != 'phase1_accepted' or child is False, 'phase1_acceptance_not_a_checkpoint')
                visit(child, depth + 1)
        elif type(node) is list:
            for child in node: visit(child, depth + 1)
        elif type(node) is str:
            require(len(node) <= 4096 and re.fullmatch(r'\+?[0-9]{7,15}', node) is None,
                    'private_or_unbounded_stage_string')
        elif type(node) is int:
            require(abs(node) <= 2 ** 53 - 1, 'stage_integer_bound')
        else:
            require(node is None or type(node) is bool, 'stage_value_type_invalid')
    visit(stage)
    data = canonical(stage)
    require(len(data) <= MAX_STAGE, 'stage_size_bound')
    text = data.decode('utf-8')
    require(all(alias not in text for alias in aliases), 'private_stage_value_refused')
    return json_bytes(data, MAX_STAGE)


@dataclass(frozen=True)
class SealedCheckpoint:
    public_receipt: dict
    held_context: dict | None
    directory: Path
    # Neither field contains fixture data; ciphertext is not represented here.


class CheckpointPackager:
    def __init__(self, root: Path, evidence_root: Path, identity: dict,
                 recipient_cert: Path, recipient_sha256: str, job_public: bytes,
                 root_key_id: str, private_aliases: tuple[str, ...]):
        identity_shape(identity)
        require(type(job_public) is bytes and len(job_public) == 32, 'job_public_key_required')
        require(type(root_key_id) is str and HEX64.fullmatch(root_key_id), 'root_public_pin_required')
        require(type(private_aliases) is tuple and len(private_aliases) > 0
                and all(type(value) is str and value for value in private_aliases), 'inmemory_private_aliases_required')
        require(type(recipient_sha256) is str and HEX64.fullmatch(recipient_sha256), 'recipient_digest_required')
        self._root, self._evidence = Path(root), Path(evidence_root)
        self._root_fd, self._evidence_fd = open_dir(self._root), None
        try:
            private_dir(self._root_fd)
            self._evidence_fd = open_dir(self._evidence)
            private_dir(self._evidence_fd)
            for name in ['checkpoints', '.checkpoint-staging']:
                try:
                    os.mkdir(name, 0o700, dir_fd=self._root_fd)
                except FileExistsError:
                    raise PackagerRefused('fresh_packager_directories_required') from None
            self._checkpoints_fd = os.open('checkpoints', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self._root_fd)
            self._staging_fd = os.open('.checkpoint-staging', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self._root_fd)
            certificate = Path(recipient_cert)
            cert_parent = open_dir(certificate.parent)
            try:
                cert_fd = os.open(certificate.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=cert_parent)
            finally:
                os.close(cert_parent)
            try:
                regular_file(cert_fd, 64 * 1024, private=False)
                cert = os.read(cert_fd, 64 * 1024 + 1)
            finally:
                os.close(cert_fd)
            require(digest(cert) == recipient_sha256 and b'-----BEGIN CERTIFICATE-----' in cert
                    and b'PRIVATE KEY' not in cert, 'pinned_public_recipient_required')
            check = subprocess.run(['openssl', 'x509', '-noout', '-checkend', '600'],
                                   input=cert, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=10)
            require(check.returncode == 0, 'public_recipient_not_current')
            self._certificate = cert
        except PackagerRefused:
            self.close()
            raise
        except Exception:
            self.close()
            raise PackagerRefused('public_packager_initialization_failed') from None
        self._identity = json_bytes(canonical(identity), 2048)
        self._job_public = base64.b64encode(job_public).decode('ascii')
        self._root_key_id = root_key_id
        self._aliases = private_aliases
        self._max_allocated = -1
        self._fixture_pin = None
        self._baseline_pin = None
        self._property_pin = None

    @property
    def max_allocated(self): return self._max_allocated

    @property
    def identity(self):
        # The identity schema contains only immutable primitive values. Return a
        # new mapping so an owner caller cannot mutate the pinned copy.
        return dict(self._identity)

    def close(self):
        for name in ['_staging_fd', '_checkpoints_fd', '_evidence_fd', '_root_fd']:
            fd = getattr(self, name, None)
            if fd is not None:
                os.close(fd)
                setattr(self, name, None)
        self._certificate = None

    def _media(self, entry):
        require(type(entry) is dict and set(entry) == {'file', 'sha256', 'kind', 'capture'}, 'explicit_media_entry_required')
        name, kind, capture = entry['file'], entry['kind'], entry['capture']
        require(type(kind) is str and type(capture) is str, 'truthful_capture_kind_required')
        require(type(name) is str and MEDIA_NAME.fullmatch(name) and name.endswith('.' + str(kind)), 'media_basename_required')
        require(type(entry['sha256']) is str and HEX64.fullmatch(entry['sha256']), 'media_digest_required')
        require((kind, capture) in {('png', 'official_emulator_console_png'),
            ('png', 'official_emulator_console_host_png'),
            ('png', 'android_guest_screencap'), ('webm', 'official_emulator_console_host_webm'),
            ('mp4', 'android_guest_screenrecord')}, 'truthful_capture_kind_required')
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self._evidence_fd)
        except OSError:
            raise PackagerRefused('media_file_unobserved') from None
        try:
            before = regular_file(fd, MAX_MEDIA)
            hasher = hashlib.sha256()
            while True:
                chunk = os.read(fd, 1024 * 1024)
                if not chunk: break
                hasher.update(chunk)
            require(hasher.hexdigest() == entry['sha256'], 'media_digest_mismatch')
            os.lseek(fd, 0, os.SEEK_SET)
            result = dict(entry, bytes=before.st_size, width=540, height=960)
            if kind == 'png':
                try:
                    with os.fdopen(os.dup(fd), 'rb') as stream, Image.open(stream) as image:
                        require(image.format == 'PNG' and image.size == (540, 960)
                                and getattr(image, 'n_frames', 1) == 1, 'actual_png_dimensions_required')
                        require(set(image.info) <= {'srgb', 'sRGB', 'gamma', 'dpi', 'chromaticity'}, 'png_metadata_refused')
                        image.verify()
                except PackagerRefused:
                    raise
                except Exception:
                    raise PackagerRefused('actual_png_invalid') from None
            else:
                head = os.read(fd, 16); os.lseek(fd, 0, os.SEEK_SET)
                require(head.startswith(b'\x1aE\xdf\xa3') if kind == 'webm' else head[4:8] == b'ftyp', 'actual_video_container_required')
                try:
                    probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                        'format=duration:stream=codec_type,codec_name,width,height,channels,sample_rate', '-of', 'json',
                        '/proc/self/fd/' + str(fd)], capture_output=True, timeout=20, pass_fds=(fd,))
                    require(probe.returncode == 0, 'actual_video_probe_failed')
                    value = json_bytes(probe.stdout, 16384)
                    streams = value.get('streams')
                    require(type(streams) is list and 1 <= len(streams) <= 2 and all(type(s) is dict for s in streams),
                            'one_actual_video_stream_required')
                    videos = [s for s in streams if s.get('codec_type') == 'video']
                    audios = [s for s in streams if s.get('codec_type') == 'audio']
                    require(len(videos) == 1 and len(audios) <= 1 and len(streams) == 1+len(audios),
                            'one_actual_video_stream_required')
                    stream = videos[0]
                    require(stream.get('codec_type') == 'video' and type(stream.get('width')) is int
                            and stream.get('width') == 540 and type(stream.get('height')) is int
                            and stream.get('height') == 960 and stream.get('codec_name') in
                            ({'vp8', 'vp9'} if kind == 'webm' else {'h264'}), 'actual_video_codec_dimensions_required')
                    duration = value.get('format', {}).get('duration')
                    require(type(duration) is str and re.fullmatch(r'[0-9]{1,3}(?:\.[0-9]{1,9})?', duration)
                            and 0 < Decimal(duration) <= 125, 'actual_video_duration_required')
                    if audios:
                        audio = audios[0]
                        require(kind == 'webm' and capture == 'official_emulator_console_host_webm'
                                and stream.get('codec_name') == 'vp9' and audio.get('codec_name') == 'vorbis'
                                and type(audio.get('channels')) is int and audio['channels'] in {1,2}
                                and audio.get('sample_rate') in {'44100','48000'}, 'native_silent_vorbis_layout_required')
                        pcm = subprocess.run(['ffmpeg','-nostdin','-v','error','-protocol_whitelist','file,pipe',
                            '-i','/proc/self/fd/'+str(fd),'-map','0:a:0','-vn','-c:a','pcm_f32le','-f','f32le','-fs','50000000','pipe:1'],
                            capture_output=True,stdin=subprocess.DEVNULL,timeout=25,pass_fds=(fd,))
                        require(pcm.returncode == 0 and 0 < len(pcm.stdout) < 50_000_000
                                and len(pcm.stdout)%4 == 0 and all(s[0] == 0.0 for s in struct.iter_unpack('<f',pcm.stdout)),
                                'native_audio_exact_silence_required')
                    result['duration_decimal'] = duration  # Preserve actual ffprobe text, no float rounding.
                except PackagerRefused:
                    raise
                except Exception:
                    raise PackagerRefused('actual_video_probe_failed') from None
            after = regular_file(fd, MAX_MEDIA)
            require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
                    (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), 'media_changed_during_validation')
            os.lseek(fd, 0, os.SEEK_SET)
            return fd, before, result
        except BaseException:
            os.close(fd)
            raise

    def seal(self, seq, kind, phase, cursor, fixture, baseline, stage, evidence,
             prev_result_sha, created_utc=None):
        require(self._root_fd is not None and self._certificate is not None, 'packager_closed')
        expected_seq = 1 if kind == 'terminal_checkpoint' and self._max_allocated == -1 else self._max_allocated + 1
        require(type(seq) is int and seq == expected_seq and 0 <= seq <= 10000,
                'fresh_checkpoint_sequence_required')
        require(type(kind) is str and kind in {'fixture_checkpoint', 'review_checkpoint', 'terminal_checkpoint'}
                and ((kind == 'fixture_checkpoint') == (seq == 0)), 'checkpoint_kind_sequence_invalid')
        require(type(phase) is str and phase in {'C1', 'C4', 'C2', 'C5'}
                and type(cursor) is str and re.fullmatch(r'[A-Z][A-Z0-9_]{0,63}', cursor), 'checkpoint_cursor_invalid')
        # The existing normal API title-only PUT has already happened here.
        # This is before native edits, not before all account mutations; a loss
        # before this ciphertext is uploaded is not artifact-recoverable.
        require(kind != 'fixture_checkpoint' or (phase == 'C1'
                and cursor == 'PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP'),
                'explicit_post_bootstrap_checkpoint_scope_required')
        require(type(prev_result_sha) is str and HEX64.fullmatch(prev_result_sha), 'previous_result_digest_invalid')
        require(type(evidence) is list and len(evidence) <= 64, 'explicit_evidence_list_required')
        fixture, baseline = minimized_fixture(fixture, baseline, kind == 'terminal_checkpoint')
        require(kind != 'fixture_checkpoint' or (fixture['property_id'] is None and not evidence), 'premutation_unpromoted_fixture_required')
        require(kind != 'review_checkpoint' or self._fixture_pin is not None,
                'premutation_fixture_checkpoint_required')
        fixture_pin = canonical({name: fixture[name] for name in ['draft_uuid', 'tag', 'actor_id']}) if fixture else None
        baseline_pin = canonical(baseline) if baseline else None
        if self._fixture_pin is not None:
            require(fixture_pin == self._fixture_pin and baseline_pin == self._baseline_pin,
                    'same_fixture_and_baseline_required')
            if self._property_pin is not None:
                require(fixture['property_id'] == self._property_pin, 'same_pinned_property_required')
        stage = stage_shape(stage, self._aliases)
        created = timestamp(created_utc)
        opened, frames = [], []
        checkpoint_fd = zip_fd = cipher_fd = None
        zip_name = f'{seq:06d}.zip'
        try:
            names = []
            for entry in evidence:
                fd, observed, record = self._media(entry)
                opened.append((fd, observed, record))
                names.append(record['file']); frames.append(record)
            require(len(names) == len(set(names)) and sum(row['bytes'] for row in frames) <= MAX_TOTAL,
                    'evidence_duplicate_or_total_bound')
            challenge = os.urandom(32).hex()
            context = dict(self._identity, seq=seq, phase=phase, cursor=cursor,
                           checkpoint_challenge=challenge, prev_result_sha=prev_result_sha)
            checkpoint = dict(context, version=1, kind=kind, created_utc=created,
                              phase1_accepted=False)
            private = {'version': 1, 'kind': kind, 'context_without_cipher':
                context if kind == 'review_checkpoint' else None,
                'job_public_b64': self._job_public, 'root_key_id': self._root_key_id,
                'checkpoint': checkpoint, 'fixture': fixture, 'baseline': baseline,
                'frames': frames, 'stage': stage}
            private_bytes = canonical(private)
            require(all(alias not in private_bytes.decode('utf-8') for alias in self._aliases), 'private_checkpoint_value_refused')
            os.mkdir(f'{seq:06d}', 0o700, dir_fd=self._checkpoints_fd)
            self._max_allocated = seq  # Allocation is consumed even if packaging/upload later fails.
            if fixture_pin is not None:
                self._fixture_pin, self._baseline_pin = fixture_pin, baseline_pin
                if fixture['property_id'] is not None:
                    self._property_pin = fixture['property_id']
            checkpoint_fd = os.open(f'{seq:06d}', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self._checkpoints_fd)
            zip_fd = os.open(zip_name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self._staging_fd)
            with os.fdopen(os.dup(zip_fd), 'wb') as stream, zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_STORED) as archive:
                archive.writestr('CHECKPOINT.json', private_bytes)
                for fd, before, record in opened:
                    hasher = hashlib.sha256()
                    with archive.open(record['file'], 'w') as target:
                        while True:
                            chunk = os.read(fd, 1024 * 1024)
                            if not chunk: break
                            hasher.update(chunk); target.write(chunk)
                    after = regular_file(fd, MAX_MEDIA)
                    require(hasher.hexdigest() == record['sha256'] and
                            (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
                            (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), 'media_changed_during_packaging')
            os.fsync(zip_fd)
            os.lseek(zip_fd, 0, os.SEEK_SET)
            cipher_fd = os.open('checkpoint.cms', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                0o600, dir_fd=checkpoint_fd)
            # The public certificate bytes were verified once and are supplied on
            # stdin, avoiding a later certificate-path substitution.
            with os.fdopen(os.dup(cipher_fd), 'wb') as cipher_stream:
                encrypted = subprocess.run(['openssl', 'cms', '-encrypt', '-binary', '-aes-256-cbc',
                    '-outform', 'DER', '-in', '/proc/self/fd/' + str(zip_fd), '/dev/stdin'],
                    input=self._certificate, stdout=cipher_stream, stderr=subprocess.DEVNULL,
                    timeout=60, pass_fds=(zip_fd,))
                require(encrypted.returncode == 0, 'checkpoint_encryption_failed')
                cipher_stream.flush(); os.fsync(cipher_stream.fileno())
            os.close(cipher_fd); cipher_fd = None
            cipher_read = os.open('checkpoint.cms', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=checkpoint_fd)
            try:
                observed = regular_file(cipher_read, MAX_CIPHER)
                hasher = hashlib.sha256()
                while True:
                    chunk = os.read(cipher_read, 1024 * 1024)
                    if not chunk: break
                    hasher.update(chunk)
            finally:
                os.close(cipher_read)
            cipher_sha = hasher.hexdigest()
            public = dict(checkpoint, cipher_sha=cipher_sha, cipher_bytes=observed.st_size)
            receipt_fd = os.open('PUBLIC_RECEIPT.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=checkpoint_fd)
            with os.fdopen(receipt_fd, 'wb') as stream:
                stream.write(canonical(public)); stream.flush(); os.fsync(stream.fileno())
            os.fsync(checkpoint_fd); os.fsync(self._checkpoints_fd)
            held = dict(context, cipher_sha=cipher_sha) if kind == 'review_checkpoint' else None
            return SealedCheckpoint(public, held, self._root / 'checkpoints' / f'{seq:06d}')
        except PackagerRefused:
            raise
        except Exception:
            raise PackagerRefused('checkpoint_packaging_failed') from None
        finally:
            for fd, _, _ in opened: os.close(fd)
            for fd in [cipher_fd, zip_fd, checkpoint_fd]:
                if fd is not None: os.close(fd)
            try: os.unlink(zip_name, dir_fd=self._staging_fd)
            except FileNotFoundError: pass
