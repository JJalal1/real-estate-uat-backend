#!/usr/bin/env python3
"""Specific RED/GREEN navigation control in an isolated disposable worktree."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
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
RETAINED = 'AQER_PHASE1_RETAINED_HOME_VERIFIED'
MAP_MISSING = 'AQER_PHASE1_MAP_AFTER_DEEP_LINK_NOT_OPEN'


def exact_print(rows, marker, test_id=None):
    return any(row.get('type') == 'print' and (test_id is None or row.get('testID') == test_id) and
               row.get('message', '').strip() == marker for row in rows)


def safe_summary(result):
    """Counts and fixed flags only; never machine messages, stderr or paths."""
    rows = protocol(result.stdout)
    selected = []
    for name in sorted(GREEN_NAMES):
        ids = [r['test']['id'] for r in rows if r.get('type') == 'testStart' and r.get('test', {}).get('name') == name]
        done = [r for r in rows if r.get('type') == 'testDone' and r.get('testID') in ids]
        selected.append({'started': min(len(ids), 100), 'completed': min(len(done), 100),
                         'skipped': min(sum(r.get('skipped') is True for r in done), 100),
                         'result': done[0].get('result') if len(done) == 1 and
                         done[0].get('result') in {'success', 'failure', 'error'} else 'unknown'})
    return {'exit_code': result.returncode if type(result.returncode) is int and -128 <= result.returncode <= 255 else -999,
            'json_event_count': min(len(rows), 10000), 'stderr_present': bool(result.stderr),
            'error_count': min(sum(r.get('type') == 'error' for r in rows), 100),
            'retained_state_observed': exact_print(rows, RETAINED),
            'expected_map_missing_observed': exact_print(rows, MAP_MISSING),
            'expected_reason_in_error': any(r.get('type') == 'error' and MAP_MISSING in r.get('error', '') for r in rows),
            'error_is_failure_count': min(sum(r.get('type') == 'error' and r.get('isFailure') is True for r in rows), 100),
            'terminal_success': next((r['success'] for r in reversed(rows) if r.get('type') == 'done' and
                                      type(r.get('success')) is bool), None),
            'selected_tests_in_sorted_fixed_order': selected}


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
    precondition = exact_print(rows, RETAINED, test_id)
    errors = [row for row in rows if row.get('type') == 'error']
    done = [row for row in rows if row.get('type') == 'testDone' and row.get('testID') == test_id]
    if (not precondition or len(errors) != 1 or errors[0].get('testID') != test_id or
            not exact_print(rows, MAP_MISSING, test_id) or
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
            any(row.get('type') == 'error' for row in rows) or exact_print(rows, MAP_MISSING) or
            not any(row.get('type') == 'done' and row.get('success') is True for row in rows) or
            any(done.get(row['id'], {}).get('result') != 'success' or
                done.get(row['id'], {}).get('skipped') is not False for row in tests)):
        raise core.GateError('fixed_navigation_regression_failed')


def _run_control(root, flutter, local, diagnostics):
    source = execute(['git', 'rev-parse', 'HEAD'], root).stdout.strip()
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        raise core.GateError('navigation_control_invalid_source')
    diagnostics['source_commit'] = source
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
    diagnostics['stage'] = 'worktree'
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
            diagnostics['stage'] = 'red'
            old = execute([flutter, 'test', '--machine', TEST, '--plain-name', RED_NAME], tree / 'mobile_app')
            diagnostics['red'] = safe_summary(old)
            validate_red(old)
        finally:
            if added and execute(['git', 'worktree', 'remove', '--force', str(tree)], root).returncode:
                raise core.GateError('navigation_control_cleanup_failed')
            if home.read_bytes() != fixed or test.read_bytes() != test_bytes:
                raise core.GateError('navigation_control_main_source_changed')
            diagnostics['cleanup_passed'] = True
            diagnostics['main_source_unchanged'] = True
    diagnostics['stage'] = 'green'
    new = execute([flutter, 'test', '--machine', TEST], root / 'mobile_app')
    diagnostics['green'] = safe_summary(new)
    validate_green(new)
    return {'status': 'passed', 'scope': 'isolated-widget-navigation-red-green',
            'source_commit': source, 'working_candidate': local,
            'baseline_commit': BASELINE, 'baseline_home_blob': HOME_BLOB,
            'fixed_home_sha256': hashlib.sha256(fixed).hexdigest(),
            'original_expected_navigation_failure': True, 'same_retained_home_state': True,
            'main_source_unchanged': True, 'green_tests': 3,
            'native_android_acceptance': False, 'diagnostics': diagnostics}


def run_control(root, flutter, local=False):
    diagnostics = {'stage': 'source', 'cleanup_passed': False, 'main_source_unchanged': None}
    try:
        return _run_control(root, flutter, local, diagnostics)
    except core.GateError as error:
        error.diagnostics = diagnostics
        raise
    except Exception:
        raise core.GateError('navigation_control_unexpected_failure', diagnostics) from None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--local-unit-only', action='store_true')
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--report', type=Path, default=ROOT / 'phase1-navigation-control/report.json')
    args = parser.parse_args()
    if args.report.exists():
        print('AQER_PHASE1_NAVIGATION_CONTROL_FAILED:stale_control_report_refused')
        return 1
    failed = False
    try:
        receipt = run_control(ROOT, args.flutter, args.local_unit_only)
    except core.GateError as error:
        failed = True
        receipt = {'status': 'failed', 'scope': 'isolated-widget-navigation-red-green',
                   'failure': str(error), 'diagnostics': error.diagnostics,
                   'native_android_acceptance': False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open('x') as output:
        output.write(json.dumps(receipt, indent=2) + '\n')
    github_output = os.environ.get('GITHUB_OUTPUT') if core.enabled(os.environ) else None
    if github_output:
        with open(github_output, 'a') as output:
            output.write('phase1_navigation_evidence=true\n')
    print(json.dumps(receipt))
    if failed:
        print('AQER_PHASE1_NAVIGATION_CONTROL_FAILED:' + receipt['failure'])
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
