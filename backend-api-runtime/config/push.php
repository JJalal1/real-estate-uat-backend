<?php

return [
    'enabled' => (bool) env('PUSH_NOTIFICATIONS_ENABLED', false),
    'provider' => env('PUSH_PROVIDER', 'fcm'),
    'queue_connection' => 'database',
    'queue' => 'push',
    'fcm' => [
        'project_id' => env('FCM_PROJECT_ID'),
        'android_package' => env('FCM_ANDROID_PACKAGE', in_array(env('APP_ENV'), ['staging', 'testing'], true) ? 'com.aqer.yemen.uat' : ''),
        'service_account_file' => env('FCM_SERVICE_ACCOUNT_FILE'),
        'service_account_json_base64' => env('FCM_SERVICE_ACCOUNT_JSON_BASE64'),
        'connect_timeout_seconds' => (int) env('FCM_CONNECT_TIMEOUT_SECONDS', 5),
        'timeout_seconds' => (int) env('FCM_TIMEOUT_SECONDS', 10),
    ],
];
