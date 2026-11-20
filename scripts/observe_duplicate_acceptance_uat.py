#!/usr/bin/env python3
"""Read the exact Frankfurt UAT acceptance fixtures without claiming them."""

import json
import os
import re
import subprocess

from prepare_duplicate_acceptance_uat import ACCEPTANCE_BRANCH
from verify_duplicate_review_uat import API, BROKER_ID, CheckFailed, REPOSITORY, SUPPORT_ID, require
from phase1_native_account_readiness import SECRET_NAME, validate_access
from phase23_preflight import API as DOCUMENTED_API, http
from run_phase23_native import Session


MARKER = 'AQER-UAT-S6-44824099709'
SOURCE = '28da333af0e54922a5b24166df119e8d4de11d17'
BACKEND_TREE = 'd8922005ba0fe9f4e80d6c1203c81a6637d1fd9c'
DEPLOYMENT = 'dep-dc0c18rm8hqs738j3bb0'
FIXTURES = {
    175: ('اختبار ٦: شقة ٨ المختلفة', 'APT', None, None, None),
    176: ('اختبار ٦: نسخة شقة ٧، تشابه النظام', 'APT', 'algorithm', 'تطابقت هوية المبنى والدور والوحدة.', 174),
    178: ('اختبار ٦: فيلا لإشارة المساعد المحاكية', 'VILLA', 'ai', 'تقارب الموقع والمواصفات وظهرت تفاصيل داخلية متطابقة في الصور.', 177),
}


def get(path, token):
    status, response = http('GET', path, token=token)
    require(status == 200 and isinstance(response, dict), 'read_only_review_request_failed')
    return response['data']


def check(row, listing_id):
    title, suffix, source, reason, _ = FIXTURES[listing_id]
    require(row['id'] == listing_id and row['title'] == f'{title} | {MARKER}-{suffix}'
            and row['owner']['id'] == BROKER_ID and row['review_status'] == 'submitted'
            and row['duplicate_detection_source'] == source and row['duplicate_detection_reason'] == reason,
            'fixture_state_or_evidence_changed')


def main():
    env = os.environ
    require(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_REPOSITORY') == REPOSITORY
            and env.get('GITHUB_REF') == ACCEPTANCE_BRANCH and env.get('GITHUB_EVENT_NAME') == 'push'
            and env.get('GITHUB_RUN_ATTEMPT') == '1' and re.fullmatch(r'\d+', env.get('GITHUB_RUN_ID', '')),
            'uat_context_refused')
    tree = subprocess.check_output(['git', '-C', env['GITHUB_WORKSPACE'], 'rev-parse', 'HEAD:backend-api-runtime'], text=True).strip()
    require(tree == BACKEND_TREE and DOCUMENTED_API == API, 'uat_source_changed')
    receipt = {'status': 'FAILED', 'source': SOURCE, 'render_deploy': DEPLOYMENT, 'fixtures': {}}
    support = None
    try:
        access = validate_access(env.pop(SECRET_NAME, ''))
        support = Session('support', access)
        support.login()
        require(support.identity.get('id') == SUPPORT_ID, 'fixture_actor_changed')
        queue = get('/admin/listing-review/queue?review_status=submitted&per_page=50', support.token)
        fixtures_in_queue = {row['id']: row for row in queue if row['id'] in FIXTURES}
        for listing_id, (_, _, source, reason, previous) in FIXTURES.items():
            require(listing_id in fixtures_in_queue, 'fixture_missing_from_review_queue')
            check(fixtures_in_queue[listing_id], listing_id)
            detail = get(f'/admin/listing-review/listings/{listing_id}', support.token)
            check(detail, listing_id)
            candidates = detail['likely_duplicate_candidates']
            require([row['listing_id'] for row in candidates] == ([previous] if previous else []),
                    'comparison_candidate_changed')
            if candidates:
                require(candidates[0]['duplicate_detection_source'] == source and candidates[0]['published'] is True,
                        'candidate_marker_or_publication_changed')
            if source == 'ai':
                require(any(row['id'] == 279 and row['action'] == 'duplicate_ai_assessed'
                            and 'محاكية' in row['reason'] for row in detail['review_history']),
                        'explicit_simulation_history_missing')
            receipt['fixtures'][listing_id] = {'source': source, 'reason': reason, 'previous_id': previous}
        receipt['status'] = 'PASS'
    except CheckFailed as error:
        receipt['error'] = str(error)
    except Exception as error:
        receipt['error_type'] = type(error).__name__
    finally:
        if support is not None:
            try:
                receipt['support_logout'] = support.close() is True
            except Exception:
                receipt['support_logout'] = False
            if not receipt['support_logout']:
                receipt['status'] = 'VERIFY_AUTH_SESSION_CLEANUP'
        print('AQER_STEP6_REVIEW_READBACK ' + json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return int(receipt['status'] != 'PASS')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except CheckFailed as error:
        raise SystemExit(str(error)) from None
