"""Bounded stdin/stdout IPC to the reviewed artifact action, no task logging."""
import copy
import json
import math
import os
from pathlib import Path
import re
import select
import threading
import time


class BridgeRefused(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise BridgeRefused(code)


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'duplicate_bridge_key')
        result[key] = value
    return result


class StdIOBridge:
    """Only immutable checkpoint-ready messages leave this Python boundary.

    The JS parent uploads with its runtime credentials and returns this fixed
    receipt. An ACK is transport evidence only, never a Root review or native
    acceptance. Descriptors belong to the caller and are never closed here.
    """
    def __init__(self, *, root, input_fd=0, output_fd=1,
                 monotonic_clock=time.monotonic):
        self.root = Path(root)
        require(self.root.is_absolute() and '..' not in self.root.parts,
                'absolute_bridge_root_required')
        require(type(input_fd) is int and input_fd >= 0 and type(output_fd) is int
                and output_fd >= 0 and input_fd != output_fd, 'bridge_descriptors_invalid')
        self._read, self._write, self._mono = input_fd, output_fd, monotonic_clock
        self._announced = set()
        self._lock = threading.Lock()
        self._last_ack = None

    @property
    def last_ack(self):
        return copy.deepcopy(self._last_ack)

    def _current(self, deadline, stop_event, cleanup):
        require(type(deadline) in (int, float) and math.isfinite(deadline),
                'bridge_deadline_invalid')
        require(cleanup is True or not stop_event.is_set(), 'bridge_stop_requested')
        remaining = deadline - self._mono()
        require(remaining > 0, 'bridge_deadline_expired')
        return min(0.1, remaining)

    def announce_and_wait(self, sealed, deadline, stop_event, *, cleanup=False):
        require(type(cleanup) is bool and isinstance(stop_event, threading.Event),
                'bridge_stop_contract_invalid')
        require(self._lock.acquire(blocking=False), 'one_bridge_upload_required')
        try:
            seq = sealed.public_receipt.get('seq')
            require(type(seq) is int and 0 <= seq <= 10000, 'bridge_sequence_invalid')
            require(seq not in self._announced, 'bridge_sequence_already_announced')
            expected = self.root / 'checkpoints' / f'{seq:06d}'
            require(isinstance(sealed.directory, Path), 'bridge_checkpoint_path_invalid')
            require(sealed.directory == expected, 'bridge_checkpoint_path_invalid')
            ready = {'event': 'checkpoint_ready', 'seq': seq,
                     'checkpoint_dir': f'checkpoints/{seq:06d}'}
            data = (json.dumps(ready, separators=(',', ':')) + '\n').encode('ascii')
            self._current(deadline, stop_event, cleanup)
            # Reserve before any possible partial write: never announce the
            # same immutable directory twice after an ambiguous IPC outcome.
            self._announced.add(seq)
            while True:
                timeout = self._current(deadline, stop_event, cleanup)
                try:
                    _, writable, _ = select.select([], [self._write], [], timeout)
                except (OSError, ValueError):
                    raise BridgeRefused('bridge_write_unobserved') from None
                if writable:
                    break
            try:
                require(os.write(self._write, data) == len(data), 'bridge_write_unobserved')
            except OSError:
                raise BridgeRefused('bridge_write_unobserved') from None
            raw = bytearray()
            while True:
                timeout = self._current(deadline, stop_event, cleanup)
                try:
                    readable, _, _ = select.select([self._read], [], [], timeout)
                    if not readable:
                        continue
                    chunk = os.read(self._read, 4097 - len(raw))
                except (OSError, ValueError):
                    raise BridgeRefused('bridge_ack_unobserved') from None
                require(bool(chunk), 'bridge_ack_unobserved')
                raw.extend(chunk)
                require(len(raw) <= 4096, 'bridge_ack_size_invalid')
                if b'\n' in raw:
                    line, tail = bytes(raw).split(b'\n', 1)
                    require(not tail and b'\r' not in line, 'bridge_ack_framing_invalid')
                    break
            try:
                value = json.loads(line.decode('utf-8'), object_pairs_hook=pairs,
                    parse_constant=lambda _: (_ for _ in ()).throw(BridgeRefused('bridge_ack_json_invalid')))
            except BridgeRefused:
                raise
            except (ValueError, UnicodeError, RecursionError):
                raise BridgeRefused('bridge_ack_json_invalid') from None
            require(type(value) is dict and set(value) == {
                'event', 'seq', 'success', 'artifact_id', 'digest'}, 'bridge_ack_shape_invalid')
            require(value['event'] == 'checkpoint_ack' and type(value['seq']) is int
                    and value['seq'] == seq and type(value['success']) is bool,
                    'bridge_ack_identity_invalid')
            digest = value['digest']
            require(digest is None or (type(digest) is str and
                    re.fullmatch(r'[0-9a-f]{64}', digest)), 'bridge_ack_digest_invalid')
            if value['success']:
                require(type(value['artifact_id']) is int and value['artifact_id'] > 0,
                        'bridge_artifact_identity_unobserved')
            else:
                require(value['artifact_id'] is None and digest is None,
                        'bridge_failed_ack_shape_invalid')
            self._current(deadline, stop_event, cleanup)
            self._last_ack = value
            return value['success']
        finally:
            self._lock.release()

    def status(self, code, seq):
        # Unsupported source/library logs must never enter the action NDJSON.
        require(code == 'COMMAND_REFUSED' and type(seq) is int and 1 <= seq <= 10000,
                'bridge_status_invalid')
