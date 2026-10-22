<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Jobs\ProcessListingVideo;
use App\Models\ListingVideo;
use App\Models\Property;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\ListingVideoUploadPolicy;
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
    ) {}

    public function upload(Request $request, Property $property): JsonResponse
    {
        abort_unless(config('listing_video.uploads_enabled', false), 404);
        /** @var User $actor */
        $actor = $request->user();
        abort_unless((int) $property->user_id === (int) $actor->id, 404);

        $data = $request->validate([
            'upload_id' => ['required', 'uuid'],
            'video' => ['required', 'file', 'max:51200'],
        ]);

        $this->policy->assertAcceptable($data['video']);
        $checksum = hash_file('sha256', $data['video']->getRealPath());
        if (! is_string($checksum)) throw new \RuntimeException('Video checksum failed.');
        $size = (int) $data['video']->getSize();

        $path = null;
        try {
            $record = DB::transaction(function () use ($actor, $property, $data, $checksum, $size, &$path): ListingVideo {
                User::query()->lockForUpdate()->findOrFail($actor->id);
                $locked = Property::query()->lockForUpdate()->findOrFail($property->id);
                abort_unless((int) $locked->user_id === (int) $actor->id, 404);
                abort_if($locked->status !== 'draft' || ! in_array($locked->review_status, ['draft', 'returned_for_correction'], true),
                    409, 'لا يمكن تعديل فيديو الإعلان أثناء المراجعة أو بعد النشر.');

                $existing = ListingVideo::query()
                    ->where('property_id', $locked->id)
                    ->where('upload_id', $data['upload_id'])
                    ->first();
                if ($existing) {
                    abort_unless($existing->content_sha256 === $checksum && (int) $existing->size_bytes === $size,
                        409, 'مفتاح رفع الفيديو مستخدم لملف مختلف.');
                    return $existing;
                }

                abort_if(ListingVideo::query()->where('property_id', $locked->id)->exists(),
                    422, 'يُسمح بفيديو واحد لكل إعلان.');

                $path = $this->storage->storePrivateStreamed(
                    $data['video'], 'listing-videos/'.$locked->id.'/original'
                );

                $video = ListingVideo::query()->create([
                    'property_id' => $locked->id,
                    'upload_id' => $data['upload_id'],
                    'status' => 'uploaded',
                    'original_path' => $path,
                    'mime_type' => (string) $data['video']->getMimeType(),
                    'size_bytes' => $size,
                    'content_sha256' => $checksum,
                ]);

                if (config('listing_video.processing_enabled', false)) {
                    ProcessListingVideo::dispatch($video->id)->onConnection('database_video')->onQueue('video')->afterCommit();
                }

                return $video;
            });
        } catch (Throwable $e) {
            if ($path !== null) {
                try { $this->storage->deletePrivate($path); } catch (Throwable) {}
            }
            throw $e;
        }

        return response()->json(['data' => $this->present($record)], 202);
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

        $paths = DB::transaction(function () use ($property): array {
            $locked = Property::query()->lockForUpdate()->findOrFail($property->id);
            abort_if($locked->status !== 'draft' || ! in_array($locked->review_status, ['draft', 'returned_for_correction'], true),
                409, 'لا يمكن حذف الفيديو أثناء المراجعة أو بعد النشر.');
            $video = ListingVideo::query()->where('property_id', $locked->id)->lockForUpdate()->first();
            if (! $video) return [];
            abort_if($video->status === 'processing', 409, 'انتظر انتهاء معالجة الفيديو قبل الحذف.');
            $paths = array_values(array_filter([
                $video->original_path, $video->playback_path, $video->poster_path,
            ]));
            $video->delete();
            return $paths;
        });

        foreach ($paths as $path) {
            try { $this->storage->deletePrivate($path); } catch (Throwable) {}
        }
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
