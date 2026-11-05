"""Fixed-origin normal HTTPS transport with explicit absolute request budgets.

No credentials, request data, response data or exceptions are retained on this
object. There is no retry, redirect, alternate origin or credential discovery.
The deadline is frozen once per call. Socket inactivity timeouts are reduced
before every send and explicit response read, and monotonic expiry is checked
before/after each blocking HTTP step. OS DNS resolution and a remote server's
work after receiving a request are not hard-cancellable by this synchronous
transport. The owner must dispose of its runtime on an unknown mutation result.
"""
from __future__ import annotations

import http.client
import copy
import json
import math
import re
import ssl
import time


HOST = 'real-estate-uat-api-frankfurt.onrender.com'
PORT = 443
BASE_PATH = '/api'
MAX_RESPONSE = 2_000_000
MAX_REQUEST = 64 * 1024
MAX_SOCKET_SECONDS = 60.0
READ_CHUNK = 64 * 1024


class ApiDeadlineError(RuntimeError):
    """Fixed error codes only; the owner must never export raw tracebacks."""


def require(ok, code):
    if not ok:
        raise ApiDeadlineError(code) from None


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'api_duplicate_json_key')
        result[key] = value
    return result


def _constant(_):
    raise ApiDeadlineError('api_nonfinite_json') from None


class _DeadlineHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host, port, *, timeout, context, remaining_timeout):
        self._remaining_timeout = remaining_timeout
        super().__init__(host, port, timeout=timeout, context=context)

    def send(self, data):
        # http.client may send headers and a body separately. Recheck/reduce
        # before EACH such send, not merely before request() as a whole.
        self.timeout = self._remaining_timeout()
        if self.sock is not None:
            self.sock.settimeout(self.timeout)
        result = super().send(data)
        self._remaining_timeout()
        return result


class DeadlineTransport:
    """Call signature matches the existing FixtureApi transport injection.

    The injected factory, used for offline tests, takes host, port and keyword
    timeout/context/remaining_timeout and returns an HTTPSConnection-compatible
    object. Runtime code should use the default verified TLS connection class.
    Environment proxy settings are not inspected or modified; this fixed direct
    HTTPS transport has no proxy or certificate-bypass fallback.
    """

    def __init__(self, *, deadline_getter, monotonic_clock=time.monotonic,
                 connection_factory=None):
        require(callable(deadline_getter) and callable(monotonic_clock),
                'api_deadline_callbacks_required')
        require(connection_factory is None or callable(connection_factory),
                'api_connection_factory_required')
        self._deadline_getter = deadline_getter
        self._monotonic = monotonic_clock
        self._factory = connection_factory or _DeadlineHTTPSConnection
        self._context = ssl.create_default_context()
        self.last_observation = None

    def __repr__(self):
        return '<DeadlineTransport fixed_origin default_tls no_retry>'

    @property
    def deadline_getter(self):
        """Exact callback identity for the composing owner's guard binding."""
        return self._deadline_getter

    def __call__(self, method, path, body=None, token=None):
        self.last_observation = {'stage': 'validate', 'method': method if type(method) is str and method in {'GET', 'POST', 'PUT', 'DELETE'} else 'OTHER'}
        require(type(method) is str and method in {'GET', 'POST', 'PUT', 'DELETE'},
                'api_method_refused')
        require(type(path) is str and 0 < len(path) <= 4096 and path.startswith('/')
                and not path.startswith('//') and '\\' not in path and '#' not in path
                and all(0x21 <= ord(char) <= 0x7e for char in path),
                'api_relative_path_refused')
        require(token is None or (type(token) is str and 0 < len(token) <= 16384
                and re.fullmatch(r'[\x21-\x7e]+', token) is not None),
                'api_token_transport_shape')
        data = None
        if body is not None:
            require(type(body) is dict, 'api_body_object_required')
            try:
                data = json.dumps(body, ensure_ascii=False, allow_nan=False,
                                  separators=(',', ':')).encode('utf-8')
            except (TypeError, ValueError, UnicodeError, RecursionError):
                raise ApiDeadlineError('api_body_json_invalid') from None
            require(len(data) <= MAX_REQUEST, 'api_request_size_bound')

        started = self._monotonic()
        deadline = self._deadline_getter()
        require(_number(started) and _number(deadline), 'api_absolute_deadline_required')

        def remaining_timeout():
            current = self._monotonic()
            require(_number(current), 'api_monotonic_clock_required')
            remaining = deadline - current
            require(remaining > 0, 'api_deadline_expired')
            return min(MAX_SOCKET_SECONDS, remaining)

        headers = {'Accept': 'application/json',
                   'User-Agent': 'AQER-Phase1-Own-Native-Fixture'}
        if token is not None:
            headers['Authorization'] = 'Bearer ' + token
        if data is not None:
            headers['Content-Type'] = 'application/json'
        connection = None
        try:
            # No DNS, connection, send or receive occurs before this check.
            connection = self._factory(HOST, PORT, timeout=remaining_timeout(),
                context=self._context, remaining_timeout=remaining_timeout)

            def bound_socket():
                timeout = remaining_timeout()
                connection.timeout = timeout
                sock = getattr(connection, 'sock', None)
                if sock is not None:
                    sock.settimeout(timeout)

            bound_socket()
            self.last_observation['stage'] = 'connect'
            connection.connect()
            remaining_timeout()
            bound_socket()
            self.last_observation['stage'] = 'request'
            connection.request(method, BASE_PATH + path, body=data, headers=headers)
            remaining_timeout()
            bound_socket()
            self.last_observation['stage'] = 'response_headers'
            response = connection.getresponse()
            remaining_timeout()
            status = response.status
            require(type(status) is int and 100 <= status <= 599, 'api_http_status_invalid')
            self.last_observation['http_status'] = status
            # HTTPConnection never follows Location. Reject every redirect
            # before reading/returning it; there is no new destination request.
            require(not 300 <= status <= 399, 'api_redirect_refused')
            raw = bytearray()
            self.last_observation['stage'] = 'response_body'
            while True:
                bound_socket()
                chunk = response.read(min(READ_CHUNK, MAX_RESPONSE + 1 - len(raw)))
                remaining_timeout()
                require(type(chunk) is bytes, 'api_response_transport_shape')
                if not chunk:
                    break
                raw.extend(chunk)
                require(len(raw) <= MAX_RESPONSE, 'api_response_size_bound')
            remaining_timeout()
            self.last_observation['stage'] = 'parse_json'
            try:
                value = json.loads(bytes(raw), object_pairs_hook=_pairs,
                                   parse_constant=_constant)
            except ApiDeadlineError:
                raise
            except (ValueError, UnicodeError, TypeError, RecursionError):
                raise ApiDeadlineError('api_response_json_invalid') from None
            require(type(value) is dict, 'api_response_object_required')
            remaining_timeout()
            elapsed_ms = round((self._monotonic() - started) * 1000)
            self.last_observation.update(stage='completed', elapsed_ms=elapsed_ms)
            return status, value, elapsed_ms
        except ApiDeadlineError as exc:
            safe_codes = {'api_deadline_expired', 'api_monotonic_clock_required',
                'api_http_status_invalid', 'api_redirect_refused', 'api_response_transport_shape',
                'api_response_size_bound', 'api_duplicate_json_key', 'api_nonfinite_json',
                'api_response_json_invalid', 'api_response_object_required'}
            self.last_observation['error'] = exc.args[0] if len(exc.args) == 1 and exc.args[0] in safe_codes else 'api_validation_failed'
            raise
        except BaseException as exc:
            kind = type(exc).__name__
            self.last_observation['error'] = kind if kind in {
                'TimeoutError', 'ConnectionResetError', 'ConnectionRefusedError',
                'RemoteDisconnected', 'SSLCertVerificationError', 'SSLError',
                'OSError', 'gaierror', 'IncompleteRead'} else 'other_transport_error'
            # A mutation's unknown completion is never retried. Do not relay
            # arbitrary exception strings, raw HTTP bodies or request values.
            raise ApiDeadlineError('api_transport_completion_unknown') from None
        finally:
            if connection is not None:
                try:
                    connection.close()
                except BaseException:
                    pass


