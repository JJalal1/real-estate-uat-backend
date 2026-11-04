#!/usr/bin/env python3
"""Title-only native-fixture setup/cleanup through normal owner UAT APIs.

No work occurs on import or construction. Credentials/tokens stay in memory and
are never read from workspace files, written to state, or installed into the app.
"""
import datetime
import hashlib
import json
import re
import time
import urllib.error
import urllib.request
import uuid

from phase1_native_account_readiness import PHONE_PATTERN

API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'


class FixtureError(RuntimeError):
    """Fixed diagnostics only; never include request/response/credential text."""


Failed = FixtureError


def require(condition, code):
    if not condition:
        raise FixtureError(code)


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def summary(rows):
    return {kind: {'count': len(values), 'sha256': digest(values)}
            for kind, values in rows.items()}


def protected_check(before, after):
    return {kind: {'all_preexisting_present': all(key in after[kind] for key in old),
                   'all_preexisting_unchanged': all(after[kind].get(key) == value
                                                  for key, value in old.items())}
            for kind, old in before.items()}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_public_reference(transport=None):
    """One bounded current public reference GET; never authenticates or archives a feed."""
    path = '/properties?per_page=24&sort=latest&_phase1=' + uuid.uuid4().hex
    try:
        if transport is not None:
            code, value, _ = transport('GET', path, None, None)
        else:
            request = urllib.request.Request(API + path, method='GET', headers={
                'Accept': 'application/json', 'User-Agent': 'AQER-Phase1-Public-Native-Reference'})
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=45) as response:
                code, raw = response.status, response.read(2_000_001)
            require(len(raw) <= 2_000_000, 'public_reference_response_size_bound')
            value = json.loads(raw)
        require(code == 200 and isinstance(value, dict), 'public_reference_http_or_shape')
        rows = value.get('data')
        require(isinstance(rows, list) and 0 < len(rows) <= 50, 'public_reference_empty_or_unbounded')
        references = []
        seen = set()
        for row in rows:
            require(isinstance(row, dict) and isinstance(row.get('id'), int)
                    and not isinstance(row['id'], bool) and row['id'] > 0
                    and row['id'] not in seen, 'public_reference_identity_shape')
            title = row.get('title')
            require(isinstance(title, str) and 0 < len(title.strip()) <= 200
                    and '\n' not in title and '\r' not in title
                    and row.get('status', 'published') == 'published',
                    'public_reference_published_title_required')
            seen.add(row['id'])
            references.append({'id': row['id'], 'title': title.strip()})
        return references
    except FixtureError:
        raise
    except Exception:
        raise FixtureError('public_reference_transport_or_response_failed') from None


def new_fixture_tag():
    # Keep synthetic identifiers distinguishable under the unchanged OTP-safe
    # accessibility label redactor, which hides standalone six-digit runs.
    for _ in range(8):
        suffix = uuid.uuid4().hex[:12]
        if not re.search(r'[0-9]{6}', suffix):
            return 'AQER-C1-' + suffix
    raise FixtureError('unambiguous_synthetic_tag_unavailable')


