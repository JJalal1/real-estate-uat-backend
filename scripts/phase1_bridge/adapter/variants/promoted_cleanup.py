"""Fail-closed cleanup of one promoted native Phase1 test fixture.

This module has no HTTP client, authentication or file I/O. The parent supplies
an already authenticated normal API callable and owns logout/revocation. Import
and construction perform no API calls. Reuse this object after pinning; never
reconstruct it to retry a mutation with uncertain outcome.

Property DELETE has no atomic revision precondition. Native writers must already
be stopped; fresh identity/state checks narrow, but do not eliminate, that race.
Storage deletion is best effort. Immutable Sai/audit/review/support history may
remain; successful cleanup means the known application rows/routes are removed.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import uuid
from typing import Callable


ACTOR = 28
BASELINE_COUNTS = {"properties": 25, "drafts": 7}
API = Callable[[str, str], tuple[int, dict]]


class GuardError(Exception):
    """A fixed diagnostic label, never an API response or arbitrary exception."""


class ApiCallError(Exception):
    """Only the exception class from the parent adapter, never its message."""


def require(condition: bool, label: str) -> None:
    if not condition:
        raise GuardError(label)


def digest(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def positive_id(value: object) -> bool:
    return type(value) is int and 0 < value <= 9223372036854775807


def canonical_uuid(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return str(uuid.UUID(value)) == value
    except (ValueError, AttributeError):
        return False


def draft_projection(row: dict) -> dict:
    result = {key: row.get(key) for key in
              ("key", "property_id", "revision", "updated_at", "payload")}
    result["image_keys"] = sorted(str(image.get("key"))
                                  for image in row.get("images", []))
    return result


def property_projection(row: dict) -> dict:
    # Identical stable projection to the original bootstrap helper; no signed
    # URLs or generated URL expiry values enter the protected-state hashes.
    keys = ("id", "updated_at", "status", "review_status", "type", "purpose",
            "title", "description", "price", "monthly_rent", "currency",
            "bedrooms", "bathrooms", "governorate", "district", "street",
            "latitude", "longitude", "building_reference", "property_asset_id",
            "floor_number", "unit_number", "building_facade", "has_parking",
            "rental_conditions", "last_review_reason")
    result = {key: row.get(key) for key in keys}
    result["image_ids"] = sorted(str(image.get("id"))
                                 for image in row.get("images", []))
    return result


class PromotedFixtureCleanup:
    def __init__(self, api: API, bootstrap_record: dict):
        # Deep copy before validation so caller mutation cannot substitute the
        # baseline, key or tag after construction. No public mutable fence.
        state = copy.deepcopy(bootstrap_record)
        require(callable(api), "api_callable_required")
        require(state.get("actor_id") == ACTOR and
                state.get("creation_request_sent") is True and
                state.get("created_confirmed") is True and
                state.get("bootstrap_only_title_label") is True,
                "original_confirmed_bootstrap_required")
        key, tag = state.get("key"), state.get("tag")
        require(canonical_uuid(key), "original_uuid_required")
        require(isinstance(tag, str) and
                re.fullmatch(r"AQER-C[124]-[a-f0-9]{12}", tag) is not None,
                "original_unique_tag_required")
        baseline = state.get("baseline")
        require(isinstance(baseline, dict) and
                set(baseline) == set(BASELINE_COUNTS), "original_baseline_required")
        for kind, count in BASELINE_COUNTS.items():
            rows = baseline[kind]
            require(isinstance(rows, dict) and len(rows) == count,
                    "original_baseline_counts_required")
            require(all(isinstance(identity, str) and identity and
                        isinstance(value, str) and
                        re.fullmatch(r"[a-f0-9]{64}", value)
                        for identity, value in rows.items()),
                    "original_baseline_digests_required")
            require(all(canonical_uuid(identity) if kind == "drafts" else
                        re.fullmatch(r"[1-9][0-9]{0,18}", identity) is not None and
                        positive_id(int(identity)) for identity in rows),
                    "original_baseline_identity_shape")
        require(key not in baseline["drafts"], "original_uuid_was_preexisting")
        self.__api = api
        self.__key, self.__tag = key, tag
        self.__baseline = baseline
        self.__baseline_digest = digest(baseline)
        self.__candidate: int | None = None
        self.__pinned_pair: dict | None = None
        self.__attempted = False

    def _call(self, method: str, path: str) -> tuple[int, dict]:
        # Destinations and all mutations are constructed internally. The parent
        # API adapter must preserve normal auth, same UAT origin and default TLS.
        try:
            response = self.__api(method, path)
        except Exception as error:
            raise ApiCallError(type(error).__name__) from None
        require(isinstance(response, tuple) and len(response) == 2,
                "api_adapter_shape")
        status, value = response
        require(type(status) is int and isinstance(value, dict),
                "api_response_shape")
        return status, value

    def _identity(self) -> None:
        code, body = self._call("GET", "/auth/me")
        user = body.get("data", {}).get("user", {})
        require(code == 200 and user.get("id") == ACTOR and
                user.get("account_type") == "broker", "expected_normal_actor_required")

    def _has_tag(self, title: object) -> bool:
        return isinstance(title, str) and re.search(
            r"(?<![A-Za-z0-9-])" + re.escape(self.__tag) +
            r"(?![A-Za-z0-9-])", title) is not None

    def _draft(self) -> dict:
        code, body = self._call("GET", "/listing-editor-drafts/" + self.__key)
        row = body.get("data")
        require(code == 200 and isinstance(row, dict), "original_draft_read_required")
        require(row.get("key") == self.__key and
                self._has_tag(row.get("payload", {}).get("fields", {}).get("title")),
                "original_draft_identity_required")
        require(type(row.get("revision")) is int and row["revision"] >= 1 and
                isinstance(row.get("images"), list), "original_draft_shape_required")
        return row

    def _snapshot(self) -> tuple[dict, dict, dict]:
        result, property_rows, draft_rows = {}, {}, {}
        for kind, route in (("properties", "/properties/mine/list"),
                            ("drafts", "/listing-editor-drafts")):
            rows = {}
            for page in range(1, 21):
                code, body = self._call("GET", route +
                                       "?per_page=50&page=" + str(page))
                data = body.get("data")
                require(code == 200 and isinstance(data, list),
                        "protected_snapshot_read_required")
                for item in data:
                    require(isinstance(item, dict), "protected_snapshot_row_shape")
                    if kind == "properties":
                        require(positive_id(item.get("id")), "property_identity_shape")
                        key = str(item["id"])
                        projection = property_projection(item)
                        property_rows[key] = item
                    else:
                        key = item.get("key")
                        require(canonical_uuid(key), "draft_identity_shape")
                        projection = draft_projection(item)
                        draft_rows[key] = item
                    require(isinstance(key, str) and key and key not in rows,
                            "protected_snapshot_identity_shape")
                    rows[key] = digest(projection)
                last = body.get("meta", {}).get("last_page", 1)
                require(type(last) is int and 1 <= last <= 20,
                        "protected_snapshot_page_bound")
                if page >= last:
                    break
            result[kind] = rows
        return result, property_rows, draft_rows

    def _protected(self, snapshot: dict, *, property_present: bool,
                   draft_present: bool) -> None:
        for kind, baseline in self.__baseline.items():
            require(all(snapshot[kind].get(key) == value
                        for key, value in baseline.items()),
                    "preexisting_state_changed")
            own = ({str(self.__candidate)} if kind == "properties" and property_present
                   else {self.__key} if kind == "drafts" and draft_present else set())
            require(set(snapshot[kind]) == set(baseline) | own,
                    "unknown_extra_or_missing_state")

    def _pair(self) -> dict:
        draft = self._draft()
        candidate = draft.get("property_id")
        require(positive_id(candidate) and
                str(candidate) not in self.__baseline["properties"],
                "new_promoted_property_required")
        if self.__candidate is not None:
            require(candidate == self.__candidate, "pinned_property_substitution_refused")
        # Candidate may be assigned temporarily only to validate exact extras.
        old_candidate = self.__candidate
        self.__candidate = candidate
        try:
            snapshot, mine, drafts = self._snapshot()
            self._protected(snapshot, property_present=True, draft_present=True)
            require(snapshot["drafts"][self.__key] == digest(draft_projection(draft)),
                    "draft_changed_during_preflight")
            code, body = self._call("GET", "/properties/" + str(candidate))
            detail, owned = body.get("data"), mine.get(str(candidate))
            require(code == 200 and isinstance(detail, dict) and isinstance(owned, dict),
                    "new_property_read_required")
            require(owned.get("is_owner") is True and
                    detail.get("advertiser", {}).get("id") == ACTOR and
                    detail.get("id") == candidate, "new_property_ownership_required")
            title = draft["payload"]["fields"]["title"]
            require(owned.get("title") == title and detail.get("title") == title and
                    self._has_tag(title), "new_property_tag_mismatch")
            for row in (owned, detail):
                require(row.get("status") == "draft" and row.get("review_status") in
                        ("draft", "returned_for_correction"),
                        "new_property_not_deletable")
            require(owned.get("review_status") == detail.get("review_status"),
                    "property_changed_during_preflight")
            require(all(owned.get(key) == detail.get(key)
                        for key in ("type", "purpose", "floor_number", "unit_number")),
                    "property_changed_during_preflight")
            images = owned.get("images")
            require(isinstance(images, list) and len(images) <= 12 and
                    all(isinstance(image, dict) and positive_id(image.get("id"))
                        for image in images), "new_property_images_shape")
            return {"draft": draft_projection(draft),
                    "property": property_projection(owned),
                    "image_ids": tuple(sorted(image["id"] for image in images))}
        except Exception:
            self.__candidate = old_candidate
            raise

    def _receipt(self) -> dict:
        return {"scope": "normal-owner promoted native test fixture cleanup only",
                "status": "BLOCKED", "actor_id": ACTOR,
                "fixture_key": self.__key, "fixture_tag": self.__tag,
                "baseline_sha256": self.__baseline_digest,
                "baseline_counts": dict(BASELINE_COUNTS),
                "property_id": self.__candidate,
                "property_delete_requested": False,
                "draft_delete_requested": False,
                "known_application_rows_removed": False,
                "protected_baseline_restored": False,
                "known_property_media_routes_404": False,
                "native_acceptance_claimed": False,
                "atomic_revision_guard": False,
                "cloud_object_deletion_independently_verified": False,
                "immutable_audit_sai_review_support_history_may_remain": True,
                "parent_owns_api_logout_and_revocation": True}

    @staticmethod
    def _failure(receipt: dict, error: Exception) -> dict:
        receipt["reason"] = (str(error) if isinstance(error, GuardError) else
                             "transport_or_runtime_" + str(error)
                             if isinstance(error, ApiCallError) else
                             "transport_or_runtime_" + type(error).__name__)
        return receipt

    def pin_candidate(self, *, native_writers_stopped: bool) -> dict:
        receipt = self._receipt()
        try:
            require(native_writers_stopped is True, "native_writers_not_stopped")
            require(not self.__attempted and self.__pinned_pair is None,
                    "candidate_already_pinned_or_attempted")
            self._identity()
            pair = self._pair()
            self.__pinned_pair = copy.deepcopy(pair)
            receipt.update(status="READY", property_id=self.__candidate,
                           image_count=len(pair["image_ids"]))
        except Exception as error:
            self._failure(receipt, error)
        return receipt

    def cleanup(self, *, native_writers_stopped: bool) -> dict:
        receipt = self._receipt()
        try:
            require(native_writers_stopped is True, "native_writers_not_stopped")
            require(not self.__attempted, "cleanup_attempt_already_consumed")
            require(self.__candidate is not None and self.__pinned_pair is not None,
                    "candidate_pin_required")
            self.__attempted = True
            self._identity()
            fresh = self._pair()
            require(fresh == self.__pinned_pair, "pinned_fixture_changed")
            # One more fresh pair immediately before the destructive request.
            require(self._pair() == fresh, "fixture_changed_before_delete")
            receipt["property_delete_requested"] = True
            code, _ = self._call("DELETE", "/properties/" + str(self.__candidate))
            receipt["property_delete_http"] = code
            require(code == 200, "property_delete_not_confirmed")
            code, _ = self._call("GET", "/properties/" + str(self.__candidate))
            receipt["property_readback_http"] = code
            require(code == 404, "property_absence_not_confirmed")
            # FK nullOnDelete changes only the linked property_id. The same tag,
            # revision and payload must remain; never delete a substituted draft.
            draft = self._draft()
            expected = copy.deepcopy(fresh["draft"])
            expected["property_id"] = None
            require(draft_projection(draft) == expected,
                    "unlinked_draft_changed_after_property_delete")
            snapshot, _, _ = self._snapshot()
            self._protected(snapshot, property_present=False, draft_present=True)
            require(snapshot["drafts"][self.__key] == digest(expected),
                    "unlinked_draft_changed_before_delete")
            receipt["draft_delete_requested"] = True
            code, _ = self._call("DELETE", "/listing-editor-drafts/" + self.__key)
            receipt["draft_delete_http"] = code
            require(code == 200, "draft_delete_not_confirmed")
            code, _ = self._call("GET", "/listing-editor-drafts/" + self.__key)
            receipt["draft_readback_http"] = code
            require(code == 404, "draft_absence_not_confirmed")
            receipt["known_application_rows_removed"] = True
            after, _, _ = self._snapshot()
            self._protected(after, property_present=False, draft_present=False)
            require(after == self.__baseline, "baseline_not_restored")
            receipt["protected_baseline_restored"] = True
            for image_id in fresh["image_ids"]:
                code, _ = self._call("GET", "/property-media/" + str(image_id))
                require(code == 404, "property_media_route_still_accessible")
            receipt.update(status="PASS", known_property_media_routes_404=True,
                           checked_property_media_route_count=len(fresh["image_ids"]))
        except Exception as error:
            self._failure(receipt, error)
        return receipt
