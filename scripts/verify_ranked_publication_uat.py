#!/usr/bin/env python3
"""Targeted ranked list and map proof using only newly created UAT listings."""

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request

from verify_duplicate_review_uat import API, BROKER_ID, REPOSITORY, SERVICE, Journey, CheckFailed, multipart, require


BRANCH = "refs/heads/work/uat-ranked-publication-live-20261121"
CONTRACT = "specification_misses,distance_when_known,tiebreakers,id"
FIXTURES = {
    "exact_near": (7, 3, 0.00045, 0.0, "المطابقة القريبة"),
    "exact_far": (8, 3, 0.00135, 0.0, "المطابقة الأبعد"),
    "outside_full_specs": (9, 3, 0.00028, 0.00024, "المواصفات كاملة خارج النطاق"),
    "inside_missing_spec": (10, 2, 0.00018, 0.0, "الأقرب بغرفة أقل"),
}
RANK_ORDER = ("outside_full_specs", "exact_near", "exact_far", "inside_missing_spec")
PHRASES = ("ثلاث غرف نوم وحمامان", "٣ غرف نوم، و٢ حمام")


def read_context(path, photo, env):
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("GITHUB_REPOSITORY") == REPOSITORY
            and env.get("GITHUB_REF") == BRANCH and env.get("GITHUB_EVENT_NAME") == "push"
            and env.get("GITHUB_RUN_ATTEMPT") == "1" and env.get("GITHUB_RUN_ID", "").isdigit(),
            "uat_action_context_refused")
    value = json.loads(path.read_bytes())
    require(value.get("service_id") == SERVICE and value.get("status") == "live"
            and re.fullmatch(r"dep-[a-z0-9]+", value.get("deploy_id", ""))
            and re.fullmatch(r"[a-f0-9]{40}", value.get("commit", "")),
            "expected_deployment_not_live")
    require(value.get("nearby_comparison_rows") == 0, "fixture_location_not_isolated")
    checked = datetime.fromisoformat(value["observed_at_utc"].replace("Z", "+00:00"))
    require(0 <= (datetime.now(timezone.utc) - checked).total_seconds() <= 1800, "stale_deployment_check")
    require(0 < len(photo) <= 2 * 1024 * 1024 and photo.startswith(b"\x89PNG\r\n\x1a\n")
            and value.get("photo_sha256") == sha256(photo).hexdigest(), "unexpected_fixture_photo")
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:backend-api-runtime"],
                                   cwd=env["GITHUB_WORKSPACE"], text=True).strip()
    require(tree == value.get("backend_tree"), "backend_tree_mismatch")
    pin = (float(value["latitude"]), float(value["longitude"]))
    require(13 <= pin[0] <= 17 and 43 <= pin[1] <= 49, "fixture_pin_outside_uat")
    return value, pin


