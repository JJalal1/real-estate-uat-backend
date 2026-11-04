<?php

namespace Tests\Unit;

use App\Services\ListingImageService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class ResumableImageFinalizationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['services.supabase_storage.enabled' => false]);
        Storage::fake('local');
    }

    public function test_completed_original_is_verified_and_only_sanitized_derivatives_are_written(): void
    {
        $image = UploadedFile::fake()->image('house.png', 400, 300);
        $bytes = file_get_contents($image->getRealPath());
        $this->assertIsString($bytes);
        $hash = hash('sha256', $bytes);
        $path = 'editor-drafts/2/11111111-1111-4111-8111-111111111111/'
            .'22222222-2222-4222-8222-222222222222-'.$hash.'.png';
        Storage::disk('local')->put($path, $bytes);

        $service = app(ListingImageService::class);
        $service->finalizeResumablePrivate($path, $hash, strlen($bytes), 'image/png');

        $this->assertSame($bytes, Storage::disk('local')->get($path));
        foreach (array_keys(config('listing_media.variants')) as $variant) {
            $target = $service->variantPath($path, $variant);
            Storage::disk('local')->assertExists($target);
            $encoded = Storage::disk('local')->get($target);
            $this->assertSame('image/jpeg', getimagesizefromstring($encoded)['mime']);
        }
    }

    public function test_server_rejects_mismatched_checksum_without_writing_any_derivatives(): void
    {
        $image = UploadedFile::fake()->image('house.png', 250, 200);
        $bytes = file_get_contents($image->getRealPath());
        $this->assertIsString($bytes);
        $hash = hash('sha256', $bytes);
        $path = 'editor-drafts/2/11111111-1111-4111-8111-111111111111/'
            .'22222222-2222-4222-8222-222222222222-'.$hash.'.png';
        Storage::disk('local')->put($path, $bytes);

        try {
            app(ListingImageService::class)->finalizeResumablePrivate(
                $path, str_repeat('0', 64), strlen($bytes), 'image/png'
            );
            $this->fail('Mismatched checksum must be rejected.');
        } catch (ValidationException) {
            foreach (array_keys(config('listing_media.variants')) as $variant) {
                Storage::disk('local')->assertMissing(
                    app(ListingImageService::class)->variantPath($path, $variant)
                );
            }
        }
    }
}
