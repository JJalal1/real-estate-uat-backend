<?php

return [
    'enabled' => (bool) env('PUSH_NOTIFICATIONS_ENABLED', false),
    'provider' => env('PUSH_PROVIDER', 'fcm'),
    'fcm' => [
        'project_id' => env('FCM_PROJECT_ID'),
        'service_account_json_base64' => env('FCM_SERVICE_ACCOUNT_JSON_BASE64'),
        'connect_timeout_seconds' => (int) env('FCM_CONNECT_TIMEOUT_SECONDS', 5),
        'timeout_seconds' => (int) env('FCM_TIMEOUT_SECONDS', 10),
    ],
];
