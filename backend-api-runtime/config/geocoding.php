<?php
return [
    // Existing shared database cache; no new table, paid provider or mobile update.
    'cache_store'=>env('GEOCODING_CACHE_STORE','database'),
    'enabled'=>env('GEOCODING_ENABLED',true),
    'user_agent'=>env('GEOCODING_USER_AGENT','AqerYemen/2.0 (+https://github.com/JJalal1/real-estate-uat-backend)'),
    'nominatim_url'=>env('GEOCODING_NOMINATIM_URL','https://nominatim.openstreetmap.org'),
    'photon_url'=>env('GEOCODING_PHOTON_URL','https://photon.komoot.io'),
];