class FixtureApi:
    def __init__(self, phone, otp, run_id, transport=None, expected_actor_id=28):
        require(isinstance(phone, str) and re.fullmatch(PHONE_PATTERN, phone.strip()),
                'fixture_phone_shape_invalid')
        require(isinstance(otp, str) and re.fullmatch(r'[0-9]{6}', otp),
                'fixture_otp_shape_invalid')
        require(isinstance(run_id, str) and re.fullmatch(r'[1-9][0-9]{0,19}', run_id),
                'fixture_run_identity_invalid')
        require(expected_actor_id == 28, 'expected_fixture_broker_required')
        self._phone, self._otp = phone.strip(), otp
        self._private_values = {phone, phone.strip(), phone.strip().lstrip('+'), otp}
        self._active_token = None
        self._transport = transport
        self.actor_id, self.run_id = expected_actor_id, run_id
        self.state = None
        self._attempt_identity = None
        self._baseline_digest = None
        self.last_receipt = None

    @property
    def has_pending_fixture(self):
        return bool(self.state and self.state.get('creation_request_sent') is True
                    and self.state.get('removed_confirmed') is not True)

    def _call(self, method, path, body=None, token=None):
        require(method in {'GET', 'POST', 'PUT', 'DELETE'} and isinstance(path, str)
                and path.startswith('/') and not path.startswith('//') and '\\' not in path,
                'fixture_relative_api_request_required')
        if self._transport is not None:
            return self._transport(method, path, body, token)
        headers = {'Accept': 'application/json', 'User-Agent': 'AQER-Phase1-Own-Native-Fixture'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        data = None
        if body is not None:
            headers['Content-Type'] = 'application/json'
            data = json.dumps(body, ensure_ascii=False).encode()
        started = time.monotonic()
        try:
            opener = urllib.request.build_opener(NoRedirect())
            request = urllib.request.Request(API + path, data=data, headers=headers, method=method)
            try:
                with opener.open(request, timeout=60) as response:
                    code, raw = response.status, response.read(2_000_001)
            except urllib.error.HTTPError as error:
                code, raw = error.code, error.read(2_000_001)
            require(len(raw) <= 2_000_000, 'fixture_response_size_bound')
            value = json.loads(raw)
            require(isinstance(value, dict), 'fixture_response_shape_invalid')
            return code, value, round((time.monotonic() - started) * 1000)
        except FixtureError:
            raise
        except Exception:
            raise FixtureError('fixture_transport_or_response_failed') from None

    def _login(self, receipt):
        code, _, elapsed = self._call('POST', '/auth/whatsapp/start',
                                      {'phone': self._phone, 'intent': 'login'})
        receipt['normal_login_start'] = {'http': code, 'elapsed_ms': elapsed}
        require(code == 200, 'fixture_normal_login_start_failed')
        code, value, elapsed = self._call('POST', '/auth/whatsapp/verify',
                                          {'phone': self._phone, 'code': self._otp})
        receipt['normal_login_verify'] = {'http': code, 'elapsed_ms': elapsed}
        data = value.get('data')
        token = data.get('token') if isinstance(data, dict) else None
        if isinstance(token, str) and token:
            # Capture before checking HTTP status so an unusual response cannot
            # skip the finally logout of a token that may have been issued.
            self._active_token = token
            self._private_values.add(token)
        require(code == 200 and self._active_token, 'fixture_normal_login_verify_failed')
        code, value, _ = self._call('GET', '/auth/me', token=self._active_token)
        data = value.get('data')
        user = data.get('user', {}) if isinstance(data, dict) else {}
        receipt['identity'] = {'http': code, 'actor_id': user.get('id'),
                               'account_type': user.get('account_type')}
        require(code == 200 and user.get('id') == self.actor_id
                and user.get('account_type') == 'broker', 'fixture_expected_actor_required')

    def _logout(self, receipt):
        token = self._active_token
        if not token:
            return True
        passed = True
        try:
            try:
                code, _, _ = self._call('POST', '/auth/logout', {}, token=token)
                receipt['logout_http'] = code
                passed = code == 200
            except Exception:
                receipt['logout_request_failed'] = True
                passed = False
            try:
                code, _, _ = self._call('GET', '/auth/me', token=token)
                receipt['revoked_token_http'] = code
                passed = passed and code == 401
            except Exception:
                receipt['revocation_check_failed'] = True
                passed = False
        finally:
            self._active_token = None
        receipt['fresh_session_cleaned'] = passed
        return passed

    def _snapshot(self):
        result = {}
        for kind, route in [('properties', '/properties/mine/list'), ('drafts', '/listing-editor-drafts')]:
            rows, page = {}, 1
            while True:
                code, value, _ = self._call('GET', route + '?per_page=50&page=' + str(page)
                                            + '&_phase1=' + uuid.uuid4().hex, token=self._active_token)
                require(code == 200, 'fixture_' + kind + '_snapshot_failed')
                data = value.get('data')
                require(isinstance(data, list), 'fixture_' + kind + '_snapshot_shape')
                for item in data:
                    require(isinstance(item, dict), 'fixture_' + kind + '_row_shape')
                    if kind == 'drafts':
                        key = item.get('key')
                        row = {name: item.get(name) for name in
                               ['key', 'property_id', 'revision', 'updated_at', 'payload']}
                        row['image_keys'] = sorted(str(image.get('key')) for image in item.get('images', []))
                    else:
                        identity = item.get('id')
                        require(isinstance(identity, int) and identity > 0, 'fixture_property_identity_shape')
                        key = str(identity)
                        row = {name: item.get(name) for name in [
                            'id', 'updated_at', 'status', 'review_status', 'type', 'purpose', 'title',
                            'description', 'price', 'monthly_rent', 'currency', 'bedrooms', 'bathrooms',
                            'governorate', 'district', 'street', 'latitude', 'longitude', 'building_reference',
                            'property_asset_id', 'floor_number', 'unit_number', 'building_facade',
                            'has_parking', 'rental_conditions', 'last_review_reason']}
                        row['image_ids'] = sorted(str(image.get('id')) for image in item.get('images', []))
                    require(isinstance(key, str) and key and key not in rows,
                            'fixture_' + kind + '_row_identity')
                    rows[key] = digest(row)
                last = value.get('meta', {}).get('last_page', 1)
                require(isinstance(last, int) and 1 <= last <= 20 and page <= last,
                        'fixture_' + kind + '_page_bound')
                if page == last:
                    break
                page += 1
            result[kind] = rows
        return result

    def _known_state(self):
        state = self.state
        require(isinstance(state, dict) and state.get('schema') == 1
                and state.get('actor_id') == self.actor_id and state.get('run_id') == self.run_id
                and state.get('creation_request_sent') is True,
                'known_owner_fixture_state_required')
        key = state.get('key')
        try:
            canonical = str(uuid.UUID(key))
        except (ValueError, TypeError, AttributeError):
            raise FixtureError('new_owned_uuid_required') from None
        baseline = state.get('baseline')
        require(canonical == key and isinstance(baseline, dict)
                and set(baseline) == {'properties', 'drafts'}
                and isinstance(baseline['drafts'], dict) and isinstance(baseline['properties'], dict)
                and key not in baseline['drafts'], 'new_owned_uuid_required')
        require(isinstance(state.get('tag'), str) and re.fullmatch(r'AQER-C1-[a-f0-9]{12}', state['tag']),
                'known_fixture_tag_required')
        require(self._attempt_identity == (key, state['tag'], state.get('title'), self.run_id)
                and self._baseline_digest == digest(baseline), 'known_fixture_identity_mismatch')
        return state

    def _own_show(self):
        state = self._known_state()
        code, value, _ = self._call('GET', '/listing-editor-drafts/' + state['key']
                                    + '?_phase1=' + uuid.uuid4().hex, token=self._active_token)
        if code == 404:
            return code, None
        require(code == 200, 'own_fixture_read_failed')
        draft = value.get('data')
        require(isinstance(draft, dict) and draft.get('key') == state['key']
                and 'property_id' in draft and draft['property_id'] is None,
                'only_unpromoted_own_fixture_allowed')
        payload = draft.get('payload')
        fields = payload.get('fields') if isinstance(payload, dict) else None
        require(isinstance(fields, dict) and state['tag'] in str(fields.get('title', '')),
                'own_fixture_tag_required')
        require(payload.get('server_property_id') is None and draft.get('server_property_id') is None
                and not payload.get('promoted_image_keys'), 'only_unpromoted_own_fixture_allowed')
        return code, draft

    def _receipt(self, mode):
        return {'scope': 'normal-owner title-only API setup/cleanup; native UI actions are separate',
                'mode': mode, 'api': API, 'actor_id': self.actor_id,
                'status': 'BLOCKED', 'native_journey_executed': False,
                'property_create_requested': False, 'image_upload_requested': False,
                'financial_acceptance_requested': False, 'submission_requested': False,
                'credentials_persisted': False,
                'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}

    def _finish(self, receipt, failure):
        if not self._logout(receipt):
            receipt['status'] = 'BLOCKED'
            receipt['session_cleanup_unproven'] = True
            failure = failure or 'fixture_session_cleanup_unproven'
        if failure:
            receipt['status'] = 'BLOCKED'
            receipt['reason'] = failure
        receipt['ended_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        serialized = json.dumps(receipt, ensure_ascii=False)
        require(not any(value and value in serialized for value in self._private_values),
                'private_value_in_fixture_receipt_refused')
        self.last_receipt = receipt
        if failure:
            raise FixtureError(failure)
        return receipt

    def bootstrap(self):
        require(self.state is None, 'existing_fixture_state_protected')
        receipt, failure = self._receipt('bootstrap'), None
        try:
            self._login(receipt)
            baseline = self._snapshot()
            key, tag = str(uuid.uuid4()), new_fixture_tag()
            title = 'مسودة اختبار الواجهة ' + tag
            require(key not in baseline['drafts'], 'new_owned_uuid_required')
            code, _, _ = self._call('GET', '/listing-editor-drafts/' + key, token=self._active_token)
            require(code == 404, 'new_uuid_absent_before_setup_required')
            self.state = {'schema': 1, 'actor_id': self.actor_id, 'run_id': self.run_id,
                          'key': key, 'tag': tag, 'title': title, 'baseline': baseline,
                          'creation_request_sent': True, 'bootstrap_only_title_label': True}
            self._attempt_identity = (key, tag, title, self.run_id)
            self._baseline_digest = digest(baseline)
            payload = {'draft_kind': 'saved', 'entry_method': 'manual', 'editor_version': 10,
                       'media_version': 1, 'step': 0, 'type_confirmed': False,
                       'purpose_confirmed': False, 'image_order': [], 'fields': {'title': title}}
            code, value, elapsed = self._call('PUT', '/listing-editor-drafts/' + key,
                                             {'expected_revision': 0, 'payload': payload}, self._active_token)
            receipt['bootstrap'] = {'http': code, 'elapsed_ms': elapsed}
            require(code == 200, 'empty_fixture_setup_failed')
            draft = value.get('data')
            require(isinstance(draft, dict) and draft.get('key') == key
                    and 'property_id' in draft and draft['property_id'] is None
                    and isinstance(draft.get('images'), list) and not draft['images'],
                    'empty_unpromoted_fixture_required')
            returned = draft.get('payload')
            require(isinstance(returned, dict) and returned.get('fields') == {'title': title},
                    'bootstrap_must_not_fill_facts')
            # Allow only the metadata we requested and the cleaner's documented
            # false same-floor default. Every other non-null value would be an
            # API-filled fact/term, even when a future key is not known here.
            metadata = {name: entry for name, entry in payload.items() if name != 'fields'}
            for name, entry in returned.items():
                if name == 'fields':
                    continue
                if name in metadata:
                    require(entry == metadata[name], 'bootstrap_metadata_mismatch')
                elif name == 'same_floor_units':
                    require(entry is False, 'bootstrap_must_not_fill_facts')
                else:
                    require(entry is None, 'bootstrap_must_not_fill_facts')
            self.state['created_confirmed'] = True
            self.state['initial_revision'] = draft.get('revision')
            after = self._snapshot()
            protected = protected_check(baseline, after)
            receipt.update(fixture_key=key, fixture_title=title,
                           bootstrap_fields=['synthetic_title_label_only'],
                           before=summary(baseline), after=summary(after), protected=protected,
                           fixture_created=True)
            require(set(after['drafts']) == set(baseline['drafts']) | {key}
                    and after['properties'] == baseline['properties']
                    and all(item['all_preexisting_unchanged'] for item in protected.values()),
                    'protected_state_observation_inconclusive')
            receipt['status'] = 'PASS'
        except FixtureError as error:
            failure = str(error)
        except Exception:
            failure = 'fixture_transport_or_runtime_failed'
        finally:
            result = self._finish(receipt, failure)
        return result

    def cleanup(self):
        # Refuse unknown or preexisting IDs before any HTTP/authentication call.
        self._known_state()
        receipt, failure = self._receipt('cleanup'), None
        try:
            self._login(receipt)
            before = self._snapshot()
            receipt['before'] = summary(before)
            receipt['protected_before'] = protected_check(self.state['baseline'], before)
            code, _ = self._own_show()
            receipt['own_draft_http'] = code
            if code == 200:
                code, _, elapsed = self._call('DELETE', '/listing-editor-drafts/' + self.state['key'],
                                             token=self._active_token)
                receipt['delete_own_fixture'] = {'http': code, 'elapsed_ms': elapsed}
                require(code == 200, 'own_fixture_delete_failed')
            code, _, _ = self._call('GET', '/listing-editor-drafts/' + self.state['key']
                                    + '?_phase1=' + uuid.uuid4().hex, token=self._active_token)
            receipt['removed_fixture_check'] = {'http': code}
            require(code == 404, 'own_fixture_not_removed')
            self.state['removed_confirmed'] = True
            after = self._snapshot()
            receipt.update(after=summary(after), fixture_removed=True,
                           protected_after=protected_check(self.state['baseline'], after))
            require(after == self.state['baseline'], 'protected_state_observation_inconclusive')
            receipt['status'] = 'PASS'
        except FixtureError as error:
            failure = str(error)
        except Exception:
            failure = 'fixture_transport_or_runtime_failed'
        finally:
            result = self._finish(receipt, failure)
        return result

    def clear_credentials(self):
        require(self._active_token is None, 'active_fixture_session_must_be_closed')
        self._phone = self._otp = ''
        self._private_values.clear()
