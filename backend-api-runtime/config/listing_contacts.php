<?php

return [
    'yemen_mobile_prefixes' => array_values(array_filter(array_map('trim', explode(',', env('LISTING_YEMEN_MOBILE_PREFIXES', '70,71,73,77,78'))), fn ($prefix) => preg_match('/^7[0-9]$/', $prefix))),
];
