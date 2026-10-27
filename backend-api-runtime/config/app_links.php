<?php

return [
    'android' => [
        'package_name' => env('ANDROID_APP_LINK_PACKAGE', env('APP_ENV') === 'staging' ? 'com.aqer.yemen.uat' : ''),
        'sha256_cert_fingerprints' => array_values(array_filter(array_map(
            static fn (string $value): string => trim($value),
            explode(',', (string) env('ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS', '')),
        ))),
    ],
];
