#!/usr/bin/env bash
set -euo pipefail

entrypoint="$PWD/docker/uat-entrypoint.sh"
test_dir="$(mktemp -d "$PWD/.aqer-probe-gates.XXXXXX")"
cleanup() {
  case "$test_dir" in
    "$PWD"/.aqer-probe-gates.*) rm -rf -- "$test_dir" ;;
    *) printf 'Unexpected temporary path; retaining it.\n' >&2 ;;
  esac
}
trap cleanup EXIT

printf '#!/bin/sh\nexit 0\n' > "$test_dir/sed"
printf '#!/bin/sh\nprintf "CALL:%%s\\n" "$*"\n' > "$test_dir/php"
printf '#!/bin/sh\nprintf "APACHE_READY\\n"\n' > "$test_dir/apache2-foreground"
chmod +x "$test_dir/sed" "$test_dir/php" "$test_dir/apache2-foreground"

default_output="$(env -i PATH="$test_dir:/usr/bin:/bin" APP_ENV=staging PORT=10000 sh "$entrypoint")"
printf '%s\n' "$default_output" | grep -Fx 'CALL:artisan uat:cloud-check --skip-storage-probe' >/dev/null
if printf '%s\n' "$default_output" | grep -Eq 'CALL:artisan (uat:ai-check|uat:video-storage-probe|uat:signed-tus-storage-probe|migrate|db:seed)'; then
  printf 'Default startup invoked an outbound or data-writing optional command.\n' >&2
  exit 1
fi
printf '%s\n' "$default_output" | grep -Fx 'APACHE_READY' >/dev/null

opt_in_output="$(env -i PATH="$test_dir:/usr/bin:/bin" APP_ENV=staging PORT=10000 UAT_CLOUD_STORAGE_PROBE_ON_STARTUP=true UAT_AI_PROBE_ON_STARTUP=true UAT_DEMO_SEED_ENABLED=true sh "$entrypoint")"
printf '%s\n' "$opt_in_output" | grep -Fx 'CALL:artisan uat:cloud-check' >/dev/null
printf '%s\n' "$opt_in_output" | grep -Fx 'CALL:artisan uat:ai-check' >/dev/null
printf '%s\n' "$opt_in_output" | grep -Fx 'CALL:artisan db:seed --class=UatDemoSeeder --force' >/dev/null
if printf '%s\n' "$opt_in_output" | grep -Fq 'CALL:artisan uat:cloud-check --skip-storage-probe'; then
  printf 'Opt-in startup skipped the requested Storage probe.\n' >&2
  exit 1
fi

printf 'STARTUP_PROBE_GATES_PASS default_no_optional_calls=yes explicit_opt_in=yes\n'
