#!/bin/sh
set -eu
umask 0077
# No migrations, seeds, Apache, media processing or secret echoes here.
php artisan push:readiness --no-interaction
exec php artisan queue:work database --queue=push --sleep=3 --tries=3 --timeout=30 --memory=128 --max-jobs=500 --max-time=3600 --no-interaction
