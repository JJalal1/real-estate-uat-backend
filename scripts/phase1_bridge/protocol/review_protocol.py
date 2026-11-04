"""Offline proposal: signed commands for one live, owned CI review session.

This module performs no network, device, credential, or environment reads. Its
only persistent state is a private, append-only consume ledger. Acceptance and
UI semantics belong to the separately reviewed integration, not this protocol.
"""
from __future__ import annotations

import base64
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import threading
import time
from typing import Callable, Iterable

from cryptography.exceptions import InvalidSignature, InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


REPOSITORY = 'JJalal1/real-estate-uat-backend'
VERSION = 1
MAX_ENVELOPE_BYTES = 48 * 1024
MAX_REVIEW_BYTES = 16 * 1024
MAX_TTL_SECONDS = 120
CLOCK_SKEW_SECONDS = 5
SIGN_DOMAIN = b'AQER-CI-ROOT-REVIEW-SIGNATURE-v1\x00'
KDF_DOMAIN = b'AQER-CI-ROOT-REVIEW-KEY-v1\x00'
MAGIC = b'AQER-R1\x00'
META_KEYS = frozenset({'version', 'repo', 'run_id', 'run_attempt', 'source_sha',
    'toolbundle_sha', 'seq', 'phase', 'cursor', 'checkpoint_challenge', 'cipher_sha',
    'prev_result_sha', 'op', 'issued_utc', 'expires_utc', 'root_key_id'})
ENVELOPE_KEYS = META_KEYS | {'encrypted_review_b64', 'signature'}
CONTEXT_KEYS = ('repo', 'run_id', 'run_attempt', 'source_sha', 'toolbundle_sha',
    'seq', 'phase', 'cursor', 'checkpoint_challenge', 'cipher_sha', 'prev_result_sha')
UTC_RE = re.compile(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z')
HEX64 = re.compile(r'[0-9a-f]{64}\Z')
AUTH_KEY = re.compile(r'(?:^|_)(?:password|otp|phone|phones|token|jwt|cookie|authorization|credential|credentials|secret|secrets)(?:_|$)', re.I)


class Refused(RuntimeError):
    """A fixed diagnostic only. Never interpolate submitted content or errors."""


def require(value: bool, code: str) -> None:
    if not value:
        raise Refused(code)


def canonical(value: object) -> bytes:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(',', ':'), allow_nan=False).encode('utf-8')
    except (TypeError, ValueError, UnicodeError):
        raise Refused('canonical_json_invalid') from None


def _pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate_json_key')
        result[key] = value
    return result


def _constant(_: str) -> None:
    raise Refused('non_finite_json_refused')


def parse_json(raw: bytes, limit: int) -> dict:
    require(type(raw) is bytes and 0 < len(raw) <= limit, 'json_size_or_type_invalid')
    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=_pairs,
                           parse_constant=_constant)
    except Refused:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise Refused('json_invalid') from None
    require(type(value) is dict, 'json_object_required')
    return value


def _utc(value: str) -> datetime:
    require(type(value) is str and UTC_RE.fullmatch(value) is not None, 'utc_format_invalid')
    try:
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        raise Refused('utc_value_invalid') from None


def _now(value: datetime) -> datetime:
    require(isinstance(value, datetime) and value.tzinfo is not None
            and value.utcoffset() == timedelta(0), 'utc_clock_required')
    return value


def _stamp(value: datetime) -> str:
    return _now(value).strftime('%Y-%m-%dT%H:%M:%SZ')


def raw_public(key: Ed25519PublicKey | X25519PublicKey) -> bytes:
    return key.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def key_id(key: Ed25519PublicKey) -> str:
    return hashlib.sha256(raw_public(key)).hexdigest()


@dataclass(frozen=True)
class Context:
    repo: str
    run_id: str
    run_attempt: int
    source_sha: str
    toolbundle_sha: str
    seq: int
    phase: str
    cursor: str
    checkpoint_challenge: str
    cipher_sha: str
    prev_result_sha: str

    def fields(self) -> dict:
        fields = {name: getattr(self, name) for name in CONTEXT_KEYS}
        _context_shape(fields)
        return fields


