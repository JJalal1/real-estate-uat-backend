"""Synthetic transport objects only; no DNS, sockets, HTTP or credentials."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bounded_api as api


class Clock:
    def __init__(self): self.now = 100.0
    def __call__(self): return self.now


class Socket:
    def __init__(self): self.timeouts = []
    def settimeout(self, value): self.timeouts.append(value)


class Response:
    def __init__(self, chunks=None, status=200, before_read=None):
        self.status = status
        self.chunks = list(chunks if chunks is not None else [b'{"data":{}}', b''])
        self.before_read = before_read
        self.reads = 0
    def read(self, amount):
        self.reads += 1
        if self.before_read: self.before_read()
        return self.chunks.pop(0)


class Connection:
    def __init__(self, host, port, *, timeout, context, remaining_timeout):
        self.host, self.port = host, port
        self.timeout, self.context, self.remaining = timeout, context, remaining_timeout
        self.sock = Socket()
        self.connected, self.closed = 0, 0
        self.requests = []
        self.response = Response()
        self.on_request = None
    def connect(self): self.connected += 1
    def request(self, method, path, *, body, headers):
        self.remaining()  # Like the real subclass, check before each send.
        self.requests.append((method, path, body, headers))
        if self.on_request: self.on_request()
    def getresponse(self): return self.response
    def close(self): self.closed += 1


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.deadline = 125.0
        self.connections = []
        self.setup_connection = None
        self.deadline_reads = 0
        def deadline():
            self.deadline_reads += 1
            return self.deadline
        def factory(*args, **kwargs):
            connection = Connection(*args, **kwargs)
            self.connections.append(connection)
            if self.setup_connection: self.setup_connection(connection)
            return connection
        self.transport = api.DeadlineTransport(deadline_getter=deadline,
            monotonic_clock=self.clock, connection_factory=factory)

    def test_fixed_https_origin_default_tls_and_exact_transport_shape(self):
        code, value, elapsed = self.transport('POST', '/auth/logout', {}, 'SYNTHETIC_TOKEN')
        self.assertEqual((code, value, elapsed), (200, {'data': {}}, 0))
        connection = self.connections[0]
        self.assertEqual((connection.host, connection.port), (api.HOST, 443))
        self.assertTrue(connection.context.check_hostname)
        self.assertEqual(connection.requests[0][:3], ('POST', '/api/auth/logout', b'{}'))
        self.assertEqual(connection.requests[0][3]['Authorization'], 'Bearer SYNTHETIC_TOKEN')
        self.assertEqual(connection.closed, 1)
        self.assertNotIn('SYNTHETIC_TOKEN', repr(self.transport))
        self.assertEqual(self.deadline_reads, 1)

    def test_deadline_getter_identity_is_read_only(self):
        original = self.transport.deadline_getter
        self.assertIs(original, self.transport._deadline_getter)
        self.assertEqual(original(), self.deadline)
        with self.assertRaises(AttributeError):
            self.transport.deadline_getter = lambda: 0
        self.assertIs(self.transport.deadline_getter, original)

    def test_expiry_before_request_prevents_even_connection_construction(self):
        self.deadline = 100
        with self.assertRaisesRegex(api.ApiDeadlineError, '^api_deadline_expired$'):
            self.transport('DELETE', '/properties/100')
        self.assertEqual(self.connections, [])

    def test_expiry_after_send_is_unknown_and_never_retried(self):
        def setup(connection):
            connection.on_request = lambda: setattr(self.clock, 'now', 126.0)
        self.setup_connection = setup
        with self.assertRaisesRegex(api.ApiDeadlineError, '^api_deadline_expired$'):
            self.transport('DELETE', '/properties/100')
        self.assertEqual(len(self.connections), 1)
        self.assertEqual(len(self.connections[0].requests), 1)
        self.assertEqual(self.connections[0].response.reads, 0)
        self.assertEqual(self.connections[0].closed, 1)

    def test_deadline_never_refreshed_and_each_read_timeout_decreases(self):
        def setup(connection):
            connection.response = Response([b'{"data":', b'{}}', b''],
                before_read=lambda: setattr(self.clock, 'now', self.clock.now + 1))
        self.setup_connection = setup
        self.transport('GET', '/auth/me')
        times = self.connections[0].sock.timeouts
        self.assertTrue(all(0 < value <= 25 for value in times))
        self.assertEqual(times, sorted(times, reverse=True))
        self.assertEqual(self.deadline_reads, 1)

    def test_actual_connection_wrapper_rechecks_each_header_body_send(self):
        remaining = [2.0]
        def timeout():
            api.require(remaining[0] > 0, 'api_deadline_expired')
            return remaining[0]
        connection = api._DeadlineHTTPSConnection(api.HOST, 443, timeout=2.0,
            context=self.transport._context, remaining_timeout=timeout)
        connection.sock = Socket()
        with patch.object(api.http.client.HTTPSConnection, 'send') as actual_send:
            connection.send(b'SYNTHETIC_HEADER')
            remaining[0] = 0.0
            with self.assertRaisesRegex(api.ApiDeadlineError, '^api_deadline_expired$'):
                connection.send(b'SYNTHETIC_BODY')
            actual_send.assert_called_once_with(b'SYNTHETIC_HEADER')

    def test_expired_during_chunk_discards_response_and_stops_next_read(self):
        def setup(connection):
            connection.response = Response([b'{"data":', b'{}}'],
                before_read=lambda: setattr(self.clock, 'now', 126.0))
        self.setup_connection = setup
        with self.assertRaisesRegex(api.ApiDeadlineError, '^api_deadline_expired$'):
            self.transport('GET', '/auth/me')
        self.assertEqual(self.connections[0].response.reads, 1)
        self.assertEqual(self.connections[0].closed, 1)

    def test_redirect_is_refused_without_following_or_reading(self):
        self.setup_connection = lambda connection: setattr(connection, 'response', Response(status=302))
        with self.assertRaisesRegex(api.ApiDeadlineError, '^api_redirect_refused$'):
            self.transport('GET', '/auth/me')
        self.assertEqual(len(self.connections), 1)
        self.assertEqual(self.connections[0].response.reads, 0)

    def test_malformed_duplicate_nonfinite_or_unbounded_responses_are_refused(self):
        for chunks, code in [([b'{"data":1,"data":2}', b''], 'api_duplicate_json_key'),
                             ([b'{"data":NaN}', b''], 'api_nonfinite_json'),
                             ([b'[]', b''], 'api_response_object_required'),
                             ([b'not json', b''], 'api_response_json_invalid'),
                             ([b'x' * (api.MAX_RESPONSE + 1)], 'api_response_size_bound')]:
            self.setup_connection = lambda connection, chunks=chunks: setattr(connection, 'response', Response(chunks))
            with self.subTest(code=code), self.assertRaisesRegex(api.ApiDeadlineError, '^' + code + '$'):
                self.transport('GET', '/auth/me')

    def test_foreign_or_control_paths_and_bad_body_never_dispatch(self):
        for path in ['//foreign.invalid/a', 'https://foreign.invalid', '/a\r\nX: injected', '/a#fragment', '/a\\b']:
            with self.subTest(path=repr(path)), self.assertRaisesRegex(api.ApiDeadlineError, '^api_relative_path_refused$'):
                self.transport('GET', path)
        with self.assertRaises(api.ApiDeadlineError): self.transport('POST', '/auth/logout', {'bad': float('nan')})
        with self.assertRaises(api.ApiDeadlineError): self.transport('GET', '/auth/me', token='bad\r\nheader')
        self.assertEqual(self.connections, [])

    def test_transport_error_has_fixed_code_and_no_retry(self):
        def setup(connection):
            def fail(): raise OSError('SYNTHETIC_PRIVATE_SENTINEL')
            connection.on_request = fail
        self.setup_connection = setup
        with self.assertRaisesRegex(api.ApiDeadlineError, '^api_transport_completion_unknown$') as caught:
            self.transport('DELETE', '/properties/100')
        self.assertNotIn('SYNTHETIC_PRIVATE_SENTINEL', str(caught.exception))
        self.assertEqual(len(self.connections), 1)
        self.assertEqual(len(self.connections[0].requests), 1)

    def test_factory_injects_transport_before_any_api_work(self):
        created = []
        def fixture(*args, **kwargs):
            created.append((args, kwargs))
            return 'synthetic-api-instance'
        factory = api.BoundedApiFactory(fixture, self.transport)
        self.assertEqual(factory('SYNTHETIC_PHONE', 'SYNTHETIC_OTP', '9001'), 'synthetic-api-instance')
        self.assertIs(created[0][1]['transport'], self.transport)
        self.assertEqual(created[0][1]['expected_actor_id'], 28)
        self.assertEqual(self.connections, [])
        with self.assertRaises(api.ApiDeadlineError): factory('x', 'y', 'z', expected_actor_id=True)


if __name__ == '__main__':
    unittest.main()
