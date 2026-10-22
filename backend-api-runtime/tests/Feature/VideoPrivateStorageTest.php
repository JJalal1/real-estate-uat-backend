<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class VideoPrivateStorageTest extends TestCase
{
    public function test_streamed_video_is_kept_private_and_range_reads_are_bounded(): void
    {
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        Storage::fake('public');

        $source = tempnam(sys_get_temp_dir(), 'aqer-storage-');
        $this->assertNotFalse($source);
        try {
            file_put_contents($source, '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
            $file = new UploadedFile($source, 'recording.mp4', 'video/mp4', null, true);
            $storage = app(CloudAssetStorageService::class);
            $path = $storage->storePrivateStreamed($file, 'listing-videos/17/original');
            $this->assertStringStartsWith('listing-videos/17/original/', $path);
            Storage::disk('local')->assertExists($path);
            $this->assertSame([], Storage::disk('public')->allFiles());
            $this->assertSame('56789', $storage->readPrivateRange($path, 5, 9));

            $download = tempnam(sys_get_temp_dir(), 'aqer-downloaded-');
            try {
                $storage->downloadPrivateToPath($path, $download);
                $this->assertSame('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', file_get_contents($download));
            } finally {
                @unlink($download);
            }
        } finally {
            @unlink($source);
        }
    }

    public function test_range_cannot_exceed_two_megabytes(): void
    {
        config()->set('services.supabase_storage.enabled', false);
        $this->expectException(\RuntimeException::class);
        app(CloudAssetStorageService::class)->readPrivateRange('any', 0, 2 * 1024 * 1024);
    }
}