def _context_shape(value: dict) -> None:
    require(value['repo'] == REPOSITORY, 'repository_invalid')
    require(type(value['run_id']) is str
            and re.fullmatch(r'[1-9][0-9]{0,19}', value['run_id']) is not None, 'run_identity_invalid')
    for key, maximum in [('run_attempt', 1000), ('seq', 10000)]:
        require(type(value[key]) is int and 1 <= value[key] <= maximum, 'numeric_identity_invalid')
    require(type(value['source_sha']) is str
            and re.fullmatch(r'[0-9a-f]{40}', value['source_sha']) is not None, 'source_sha_invalid')
    for key in ['toolbundle_sha', 'checkpoint_challenge', 'cipher_sha', 'prev_result_sha']:
        require(type(value[key]) is str and HEX64.fullmatch(value[key]) is not None, 'digest_or_challenge_invalid')
    require(type(value['phase']) is str and value['phase'] in {'C1', 'C4', 'C2', 'C5'}, 'phase_invalid')
    require(type(value['cursor']) is str
            and re.fullmatch(r'[A-Z][A-Z0-9_]{0,63}', value['cursor']) is not None, 'cursor_invalid')


def _metadata_shape(value: dict) -> None:
    require(type(value.get('version')) is int and value['version'] == VERSION, 'version_invalid')
    _context_shape(value)
    require(type(value['op']) is str and value['op'] in {'advance', 'reject', 'finish'}, 'operation_invalid')
    require(type(value['root_key_id']) is str and HEX64.fullmatch(value['root_key_id']) is not None, 'root_key_identity_invalid')
    issued, expires = _utc(value['issued_utc']), _utc(value['expires_utc'])
    require(0 < (expires - issued).total_seconds() <= MAX_TTL_SECONDS, 'command_ttl_invalid')


def _review(value: dict, forbidden_values: Iterable[str]) -> bytes:
    require(type(value) is dict, 'review_object_required')
    count = 0

    def visit(node: object, depth: int) -> None:
        nonlocal count
        count += 1
        require(depth <= 10 and count <= 512, 'review_structure_bound')
        if type(node) is dict:
            for name, child in node.items():
                require(type(name) is str
                        and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,95}', name) is not None,
                        'review_key_invalid')
                require(AUTH_KEY.search(name) is None, 'authentication_review_data_refused')
                visit(child, depth + 1)
        elif type(node) is list:
            for child in node:
                visit(child, depth + 1)
        elif type(node) is str:
            require(len(node) <= 4096, 'review_string_bound')
            require(re.fullmatch(r'\+?[0-9]{7,15}', node) is None, 'phone_shaped_review_data_refused')
        elif type(node) is int:
            require(abs(node) <= 2 ** 53 - 1, 'review_integer_bound')
        else:
            require(node is None or type(node) is bool, 'review_value_type_invalid')

    visit(value, 0)
    data = canonical(value)
    require(len(data) <= MAX_REVIEW_BYTES, 'review_size_bound')
    text = data.decode('utf-8')
    for private in forbidden_values:
        require(type(private) is str and private != '', 'private_alias_configuration_invalid')
        require(private not in text, 'private_review_value_refused')
    return data


def _b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode('ascii')


def _unb64(value: str, maximum: int) -> bytes:
    require(type(value) is str and 0 < len(value) <= maximum * 2, 'encoded_data_bound')
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, UnicodeError):
        raise Refused('encoded_data_invalid') from None
    require(len(raw) <= maximum and _b64(raw) == value, 'encoded_data_invalid')
    return raw


def _derive(private: X25519PrivateKey, peer: bytes, salt: bytes, aad: bytes) -> bytes:
    try:
        shared = private.exchange(X25519PublicKey.from_public_bytes(peer))
        return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt,
                    info=KDF_DOMAIN + hashlib.sha256(aad).digest()).derive(shared)
    except ValueError:
        raise Refused('review_key_exchange_invalid') from None


class JobEphemeralKey:
    """One job lifetime only; never serialize/export the private component."""
    def __init__(self) -> None:
        self._private = X25519PrivateKey.generate()

    def public(self) -> bytes:
        require(self._private is not None, 'job_key_closed')
        return raw_public(self._private.public_key())

    def decrypt(self, encoded: str, aad: bytes) -> bytes:
        require(self._private is not None, 'job_key_closed')
        data = _unb64(encoded, MAX_REVIEW_BYTES + 128)
        require(data.startswith(MAGIC) and len(data) >= len(MAGIC) + 32 + 32 + 12 + 16,
                'review_cipher_format_invalid')
        offset = len(MAGIC)
        peer, salt, nonce, cipher = (data[offset:offset + 32], data[offset + 32:offset + 64],
                                   data[offset + 64:offset + 76], data[offset + 76:])
        key = _derive(self._private, peer, salt, aad)
        try:
            return AESGCM(key).decrypt(nonce, cipher, aad)
        except InvalidTag:
            raise Refused('review_cipher_authentication_failed') from None

    def close(self) -> None:
        self._private = None


