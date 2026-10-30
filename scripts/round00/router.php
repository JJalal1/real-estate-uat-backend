<?php
// Test transport only; keep Laravel routes/controllers unchanged and HTTPS URLs.
if (getenv('AQER_ROUND00_DISPOSABLE') !== '20261030' || getenv('DB_DATABASE') !== 'aqer_round00') exit;
$_SERVER['HTTPS'] = 'on';
$_SERVER['SERVER_PORT'] = 443;
require dirname(__DIR__, 2).'/backend-api-runtime/public/index.php';
