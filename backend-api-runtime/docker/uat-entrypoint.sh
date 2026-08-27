#!/bin/sh
set -eu

php artisan config:clear
php artisan cache:clear || true

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

php artisan config:cache
exec apache2-foreground
