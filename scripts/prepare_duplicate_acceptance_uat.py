#!/usr/bin/env python3
"""Prepare only the five named Frankfurt UAT handset acceptance listings."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from time import sleep

from verify_duplicate_review_uat import (
    API, BROKER_ID, CheckFailed, Journey, REPOSITORY, SERVICE, SUPPORT_ID,
    require, validate_receipt,
)
import verify_duplicate_review_uat as earlier


ACCEPTANCE_BRANCH = 'refs/heads/work/uat-duplicate-acceptance-fixtures-20261120'


def make_journeys(receipt, plan, root, run_id, http, no_redirect):
    marker = f'AQER-UAT-S6-{run_id}'
    suites = []
    labels = [
        {'original': 'شقة ٧ السابقة', 'distinct': 'شقة ٨ المختلفة', 'duplicate': 'نسخة شقة ٧، تشابه النظام'},
        {'original': 'الفيلا السابقة', 'ambiguous': 'فيلا لإشارة المساعد المحاكية'},
    ]
    for index, key in enumerate(('apartment', 'villa')):
        case = plan[key]
        require(Path(case['photo_file']).name == case['photo_file'], 'unknown_fixture_photo_path')
        photo = (root / 'scripts' / case['photo_file']).read_bytes()
        _, *pin = validate_receipt(plan | case, photo)
        journey = Journey(receipt, photo, pin, http, no_redirect, exercise_ai=index == 1)
        journey.marker = marker + ('-APT' if index == 0 else '-VILLA')
        journey.titles = {k: f'اختبار ٦: {label} | {journey.marker}' for k, label in labels[index].items()}
        suites.append(journey)
    require(suites[0].pin != suites[1].pin, 'identical_fixture_pins')
    receipt['fixture_marker'] = marker
    return suites


def keep_for_owner(apartment, villa):
    previous, photo = apartment.create('original', 7)
    apartment.submit('original', 'distinct')
    apartment.approve('original', photo)

    distinct, _ = apartment.create('distinct', 8)
    detail = apartment.submit('distinct', 'distinct')
    require(detail['likely_duplicate_candidates'] == [] and detail.get('duplicate_detection_source') is None,
            'different_units_in_same_building_matched')

    duplicate, _ = apartment.create('duplicate', 7)
    detail = apartment.submit('duplicate', 'confirmed_duplicate')
    candidates = detail['likely_duplicate_candidates']
    require(detail['duplicate_detection_source'] == 'algorithm' and bool(detail['duplicate_detection_reason'])
            and [row['listing_id'] for row in candidates] == [previous]
            and 'same_building_same_unit' in candidates[0]['signals'], 'algorithm_indicator_unavailable')

    villa_previous, photo = villa.create('original')
    villa.submit('original', 'distinct')
    villa.approve('original', photo)
    villa_target, _ = villa.create('ambiguous')
    detail = villa.submit('ambiguous', 'possible_duplicate', villa.own('original')['property_asset_id'])
    for attempt in range(10):
        if any(row['action'] == 'duplicate_ai_assessed' for row in detail['review_history']):
            break
        sleep(4)
        detail = villa.review('ambiguous')
    else:
        raise CheckFailed('actual_ai_assessment_event_not_ready')
    require([row['listing_id'] for row in detail['likely_duplicate_candidates']] == [villa_previous]
            and detail.get('duplicate_detection_source') in (None, 'ai'), 'unexpected_villa_comparison')
    require(detail['review_status'] == 'submitted', 'fixture_review_status_changed')
    natural_source = detail.get('duplicate_detection_source')

    for journey, key in ((apartment, 'distinct'), (apartment, 'duplicate'), (villa, 'ambiguous')):
        require(journey.own(key)['review_status'] == 'submitted', 'fixture_not_waiting_for_handset')
        journey.request(None, 'GET', f'/properties/{journey.record[key]}', expected=404)

    return {
        'apartment_previous': previous, 'apartment_distinct': distinct, 'apartment_duplicate': duplicate,
        'villa_previous': villa_previous, 'villa_advisory': villa_target,
        'villa_natural_source': natural_source,
        'villa_comparison_signals': detail['likely_duplicate_candidates'][0]['signals'],
        'villa_comparison_events': [
            {'id': row['id'], 'action': row['action']} for row in detail['review_history']
            if row['action'] in ('submitted', 'duplicate_ai_assessment_started', 'duplicate_ai_assessed')
        ],
    }


def reconcile_cleanup(journeys):
    """Combine exact titles and attempted writes into one guarded cleanup/login lifecycle."""
    apartment, villa = journeys
    apartment.titles.update({f'villa_{k}': v for k, v in villa.titles.items()})
    apartment.record.update({f'villa_{k}': v for k, v in villa.record.items()})
    apartment.attempts.update(f'villa_{k}' for k in villa.attempts)
    return apartment.clean_up()


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--receipt', type=Path, required=True)
    args = cli.parse_args()
    env = os.environ
    run_id = env.get('GITHUB_RUN_ID', '')
    require(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_REPOSITORY') == REPOSITORY
            and env.get('GITHUB_REF') == ACCEPTANCE_BRANCH and env.get('GITHUB_EVENT_NAME') == 'push'
            and env.get('GITHUB_RUN_ATTEMPT') == '1' and run_id.isdigit(), 'uat_context_refused')
    root = Path(env['GITHUB_WORKSPACE'])
    plan = json.loads(args.receipt.read_bytes())
    require(plan['service_id'] == SERVICE and plan['retain_until_handset_acceptance'] is True,
            'missing_named_fixture_scope')
    commit = plan['commit']
    require(re.fullmatch('[a-f0-9]{40}', commit), 'invalid_deployed_source')
    tree = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD:backend-api-runtime'], text=True).strip()
    require(tree == plan['backend_tree'], 'action_backend_tree_changed')
    earlier.SOURCE = commit

    from phase1_native_account_readiness import SECRET_NAME, validate_access
    from phase23_preflight import API as documented_api, NoRedirect, http
    from run_phase23_native import Session

    require(documented_api == API, 'different_fixture_api')
    receipt = {'run_id': run_id, 'target_commit': commit, 'render_deploy': plan['deploy_id'], 'status': 'FAILED'}
    journeys = make_journeys(receipt, plan, root, run_id, http, NoRedirect)
    apartment, villa = journeys
    broker = support = None
    try:
        health = apartment.request(None, 'GET', '/health')
        require(health.get('status') == 'ok' and health.get('database') is True and health.get('postgis') is True,
                'uat_health_not_ready')
        apartment.request(None, 'POST', '/admin/listing-review/listings/9223372036854775807/reject-duplicate',
                          expected=401, body={})
        access = validate_access(env.pop(SECRET_NAME, ''))
        broker, support = Session('broker', access), Session('support', access)
        apartment.broker = villa.broker = broker
        apartment.support = villa.support = support
        broker.login()
        support.login()
        require(broker.identity.get('id') == BROKER_ID and broker.identity.get('account_type') == 'broker'
                and support.identity.get('id') == SUPPORT_ID, 'fixture_actor_changed')
        policy = apartment.request(broker, 'GET', '/listing-access')
        require(policy.get('can_create') is True and policy.get('mode') == 'professional', 'fixture_broker_unavailable')
        apartment.reconcile()
        villa.reconcile()
        receipt['fixtures'] = keep_for_owner(apartment, villa)
        receipt['status'] = 'READY_FOR_BADGE_VERIFICATION'
    except CheckFailed as error:
        receipt['error'] = str(error)
    except Exception as error:
        receipt['error_type'] = type(error).__name__
    finally:
        if receipt['status'] == 'READY_FOR_BADGE_VERIFICATION':
            for alias, session in (('support', support), ('broker', broker)):
                try:
                    receipt[alias + '_logout'] = session.close() is True
                except Exception:
                    receipt[alias + '_logout'] = False
            if not receipt['broker_logout'] or not receipt['support_logout']:
                receipt['status'] = 'VERIFY_AUTH_SESSION_CLEANUP'
        elif not reconcile_cleanup(journeys):
            receipt['status'] = 'FIXTURE_CLEANUP_REQUIRED'
        print('AQER_STEP6_FIXTURES ' + json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return int(receipt['status'] != 'READY_FOR_BADGE_VERIFICATION')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except CheckFailed as error:
        raise SystemExit(str(error)) from None
