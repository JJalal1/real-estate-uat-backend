<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ListingVideo;
use App\Services\ApiTokenService;
use App\Services\CloudAssetStorageService;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class ListingVideoMediaController extends Controller
{
    public function __construct(
        private readonly ApiTokenService $tokens,
        private readonly CloudAssetStorageService $storage,
    ) {}

    public function poster(Request $request, ListingVideo $video): Response
    {
        $this->assertAllowed($request, $video);
        abort_unless($video->status === 'ready' && $video->poster_path, 404);
        return $this->storage->responsePrivate($video->poster_path, null, [
            'Content-Type' => 'image/jpeg',
            'Cache-Control' => $video->property->status === 'published' ? 'public, max-age=3600' : 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    public function stream(Request $request, ListingVideo $video): Response
    {
        $this->assertAllowed($request, $video);
        abort_unless($video->status === 'ready' && $video->playback_path && $video->playback_size_bytes, 404);
        $total = (int) $video->playback_size_bytes;
        $range = trim((string) $request->header('Range', 'bytes=0-'));
        if (! preg_match('/^bytes=(\\d+)-(\\d*)$/D', $range, $parts)) {
            return response('', 416, [
                'Accept-Ranges' => 'bytes',
                'Content-Range' => 'bytes */'.$total,
            ]);
        }

        $start = (int) $parts[1];
        if ($start >= $total || $start < 0) {
            return response('', 416, [
                'Accept-Ranges' => 'bytes',
                'Content-Range' => 'bytes */'.$total,
            ]);
        }
        $endRequested = $parts[2] === '' ? $total - 1 : (int) $parts[2];
        if ($endRequested < $start) {
            return response('', 416, [
                'Accept-Ranges' => 'bytes',
                'Content-Range' => 'bytes */'.$total,
            ]);
        }

        $chunk = max(65536, min(1024 * 1024, (int) config('listing_video.range_chunk_bytes', 1024 * 1024)));
        $end = min($total - 1, $endRequested, $start + $chunk - 1);
        $body = $this->storage->readPrivateRange($video->playback_path, $start, $end);
        return response($body, 206, [
            'Accept-Ranges' => 'bytes',
            'Content-Range' => 'bytes '.$start.'-'.$end.'/'.$total,
            'Content-Length' => (string) strlen($body),
            'Content-Type' => 'video/mp4',
            'Content-Disposition' => 'inline',
            'Cache-Control' => $video->property->status === 'published' ? 'public, max-age=300' : 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    private function assertAllowed(Request $request, ListingVideo $video): void
    {
        abort_unless(config('listing_video.uploads_enabled', false), 404);
        $video->loadMissing('property');
        $property = $video->property;
        abort_unless($property, 404);
        $user = $this->tokens->authenticate($request, false);
        $owner = $user && (int) $property->user_id === (int) $user->id;
        $moderator = $user && $user->hasPermission('listings.moderate');
        abort_unless($property->status === 'published' || $owner || $moderator, 404);
    }
}