class RankedJourney(Journey):
    def __init__(self, receipt, photo, pin, http, no_redirect):
        super().__init__(receipt, photo, pin, http, no_redirect)
        self.marker = "AQER-UAT-RANK5-" + os.environ["GITHUB_RUN_ID"]
        self.titles = {key: self.marker + " " + fixture[4] for key, fixture in FIXTURES.items()}
        self.scope = {
            "advertiser_id": BROKER_ID, "type": "apartment", "purpose": "rent",
            "currency": "YER", "search": self.marker, "latitude": self.pin[0],
            "longitude": self.pin[1], "radius_km": 0.2,
            "south": round(self.pin[0] + 0.00011, 6), "north": round(self.pin[0] + 0.003, 6),
            "west": round(self.pin[1] - 0.002, 6), "east": round(self.pin[1] + 0.00009, 6),
        }

    def page(self, path, filters, number):
        query = urlencode(filters | {"ranked_search": 1, "ranking_version": 2,
                                     "per_page": 1, "page": number})
        request = Request(API + path + "?" + query, headers={"Accept": "application/json"})
        with self.opener.open(request, timeout=30) as response:
            require(response.status == 200, "ranked_http_not_ok")
            require(response.headers.get("X-Aqer-Ranked-Contract") == "2", "ranked_contract_2_absent")
            raw = response.read(262145)
        require(len(raw) <= 262144, "ranked_page_too_large")
        envelope = json.loads(raw)
        require(envelope.get("meta", {}).get("ranking") == CONTRACT, "unexpected_ranking_contract")
        return envelope

    def create(self, key):
        unit, rooms, delta_lat, delta_lon, _ = FIXTURES[key]
        self.receipt["stage"] = "create_" + key
        fields = {
            "listing_input_version": 3, "title": self.titles[key],
            "description": "إعلان اصطناعي عابر لفحص نتائج خادم الاختبار. غير معروض للإيجار فعليًا.",
            "type": "apartment", "purpose": "rent", "price": 80000, "currency": "YER",
            "monthly_rent": 80000, "rental_term_months": 12, "advance_months": 1,
            "bedrooms": rooms, "bathrooms": 2, "area_m2": 130,
            "address": "مبنى اصطناعي لاختبار البحث " + self.marker,
            "building_reference": self.marker, "floor_number": 3, "unit_number": unit,
            "latitude": f"{self.pin[0] + delta_lat:.6f}", "longitude": f"{self.pin[1] + delta_lon:.6f}",
        }
        self.attempts.add(key)
        created = self.request(self.broker, "POST", "/properties", expected=201,
                               raw=multipart(fields, self.photo))
        listing_id = created.get("id")
        require(type(listing_id) is int and listing_id > 107 and listing_id not in self.record.values()
                and created.get("title") == self.titles[key], "unexpected_created_listing")
        self.record[key] = listing_id
        owned = self.own(key)
        require(owned.get("review_status") == "draft" and owned.get("unit_number") == str(unit)
                and owned.get("bedrooms") == rooms and owned.get("monthly_rent") == 80000
                and owned.get("rental_term_months") == 12 and owned.get("advance_months") == 1
                and len(owned.get("images", [])) == 1, "created_fixture_shape")
        self.request(self.broker, "PUT", f"/properties/{listing_id}/sai",
                     body={"sai_payer": "tenant", "broker_sai_rate_percent": 0})
        return listing_id, owned["images"][0]["id"]

    def check_source_and_publish(self, Session, access):
        self.receipt["stage"] = "verify_live_contract_before_mutation"
        health = self.request(None, "GET", "/health")
        require(health.get("database") is True and health.get("postgis") is True, "uat_unhealthy")
        require(self.page("/properties", self.scope, 1).get("meta", {}).get("total") == 0,
                "fixture_marker_already_exists")
        self.receipt["stage"] = "authenticate_approved_fixtures"
        self.broker, self.support = Session("broker", access), Session("support", access)
        self.broker.login()
        self.support.login()
        listing_access = self.request(self.broker, "GET", "/listing-access")
        require(listing_access.get("can_create") is True and listing_access.get("mode") == "professional",
                "fixture_broker_not_authorized_to_publish")
        self.reconcile()
        for key in FIXTURES:
            listing_id, image_id = self.create(key)
            self.request(None, "GET", f"/properties/{listing_id}", expected=404)
            self.submit(key, "distinct")
            self.request(None, "GET", f"/properties/{listing_id}", expected=404)
            self.approve(key, image_id)
        self.receipt["approved_listings_became_public"] = len(self.record)

    def check_public_image(self, row):
        url = row.get("main_image")
        require(isinstance(url, str) and row.get("image_count") == 1
                and row.get("image_urls") == [url], "ranked_image_contract_missing")
        parsed = urlsplit(url)
        require(parsed.scheme == "https" and parsed.netloc == urlsplit(API).netloc
                and re.fullmatch(r"/api/property-media/[0-9]+", parsed.path)
                and parse_qs(parsed.query).get("variant") == ["card"], "unexpected_fixture_image_endpoint")
        request = Request(url, headers={"Accept": "image/jpeg"})
        with self.opener.open(request, timeout=30) as response:
            require(response.status == 200 and response.headers.get_content_type() == "image/jpeg",
                    "approved_listing_jpeg_unavailable")
            size = len(response.read(262145)) if response.read(2) == b"\xff\xd8" else 0
        require(0 < size <= 262144, "approved_listing_invalid_jpeg")

    def check_pages(self, filters):
        self.receipt["stage"] = "verify_order_and_parity_across_four_pages"
        ids, kinds, misses, distances = [], [], [], []
        for number, key in enumerate(RANK_ORDER, 1):
            page = self.page("/properties", filters, number)
            map_page = self.page("/properties/nearby", filters, number)
            require(page == map_page, "ranked_list_and_map_page_differ")
            meta = page.get("meta", {})
            require(meta.get("current_page") == number and meta.get("last_page") == 4
                    and meta.get("total") == 4 and meta.get("exact_total") == 2
                    and meta.get("alternative_total") == 2
                    and meta.get("ranking_distance_reference") == "point", "unexpected_ranked_page_metadata")
            rows = page.get("data", [])
            require(len(rows) == 1 and rows[0].get("id") == self.record[key], "rank_order_mismatch_" + key)
            row = rows[0]
            match = row.get("discovery_match", {})
            ids.append(row["id"])
            kinds.append(match.get("kind"))
            misses.append(match.get("criteria_misses"))
            distances.append(match.get("rank_distance_m"))
            if key == "exact_near":
                self.check_public_image(row)
            if key == "outside_full_specs":
                require([reason.get("field") for reason in match.get("reasons", [])] == ["location"],
                        "location_only_alternative_reason_missing")
            if key == "inside_missing_spec":
                require([reason.get("field") for reason in match.get("reasons", [])] == ["min_bedrooms"],
                        "specification_alternative_reason_missing")
        require(len(set(ids)) == 4 and kinds == ["nearby", "exact", "exact", "nearby"]
                and misses == [0, 0, 0, 1]
                and all(isinstance(value, (int, float)) for value in distances)
                and distances[3] < distances[0] < distances[1] < distances[2],
                "specifications_then_distance_not_verified")
        self.receipt.update(rank_pages_equal=4, ranked_specs_misses=misses,
                            ranked_distances_m=distances, public_image_jpeg=True)

    def check_text_equivalence(self, expected):
        self.receipt["stage"] = "compare_typed_with_dictated_text_at_api_boundary"
        proposals = []
        for revision, phrase in enumerate(PHRASES, 1):
            result = self.request(None, "POST", "/ai/search",
                                  body={"message": phrase, "filters": self.scope, "revision": revision})
            proposed = result.get("filters")
            require(isinstance(proposed, dict), "arabic_search_filters_missing")
            proposals.append(proposed)
        require(proposals[0] == proposals[1], "typed_and_dictated_text_filters_differ")
        require(proposals[0] == expected, "arabic_search_scope_or_specifications_changed")
        self.receipt["typed_and_dictated_text_same_api_filters"] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--photo", type=Path, required=True)
    args = parser.parse_args()
    photo = args.photo.read_bytes()
    meta, pin = read_context(args.receipt, photo, os.environ)
    from phase1_native_account_readiness import SECRET_NAME, validate_access
    from phase23_preflight import API as documented_api, NoRedirect, http
    from run_phase23_native import Session

    require(documented_api == API, "unexpected_fixture_api")
    receipt = {"run_id": os.environ["GITHUB_RUN_ID"], "target_commit": meta["commit"],
               "render_deploy": meta["deploy_id"], "status": "FAILED",
               "stage": "validate_fixture_access", "device_audio_used": False}
    journey = RankedJourney(receipt, photo, pin, http, NoRedirect)
    ordering_error = None
    try:
        access = validate_access(os.environ.pop(SECRET_NAME, ""))
        journey.check_source_and_publish(Session, access)
        expected = journey.scope | {"min_bedrooms": 3, "min_bathrooms": 2}
        try:
            journey.check_pages(expected)
        except Exception as error:
            ordering_error = str(error) if isinstance(error, CheckFailed) else type(error).__name__
        journey.check_text_equivalence(expected)
        if ordering_error is None:
            receipt["status"] = "PASS"
    except CheckFailed as error:
        receipt["error"] = str(error)
    except Exception as error:
        receipt["error_type"] = type(error).__name__
    finally:
        if ordering_error is not None:
            receipt["ranking_error"] = ordering_error
        if not journey.clean_up():
            receipt["status"] = "CLEANUP_REQUIRED"
        print("AQER_RANKED_PUBLICATION_UAT " + json.dumps(receipt, sort_keys=True))
    return int(receipt["status"] != "PASS")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckFailed as error:
        raise SystemExit(str(error)) from None
