import copy
import sys
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
from run_phase23_native import validate_command, GateError
from run_phase23_native import NativeRun


class CommandSafetyTest(unittest.TestCase):
    def setUp(self):
        self.command = {'run_id': '1234', 'seq': 1, 'challenge': 'a' * 64, 'op': 'observe', 'args': {}}

    def test_stale_or_cross_run_commands_cannot_execute(self):
        for field, bad in [('run_id', '1235'), ('seq', 0), ('challenge', 'b' * 64)]:
            value = copy.deepcopy(self.command)
            value[field] = bad
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)

    def test_credentials_and_arbitrary_operations_cannot_enter_commands(self):
        for op, args in [('shell', {}), ('set', {'label': 'رمز التحقق', 'value': 'example'}),
                         ('login', {'alias': 'broker', 'otp': 'example'})]:
            value = dict(self.command, op=op, args=args)
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)

    def test_coordinate_boundary_is_checked_before_native_input(self):
        for x in [-1, 1080, True]:
            value = dict(self.command, op='touch', args={'x': x, 'y': 200})
            with self.assertRaises(GateError): validate_command(value, '1234', 1, 'a' * 64)
        self.assertEqual(validate_command(dict(self.command, op='touch', args={'x': 500, 'y': 800}), '1234', 1, 'a' * 64)['op'], 'touch')

    def test_fresh_picker_directory_is_prepared_before_any_fixture_write(self):
        class Device:
            ready = False
            directory = False
            writes = []
            def require_preauth_runtime(self): self.ready = True
            def adb(self, *args, **kwargs):
                if args[:2] == ('shell', 'mkdir'):
                    self.directory = True
                if args[0] == 'push':
                    if not self.ready or not self.directory:
                        raise RuntimeError('fresh Download directory is not ready')
                    self.writes.append(args[-1])
                return ''
        with tempfile.TemporaryDirectory() as folder:
            private = Path(folder)
            for name in ['phase23-property.jpg', 'phase23-rotated-exif.jpg', 'phase23-unsuitable.jpg']:
                (private / name).write_bytes(b'synthetic test bytes')
            run = object.__new__(NativeRun)
            run.driver = Device()
            with patch('run_phase23_native.PRIVATE', private):
                receipt = run.seed_media()
            self.assertEqual(len(receipt['files']), 3)
            self.assertEqual(len(run.driver.writes), 3)
            self.assertTrue(all(p.startswith('/sdcard/Download/phase23-') for p in run.driver.writes))


if __name__ == '__main__': unittest.main()
