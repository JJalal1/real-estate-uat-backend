<?php

namespace Tests\Feature;

use App\Services\ListingVideoProcessingPolicy;
use PHPUnit\Framework\Attributes\DataProvider;
use RuntimeException;
use Tests\TestCase;

class ListingVideoProcessingPolicyTest extends TestCase
{
    private static function probe(array $overrides = []): array
    {
        return array_replace_recursive([
            'format' => ['duration' => '23.125'],
            'streams' => [
                ['codec_type' => 'video', 'codec_name' => 'h264', 'width' => 1280, 'height' => 720],
                ['codec_type' => 'audio', 'codec_name' => 'aac'],
            ],
        ], $overrides);
    }

    public function test_valid_video_metadata_has_bounded_duration_and_dimensions(): void
    {
        $result = app(ListingVideoProcessingPolicy::class)->inspect(self::probe());
        $this->assertSame(['duration_ms' => 23125, 'width' => 1280, 'height' => 720], $result);
    }

    public function test_rejects_over_ninety_second_video(): void
    {
        $this->expectException(RuntimeException::class);
        app(ListingVideoProcessingPolicy::class)->inspect(self::probe(['format' => ['duration' => '91']]));
    }

    public function test_rejects_excessive_dimensions(): void
    {
        $this->expectException(RuntimeException::class);
        app(ListingVideoProcessingPolicy::class)->inspect(self::probe(['streams' => [
            ['codec_type' => 'video', 'codec_name' => 'h264', 'width' => 8192, 'height' => 4320],
        ]]));
    }

    public function test_rejects_non_video_or_unknown_codecs(): void
    {
        $this->expectException(RuntimeException::class);
        app(ListingVideoProcessingPolicy::class)->inspect(self::probe(['streams' => [
            ['codec_type' => 'video', 'codec_name' => 'unknown', 'width' => 1280, 'height' => 720],
        ]]));
    }

    public function test_rejects_subtitle_or_attachment_streams(): void
    {
        $probe = self::probe();
        $probe['streams'][] = ['codec_type' => 'subtitle', 'codec_name' => 'subrip'];
        $this->expectException(RuntimeException::class);
        app(ListingVideoProcessingPolicy::class)->inspect($probe);
    }

    public function test_rejects_missing_duration(): void
    {
        $this->expectException(RuntimeException::class);
        app(ListingVideoProcessingPolicy::class)->inspect(['format' => [], 'streams' => [
            ['codec_type' => 'video', 'codec_name' => 'h264', 'width' => 1280, 'height' => 720],
        ]]);
    }
}

