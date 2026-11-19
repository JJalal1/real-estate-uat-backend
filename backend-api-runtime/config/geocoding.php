<?php
return [
    // Existing shared database cache for public geocoders and request limits.
    'cache_store'=>env('GEOCODING_CACHE_STORE','database'),
    'enabled'=>env('GEOCODING_ENABLED',true),
    'user_agent'=>env('GEOCODING_USER_AGENT','AqerYemen/2.0 (+https://github.com/JJalal1/real-estate-uat-backend)'),
    'nominatim_url'=>env('GEOCODING_NOMINATIM_URL','https://nominatim.openstreetmap.org'),
    'photon_url'=>env('GEOCODING_PHOTON_URL','https://photon.komoot.io'),
    'google_address_search' => [
        'enabled' => filter_var(env('GOOGLE_ADDRESS_SEARCH_ENABLED', false), FILTER_VALIDATE_BOOLEAN),
        'key' => env('GOOGLE_GEOCODING_SERVER_KEY'),
        'daily_limit' => max(1, min(1000, (int) env('GOOGLE_ADDRESS_SEARCH_DAILY_LIMIT', 100))),
    ],
];
