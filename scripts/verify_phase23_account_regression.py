#!/usr/bin/env python3
"""Run the new behavioral cases against the accepted old implementation.

The current files are restored in finally. A compile/setup failure cannot count
as a reproduced regression: named behavioral failures and completed tests are
required. This operates only on the disposable CI checkout, never on UAT.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '70621ba2df62036a81b6a7b8447527679b64b252'
FILES = (
    'mobile_app/lib/features/discovery/data/smart_search_session.dart',
    'mobile_app/lib/features/discovery/data/marketplace_search_session.dart',
)
REQUIRED_FAILURES = {
    'late AI delivery cannot set filters or request results for another account',
    'an old AI error cannot become the next account error',
    'same actor renewed session clears old search state for assistant',
}


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('disposable_ci_checkout_required')
    saved = {name: (ROOT / name).read_bytes() for name in FILES}
    output = ROOT / 'phase23-regression-evidence'
    output.mkdir(exist_ok=True)
    log = output / 'baseline-account-tests.jsonl'
    try:
        for name in FILES:
            (ROOT / name).write_bytes(subprocess.check_output(
                ['git', 'show', BASELINE + ':' + name], cwd=ROOT))
        with log.open('w') as stream:
            run = subprocess.run(['flutter', 'test', '--no-pub', '--reporter', 'json',
                                  'test/search_account_boundary_test.dart'],
                                 cwd=ROOT / 'mobile_app', stdout=stream,
                                 stderr=subprocess.STDOUT, timeout=240)
    finally:
        for name, content in saved.items():
            (ROOT / name).write_bytes(content)
    names, outcomes, assertions = {}, {}, set()
    for line in log.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') == 'testStart':
            names[event['test']['id']] = event['test']['name']
        if event.get('type') == 'testDone' and not event.get('hidden'):
            outcomes[event['testID']] = event['result']
        if event.get('type') == 'error' and event.get('isFailure') is True:
            assertions.add(event['testID'])
    failed = {names[key] for key, value in outcomes.items()
              if value == 'failure' and key in assertions and key in names}
    passed = [names[key] for key, value in outcomes.items()
              if value == 'success' and key in names]
    reproduced = (run.returncode != 0 and REQUIRED_FAILURES <= failed
                  and len(passed) >= 3)
    receipt = {'baseline_source': BASELINE,
               'behavioral_regression_reproduced': reproduced,
               'failed_assertion_cases': sorted(failed),
               'passed_control_cases': passed,
               'current_source_restored': all((ROOT / n).read_bytes() == c for n, c in saved.items()),
               'native_acceptance': False}
    (output / 'baseline-summary.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, sort_keys=True))
    if not reproduced or not receipt['current_source_restored']:
        raise SystemExit('baseline_behavioral_failure_not_established')


if __name__ == '__main__':
    main()
