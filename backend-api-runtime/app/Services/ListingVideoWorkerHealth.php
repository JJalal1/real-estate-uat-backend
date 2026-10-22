<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Fails video admission closed when the isolated FFmpeg worker is unavailable.
 *
 * The fixed 720s lease covers a maximum 540s processing job during which
 * Laravel's queue loop cannot emit idle heartbeats. The lease bounds the
 * time a crashed worker can appear present; it is not a billing/uptime claim.
 */
final class ListingVideoWorkerHealth
{
    public function healthy(): bool
    {
        if (! (bool) config('listing_video.worker_heartbeat_required', true)) {
            return true;
        }

        try {
            return DB::table('listing_video_worker_health')
                ->where('id', 1)
                ->where('last_seen_at', '>=', now()->subSeconds(
                    (int) config('listing_video.worker_heartbeat_ttl_seconds', 720)
                ))
                ->exists();
        } catch (Throwable) {
            // Missing migration, DB outage or permissions: do not accept work.
            return false;
        }
    }

    /** Call only from the dedicated video queue's Looping event. */
    public function beat(): void
    {
        DB::table('listing_video_worker_health')->upsert(
            [['id' => 1, 'last_seen_at' => now()]],
            ['id'],
            ['last_seen_at'],
        );
    }
}
