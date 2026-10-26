<?php

namespace Tests\Feature;

use App\Services\ListingVideoUploadPolicy;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class ListingVideoUploadPolicyTest extends TestCase
{
    private array $temporaryFiles = [];

    protected function tearDown(): void
    {
        foreach ($this->temporaryFiles as $path) {
            @unlink($path);
        }
        parent::tearDown();
    }

    private function upload(string $contents, string $filename = 'clip.mp4'): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'aqer-video-policy-');
        $this->assertNotFalse($path);
        $this->temporaryFiles[] = $path;
        file_put_contents($path, $contents);
        return new UploadedFile($path, $filename, null, null, true);
    }

    private function mp4Header(int $boxSize = 24): string
    {
        return pack('N', $boxSize).'ftypisom'.pack('N', 0).'isom';
    }

    public function test_valid_iso_bmff_container_passes_initial_admission_only(): void
    {
        $file = $this->upload($this->mp4Header().str_repeat("\0", 8));
        app(ListingVideoUploadPolicy::class)->assertAcceptable($file);
        $this->assertTrue(true);
    }

    public function test_disguised_non_video_payload_is_rejected(): void
    {
        $file = $this->upload("%PDF-1.7\nnot a video", 'video.mp4');
        $this->expectException(ValidationException::class);
        app(ListingVideoUploadPolicy::class)->assertAcceptable($file);
    }

    public function test_malformed_ftyp_box_is_rejected(): void
    {
        $file = $this->upload($this->mp4Header(0).str_repeat("\0", 8));
        $this->expectException(ValidationException::class);
        app(ListingVideoUploadPolicy::class)->assertAcceptable($file);
    }

    public function test_oversized_video_is_rejected_before_file_processing(): void
    {
        $path = tempnam(sys_get_temp_dir(), 'aqer-video-oversize-');
        $this->assertNotFalse($path);
        $this->temporaryFiles[] = $path;
        $f = fopen($path, 'wb');
        $this->assertNotFalse($f);
        fwrite($f, $this->mp4Header());
        ftruncate($f, ListingVideoUploadPolicy::MAX_UPLOAD_BYTES + 1);
        fclose($f);
        $file = new UploadedFile($path, 'huge.mp4', null, null, true);
        $this->expectException(ValidationException::class);
        app(ListingVideoUploadPolicy::class)->assertAcceptable($file);
    }
}

