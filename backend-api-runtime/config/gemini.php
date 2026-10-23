<?php

return [
    // The existing Render secret is read only by Laravel. No client key.
    'enabled' => filter_var(env('GEMINI_ENABLED', in_array(env('APP_ENV'), ['uat', 'staging'], true)), FILTER_VALIDATE_BOOLEAN),
    'key' => env('GEMINI_API_KEY'),
    'model' => env('GEMINI_MODEL', 'gemini-3.1-flash-lite'),
    'daily_limit' => max(1, min(5000, (int) env('GEMINI_DAILY_LIMIT', 200))),
    'timeout' => 25,
];
