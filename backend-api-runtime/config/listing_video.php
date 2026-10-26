<?php

return [
    // No new video route or queue consumption is active until security,
    // upload API, UI, worker capacity and storage tests all pass.
    'uploads_enabled' => (bool) env('LISTING_VIDEO_UPLOADS_ENABLED', false),
    'processing_enabled' => (bool) env('LISTING_VIDEO_PROCESSING_ENABLED', false),
    // Fail closed for uploads until a dedicated worker has checked in.
    // A 12-minute lease covers a full 540s transcoding job + shutdown margin.
    'worker_heartbeat_required' => (bool) env('VIDEO_WORKER_HEARTBEAT_REQUIRED', true),
    'worker_heartbeat_enabled' => (bool) env('VIDEO_WORKER_HEARTBEAT_ENABLED', false),
    'worker_heartbeat_ttl_seconds' => 720,
    'max_upload_bytes' => 50 * 1024 * 1024,
    'max_duration_seconds' => 90,
    'range_chunk_bytes' => 1024 * 1024,
];

