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
