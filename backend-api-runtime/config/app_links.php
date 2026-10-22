<?php

return [
    'android' => [
        'package_name' => env('ANDROID_APP_LINK_PACKAGE', 'com.example.real_estate_mobile'),
        'sha256_cert_fingerprints' => array_values(array_filter(array_map(
            static fn (string $value): string => trim($value),
            explode(',', (string) env('ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS', '')),
        ))),
    ],
];
