"""Offline foundation for admitted, checked one-shot instrumentation calls.

No device, network, process or file work occurs here. The owner binds an existing
synchronous checked instrument callable and keeps this gate for its whole owned
runtime. This is not a persistent UiAutomation connection or native acceptance.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
import re
import threading
from typing import Callable


ALLOWED_OPS = frozenset({
    'account-snapshot', 'account-click', 'account-set', 'account-scroll',
})
_NODE_PATH = re.compile(r'0(?:\.[0-9]{1,4}){0,40}\Z')
_WITNESS = re.compile(r'[a-f0-9]{64}\Z')
_BASE64 = re.compile(r'[A-Za-z0-9+/=]{0,12000}\Z')


class AdmissionError(RuntimeError):
    """Fixed diagnostics only; never format caller or driver values."""


@dataclass(frozen=True)
class _Reservation:
    epoch: int
    sequence: int


class OneShotAdmission:
    """A permanent per-owner admission/uncertainty latch, not a connection.

    A completed call means the bound checked driver returned its successful
    instrumentation receipt. Unknown completion must be resolved by disposing
    of the owned runtime, never by restarting this gate or replacing it.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._state = 'closed'
        self._epoch = 0
        self._inflight = 0
        self._known_completion = True  # No operation has been reserved yet.
        self._reserved = 0
        self._completed = 0
        self._uncertain = 0
        self._refused = 0
        self._active: _Reservation | None = None

    def __repr__(self) -> str:
        return '<OneShotAdmission state=' + self.metrics['state'] + '>'

    @property
    def metrics(self) -> dict:
        """A fresh safe projection; never return internal objects or call data."""
        with self._lock:
            return {
                'state': self._state,
                'admission_epoch': self._epoch,
                'inflight': self._inflight,
                'last_reserved_call_completion_known': self._known_completion if self._reserved else None,
                'reserved_calls': self._reserved,
                'checked_calls_completed': self._completed,
                'uncertain_calls': self._uncertain,
                'refused_calls': self._refused,
                'driver_model': 'one_shot_checked_instrumentation',
                'persistent_connection_claimed': False,
            }

    def _refuse(self, code: str) -> None:
        # Called only under _lock; every caller supplies a literal fixed code.
        self._refused += 1
        raise AdmissionError(code) from None

    def start(self) -> int:
        """Open an operation-admission epoch; this opens no device connection."""
        with self._lock:
            if self._state == 'uncertain':
                self._refuse('admission_uncertain')
            if self._inflight:
                self._refuse('instrumentation_inflight')
            if self._state != 'closed':
                self._refuse('admission_already_open')
            if not self._known_completion:
                self._refuse('admission_uncertain')
            self._epoch += 1
            self._state = 'open'
            return self._epoch

    def stop(self) -> dict:
        """Close admission only; do not claim to release a native connection."""
        with self._lock:
            if self._state == 'uncertain' or (not self._known_completion and not self._inflight):
                self._refuse('admission_uncertain')
            if self._inflight:
                self._refuse('instrumentation_inflight')
            self._state = 'closed'
        return self.metrics

    def _reserve(self, expected_epoch: int) -> _Reservation:
        with self._lock:
            if self._state == 'uncertain':
                self._refuse('admission_uncertain')
            if self._state != 'open':
                self._refuse('admission_closed')
            if type(expected_epoch) is not int or expected_epoch != self._epoch:
                self._refuse('admission_epoch_mismatch')
            if self._inflight:
                self._refuse('instrumentation_inflight')
            if not self._known_completion:
                self._refuse('admission_uncertain')
            self._reserved += 1
            reservation = _Reservation(self._epoch, self._reserved)
            self._active = reservation
            self._inflight = 1
            self._known_completion = False
            return reservation

    def _complete(self, reservation: _Reservation, *, known: bool) -> None:
        with self._lock:
            valid = (self._state == 'open' and self._inflight == 1
                     and self._active == reservation and self._epoch == reservation.epoch)
            self._active = None
            self._inflight = 0
            if valid and known:
                self._known_completion = True
                self._completed += 1
            else:
                self._known_completion = False
                self._state = 'uncertain'
                self._uncertain += 1


