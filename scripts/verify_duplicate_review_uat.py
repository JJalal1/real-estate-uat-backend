#!/usr/bin/env python3
"""One deliberate Frankfurt UAT check against the exact PR #200 revision."""

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, build_opener


REPOSITORY = "JJalal1/real-estate-uat-backend"
BRANCH = "refs/heads/work/uat-listing-duplicate-live-20261120"
SOURCE = "aa7940b0a1772a7cc14eab268cac807af1c8f6c8"
BACKEND_TREE = "633de2db3cde9712d806a860bcd2297f9350000a"
SERVICE = "srv-dahj3vlg1s2s73bdqhtg"
API = "https://real-estate-uat-api-frankfurt.onrender.com/api"
BROKER_ID = 28
SUPPORT_ID = 6
REJECTION = "تطابقت بيانات المبنى والطابق والوحدة في الإعلان الاصطناعي."
PREFIX = "سبق نشره من قبلك. "


class CheckFailed(Exception):
    """A reason code suitable for a sanitized test receipt."""


def require(condition, code):
    if not condition:
        raise CheckFailed(code)


def validate_receipt(receipt, photo):
    require(receipt["service_id"] == SERVICE, "different_render_service")
    require(receipt["status"] == "live" and receipt["commit"] == SOURCE, "exact_deploy_not_live")
    require(re.fullmatch(r"dep-[a-z0-9]+", receipt["deploy_id"]), "invalid_deploy_id")
    require(receipt["publication_and_retained_synthetic_history_approved"] is True,
            "live_fixture_scope_not_approved")
    require(receipt["comparison_rows_in_scoring_window"] == 0, "fixture_location_not_isolated")
    observed = datetime.fromisoformat(receipt["observed_at_utc"].replace("Z", "+00:00"))
    age = (datetime.now(timezone.utc) - observed).total_seconds()
    require(0 <= age <= 1800, "deployment_or_isolation_receipt_stale")
    latitude, longitude = float(receipt["latitude"]), float(receipt["longitude"])
    require(13 <= latitude <= 17 and 43 <= longitude <= 49, "fixture_pin_outside_uat_region")
    require(0 < len(photo) <= 2 * 1024 * 1024 and photo.startswith(b"\x89PNG\r\n\x1a\n"),
            "invalid_synthetic_png")
    require(sha256(photo).hexdigest() == receipt["visually_reviewed_synthetic_png_sha256"],
            "media_not_reviewed_for_this_run")
    return receipt["deploy_id"], f"{latitude:.6f}", f"{longitude:.6f}"


def multipart(fields, photo):
    boundary = secrets.token_hex(24)
    start = ("--" + boundary + "\r\n").encode()
    payload = bytearray()
    for key, value in fields.items():
        payload += start
        payload += f'Content-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
    payload += start
    payload += b'Content-Disposition: form-data; name="images[]"; filename="synthetic.png"\r\n'
    payload += b"Content-Type: image/png\r\n\r\n" + photo + b"\r\n"
    payload += f"--{boundary}--\r\n".encode()
    return bytes(payload), f"multipart/form-data; boundary={boundary}"


