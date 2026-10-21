<?php

return [
    // Fixed bounded variants, produced from the original once, never from another derivative.
    'variants' => ['card'=>[640,80], 'detail'=>[1280,85], 'gallery'=>[1920,88], 'zoom'=>[3072,92]],
    // Activation requires the reviewed vector file and exact SHA; no new external service.
    'watermark' => ['enabled'=>env('LISTING_WATERMARK_ENABLED',false), 'approved_sha256'=>env('LISTING_WATERMARK_APPROVED_SHA256','')],
    'max_pixels' => 24000000,
    'max_side' => 16384,
    'max_bytes' => 8 * 1024 * 1024,
];
