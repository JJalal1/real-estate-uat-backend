<?php

return [
    'android' => [
        'minimum_supported_build' => (int) env('ANDROID_MIN_SUPPORTED_BUILD', 1),
        'latest_build' => (int) env('ANDROID_LATEST_BUILD', 1124),
        'store_url' => env('ANDROID_STORE_URL'),
        'message' => env('ANDROID_UPDATE_MESSAGE', 'يتوفر إصدار أحدث من عقار.'),
    ],
];
