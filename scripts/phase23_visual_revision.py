#!/usr/bin/env python3
"""Read-only source gate for the reviewed Phase23 text-contrast revision.

The previous phase23_preflight pin remains an immutable acceptance baseline.
This gate performs no HTTP, login, database, storage or deployment operation.
"""
import os
from pathlib import Path
import re
import subprocess

from phase23_preflight import API, BRANCH, GateError

ROOT = Path(__file__).resolve().parents[1]
SHARE_BASE = 'https://real-estate-uat-api-frankfurt.onrender.com'
BASE_MOBILE_TREE = '727cc7c154ae7020ce0302e21a3699379cf90c4d'
# Exact tree of the final one-line product correction plus its behavioral test.
TREES = {'mobile_app': '62e39d1cdb1057068e60f3f64f56cc6d9d5a7b0e',
         'backend-api-runtime': '76dcc5b61ed2bf55d05935289d09885182fef96e'}
MOBILE_DELTA = {
    'M\tlib/core/widgets/app_components.dart',
    'A\ttest/phase23_centered_state_contrast_test.dart',
}


def _git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args],
                                   text=True, timeout=30).strip()


def guard(env, root=ROOT):
    """Verify the exact checkout and the two-file delta; return safe identity."""
    def matches(pattern, key):
        value = env.get(key)
        return isinstance(value, str) and re.fullmatch(pattern, value)
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
            env.get('GITHUB_REF') == BRANCH and
            env.get('GITHUB_EVENT_NAME') == 'push' and
            env.get('PHASE23_VISUAL_REVISION') == 'true' and
            matches('[0-9a-f]{40}', 'GITHUB_SHA') and
            env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA') and
            matches('[1-9][0-9]*', 'GITHUB_RUN_ID')):
        raise GateError('explicit_visual_revision_ci_context_required')
    if not re.fullmatch('[0-9a-f]{40}', TREES['mobile_app']):
        raise GateError('reviewed_visual_mobile_pin_required')
    if _git(root, 'rev-parse', 'HEAD') != env['GITHUB_SHA']:
        raise GateError('visual_revision_checkout_mismatch')
    for component, expected in TREES.items():
        if _git(root, 'rev-parse', 'HEAD:' + component) != expected:
            raise GateError('unreviewed_visual_product_tree')
    changed = set(_git(root, 'diff', '--name-status', '--no-renames',
                       BASE_MOBILE_TREE, TREES['mobile_app']).splitlines())
    if changed != MOBILE_DELTA:
        raise GateError('visual_revision_two_file_scope_required')
    # Generated build output is ignored; every tracked product file is checked.
    if _git(root, 'diff', '--name-only', 'HEAD', '--',
            'mobile_app', 'backend-api-runtime'):
        raise GateError('visual_revision_product_worktree_dirty')
    return {'source_commit': env['GITHUB_SHA'], 'ci_run_id': env['GITHUB_RUN_ID'],
            'product_trees': dict(TREES), 'prior_mobile_tree': BASE_MOBILE_TREE,
            'reviewed_mobile_changes': sorted(MOBILE_DELTA),
            'backend_unchanged': True, 'live_preflight_rerun': False}


if __name__ == '__main__':
    import json
    print(json.dumps(guard(os.environ), sort_keys=True))
