"""Offline fixed IPC tests using actual OS pipes, never runtime credentials."""
import json
import os
from pathlib import Path
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest

from checkpoint_io import BridgeRefused, StdIOBridge


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ack_read, self.ack_write = os.pipe()
        self.ready_read, self.ready_write = os.pipe()
        for fd in [self.ack_read, self.ack_write, self.ready_read, self.ready_write]:
            self.addCleanup(os.close, fd)
        self.bridge = StdIOBridge(root=self.root, input_fd=self.ack_read, output_fd=self.ready_write)
        self.stop = threading.Event()
        self.sealed = SimpleNamespace(public_receipt={'seq': 1}, directory=self.root / 'checkpoints/000001')

    def ack(self, **changes):
        value = {'event': 'checkpoint_ack', 'seq': 1, 'success': True,
                 'artifact_id': 9001, 'digest': 'a' * 64}
        value.update(changes)
        return (json.dumps(value) + '\n').encode()

    def call(self, **changes):
        args = dict(sealed=self.sealed, deadline=time.monotonic() + 1,
                    stop_event=self.stop)
        args.update(changes)
        return self.bridge.announce_and_wait(**args)

    def test_actual_ready_event_and_observed_ack_are_fixed_metadata_only(self):
        os.write(self.ack_write, self.ack())
        self.assertTrue(self.call())
        ready = json.loads(os.read(self.ready_read, 4096))
        self.assertEqual(ready, {'event': 'checkpoint_ready', 'seq': 1,
                                'checkpoint_dir': 'checkpoints/000001'})
        self.assertNotIn(str(self.root), json.dumps(ready))
        receipt = self.bridge.last_ack; receipt['artifact_id'] = 8
        self.assertEqual(self.bridge.last_ack['artifact_id'], 9001)
        with self.assertRaisesRegex(BridgeRefused, 'already_announced'):
            self.call()

    def test_failed_ack_has_no_invented_identity_and_terminal_can_follow(self):
        os.write(self.ack_write, self.ack(success=False, artifact_id=None, digest=None))
        self.assertFalse(self.call())
        terminal = SimpleNamespace(public_receipt={'seq': 2}, directory=self.root / 'checkpoints/000002')
        self.stop.set()
        os.write(self.ack_write, self.ack(seq=2, digest=None))
        self.assertTrue(self.call(sealed=terminal, cleanup=True))
        self.assertIsNone(self.bridge.last_ack['digest'])

    def test_wrong_duplicate_unknown_and_raw_private_ack_errors_are_fixed(self):
        malformed = [self.ack(seq=2), self.ack(seq=True), self.ack(artifact_id=True),
            self.ack(digest='bad'), self.ack(unexpected='PRIVATE_SENTINEL'),
            self.ack(success=False), b'{"seq":1,"seq":1}\n',
            b'PRIVATE_SENTINEL\n', self.ack() + self.ack(), b'x' * 4097,
            b'\xff\n', b'[]\n']
        for raw in malformed:
            with self.subTest(size=len(raw)):
                # A fresh IPC lifecycle isolates each malformed ACK completely.
                ack_read, ack_write = os.pipe(); out_read, out_write = os.pipe()
                try:
                    bridge = StdIOBridge(root=self.root, input_fd=ack_read, output_fd=out_write)
                    os.write(ack_write, raw)
                    with self.assertRaises(BridgeRefused) as error:
                        bridge.announce_and_wait(self.sealed, time.monotonic()+1, self.stop)
                    self.assertNotIn('PRIVATE_SENTINEL', str(error.exception))
                finally:
                    for fd in [ack_read, ack_write, out_read, out_write]: os.close(fd)

    def test_stop_expiry_eof_and_directory_escape_never_count_acknowledged(self):
        self.stop.set()
        with self.assertRaisesRegex(BridgeRefused, 'stop_requested'): self.call()
        self.stop.clear()
        with self.assertRaisesRegex(BridgeRefused, 'deadline_expired'):
            self.call(deadline=time.monotonic()-1)
        other = SimpleNamespace(public_receipt={'seq': 1}, directory=self.root / 'elsewhere/000001')
        with self.assertRaisesRegex(BridgeRefused, 'path_invalid'): self.call(sealed=other)
        before = time.monotonic()
        with self.assertRaisesRegex(BridgeRefused, 'deadline_expired'):
            self.call(deadline=before+0.02)
        self.assertLess(time.monotonic()-before, 0.5)
        self.assertIsNone(self.bridge.last_ack)

    def test_status_never_emits_protocol_or_private_text(self):
        self.bridge.status('COMMAND_REFUSED', 1)
        with self.assertRaisesRegex(BridgeRefused, 'status_invalid'):
            self.bridge.status('PRIVATE_SENTINEL', 1)

    def test_closed_supervisor_input_does_not_invent_an_ack(self):
        ack_read, ack_write = os.pipe()
        os.close(ack_write)
        try:
            bridge = StdIOBridge(root=self.root, input_fd=ack_read, output_fd=self.ready_write)
            with self.assertRaisesRegex(BridgeRefused, 'ack_unobserved'):
                bridge.announce_and_wait(self.sealed, time.monotonic()+1, self.stop)
            self.assertIsNone(bridge.last_ack)
        finally:
            os.close(ack_read)


if __name__ == '__main__': unittest.main()
