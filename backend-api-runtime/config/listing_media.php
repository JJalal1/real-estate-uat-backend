<?php

return [
    // Fixed bounded variants, produced from the original once, never from another derivative.
    'variants' => ['thumb'=>[320,64], 'card'=>[640,80], 'preview'=>[960,72],
        'detail'=>[1280,85], 'gallery'=>[1920,88], 'zoom'=>[3072,92]],
    // Activation requires the reviewed vector file and exact SHA; no new external service.
    'watermark' => ['enabled'=>env('LISTING_WATERMARK_ENABLED',false), 'approved_sha256'=>env('LISTING_WATERMARK_APPROVED_SHA256','bf7611483e0689ad9ccd73458442745ff9fc4c91a07d60cf2c3521be90698b6e')],
    'max_pixels' => 24000000,
    'max_side' => 16384,
    'max_bytes' => 8 * 1024 * 1024,
];
