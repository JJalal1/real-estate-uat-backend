#!/usr/bin/env bash
set -euo pipefail
seed=dc2805c9215dcd500fc7034effa953a4c3751761
actual="$(git rev-parse HEAD)"
test "$actual" = "$CANDIDATE_SHA"
git merge-base --is-ancestor "$seed" "$actual"
test -z "$(git status --porcelain)"
git ls-files --error-unmatch mobile_app/pubspec.lock backend-api-runtime/composer.lock >/dev/null
printf 'candidate_sha=%s\nsource_ref=%s\ngithub_sha_context=%s\nrun_id=%s\nrun_number=%s\nrun_attempt=%s\n' \
  "$actual" "$SOURCE_REF" "$GITHUB_SHA" "$GITHUB_RUN_ID" "$GITHUB_RUN_NUMBER" "$GITHUB_RUN_ATTEMPT"

if [ "$GITHUB_EVENT_NAME" = pull_request ]; then
  python3 - <<'PY'
import json
import os
from pathlib import Path
event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
assert event["pull_request"]["base"]["ref"] == "reconciliation/unified-uat"
assert event["pull_request"]["head"]["sha"] == os.environ["CANDIDATE_SHA"]
PY
else
  case "$GITHUB_REF" in
    refs/heads/reconciliation/ci-release-gate|refs/heads/reconciliation/unified-uat) ;;
    *) echo "Unapproved workflow_dispatch source ref"; exit 1 ;;
  esac
fi

check_hash() {
  file="$1"
  expected="$2"
  actual_hash="$(git hash-object "$file")"
  if [ "$actual_hash" != "$expected" ]; then
    printf '%s: FAILED; expected=%s actual=%s\n' "$file" "$expected" "$actual_hash"
    exit 1
  fi
  printf '%s: OK %s\n' "$file" "$actual_hash"
}

# Intentional W2 diff reviewed: exact UAT Frankfurt enforcement only.
# Previous API blob: ab1db55e0ba0058a1e992e2df677b03871bbe95c.
check_hash mobile_app/lib/core/network/api_client.dart 015bc0b63e7e76df6ba859da32b41120e99a2293
check_hash mobile_app/lib/router/app_router.dart 89ae86ee056585f1ea50423005282e695ce12a06
check_hash mobile_app/lib/features/services/presentation/services_screen.dart 7b6c3f3ae5947ad30b898606e93b1ae31ac6d04f

# Preserve every one of the 47 historical migration blobs; forward additions are separate waves.
mapfile -t migrations < <(git ls-tree -r --name-only "$seed" -- backend-api-runtime/database/migrations/ | sort)
test "${#migrations[@]}" -eq 47
for file in "${migrations[@]}"; do
  check_hash "$file" "$(git rev-parse "$seed:$file")"
done
git diff --check
