<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Jobs\ProcessListingVideo;
use App\Models\ListingVideo;
use App\Models\Property;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\ListingVideoUploadPolicy;
use App\Services\ListingVideoWorkerHealth;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Throwable;

final class ListingVideoController extends Controller
{
    public function __construct(
        private readonly CloudAssetStorageService $storage,
        private readonly ListingVideoUploadPolicy $policy,
        private readonly ListingVideoWorkerHealth $workerHealth,
    ) {}

    /**
     * Reserve an idempotent row in a short transaction, upload private bytes
     * with NO database locks held, then promote the row to 'uploaded'.
     * A request crash leaves a tracked reservation, not an invisible object.
     */
    public function upload(Request $request, Property $property): JsonResponse
    {
        abort_unless(config('listing_video.uploads_enabled', false)
            && config('listing_video.processing_enabled', false), 404);

        /** @var User|null $actor */
        $actor = $request->user();
        abort_unless($actor && (int) $property->user_id === (int) $actor->id, 404);
        // Do not accept 50 MiB originals into a queue with no live processor.
        abort_unless($this->workerHealth->healthy(), 503,
            'معالجة الفيديو غير متاحة حاليًا. حاول لاحقًا.');

        $data = $request->validate([
            'upload_id' => ['required', 'uuid'],
            'video' => ['required', 'file', 'max:51200'],
        ]);
        $this->policy->assertAcceptable($data['video']);
        $source = $data['video']->getRealPath();
        if (! is_string($source) || ! is_file($source)) {
            throw new \RuntimeException('Video source is unavailable.');
        }
        $checksum = hash_file('sha256', $source);
        if (! is_string($checksum)) throw new \RuntimeException('Video checksum failed.');
        $size = (int) $data['video']->getSize();
        $mime = (string) $data['video']->getMimeType();

        [$reserved, $needsUpload, $previousPath] = DB::transaction(function () use (
            $actor, $property, $data, $checksum, $size, $mime
        ): array {
            $lockedActor = User::query()->lockForUpdate()->findOrFail($actor->id);
            abort_unless($lockedActor->account_status === User::STATUS_ACTIVE, 404);
            $locked = Property::query()->lockForUpdate()->findOrFail($property->id);
            abort_unless((int) $locked->user_id === (int) $actor->id, 404);
            abort_if($locked->status !== 'draft'
                || ! in_array($locked->review_status, ['draft', 'returned_for_correction'], true),
                409, 'لا يمكن تعديل فيديو الإعلان أثناء المراجعة أو بعد النشر.');

            $existing = ListingVideo::query()
                ->where('property_id', $locked->id)->lockForUpdate()->first();
            $newPath = 'listing-videos/'.$locked->id.'/original/'
                .bin2hex(random_bytes(16)).'.mp4';

            if ($existing) {
                abort_unless((string) $existing->upload_id === (string) $data['upload_id'],
                    422, 'يُسمح بفيديو واحد لكل إعلان.');
                abort_unless($existing->content_sha256 === $checksum
                    && (int) $existing->size_bytes === $size,
                    409, 'مفتاح رفع الفيديو مستخدم لملف مختلف.');

                if ($existing->status === 'uploading'
                    && $existing->updated_at?->isAfter(now()->subMinutes(4))) {
                    abort(409, 'رفع الفيديو جارٍ بالفعل. حاول لاحقًا.');
                }

                if (in_array($existing->status, ['upload_failed', 'uploading'], true)) {
                    $previousPath = $existing->original_path;
                    $existing->fill([
                        'status' => 'uploading',
                        'original_path' => $newPath,
                        'cleanup_paths'=>array_values(array_unique(array_merge($existing->cleanup_paths ?? [],[$previousPath]))),
                        'failure_code' => null,
                    ])->save();
                    return [$existing, true, $previousPath];
                }

                // A repeated upload ID after a lost response returns the same
                // accepted video, not a duplicate or another cloud upload.
                return [$existing, false, null];
            }

            $video = ListingVideo::query()->create([
                'property_id' => $locked->id,
                'upload_id' => $data['upload_id'],
                'status' => 'uploading',
                'original_path' => $newPath,
                'mime_type' => $mime,
                'size_bytes' => $size,
                'content_sha256' => $checksum,
            ]);
            return [$video, true, null];
        });

        if (! $needsUpload) {
            return response()->json(['data' => $this->present($reserved)], 202);
        }

        try {
            // No path is forgotten if provider deletion fails. Retry keeps
            // these tombstones; no further original bytes are admitted first.
            foreach($reserved->cleanup_paths ?? [] as $path) {
                $this->storage->deletePrivate($path);
            }
            ListingVideo::query()->whereKey($reserved->id)->where('status','uploading')
                ->where('original_path',$reserved->original_path)->update(['cleanup_paths'=>null]);
            // Cloud storage can take ~90s; no DB transaction/row lock here.
            $this->storage->writePrivateFromFile($reserved->original_path, $source, $mime);

            $completed = DB::transaction(function () use ($actor, $property, $reserved): ListingVideo {
                $lockedActor = User::query()->lockForUpdate()->findOrFail($actor->id);
                abort_unless($lockedActor->account_status === User::STATUS_ACTIVE, 404);
                $locked = Property::query()->lockForUpdate()->findOrFail($property->id);
                abort_unless((int) $locked->user_id === (int) $actor->id
                    && $locked->status === 'draft'
                    && in_array($locked->review_status, ['draft', 'returned_for_correction'], true),
                    409, 'تغيّرت حالة الإعلان أثناء رفع الفيديو.');

                $record = ListingVideo::query()->lockForUpdate()->findOrFail($reserved->id);
                abort_unless($record->status === 'uploading'
                    && $record->original_path === $reserved->original_path, 409);

                $record->status = 'uploaded';
                $record->save();

                ProcessListingVideo::dispatch($record->id)
                    ->onConnection('database_video')->onQueue('video')->afterCommit();
                return $record;
            });
        } catch (Throwable $error) {
            // Never delete a file now owned by an accepted or processing job.
            // Only a still-uploading reservation may be marked failed/cleaned.
            $markedFailed = false;
            try {
                $markedFailed = ListingVideo::query()
                    ->whereKey($reserved->id)
                    ->where('status', 'uploading')
                    ->where('original_path', $reserved->original_path)
                    ->update(['status' => 'upload_failed', 'failure_code' => 'upload_failed']) === 1;
            } catch (Throwable) {}
            if ($markedFailed) {
                try { $this->storage->deletePrivate($reserved->original_path); } catch (Throwable) {}
            }
            throw $error;
        }

        return response()->json(['data' => $this->present($completed)], 202);
    }

