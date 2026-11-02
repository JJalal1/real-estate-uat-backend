"""RED/GREEN receipt and disposable-source safety; no Flutter/Android execution."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import test_phase1_android_ui as shared

SPEC = importlib.util.spec_from_file_location('phase1_navigation', Path(__file__).parents[1] /
                                            'check_phase1_navigation_regression.py')
control = importlib.util.module_from_spec(SPEC)
with patch.dict('sys.modules', {'probe_phase1_android_ui': shared.ui}):
    SPEC.loader.exec_module(control)


def result(rows, code=0):
    return subprocess.CompletedProcess([], code, '\n'.join(json.dumps(row) for row in rows), '')


def red():
    return [
        {'type': 'testStart', 'test': {'id': 1, 'name': control.RED_NAME}},
        {'type': 'print', 'testID': 1, 'message': 'AQER_PHASE1_RETAINED_HOME_VERIFIED'},
        {'type': 'error', 'testID': 1, 'isFailure': True,
         'error': 'AQER_PHASE1_MAP_AFTER_DEEP_LINK_NOT_OPEN'},
        {'type': 'testDone', 'testID': 1, 'result': 'failure', 'skipped': False},
        {'type': 'done', 'success': False},
    ]


def green():
    rows = []
    for index, name in enumerate(sorted(control.GREEN_NAMES)):
        rows += [{'type': 'testStart', 'test': {'id': index, 'name': name}},
                 {'type': 'testDone', 'testID': index, 'result': 'success', 'skipped': False}]
    return rows + [{'type': 'done', 'success': True}]


class NavigationControlSafetyTest(unittest.TestCase):
    def test_only_the_specific_navigation_failure_after_the_retained_state_precondition_is_red(self):
        control.validate_red(result(red(), 1))
        invalid = [([], 1), (red(), 0)]
        for index, field, value in [(0, 'test', {'id': 1, 'name': 'different test'}),
                                    (1, 'message', 'AQER_PHASE1_HOME_STATE_RECREATED'),
                                    (2, 'error', 'Compilation error'), (2, 'isFailure', False),
                                    (2, 'testID', 9), (3, 'skipped', True), (4, 'success', True)]:
            rows = copy.deepcopy(red())
            rows[index][field] = value
            invalid.append((rows, 1))
        invalid.append((red() + [{'type': 'error', 'error': 'another failure'}], 1))
        for rows, code in invalid:
            with self.subTest(rows=rows, code=code), self.assertRaises(shared.ui.GateError):
                control.validate_red(result(rows, code))

    def test_green_requires_all_three_named_tests_to_execute_without_skips_or_other_errors(self):
        control.validate_green(result(green()))
        invalid = [green()[:-1], green()[2:], green() + [{'type': 'error', 'error': 'other'}]]
        for field, value in [('result', 'failure'), ('skipped', True)]:
            rows = green()
            rows[1][field] = value
            invalid.append(rows)
        for rows in invalid:
            with self.subTest(rows=rows), self.assertRaises(shared.ui.GateError):
                control.validate_green(result(rows))

    def test_failed_control_removes_only_its_disposable_worktree_and_preserves_main_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / control.HOME
            test = root / 'mobile_app' / control.TEST
            home.parent.mkdir(parents=True)
            test.parent.mkdir(parents=True)
            home.write_bytes(b'candidate')
            test.write_bytes(b'candidate regression test')
            old = b'pinned baseline'
            blob = hashlib.sha1(b'blob ' + str(len(old)).encode() + b'\0' + old).hexdigest()
            calls = []
            def execute(argv, cwd, timeout=180):
                calls.append((argv, cwd))
                if argv[:2] == ['git', 'rev-parse']:
                    return subprocess.CompletedProcess(argv, 0, shared.SOURCE, '')
                if argv[:2] == ['git', 'show']:
                    return subprocess.CompletedProcess(argv, 0, old.decode(), '')
                if argv[:3] == ['git', 'worktree', 'add']:
                    tree = Path(argv[4])
                    baseline_home, old_test = tree / control.HOME, tree / 'mobile_app' / control.TEST
                    baseline_home.parent.mkdir(parents=True)
                    old_test.parent.mkdir(parents=True)
                    baseline_home.write_bytes(old)
                if argv[:2] == ['flutter', 'test']:
                    return result([], 1)  # Compilation failure is never a valid RED.
                return subprocess.CompletedProcess(argv, 0, '', '')
            with patch.object(control, 'execute', side_effect=execute), patch.object(control, 'HOME_BLOB', blob):
                with self.assertRaisesRegex(shared.ui.GateError, 'specific_red_control_not_established'):
                    control.run_control(root, 'flutter', local=True)
            removed = [argv for argv, _ in calls if argv[:3] == ['git', 'worktree', 'remove']]
            self.assertEqual(1, len(removed))
            self.assertEqual(b'candidate', home.read_bytes())
            self.assertEqual(b'candidate regression test', test.read_bytes())
            self.assertEqual(1, sum(argv[:2] == ['flutter', 'test'] for argv, _ in calls))
            self.assertFalse(any(argv[:2] in [['git', 'checkout'], ['git', 'reset']] for argv, _ in calls))


if __name__ == '__main__':
    unittest.main()
