<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'supabase_storage' => [
        // Server-only UAT object storage. The secret key must exist only in the
        // hosting provider's environment variables and must never enter Flutter.
        'enabled' => filter_var(env('UAT_CLOUD_STORAGE_ENABLED', false), FILTER_VALIDATE_BOOLEAN),
        'url' => env('SUPABASE_URL'),
        'server_key' => env('SUPABASE_STORAGE_SERVER_KEY'),
        'bucket' => env('SUPABASE_STORAGE_BUCKET', 'real-estate-uat'),
        'public_prefix' => env('UAT_PUBLIC_STORAGE_PREFIX', 'public'),
        'private_prefix' => env('UAT_PRIVATE_STORAGE_PREFIX', 'private'),
        'connect_timeout' => (int) env('UAT_STORAGE_CONNECT_TIMEOUT', 15),
        'timeout' => (int) env('UAT_STORAGE_TIMEOUT', 90),
    ],

    'whatsapp' => [
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'api_version' => env('WHATSAPP_API_VERSION', 'v23.0'),
        'auth_template' => env('WHATSAPP_AUTH_TEMPLATE'),
        'locale' => env('WHATSAPP_AUTH_LOCALE', 'ar'),
        'uat_test_otp' => [
            'enabled' => filter_var(env('UAT_TEST_OTP_ENABLED', false), FILTER_VALIDATE_BOOLEAN),
            'code' => env('UAT_TEST_OTP_CODE'),
            'phone_numbers' => array_values(array_filter(array_map(
                static fn ($value) => trim((string) $value),
                explode(',', (string) env('UAT_TEST_PHONE_NUMBERS', '')),
            ))),
        ],
    ],

];
