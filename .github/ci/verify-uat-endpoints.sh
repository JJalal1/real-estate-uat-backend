#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/mobile_app"
test "${UAT_APP_ENVIRONMENT}" = uat
test "${UAT_API_BASE_URL}" = https://real-estate-uat-api-frankfurt.onrender.com/api

# The positive compile guard and APK use these same two environment variables.
flutter test --no-pub --machine \
  "--dart-define=APP_ENVIRONMENT=${UAT_APP_ENVIRONMENT}" \
  "--dart-define=API_BASE_URL=${UAT_API_BASE_URL}" \
  test/uat_compiled_environment_test.dart | tee uat-compiled-positive.jsonl
python3 "$repo_root/.github/ci/verify-test-results.py" flutter uat-compiled-positive.jsonl

# Every negative case compiles the real resolver and asserts that it throws.
rejected=(
  'https://localhost/api'
  'https://127.0.0.1/api'
  'https://10.0.2.2/api'
  'https://[::1]/api'
  'http://real-estate-uat-api-frankfurt.onrender.com/api'
  'ftp://real-estate-uat-api-frankfurt.onrender.com/api'
  'https://real-estate-uat-api.onrender.com/api'
  'https://unintended-uat.example.test/api'
  'https://real-estate-uat-api-frankfurt.onrender.com.evil.test/api'
  'https://user@real-estate-uat-api-frankfurt.onrender.com/api'
  'https://real-estate-uat-api-frankfurt.onrender.com:443/api'
  'https://real-estate-uat-api-frankfurt.onrender.com/other'
  'https://real-estate-uat-api-frankfurt.onrender.com/api?target=oregon'
  'https://real-estate-uat-api-frankfurt.onrender.com/api#other'
)
for index in "${!rejected[@]}"; do
  printf 'Compiling negative UAT endpoint probe: %s\n' "${rejected[$index]}"
  report="uat-compiled-negative-${index}.jsonl"
  flutter test --no-pub --machine \
    "--dart-define=APP_ENVIRONMENT=${UAT_APP_ENVIRONMENT}" \
    "--dart-define=API_BASE_URL=${rejected[$index]}" \
    --dart-define=EXPECT_REJECTED_UAT=true \
    test/uat_compiled_environment_test.dart | tee "$report"
  python3 "$repo_root/.github/ci/verify-test-results.py" flutter "$report"
done