def build_command(context: Context, review: dict, root_private: Ed25519PrivateKey,
                  job_public: bytes, now: datetime, *, op: str = 'advance',
                  ttl_seconds: int = 90, forbidden_values: Iterable[str] = ()) -> bytes:
    """Operator-side builder. Caller supplies the actual completed Root review."""
    require(type(ttl_seconds) is int and 1 <= ttl_seconds <= MAX_TTL_SECONDS, 'command_ttl_invalid')
    require(isinstance(root_private, Ed25519PrivateKey), 'root_private_key_type_invalid')
    require(type(job_public) is bytes and len(job_public) == 32, 'job_public_key_invalid')
    metadata = dict(context.fields(), version=VERSION, op=op, issued_utc=_stamp(now),
                    expires_utc=_stamp(now + timedelta(seconds=ttl_seconds)),
                    root_key_id=key_id(root_private.public_key()))
    _metadata_shape(metadata)
    plain, aad = _review(review, forbidden_values), canonical(metadata)
    sender = X25519PrivateKey.generate()
    salt, nonce = os.urandom(32), os.urandom(12)
    key = _derive(sender, job_public, salt, aad)
    encrypted = MAGIC + raw_public(sender.public_key()) + salt + nonce + AESGCM(key).encrypt(nonce, plain, aad)
    unsigned = dict(metadata, encrypted_review_b64=_b64(encrypted))
    result = dict(unsigned, signature=_b64(root_private.sign(SIGN_DOMAIN + canonical(unsigned))))
    data = canonical(result)
    require(len(data) <= MAX_ENVELOPE_BYTES, 'envelope_size_bound')
    return data


@dataclass(frozen=True)
class Validated:
    seq: int
    op: str
    command_sha: str
    context_sha: str
    session_sha: str
    expires_utc: datetime
    review_json: bytes = field(repr=False)

    @property
    def review(self) -> dict:
        # Each integration callback receives a separate copy. A scene checker
        # cannot add an approval flag to the record later given to dispatch.
        return parse_json(self.review_json, MAX_REVIEW_BYTES)


def validate_command(raw: bytes, context: Context, root_public: Ed25519PublicKey,
                     job_key: JobEphemeralKey, now: datetime, *,
                     forbidden_values: Iterable[str] = ()) -> Validated:
    value = parse_json(raw, MAX_ENVELOPE_BYTES)
    require(set(value) == ENVELOPE_KEYS, 'envelope_schema_invalid')
    _metadata_shape(value)
    expected = context.fields()
    require(all(value[name] == expected[name] for name in CONTEXT_KEYS), 'held_context_mismatch')
    require(isinstance(root_public, Ed25519PublicKey)
            and value['root_key_id'] == key_id(root_public), 'pinned_root_key_required')
    issued, expires, current = _utc(value['issued_utc']), _utc(value['expires_utc']), _now(now)
    require(issued <= current + timedelta(seconds=CLOCK_SKEW_SECONDS), 'command_from_future')
    require(current <= expires and current - issued <= timedelta(seconds=MAX_TTL_SECONDS), 'command_expired')
    signature = _unb64(value['signature'], 64)
    require(len(signature) == 64, 'signature_size_invalid')
    unsigned = {name: item for name, item in value.items() if name != 'signature'}
    try:
        root_public.verify(signature, SIGN_DOMAIN + canonical(unsigned))
    except InvalidSignature:
        raise Refused('root_signature_invalid') from None
    metadata = {name: value[name] for name in META_KEYS}
    plain = job_key.decrypt(value['encrypted_review_b64'], canonical(metadata))
    review = parse_json(plain, MAX_REVIEW_BYTES)
    review_json = _review(review, forbidden_values)
    # No acceptance flags, timestamps, actor identities or fields are synthesized.
    session = {name: expected[name] for name in ['repo', 'run_id', 'run_attempt',
               'source_sha', 'toolbundle_sha']}
    session.update(root_key_id=value['root_key_id'], job_public_key_sha256=
                   hashlib.sha256(job_key.public()).hexdigest())
    return Validated(value['seq'], value['op'], hashlib.sha256(canonical(value)).hexdigest(),
                     hashlib.sha256(canonical(expected)).hexdigest(),
                     hashlib.sha256(canonical(session)).hexdigest(), expires, review_json)


