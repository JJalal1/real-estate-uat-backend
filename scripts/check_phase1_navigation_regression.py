#!/usr/bin/env python3
"""Specific RED/GREEN navigation control in an isolated disposable worktree."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile

import probe_phase1_android_ui as core

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '4ab8c6fa184a6cc4eb929c71fbcd1eb7dcf1635a'
HOME = 'mobile_app/lib/features/discovery/presentation/marketplace_home_screen.dart'
HOME_BLOB = '01c770bb0674fe5f28cf8ec45ee697bdfa7d7534'
TEST = 'test/phase1_home_navigation_test.dart'
RED_NAME = 'phase1 retained home opens map after platform deep link'
GREEN_NAMES = {RED_NAME, 'phase1 same-frame duplicate search pushes only once',
               'phase1 stale pop completion cannot unlock a newer push'}


def execute(argv, cwd, timeout=180):
    env = {**os.environ, 'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true'}
    child = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, start_new_session=True)
    try:
        stdout, stderr = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.communicate()
        raise core.GateError('navigation_control_timeout') from None
    return subprocess.CompletedProcess(argv, child.returncode, stdout, stderr)


def protocol(output):
    rows = []
    for line in output.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def validate_red(result):
    rows = protocol(result.stdout)
    ids = [row['test']['id'] for row in rows if row.get('type') == 'testStart'
           and row.get('test', {}).get('name') == RED_NAME]
    if result.returncode != 1 or len(ids) != 1:
        raise core.GateError('specific_red_control_not_established')
    test_id = ids[0]
    precondition = any(row.get('type') == 'print' and row.get('testID') == test_id and
                       row.get('message', '').strip() == 'AQER_PHASE1_RETAINED_HOME_VERIFIED' for row in rows)
    errors = [row for row in rows if row.get('type') == 'error']
    done = [row for row in rows if row.get('type') == 'testDone' and row.get('testID') == test_id]
    if (not precondition or len(errors) != 1 or errors[0].get('testID') != test_id or
            errors[0].get('isFailure') is not True or
            'AQER_PHASE1_MAP_AFTER_DEEP_LINK_NOT_OPEN' not in errors[0].get('error', '') or
            len(done) != 1 or done[0].get('skipped') is not False or
            done[0].get('result') not in {'failure', 'error'} or
            not any(row.get('type') == 'done' and row.get('success') is False for row in rows)):
        raise core.GateError('red_control_failed_for_another_reason')


def validate_green(result):
    rows = protocol(result.stdout)
    tests = [row['test'] for row in rows if row.get('type') == 'testStart' and
             row.get('test', {}).get('name') in GREEN_NAMES]
    done = {row.get('testID'): row for row in rows if row.get('type') == 'testDone'}
    if (result.returncode != 0 or len(tests) != 3 or {row['name'] for row in tests} != GREEN_NAMES or
            any(row.get('type') == 'error' for row in rows) or
            not any(row.get('type') == 'done' and row.get('success') is True for row in rows) or
            any(done.get(row['id'], {}).get('result') != 'success' or
                done.get(row['id'], {}).get('skipped') is not False for row in tests)):
        raise core.GateError('fixed_navigation_regression_failed')


def run_control(root, flutter, local=False):
    source = execute(['git', 'rev-parse', 'HEAD'], root).stdout.strip()
    if not local:
        if (not core.enabled(os.environ) or source != os.environ.get('SOURCE_COMMIT') or
                source != os.environ.get('GITHUB_SHA')):
            raise core.GateError('navigation_control_ci_opt_in_required')
        if execute(['git', 'diff', '--exit-code', '--', HOME, 'mobile_app/' + TEST], root).returncode:
            raise core.GateError('navigation_control_source_dirty')
    home, test = root / HOME, root / 'mobile_app' / TEST
    fixed, test_bytes = home.read_bytes(), test.read_bytes()
    baseline = execute(['git', 'show', BASELINE + ':' + HOME], root)
    data = baseline.stdout.encode()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if baseline.returncode or blob != HOME_BLOB or data == fixed:
        raise core.GateError('navigation_control_baseline_mismatch')
    with tempfile.TemporaryDirectory(prefix='aqer-phase1-nav-') as temporary:
        tree = Path(temporary) / 'worktree'
        added = False
        try:
            result = execute(['git', 'worktree', 'add', '--detach', str(tree), BASELINE], root)
            if result.returncode:
                raise core.GateError('navigation_control_worktree_failed')
            added = True
            if (tree / HOME).read_bytes() != data:
                raise core.GateError('navigation_control_old_source_changed')
            old_test = tree / 'mobile_app' / TEST
            old_test.write_bytes(test_bytes)
            # Match the already resolved locked dependency graph without network.
            for name in ['pubspec.lock', 'pubspec_overrides.yaml']:
                current = root / 'mobile_app' / name
                if current.is_file():
                    (tree / 'mobile_app' / name).write_bytes(current.read_bytes())
            resolved = execute([flutter, 'pub', 'get', '--offline', '--enforce-lockfile'], tree / 'mobile_app')
            if resolved.returncode:
                raise core.GateError('navigation_control_dependencies_failed')
            old = execute([flutter, 'test', '--machine', TEST, '--plain-name', RED_NAME], tree / 'mobile_app')
            validate_red(old)
        finally:
            if added and execute(['git', 'worktree', 'remove', '--force', str(tree)], root).returncode:
                raise core.GateError('navigation_control_cleanup_failed')
            if home.read_bytes() != fixed or test.read_bytes() != test_bytes:
                raise core.GateError('navigation_control_main_source_changed')
    new = execute([flutter, 'test', '--machine', TEST], root / 'mobile_app')
    validate_green(new)
    return {'status': 'passed', 'scope': 'isolated-widget-navigation-red-green',
            'source_commit': source, 'working_candidate': local,
            'baseline_commit': BASELINE, 'baseline_home_blob': HOME_BLOB,
            'fixed_home_sha256': hashlib.sha256(fixed).hexdigest(),
            'original_expected_navigation_failure': True, 'same_retained_home_state': True,
            'main_source_unchanged': True, 'green_tests': 3,
            'native_android_acceptance': False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--local-unit-only', action='store_true')
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--report', type=Path, default=ROOT / 'phase1-navigation-control/report.json')
    args = parser.parse_args()
    try:
        receipt = run_control(ROOT, args.flutter, args.local_unit_only)
    except Exception as error:
        print('AQER_PHASE1_NAVIGATION_CONTROL_FAILED:' +
              (str(error) if isinstance(error, core.GateError) else type(error).__name__))
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