def _request_is_supported(op: object, extras: dict) -> bool:
    if type(op) is not str or op not in ALLOWED_OPS:
        return False
    if op == 'account-snapshot':
        return not extras
    wanted = {'node_path', 'node_witness'}
    if op == 'account-set':
        wanted.add('value_b64')
    elif op == 'account-scroll':
        wanted.add('direction')
        if 'scroll_step' in extras:
            wanted.add('scroll_step')
    if set(extras) != wanted:
        return False
    if not (type(extras['node_path']) is str and _NODE_PATH.fullmatch(extras['node_path'])
            and type(extras['node_witness']) is str and _WITNESS.fullmatch(extras['node_witness'])):
        return False
    if op == 'account-set':
        return type(extras['value_b64']) is str and bool(_BASE64.fullmatch(extras['value_b64']))
    if op == 'account-scroll':
        return (type(extras['direction']) is str and extras['direction'] in {'forward', 'backward'}
                and ('scroll_step' not in extras or
                     (type(extras['scroll_step']) is str and extras['scroll_step'] == 'short')))
    return True


def _completion_is_checked(op: str, result: object) -> bool:
    # The bound base driver is responsible for checking am -w completion and
    # INSTRUMENTATION_CODE before returning. These additional shape checks never
    # convert an exception or malformed return into a successful completion.
    if type(result) is not dict:
        return False
    if not (type(result.get('passed')) is str and result['passed'] == 'true'
            and type(result.get('op')) is str and result['op'] == op):
        return False
    if op == 'account-snapshot':
        if not (type(result.get('tree_b64')) is str and 0 < len(result['tree_b64']) <= 2_000_000):
            return False
        try:
            # Validate only transport shape. The caller still owns JSON/node,
            # foreground, scene, privacy and input-witness checks.
            return bool(base64.b64decode(result['tree_b64'], validate=True))
        except (ValueError, TypeError):
            return False
    if not (type(result.get('account_action_delivered')) is str
            and result['account_action_delivered'] == 'true'):
        return False
    return op != 'account-set' or (type(result.get('set_text_delivered')) is str
                                  and result['set_text_delivered'] == 'true')


class OneShotInstrumentAdapter:
    """Serialize calls to an externally supplied checked base instrument method.

    Every call requires the epoch issued by start(). The adapter never stores
    arguments, payloads, trees, witnesses, exceptions or the previous operation,
    and it has no replay or reset method. The supplied callable must not retry.
    """

    def __init__(self, checked_instrument: Callable, *, admission: OneShotAdmission | None = None) -> None:
        if not callable(checked_instrument):
            raise AdmissionError('checked_instrument_callable_required')
        if admission is not None and type(admission) is not OneShotAdmission:
            raise AdmissionError('oneshot_admission_required')
        self._checked_instrument = checked_instrument
        self._admission = admission if admission is not None else OneShotAdmission()

    def __repr__(self) -> str:
        return '<OneShotInstrumentAdapter state=' + self.metrics['state'] + '>'

    @property
    def metrics(self) -> dict:
        return self._admission.metrics

    def start(self) -> int:
        return self._admission.start()

    def stop(self) -> dict:
        return self._admission.stop()

    def instrument(self, op: str, *, expected_epoch: int, **extras) -> dict:
        if not _request_is_supported(op, extras):
            raise AdmissionError('unsupported_instrumentation_request') from None
        reservation = self._admission._reserve(expected_epoch)
        result = None
        known = False
        try:
            result = self._checked_instrument(op, **extras)
            known = _completion_is_checked(op, result)
        except BaseException:
            # A timeout, interruption or arbitrary driver error has unknown
            # native completion. Do not retain or relay the original exception.
            pass
        finally:
            self._admission._complete(reservation, known=known)
        if not known or self.metrics['state'] == 'uncertain':
            result = None
            raise AdmissionError('instrumentation_completion_uncertain') from None
        return result
