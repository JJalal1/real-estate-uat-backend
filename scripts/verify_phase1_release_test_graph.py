#!/usr/bin/env python3
"""Refuse a missing, debug, or misordered release instrumentation task graph."""
from pathlib import Path
import re
import sys


def validate_graph(output):
    tasks = re.findall(r'^(:\S+)\s+SKIPPED\s*$', output, re.M)
    release, tests = ':app:assembleUatRelease', ':app:assembleUatReleaseAndroidTest'
    if tasks.count(release) != 1 or tasks.count(tests) != 1:
        raise ValueError('release_and_test_tasks_required')
    # Release tasks legitimately include stripUatReleaseDebugSymbols and
    # mergeUatReleaseNativeDebugMetadata. Reject variants, not symbol handling.
    debug_variant = re.compile(r':(?:assemble|bundle|compile|merge|process|package|connected|test|check|'
                               r'generate|lint|prepare|validate|javaPreCompile|kapt|ksp)Debug(?:[A-Z]|$)')
    if any('UatDebug' in task or 'Production' in task or debug_variant.search(task) for task in tasks):
        raise ValueError('only_uat_release_graph_allowed')
    if tasks.index(release) >= tasks.index(tests):
        raise ValueError('test_finalizer_must_follow_release')
    return {'release_task': release, 'test_task': tests, 'order': 'release_then_tests'}


if __name__ == '__main__':
    try:
        validate_graph(Path(sys.argv[1]).read_text())
    except (ValueError, OSError, IndexError):
        print('AQER_PHASE1_RELEASE_TEST_GRAPH_FAILED')
        raise SystemExit(1)
    print('AQER_PHASE1_RELEASE_TEST_GRAPH_PASS')