def read_public_with_retry(reader, transport, *, diagnostic=None, wait=time.sleep):
    """Retry only a failed public GET once; preserve the transport's deadline.

    No credentials, writes, response bodies or exception messages are recorded.
    A valid public response is still required before native matching can pass.
    """
    transient = {'TimeoutError', 'ConnectionResetError', 'ConnectionRefusedError',
                 'RemoteDisconnected', 'OSError', 'gaierror', 'IncompleteRead'}
    for attempt in (1, 2):
        try:
            result = reader(transport=transport)
        except Exception:
            observed = copy.deepcopy(getattr(transport, 'last_observation', None) or {})
            if diagnostic is not None:
                diagnostic(dict(attempt=attempt, outcome='failed', transport=observed))
            retryable = observed.get('http_status') in {408, 429, 502, 503, 504} or observed.get('error') in transient
            if attempt == 2 or not retryable:
                raise
            # The next request must recheck the same absolute owner deadline.
            wait(2)
        else:
            if diagnostic is not None:
                diagnostic(dict(attempt=attempt, outcome='passed',
                    transport=copy.deepcopy(getattr(transport, 'last_observation', None) or {})))
            return result


class BoundedApiFactory:
    """Inject the bounded transport BEFORE FixtureApi bootstrap/authentication."""

    def __init__(self, fixture_api_class, transport):
        require(callable(fixture_api_class) and callable(transport),
                'bounded_fixture_dependencies_required')
        self._class, self._transport = fixture_api_class, transport

    def __repr__(self):
        return '<BoundedApiFactory redacted>'

    def __call__(self, phone, otp, run_id, *, expected_actor_id=28):
        require(expected_actor_id == 28 and type(expected_actor_id) is int,
                'fixed_fixture_actor_required')
        try:
            return self._class(phone, otp, run_id, transport=self._transport,
                               expected_actor_id=expected_actor_id)
        except BaseException:
            raise ApiDeadlineError('bounded_fixture_construction_failed') from None
