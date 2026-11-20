#!/usr/bin/env python3
"""Verify the two prior Arabic query inputs on the corrected Frankfurt UAT API."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, build_opener

from phase23_preflight import API, NoRedirect


ROOT = Path(__file__).resolve().parents[1]
REF = "refs/heads/work/uat-ranked-text-retest-20261121"
SERVICE = "srv-dahj3vlg1s2s73bdqhtg"
UA = "AQER UAT Arabic filter regression"
SCOPE = {
    "advertiser_id": 28, "type": "apartment", "purpose": "rent", "currency": "YER",
    "latitude": 15.154277, "longitude": 44.682468, "radius_km": 0.2,
    "south": 15.154387, "north": 15.157277, "west": 44.680468, "east": 44.682558,
}
SUITE = (("typed", "ثلاث غرف نوم وحمامان"), ("dictated_text", "٣ غرف نوم، و٢ حمام"))


def validate_context():
    env = os.environ
    if (env.get("GITHUB_ACTIONS") != "true"
            or env.get("GITHUB_REPOSITORY") != "JJalal1/real-estate-uat-backend"
            or env.get("GITHUB_REF") != REF or env.get("GITHUB_EVENT_NAME") != "push"
            or env.get("GITHUB_RUN_ATTEMPT") != "1"
            or API != "https://real-estate-uat-api-frankfurt.onrender.com/api"):
        raise SystemExit("unsafe_test_execution_context")
    manifest = json.loads((ROOT / "scripts/uat_ranked_text_retest_deploy.json").read_bytes())
    observed = datetime.fromisoformat(manifest["observed_at_utc"].replace("Z", "+00:00"))
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:backend-api-runtime"], cwd=ROOT, text=True).strip()
    if (manifest["service_id"] != SERVICE or manifest["status"] != "live"
            or not re.fullmatch(r"dep-[a-z0-9]+", manifest["deploy_id"])
            or not re.fullmatch(r"[a-f0-9]{40}", manifest["commit"])
            or not 0 <= (datetime.now(timezone.utc) - observed).total_seconds() <= 1800
            or manifest["backend_tree"] != tree):
        raise SystemExit("deployment_receipt_or_tree_mismatch")
    return manifest


def query(opener, phrase, revision):
    body = {"message": phrase, "filters": SCOPE, "revision": revision}
    request = Request(API + "/ai/search", data=json.dumps(body).encode(), method="POST",
                      headers={"Accept": "application/json", "Content-Type": "application/json",
                               "User-Agent": UA})
    try:
        with opener.open(request, timeout=45) as response:
            data = response.read(131073)
            if len(data) > 131072:
                return response.status, None
            return response.status, json.loads(data)["data"].get("filters")
    except HTTPError as error:
        return error.code, None


def main():
    deployment = validate_context()
    receipt = {"render_deploy": deployment["deploy_id"], "target_commit": deployment["commit"],
               "api_route": "/api/ai/search", "role": "guest", "device_audio_used": False,
               "listing_writes": 0, "cases": {}}
    expected = SCOPE | {"min_bedrooms": 3, "min_bathrooms": 2}
    proposals = []
    opener = build_opener(NoRedirect())
    for revision, (label, phrase) in enumerate(SUITE, 1):
        observed = receipt["cases"][label] = {}
        try:
            status, filters = query(opener, phrase, revision)
            observed["http"] = status
            if isinstance(filters, dict):
                observed.update(
                    added=sorted(filters.keys() - expected.keys()),
                    missing=sorted(expected.keys() - filters.keys()),
                    changed=sorted(k for k in expected.keys() & filters.keys() if expected[k] != filters[k]),
                    exact=filters == expected,
                )
                proposals.append(filters)
        except Exception as error:
            observed["error_type"] = type(error).__name__
    receipt["equivalent"] = len(proposals) == 2 and proposals[0] == proposals[1]
    passed = receipt["equivalent"] and all(case.get("exact") is True for case in receipt["cases"].values())
    receipt["status"] = "PASS" if passed else "FAIL"
    print("AQER_RANKED_TEXT_RETEST " + json.dumps(receipt, sort_keys=True))
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