    public function show(Request $request, Property $property): JsonResponse
    {
        abort_unless(config('listing_video.uploads_enabled', false), 404);
        $actor = $request->user();
        abort_unless($actor && (int) $property->user_id === (int) $actor->id, 404);
        $video = ListingVideo::query()->where('property_id', $property->id)->first();
        return response()->json(['data' => $video ? $this->present($video) : null]);
    }

    public function remove(Request $request, Property $property): JsonResponse
    {
        abort_unless(config('listing_video.uploads_enabled', false), 404);
        $actor = $request->user();
        abort_unless($actor && (int) $property->user_id === (int) $actor->id, 404);

        DB::transaction(function () use ($property,$actor): void {
            $lockedActor=User::query()->lockForUpdate()->findOrFail($actor->id);
            abort_unless($lockedActor->account_status===User::STATUS_ACTIVE,404);
            $locked = Property::query()->lockForUpdate()->findOrFail($property->id);
            abort_unless((int)$locked->user_id===(int)$actor->id,404);
            abort_if($locked->status !== 'draft' || ! in_array($locked->review_status, ['draft', 'returned_for_correction'], true),
                409, 'لا يمكن حذف الفيديو أثناء المراجعة أو بعد النشر.');
            $video = ListingVideo::query()->where('property_id', $locked->id)->lockForUpdate()->first();
            if (! $video) return;
            abort_if(in_array($video->status, ['uploading', 'processing'], true), 409, 'انتظر انتهاء رفع أو معالجة الفيديو قبل الحذف.');
            $paths = $video->trackedPaths();
            // Preserve tracked paths on provider failure so retry can finish.
            // Never acknowledge deletion after swallowing a storage error.
            foreach ($paths as $path) $this->storage->deletePrivate($path);
            $video->delete();
        });
        return response()->json(['message' => 'حُذف فيديو الإعلان.']);
    }

    private function present(ListingVideo $video): array
    {
        return [
            'id' => (int) $video->id,
            'status' => $video->status,
            'size_bytes' => (int) $video->size_bytes,
            'duration_ms' => $video->duration_ms,
            'failure_code' => $video->failure_code,
            'processed_at' => $video->processed_at?->toIso8601String(),
        ];
    }
}

