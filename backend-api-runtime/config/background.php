<?php

return [
    // Every producer is opt-in. Each queue has its own consumer process.
    'features' => [
        'push_messages' => env('BG_PUSH_MESSAGES', false),
        'push_other' => env('BG_PUSH_OTHER', false),
        'broker_reminders' => env('BG_BROKER_REMINDERS', false),
        'availability' => env('BG_AVAILABILITY', false),
        'instant_search' => env('BG_INSTANT_SEARCH', false),
        'daily_search' => env('BG_DAILY_SEARCH', false),
        'favorite_price' => env('BG_FAVORITE_PRICE', false),
        'images' => env('BG_IMAGES', false),
        'duplicates' => env('BG_DUPLICATES', false),
        'receivables' => env('BG_RECEIVABLES', false),
        'entitlements' => env('BG_ENTITLEMENTS', false),
        'listing_expiry' => env('BG_LISTING_EXPIRY', false),
        'reports' => env('BG_REPORTS', false),
    ],
    'registration' => env('BG_PUSH_REGISTRATION', env('PUSH_NOTIFICATIONS_ENABLED', false)),
    'deal_confirmation_reminder_token' => env('DEAL_CONFIRMATION_REMINDER_TOKEN'),
    'capacity' => (int) env('BG_QUEUE_CAPACITY', 200),
    'receivable_lead_minutes' => (int) env('BG_RECEIVABLE_LEAD_MINUTES', 0),
    'entitlement_lead_minutes' => (int) env('BG_ENTITLEMENT_LEAD_MINUTES', 0),
    'expiry_lead_minutes' => (int) env('BG_LISTING_EXPIRY_LEAD_MINUTES', 0),
    'sale_days' => (int) env('BG_SALE_EXPIRY_DAYS', 0),
    'rent_days' => (int) env('BG_RENT_EXPIRY_DAYS', 0),
];
