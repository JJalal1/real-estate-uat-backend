#!/bin/bash
set -euo pipefail
cd backend-api-runtime
export APP_ENV=testing
export CACHE_STORE=file
export SESSION_DRIVER=file
export QUEUE_CONNECTION=sync
export MAIL_MAILER=array
export UAT_CLOUD_STORAGE_ENABLED=false
php artisan migrate --force
PHP_CLI_SERVER_WORKERS=3 php -S 127.0.0.1:8099 -t public public/index.php > /tmp/aqer-role-http.log 2>&1 &
aqer_http_pid=$!
trap 'kill "$aqer_http_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 30); do
  if curl --silent --fail --max-time 1 http://127.0.0.1:8099/up > /dev/null; then break; fi
  sleep 1
done
php artisan uat:role-journeys --run=disposable-ci --base-url=http://127.0.0.1:8099
php artisan uat:role-journeys --run=disposable-ci --base-url=http://127.0.0.1:8099
