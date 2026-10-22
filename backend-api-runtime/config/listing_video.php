<?php

return [
    // No new video route or queue consumption is active until security,
    // upload API, UI, worker capacity and storage tests all pass.
    'uploads_enabled' => (bool) env('LISTING_VIDEO_UPLOADS_ENABLED', false),
    'processing_enabled' => (bool) env('LISTING_VIDEO_PROCESSING_ENABLED', false),
    'max_upload_bytes' => 50 * 1024 * 1024,
    'max_duration_seconds' => 90,
    'range_chunk_bytes' => 1024 * 1024,
];
