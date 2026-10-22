<?php

namespace App\Jobs;

use App\Models\ListingVideo;
use App\Services\CloudAssetStorageService;
use App\Services\ListingVideoTranscoder;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

final class ProcessListingVideo implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public int $timeout = 540;

    public function __construct(public readonly int $videoId) {}

    public function backoff(): array
    {
        return [120, 600, 1800];
    }

    public function handle(CloudAssetStorageService $storage, ListingVideoTranscoder $transcoder): void
    {
        // The rollout flag is deliberately OFF until a dedicated worker,
        // transcoding binary, DB migration and storage policy are verified.
        if (! config('listing_video.processing_enabled', false)) return;

        $video = DB::transaction(function (): ?ListingVideo {
            $record = ListingVideo::query()->lockForUpdate()->find($this->videoId);
            if (! $record || $record->status === 'ready') return null;
            // Recover a crashed worker after its 660s queue visibility lease.
            // A fresh processing lease means another worker still owns it.
            if ($record->status === 'processing' && $record->updated_at?->isAfter(now()->subSeconds(660))) {
                return null;
            }
            if (! in_array($record->status, ['uploaded', 'failed', 'processing'], true)) return null;
            $record->status = 'processing';
            $record->attempts++;
            $record->failure_code = null;
            $record->save();
            return $record;
        });
        if (! $video) return;

        $directory = sys_get_temp_dir().'/aqer-video-'.bin2hex(random_bytes(12));
        // Stable per-video derivative keys make every crashed/aborted attempt
        // discoverable without listing the entire private bucket. A retry
        // removes stale partial objects before re-uploading with x-upsert=false.
        // A fresh processing lease cannot reach here, so no active worker's
        // assets may be overwritten by a duplicate queue delivery.
        $playbackPath = 'listing-video-display/'.$video->id.'/playback.mp4';
        $posterPath = 'listing-video-display/'.$video->id.'/poster.jpg';

        try {
            if (! mkdir($directory, 0700)) {
                throw new RuntimeException('video_temp_unavailable');
            }
            // A previous worker may have crashed AFTER storing an object but
            // BEFORE recording a ready row. Never leak those orphaned bytes
            // or use an accidental implicit cloud overwrite on retries.
            $storage->deletePrivate($playbackPath);
            $storage->deletePrivate($posterPath);

            $input = $directory.'/source';
            $storage->downloadPrivateToPath($video->original_path, $input);
            if (hash_file('sha256', $input) !== $video->content_sha256) {
                throw new RuntimeException('video_checksum_mismatch');
            }
            $output = $transcoder->transcode($input, $directory);
            $storage->writePrivateFromFile($playbackPath, $output['playback_file'], 'video/mp4');
            $storage->writePrivateFromFile($posterPath, $output['poster_file'], 'image/jpeg');

            DB::transaction(function () use ($video, $output, $playbackPath, $posterPath): void {
                $record = ListingVideo::query()->lockForUpdate()->find($video->id);
                if (! $record || $record->status !== 'processing') {
                    throw new RuntimeException('video_processing_state_changed');
                }
                $record->fill([
                    'status' => 'ready',
                    'playback_path' => $playbackPath,
                    'playback_size_bytes' => filesize($output['playback_file']),
                    'poster_path' => $posterPath,
                    'duration_ms' => $output['duration_ms'],
                    'width' => $output['width'],
                    'height' => $output['height'],
                    'processed_at' => now(),
                    'failure_code' => null,
                ])->save();
            });
        } catch (Throwable $error) {
            // Partial derivatives are never exposed; cleanup is best-effort.
            foreach ([$playbackPath, $posterPath] as $path) {
                try { $storage->deletePrivate($path); } catch (Throwable) {}
            }
            ListingVideo::query()->whereKey($video->id)->where('status', 'processing')
                ->update(['status' => 'failed', 'failure_code' => 'processing_failed']);
            throw $error;
        } finally {
            foreach (['source', 'playback.mp4', 'poster.jpg'] as $name) {
                @unlink($directory.'/'.$name);
            }
            @rmdir($directory);
        }
    }
}
