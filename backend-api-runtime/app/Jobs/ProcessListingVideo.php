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
            $hint=ListingVideo::query()->find($this->videoId);
            if (! $hint) return null;
            $property=\App\Models\Property::query()->find($hint->property_id);
            if (! $property || ! $property->user_id) return null;
            $owner=\App\Models\User::query()->lockForUpdate()->find($property->user_id);
            if (! $owner || $owner->account_status!==\App\Models\User::STATUS_ACTIVE) return null;
            $property=\App\Models\Property::query()->lockForUpdate()->find($hint->property_id);
            if (! $property || (int)$property->user_id!==(int)$owner->id || $property->status==='archived') return null;
            $record = ListingVideo::query()->lockForUpdate()->find($this->videoId);
            if (! $record || $record->status === 'ready') return null;
            // Recover a crashed worker after its 660s queue visibility lease.
            // A fresh processing lease means another worker still owns it.
            if ($record->status === 'processing' && $record->updated_at?->isAfter(now()->subSeconds(660))) {
                return null;
            }
            if (! in_array($record->status, ['uploaded', 'failed', 'processing'], true)) return null;
            if ((int)$record->attempts>=ListingVideo::MAX_PROCESS_ATTEMPTS) {
                $record->fill(['status'=>'failed','failure_code'=>'processing_attempt_limit'])->save();
                return null;
            }
            $record->status = 'processing';
            $record->attempts++;
            $record->failure_code = null;
            $record->save();
            return $record;
        });
        if (! $video) return;

        $directory = sys_get_temp_dir().'/aqer-video-'.bin2hex(random_bytes(12));
        // Attempt-scoped objects prevent a stale worker's cleanup from deleting
        // another worker's accepted output after a lease is reclaimed.
        [$playbackPath,$posterPath]=$video->derivativePathsForAttempt($video->attempts);

        try {
            if (! mkdir($directory, 0700)) {
                throw new RuntimeException('video_temp_unavailable');
            }
            $this->assertClaim($video);
            // All earlier keys are derivable from the bounded attempts counter.
            // Keep incomplete outputs tracked for retry and account deletion.
            foreach($video->trackedPaths() as $path) {
                if($path!==$video->original_path && $path!==$playbackPath && $path!==$posterPath) {
                    $storage->deletePrivate($path);
                }
            }

            $input = $directory.'/source';
            $storage->downloadPrivateToPath($video->original_path, $input);
            if (hash_file('sha256', $input) !== $video->content_sha256) {
                throw new RuntimeException('video_checksum_mismatch');
            }
            $this->assertClaim($video);
            $output = $transcoder->transcode($input, $directory);
            $this->assertClaim($video);
            $storage->writePrivateFromFile($playbackPath, $output['playback_file'], 'video/mp4');
            $this->assertClaim($video);
            $storage->writePrivateFromFile($posterPath, $output['poster_file'], 'image/jpeg');

            DB::transaction(function () use ($video, $output, $playbackPath, $posterPath): void {
                $record = ListingVideo::query()->lockForUpdate()->find($video->id);
                if (! $record || $record->status !== 'processing' || (int)$record->attempts!==(int)$video->attempts) {
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
                ->where('attempts',$video->attempts)
                ->update(['status' => 'failed', 'failure_code' => 'processing_failed']);
            throw $error;
        } finally {
            foreach (['source', 'playback.mp4', 'poster.jpg'] as $name) {
                @unlink($directory.'/'.$name);
            }
            @rmdir($directory);
        }
    }

    private function assertClaim(ListingVideo $video): void
    {
        if(!ListingVideo::query()->whereKey($video->id)->where('status','processing')
            ->where('attempts',$video->attempts)->exists()) {
            throw new RuntimeException('video_processing_state_changed');
        }
    }
}