class ConsumeLedger:
    """Append-only, dirfd-anchored reservation/outcome records; no auth content."""
    def __init__(self, directory: Path):
        directory = Path(directory)
        require(directory.is_absolute() and '..' not in directory.parts, 'ledger_absolute_path_required')
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        fd = os.open('/', flags)
        try:
            for index, component in enumerate(directory.parts[1:]):
                try:
                    child = os.open(component, flags, dir_fd=fd)
                except FileNotFoundError:
                    require(index == len(directory.parts) - 2, 'ledger_parent_missing')
                    try:
                        os.mkdir(component, 0o700, dir_fd=fd)
                    except FileExistsError:
                        pass
                    child = os.open(component, flags, dir_fd=fd)
                os.close(fd)
                fd = child
            info = os.fstat(fd)
        except Refused:
            os.close(fd)
            raise
        except OSError:
            os.close(fd)
            raise Refused('ledger_directory_required') from None
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
            os.close(fd)
            raise Refused('private_owned_ledger_required')
        self._fd = fd
        self._transaction = threading.Lock()

    @contextmanager
    def exclusive(self):
        """No overlapping commands, even with distinct ledger objects/processes."""
        require(self._fd is not None, 'ledger_closed')
        require(self._transaction.acquire(blocking=False), 'owner_transaction_busy')
        locked = False
        try:
            try:
                fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                locked = True
            except OSError:
                raise Refused('owner_transaction_busy') from None
            yield
        finally:
            if locked:
                fcntl.flock(self._fd, fcntl.LOCK_UN)
            self._transaction.release()

    def close(self) -> None:
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def _read(self, name: str) -> dict | None:
        require(self._fd is not None, 'ledger_closed')
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self._fd)
        except FileNotFoundError:
            return None
        except OSError:
            raise Refused('ledger_entry_unobserved') from None
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                    and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o600
                    and 0 < info.st_size <= 2048, 'private_ledger_entry_required')
            return parse_json(os.read(fd, 2049), 2048)
        finally:
            os.close(fd)

    def _write_once(self, name: str, value: dict) -> None:
        require(self._fd is not None, 'ledger_closed')
        data = canonical(value)
        try:
            fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=self._fd)
        except FileExistsError:
            raise Refused('ledger_entry_already_exists') from None
        except OSError:
            raise Refused('ledger_reservation_failed') from None
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                    and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o600,
                    'private_ledger_entry_required')
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                require(written > 0, 'ledger_write_failed')
                view = view[written:]
            os.fsync(fd)
            os.fsync(self._fd)
        except OSError:
            raise Refused('ledger_write_failed') from None
        finally:
            os.close(fd)

    @staticmethod
    def _names(seq: int) -> tuple[str, str]:
        require(type(seq) is int and 1 <= seq <= 10000, 'ledger_sequence_invalid')
        return f'{seq:06d}.command.json', f'{seq:06d}.outcome.json'

    def _outcome(self, seq: int, command_sha: str) -> str:
        value = self._read(self._names(seq)[1])
        if value is None:
            return 'reserved_unobserved'
        require(set(value) == {'version', 'command_sha', 'outcome'}
                and type(value['version']) is int and value['version'] == VERSION
                and value['command_sha'] == command_sha
                and type(value['outcome']) is str
                and value['outcome'] in {'completed', 'failed_uncertain', 'scene_rejected'},
                'ledger_outcome_invalid')
        return value['outcome']

    @staticmethod
    def _reservation(value: dict, seq: int) -> dict:
        require(set(value) == {'version', 'seq', 'op', 'command_sha', 'context_sha', 'session_sha'}
                and type(value['version']) is int and value['version'] == VERSION
                and type(value['seq']) is int and value['seq'] == seq
                and type(value['op']) is str and value['op'] in {'advance', 'reject', 'finish'}
                and all(type(value[name]) is str and HEX64.fullmatch(value[name]) is not None
                        for name in ['command_sha', 'context_sha', 'session_sha']),
                'ledger_reservation_type_invalid')
        return value

    def reserve(self, command: Validated) -> str | None:
        require(self._fd is not None, 'ledger_closed')
        names = os.listdir(self._fd)
        require(all(re.fullmatch(r'[0-9]{6}\.(?:command|outcome)\.json', n) for n in names), 'ledger_unknown_entry')
        reserved = sorted(int(n[:6]) for n in names if n.endswith('.command.json'))
        require(reserved == list(range(1, len(reserved) + 1)), 'ledger_sequence_gap')
        require(all(int(n[:6]) in reserved for n in names if n.endswith('.outcome.json')),
                'orphan_ledger_outcome')
        name, _ = self._names(command.seq)
        old = self._read(name)
        if old is not None:
            self._reservation(old, command.seq)
            require(old == {'version': VERSION, 'seq': command.seq, 'op': command.op,
                            'command_sha': command.command_sha, 'context_sha': command.context_sha,
                            'session_sha': command.session_sha},
                    'consumed_sequence_payload_mismatch')
            return self._outcome(command.seq, command.command_sha)
        require(command.seq == len(reserved) + 1, 'unexpected_next_sequence')
        if reserved:
            previous = self._read(self._names(reserved[-1])[0])
            require(previous is not None, 'previous_reservation_unobserved')
            self._reservation(previous, reserved[-1])
            require(previous.get('session_sha') == command.session_sha, 'ledger_session_mismatch')
            require(previous.get('op') not in {'reject', 'finish'}, 'ledger_session_closed')
            if self._outcome(reserved[-1], previous['command_sha']) != 'completed':
                require(command.op in {'reject', 'finish'}, 'uncertain_previous_advance_refused')
        self._write_once(name, {'version': VERSION, 'seq': command.seq, 'op': command.op,
                               'command_sha': command.command_sha, 'context_sha': command.context_sha,
                               'session_sha': command.session_sha})
        return None

    def finish(self, command: Validated, outcome: str) -> None:
        require(self._fd is not None, 'ledger_closed')
        require(type(outcome) is str
                and outcome in {'completed', 'failed_uncertain', 'scene_rejected'}, 'fixed_outcome_required')
        self._write_once(self._names(command.seq)[1],
                         {'version': VERSION, 'command_sha': command.command_sha, 'outcome': outcome})


