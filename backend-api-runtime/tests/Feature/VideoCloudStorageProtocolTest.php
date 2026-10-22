<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

/**
 * Simulated Supabase Storage wire contract.
 * Tests authenticate and Range semantics without touching real UAT objects.
 * A green mock test DOES NOT replace a live private-bucket canary.
 */
class VideoCloudStorageProtocolTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('services.supabase_storage.enabled', true);
        config()->set('services.supabase_storage.url', 'https://video-storage.example.test');
        config()->set('services.supabase_storage.bucket', 'real-estate-uat');
        config()->set('services.supabase_storage.server_key', 'sb_secret_test_not_a_real_key');
        config()->set('services.supabase_storage.private_prefix', 'private');
    }

    public function test_private_video_range_must_be_exact_and_partially_served(): void
    {
        Http::fake([
            '*' => function (Request $request) {
                if ($request->hasHeader('Range', 'bytes=5-9')) {
                    return Http::response('56789', 206, ['Content-Range' => 'bytes 5-9/20']);
                }
                return Http::response('', 400);
            },
        ]);
        $bytes = app(CloudAssetStorageService::class)->readPrivateRange('listing-videos/9/output.mp4', 5, 9);
        $this->assertSame('56789', $bytes);
        Http::assertSent(fn (Request $request) =>
            $request->method() === 'GET'
            && str_contains($request->url(), '/storage/v1/object/real-estate-uat/private/listing-videos/9/output.mp4')
            && $request->hasHeader('Range', 'bytes=5-9')
            && $request->hasHeader('apikey', 'sb_secret_test_not_a_real_key')
            && ! $request->hasHeader('Authorization')
        );
    }

    public function test_storage_ignoring_range_is_never_fallback_to_full_video_download(): void
    {
        Http::fake(['*' => Http::response(str_repeat('x', 25), 200)]);
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('did not honor byte range');
        app(CloudAssetStorageService::class)->readPrivateRange('listing-videos/9/output.mp4', 0, 9);
    }

    public function test_mismatched_partial_range_is_not_treated_as_valid_media(): void
    {
        Http::fake(['*' => Http::response('abcdefghij', 206, ['Content-Range' => 'bytes 2-11/20'])]);
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('unexpected range');
        app(CloudAssetStorageService::class)->readPrivateRange('listing-videos/9/output.mp4', 0, 9);
    }

    public function test_truncated_partial_content_is_never_served(): void
    {
        Http::fake(['*' => Http::response('abc', 206, ['Content-Range' => 'bytes 0-9/20'])]);
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('range incomplete');
        app(CloudAssetStorageService::class)->readPrivateRange('listing-videos/9/output.mp4', 0, 9);
    }

    public function test_private_upload_uses_supabase_storage_without_upsert(): void
    {
        Http::fake(['*' => Http::response('{"Key":"private/listing-videos/9/file.mp4"}', 200)]);
        $temp = tempnam(sys_get_temp_dir(), 'aqer-video-cloud-');
        $this->assertNotFalse($temp);
        try {
            file_put_contents($temp, str_repeat('a', 1024));
            app(CloudAssetStorageService::class)->writePrivateFromFile(
                'listing-videos/9/file.mp4', $temp, 'video/mp4'
            );
            Http::assertSent(fn (Request $request) =>
                $request->method() === 'POST'
                && str_contains($request->url(), '/storage/v1/object/real-estate-uat/private/listing-videos/9/file.mp4')
                && $request->hasHeader('x-upsert', 'false')
                && $request->hasHeader('Content-Type', 'video/mp4')
            );
        } finally {
            @unlink($temp);
        }
    }
}