class Journey:
    def __init__(self, receipt, photo, pin, http, no_redirect):
        self.receipt, self.photo, self.pin, self.http = receipt, photo, pin, http
        self.opener = build_opener(no_redirect())
        self.record = {}
        self.attempts = set()
        self.marker = "AQER-UAT-DUP200-" + os.environ["GITHUB_RUN_ID"]
        self.titles = {
            "original": self.marker + " شقة ٧",
            "distinct": self.marker + " شقة ٨",
            "duplicate": self.marker + " نسخة الشقة ٧",
        }
        self.broker = self.support = None

    def request(self, session, method, path, *, expected=200, body=None, raw=None):
        token = session.token if session else None
        if method in ("GET", "POST") and raw is None:
            code, result = self.http(method, path, body, token=token)
        else:
            require(token and path.startswith("/properties"), "invalid_owner_request")
            payload, content_type = raw or (json.dumps(body).encode() if body is not None else None,
                                             "application/json")
            request = Request(API + path, data=payload, method=method, headers={
                "Accept": "application/json", "Content-Type": content_type,
                "Authorization": "Bearer " + token,
            })
            try:
                with self.opener.open(request, timeout=45) as response:
                    code, response_bytes = response.status, response.read(2_000_001)
            except HTTPError as error:
                code, response_bytes = error.code, error.read(2_000_001)
            require(len(response_bytes) <= 2_000_000, "owner_response_too_large")
            result = json.loads(response_bytes)
        require(code == expected, f"unexpected_http_{code}")
        require(isinstance(result, dict), "invalid_response_envelope")
        return result.get("data", result)

    def own(self, key):
        listing_id = self.record[key]
        listing = self.request(self.broker, "GET", f"/properties/{listing_id}")
        require(listing.get("id") == listing_id and listing.get("title") == self.titles[key]
                and listing.get("advertiser", {}).get("id") == BROKER_ID, "fixture_owner_changed")
        return listing

    def review(self, key, action=None, body=None):
        listing_id = self.record[key]
        path = f"/admin/listing-review/listings/{listing_id}"
        if action:
            return self.request(self.support, "POST", f"{path}/{action}", body=body or {})
        result = self.request(self.support, "GET", path)
        require(result.get("id") == listing_id and result.get("title") == self.titles[key]
                and result.get("owner", {}).get("id") == BROKER_ID, "support_fixture_changed")
        return result

    def reconcile(self):
        recent = self.request(self.broker, "GET", "/properties/mine/list?per_page=50")
        inverse = {value: key for key, value in self.titles.items()}
        seen = set()
        for row in recent:
            key = inverse.get(row.get("title"))
            if key is None:
                continue
            require(key in self.attempts and key not in seen, "unexpected_fixture_title")
            listing_id = row.get("id")
            require(type(listing_id) is int and listing_id > 107
                    and self.record.get(key, listing_id) == listing_id, "unexpected_fixture_id")
            self.record[key] = listing_id
            seen.add(key)

    def create(self, key, unit):
        self.receipt["stage"] = "create_" + key
        fields = {
            "listing_input_version": 3, "title": self.titles[key],
            "description": "إعلان عقار اصطناعي لفحص خادم الاختبار فقط. غير معروض للإيجار فعلياً.",
            "type": "apartment", "purpose": "rent", "price": 80000, "currency": "YER",
            "bedrooms": 3, "bathrooms": 2, "area_m2": 130,
            "address": "مبنى اصطناعي لاختبار UAT " + self.marker,
            "building_reference": self.marker, "floor_number": 3, "unit_number": unit,
            "latitude": self.pin[0], "longitude": self.pin[1],
        }
        self.attempts.add(key)
        listing = self.request(self.broker, "POST", "/properties", expected=201,
                               raw=multipart(fields, self.photo))
        listing_id = listing.get("id")
        require(type(listing_id) is int and listing_id > 107 and listing_id not in self.record.values()
                and listing.get("title") == self.titles[key], "unexpected_created_listing")
        self.record[key] = listing_id
        owned = self.own(key)
        require(owned.get("review_status") == "draft" and owned.get("unit_number") == str(unit)
                and len(owned.get("images", [])) == 1, "created_fixture_shape")
        self.request(self.broker, "PUT", f"/properties/{listing_id}/sai", body={
            "sai_payer": "tenant", "broker_sai_rate_percent": 0,
        })
        return listing_id, owned["images"][0]["id"]

    def submit(self, key, expected):
        self.receipt["stage"] = "submit_" + key
        listing_id = self.record[key]
        check = self.request(self.broker, "POST", f"/properties/{listing_id}/identity/check", body={})
        require(check.get("decision") == expected, "identity_preflight_conflict")
        submitted = self.request(self.broker, "POST", f"/properties/{listing_id}/submit", body={})
        require(submitted.get("review_status") == "submitted", "fixture_not_submitted")
        return self.review(key)

    def approve(self, key, image_id):
        self.receipt["stage"] = "approve_" + key
        require(self.review(key).get("likely_duplicate_candidates") == [], "unrelated_candidate_found")
        self.review(key, "start")
        images = self.review(key).get("images", [])
        require(len(images) == 1 and images[0].get("id") == image_id
                and re.fullmatch(r"[a-f0-9]{64}", images[0].get("relevance_token") or ""),
                "unexpected_review_image")
        media = self.review(key, "media-review", {
            "image_id": image_id, "image_token": images[0]["relevance_token"],
            "decision": "relevant", "reason": "صورة العقار الاصطناعية التي روجعت قبل الاختبار.",
        })
        require(media.get("decision") == "relevant", "media_review_not_recorded")
        approved = self.review(key, "approve", {"reason": "تأكدت هوية الوحدة الاصطناعية."})
        require(approved.get("status") == "published" and approved.get("review_status") == "approved",
                "fixture_not_approved")
        public = self.request(None, "GET", f"/properties/{self.record[key]}")
        require(public.get("id") == self.record[key], "approved_fixture_not_public")

    def notifications(self):
        notifications = self.request(self.broker, "GET", "/notifications?per_page=100")
        return [row for row in notifications if row.get("entity_type") == "property"
                and row.get("entity_id") in self.record.values()]

    def run(self, Session, access):
        self.receipt["stage"] = "public_health"
        health = self.request(None, "GET", "/health")
        require(health.get("status") == "ok" and health.get("database") is True
                and health.get("postgis") is True, "uat_health_not_ready")
        self.request(None, "POST", "/admin/listing-review/listings/9223372036854775807/reject-duplicate",
                     expected=401, body={})
        self.receipt["health"] = "ok"
        self.receipt["stage"] = "authenticate_fixture_actors"
        self.broker, self.support = Session("broker", access), Session("support", access)
        self.broker.login()
        self.support.login()
        require(self.broker.identity.get("id") == BROKER_ID
                and self.broker.identity.get("account_type") == "broker"
                and self.support.identity.get("id") == SUPPORT_ID, "fixture_actor_changed")
        access_policy = self.request(self.broker, "GET", "/listing-access")
        require(access_policy.get("can_create") is True and access_policy.get("mode") == "professional",
                "fixture_broker_not_authorized_to_publish")
        self.reconcile()

        original, original_image = self.create("original", 7)
        self.submit("original", "distinct")
        self.approve("original", original_image)

        distinct, distinct_image = self.create("distinct", 8)
        self.submit("distinct", "distinct")
        require(self.own("original")["property_asset_id"] != self.own("distinct")["property_asset_id"],
                "distinct_units_share_identity")
        self.approve("distinct", distinct_image)
        self.receipt["distinct_unit_approved"] = True

        duplicate, _ = self.create("duplicate", 7)
        evidence = self.submit("duplicate", "confirmed_duplicate")
        candidates = evidence.get("likely_duplicate_candidates", [])
        require(evidence.get("duplicate_detection_source") == "algorithm"
                and bool(evidence.get("duplicate_detection_reason"))
                and [row.get("listing_id") for row in candidates] == [original]
                and "same_building_same_unit" in candidates[0].get("signals", []),
                "support_algorithm_evidence_missing")
        self.receipt["algorithm_evidence"] = True
        self.receipt["stage"] = "reject_duplicate"
        self.review("duplicate", "start")
        rejected = self.review("duplicate", "reject-duplicate", {
            "candidate_property_id": original, "reason": REJECTION,
        })
        require(rejected.get("review_status") == "rejected_duplicate"
                and rejected.get("last_review_reason") == PREFIX + REJECTION, "duplicate_not_rejected")
        self.request(None, "GET", f"/properties/{duplicate}", expected=404)
        for listing_id in (original, distinct):
            require(self.request(None, "GET", f"/properties/{listing_id}").get("id") == listing_id,
                    "published_unit_affected_by_rejection")
        matches = [row for row in self.notifications() if row.get("entity_id") == duplicate
                   and row.get("type") == "listing_duplicate_rejected"]
        require(len(matches) == 1, "duplicate_notification_count")
        notice = matches[0]
        require(notice.get("body") == PREFIX + REJECTION
                and notice.get("data", {}).get("previous_property_id") == original
                and notice.get("data", {}).get("previous_listing_same_owner") is True,
                "duplicate_notification_target_or_copy")
        self.receipt["rejection_reason_and_previous_link"] = True

    def clean_up(self):
        complete = True
        if self.attempts:
            try:
                self.reconcile()
            except Exception:
                complete = False
        for key in reversed(self.record):
            listing_id = self.record[key]
            try:
                listing = self.own(key)
                if listing.get("review_status") in ("submitted", "under_review"):
                    self.review(key)
                    self.review(key, "start")
                    self.review(key, "return", {"reason": "تنظيف إعلان اصطناعي بعد فحص خادم الاختبار."})
                    require(self.own(key).get("review_status") == "returned_for_correction",
                            "cleanup_return_failed")
                self.request(self.broker, "DELETE", f"/properties/{listing_id}")
                self.request(self.broker, "GET", f"/properties/{listing_id}", expected=404)
                self.request(None, "GET", f"/properties/{listing_id}", expected=404)
            except Exception:
                self.receipt.setdefault("remaining_fixture_ids", []).append(listing_id)
                complete = False
        if self.record:
            try:
                for notice in self.notifications():
                    notice_id = notice.get("id")
                    require(type(notice_id) is int, "unknown_notification_id")
                    self.request(self.broker, "POST", f"/notifications/{notice_id}/read", body={})
                require(self.notifications() == [], "unread_fixture_notifications_remain")
            except Exception:
                complete = False
        for alias, session in (("support", self.support), ("broker", self.broker)):
            if session is not None:
                try:
                    closed = session.close()
                except Exception:
                    closed = False
                self.receipt[alias + "_logout"] = closed
                complete = closed and complete
        self.receipt["active_fixture_cleanup"] = complete
        return complete


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment-receipt", type=Path, required=True)
    parser.add_argument("--photo", type=Path, required=True)
    args = parser.parse_args()
    action = os.environ
    require(action.get("GITHUB_ACTIONS") == "true" and action.get("GITHUB_REPOSITORY") == REPOSITORY
            and action.get("GITHUB_REF") == BRANCH and action.get("GITHUB_EVENT_NAME") == "push"
            and action.get("GITHUB_RUN_ATTEMPT") == "1" and action.get("GITHUB_RUN_ID", "").isdigit(),
            "uat_action_context_refused")
    root = Path(action["GITHUB_WORKSPACE"])
    tree = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD:backend-api-runtime"],
                                   text=True).strip()
    require(tree == BACKEND_TREE, "action_backend_tree_changed")
    photo = args.photo.read_bytes()
    metadata = json.loads(args.deployment_receipt.read_bytes())
    deploy, *pin = validate_receipt(metadata, photo)

    sys.path.insert(0, str(root / "scripts"))
    from phase1_native_account_readiness import SECRET_NAME, validate_access
    from phase23_preflight import API as documented_api, NoRedirect, http
    from run_phase23_native import Session

    require(documented_api == API, "unexpected_fixture_api")
    receipt = {
        "run_id": action["GITHUB_RUN_ID"], "target_commit": SOURCE, "render_deploy": deploy,
        "stage": "validate_fixture_access", "status": "FAILED",
        "real_ai_comparison_exercised": False,
    }
    journey = Journey(receipt, photo, pin, http, NoRedirect)
    try:
        access = validate_access(action.pop(SECRET_NAME, ""))
        journey.run(Session, access)
        receipt["status"] = "PASS"
    except CheckFailed as error:
        receipt["error"] = str(error)
    except Exception as error:
        receipt["error_type"] = type(error).__name__
    finally:
        if not journey.clean_up():
            receipt["status"] = "CLEANUP_REQUIRED"
        print("AQER_DUPLICATE_REVIEW_UAT " + json.dumps(receipt, sort_keys=True))
    return int(receipt["status"] != "PASS")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckFailed as error:
        raise SystemExit(str(error)) from None
