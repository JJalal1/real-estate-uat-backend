<?php

namespace Tests\Feature;

use App\Services\ListingImageEncodingGate;
use App\Services\ListingImageService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

class LargeImageAdmissionTest extends TestCase
{
    public function test_encoder_contention_is_retryable_before_any_storage_write(): void
    {
        Storage::fake('local'); $gate=app(ListingImageEncodingGate::class);
        $gate->run(function () {
            try {
                app(ListingImageService::class)->store(UploadedFile::fake()->image('synthetic.jpg',20,20),'listing-originals/test');
                $this->fail('Contended decode must not run');
            } catch (HttpException $error) {
                $this->assertSame(503,$error->getStatusCode());
                $this->assertSame('2',$error->getHeaders()['Retry-After']);
            }
            $this->assertSame([],Storage::disk('local')->allFiles());
        });
        $path=app(ListingImageService::class)->store(UploadedFile::fake()->image('synthetic.jpg',20,20),'listing-originals/test');
        Storage::disk('local')->assertExists($path);
    }

    public function test_encoder_lock_is_released_after_an_exception(): void
    {
        $gate=app(ListingImageEncodingGate::class);
        try { $gate->run(fn () => throw new \RuntimeException('synthetic failure')); }
        catch (\RuntimeException $error) { $this->assertSame('synthetic failure',$error->getMessage()); }
        $this->assertSame('retry succeeded',$gate->run(fn () => 'retry succeeded'));
    }

    public function test_pixel_and_byte_limits_are_checked_before_entering_the_encoder(): void
    {
        Storage::fake('local');
        $gate=\Mockery::mock(ListingImageEncodingGate::class); $gate->shouldNotReceive('run'); $this->app->instance(ListingImageEncodingGate::class,$gate);
        // Valid PNG signature/IHDR with a too-large canvas; no pixel allocation.
        $image=imagecreatetruecolor(1,1);ob_start();imagepng($image);$png=ob_get_clean();imagedestroy($image);
        $png=substr_replace($png,pack('NN',6001,4000),16,8);
        foreach ([$png,str_repeat('x',8*1024*1024+1)] as $bytes) {
            try { app(ListingImageService::class)->store(UploadedFile::fake()->createWithContent('synthetic.png',$bytes),'listing-originals/test');$this->fail('Oversized image accepted'); }
            catch (\Illuminate\Validation\ValidationException $error) { $this->assertArrayHasKey('image',$error->errors()); }
        }
        $this->assertSame([],Storage::disk('local')->allFiles());
    }
}
