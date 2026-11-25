#!/bin/sh
set -eu
umask 0077
exec php artisan background:work "${BACKGROUND_QUEUE:-push}" --no-interaction
