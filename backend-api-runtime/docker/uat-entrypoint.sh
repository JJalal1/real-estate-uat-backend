#!/bin/sh
set -eu

listen_port="${PORT:-10000}"
case "$listen_port" in
  ''|*[!0-9]*)
    echo "PORT must be a numeric TCP port." >&2
    exit 1
    ;;
esac
sed -ri "s/^Listen [0-9]+$/Listen ${listen_port}/" /etc/apache2/ports.conf
sed -ri "s#<VirtualHost \*:[0-9]+>#<VirtualHost *:${listen_port}>#" /etc/apache2/sites-available/000-default.conf

php artisan config:clear
php artisan cache:clear || true

# Fail fast in UAT if the cloud runtime is misconfigured. This command verifies
# HTTPS URL, PostgreSQL/PostGIS, Supabase Storage, and UAT guards without
# printing secrets.
php artisan uat:cloud-check

# Opt-in synthetic storage canary for the new video protocol. It never reads
# real listings and is off by default. If enabled, a failed range/download
# causes this UAT deployment to fail closed rather than open broken playback.
if [ "${UAT_VIDEO_STORAGE_PROBE_ON_STARTUP:-false}" = "true" ]; then
  php artisan uat:video-storage-probe
fi

# One-shot opt-in signed TUS protocol canary for synthetic private bytes only.
# Does not require a schema migration or activate listing resumable uploads.
if [ "${UAT_IMAGE_TUS_PROBE_ON_STARTUP:-false}" = "true" ]; then
  php artisan uat:signed-tus-storage-probe
fi

if [ "${UAT_RUN_MIGRATIONS:-false}" = "true" ]; then
  php artisan migrate --force
fi

# Safe, idempotent UAT-only test accounts and published demo properties.
if [ "${UAT_DEMO_SEED_ENABLED:-true}" = "true" ]; then
  case "${APP_ENV:-production}" in
    uat|staging)
      php artisan db:seed --class=UatDemoSeeder --force
      ;;
  esac
fi

# Separate, opt-in additive city fixtures; never rerun the historical cleanup.
if [ "${UAT_CITY_DEMO_SEED_ENABLED:-false}" = "true" ]; then
  php artisan db:seed --class=UatCityDemoSeeder --force
fi

case "${APP_ENV:-production}" in
  uat|staging)
    if ! php artisan uat:ai-check; then
      echo "AI provider is unavailable; manual marketplace workflows remain ready."
    fi
    ;;
esac

php artisan config:cache
# Explicit one-shot acceptance on the current UAT only. The command rejects
# Production/foreign Storage/foreign origins and persists a DB audit marker
# before creating any fixture, so Free-service wakes never replay the run.
# It uses ordinary HTTP routes and revokes every generated short-lived token.
if [ "${UAT_EXECUTIVE_JOURNEY_RUN:-}" = "2026-10-26-109-v5" ]; then
  (
    ready=false
    for attempt in $(seq 1 60); do
      if curl --silent --fail --max-time 1 "http://127.0.0.1:${listen_port}/up" >/dev/null; then
        ready=true
        break
      fi
      sleep 1
    done
    if [ "$ready" = "true" ]; then
      # Finish the bounded regression before owner fixtures, avoiding concurrent
      # image encoders/OTP throttles on the shared Free UAT service.
      if php artisan uat:role-journeys --run="$UAT_EXECUTIVE_JOURNEY_RUN" --base-url="http://127.0.0.1:${listen_port}"; then
        if [ "${UAT_OWNER_ACCEPTANCE_RUN:-}" = "2026-10-26-owner-v1" ]; then
          php artisan uat:owner-acceptance-preflight --run="$UAT_OWNER_ACCEPTANCE_RUN" --base-url="http://127.0.0.1:${listen_port}"
        fi
      else
        echo 'AQER_UAT_ROLE_JOURNEYS execution-failed; owner preparation not started'
      fi
    else
      echo 'AQER_UAT_ROLE_JOURNEYS readiness-failed; no fixtures created'
    fi
  ) &
fi

exec apache2-foreground
