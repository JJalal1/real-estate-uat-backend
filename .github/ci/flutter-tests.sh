#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/mobile_app"
mapfile -d '' -t tests < <(find test -type f -name '*_test.dart' ! -path 'test/uat_compiled_environment_test.dart' -print0 | sort -z)
test "${#tests[@]}" -gt 0
printf 'Full recursive Flutter suite: %s files\n' "${#tests[@]}"
printf '%s\n' "${tests[@]}"
flutter test --no-pub --machine "${tests[@]}" | tee flutter-tests.jsonl
python3 "$repo_root/.github/ci/verify-test-results.py" flutter flutter-tests.jsonl
