<?php

namespace Tests\Feature;

use App\Services\ListingVideoTranscoder;
use Symfony\Component\Process\Process;
use Tests\TestCase;

class ListingVideoTranscoderTest extends TestCase
{
    #[\PHPUnit\Framework\Attributes\DataProvider('sizes')]
    public function test_actual_media_processing_produces_bounded_playback_and_poster(string $size,int $width,int $height): void
    {
        $directory = sys_get_temp_dir().'/aqer-transcoder-test-'.bin2hex(random_bytes(8));
        $this->assertTrue(mkdir($directory, 0700));
        $original = $directory.'/source.mp4';
        try {
            $make = new Process([
                'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
                '-f', 'lavfi', '-i', 'testsrc2=size='.$size.':rate=10',
                '-t', '2', '-c:v', 'libx264', '-threads','1','-preset', 'ultrafast',
                '-pix_fmt', 'yuv420p', '-y', $original,
            ]);
            $make->setTimeout(30);
            $make->mustRun();

            $out = app(ListingVideoTranscoder::class)->transcode($original, $directory);
            $this->assertSame($width, $out['width']);
            $this->assertSame($height, $out['height']);
            $this->assertSame(2000, $out['duration_ms']);
            $this->assertGreaterThan(0, filesize($out['playback_file']));
            $this->assertGreaterThan(0, filesize($out['poster_file']));

            $metadata = new Process(['ffprobe', '-v', 'error', '-show_entries',
                'format_tags:stream_tags', '-of', 'json', $out['playback_file']]);
            $metadata->mustRun();
            $tags = json_decode($metadata->getOutput(), true);
            $this->assertIsArray($tags);
        } finally {
            foreach (['source.mp4', 'playback.mp4', 'poster.jpg'] as $name) @unlink($directory.'/'.$name);
            @rmdir($directory);
        }
    }

    public static function sizes(): array
    {
        return [['320x240',320,240],['1920x1080',1280,720]];
    }
}