@dataclass(frozen=True)
class Receipt:
    status: str
    seq: int
    command_sha: str
    outcome: str


def _receive_one(raw: bytes, *, context: Context, root_public: Ed25519PublicKey,
            job_key: JobEphemeralKey, ledger: ConsumeLedger, now: datetime,
            fresh_scene_check: Callable[[dict], bool], dispatch: Callable[[str, dict], bool],
            forbidden_values: Iterable[str] = ()) -> Receipt:
    """Verify -> decrypt -> durable reservation -> fresh scene -> one dispatch.

    The integration must throw or return non-True on uncertain UI delivery.
    finish/reject dispatches must implement only bounded close/cleanup behavior.
    """
    arrived = time.monotonic()
    command = validate_command(raw, context, root_public, job_key, now,
                               forbidden_values=forbidden_values)
    deadline = arrived + (command.expires_utc - _now(now)).total_seconds()
    old_outcome = ledger.reserve(command)
    if old_outcome is not None:
        return Receipt('already_consumed', command.seq, command.command_sha, old_outcome)
    outcome = 'failed_uncertain'
    try:
        require(time.monotonic() <= deadline, 'command_expired_before_dispatch')
        if command.op == 'advance':
            try:
                scene_matches = fresh_scene_check(command.review)
            except Exception:
                raise Refused('fresh_scene_check_failed') from None
            if scene_matches is not True:
                outcome = 'scene_rejected'
                raise Refused('fresh_scene_mismatch')
        require(time.monotonic() <= deadline, 'command_expired_before_dispatch')
        try:
            result = dispatch(command.op, command.review)
        except Exception:
            raise Refused('dispatch_failed_uncertain') from None
        require(result is True, 'dispatch_not_confirmed')
        outcome = 'completed'
        return Receipt('executed', command.seq, command.command_sha, outcome)
    finally:
        # Even BaseException leaves a durable reservation; no later retry can
        # dispatch the same sequence. No callback data is written into the ledger.
        ledger.finish(command, outcome)


def receive(raw: bytes, *, context: Context, root_public: Ed25519PublicKey,
            job_key: JobEphemeralKey, ledger: ConsumeLedger, now: datetime,
            fresh_scene_check: Callable[[dict], bool], dispatch: Callable[[str, dict], bool],
            forbidden_values: Iterable[str] = ()) -> Receipt:
    """Serial admission; see _receive_one for verify/reserve/scene/dispatch order.

    Integration must also enforce the signed deadline immediately before every
    individual UI input within a multi-input segment; this function guards entry.
    """
    with ledger.exclusive():
        return _receive_one(raw, context=context, root_public=root_public,
                            job_key=job_key, ledger=ledger, now=now,
                            fresh_scene_check=fresh_scene_check, dispatch=dispatch,
                            forbidden_values=forbidden_values)
