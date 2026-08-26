#!/bin/sh
set -eu

PORT_VALUE="${PORT:-10000}"
case "$PORT_VALUE" in
    ''|*[!0-9]*)
        echo "Invalid PORT value." >&2
        exit 70
        ;;
esac

# Render routes traffic to the port in PORT (10000 by default).
sed -ri "s/^Listen[[:space:]]+[0-9]+/Listen ${PORT_VALUE}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT_VALUE}>/" /etc/apache2/sites-available/000-default.conf

if [ "${APP_ENV:-}" = "production" ] && [ "${UAT_TEST_OTP_ENABLED:-false}" = "true" ]; then
    echo "Refusing to start: UAT test OTP cannot run in production." >&2
    exit 71
fi

php artisan config:clear
php artisan cache:clear || true

# External infrastructure must be valid before mutating the UAT schema.
if [ "${APP_ENV:-}" = "staging" ]; then
    php artisan uat:cloud-check
fi

if [ "${UAT_RUN_MIGRATIONS:-false}" = "true" ]; then
    php artisan migrate --force
fi

php artisan config:cache
exec apache2-foreground
