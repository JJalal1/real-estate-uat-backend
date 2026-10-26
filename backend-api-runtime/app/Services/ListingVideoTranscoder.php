<?php

namespace App\Services;

use RuntimeException;
use Symfony\Component\Process\Process;

/**
 * Offline-only transcoding with no external URLs, network protocols, shell,
 * interactive progress or shared temp filenames.
 */
final class ListingVideoTranscoder
{
    public function transcode(string $input, string $directory): array
    {
        $this->probe($input);
        $video = $directory.'/playback.mp4';
        $poster = $directory.'/poster.jpg';
        $this->run([
            'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
            '-protocol_whitelist', 'file,pipe', '-i', $input, '-map', '0:v:0', '-map', '0:a:0?',
            '-vf', "scale=w='min(1280,iw)':h='min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
            '-threads', '1', '-filter_threads', '1',
            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '27',
            '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
            '-c:a', 'aac', '-b:a', '96k', '-ac', '2',
            '-map_metadata', '-1', '-map_chapters', '-1',
            '-t', '90', $video,
        ], 150);

        $this->run([
            'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
            '-protocol_whitelist', 'file,pipe', '-ss', '0.5', '-i', $video, '-map', '0:v:0', '-frames:v', '1',
            '-threads', '1', '-filter_threads', '1',
            '-vf', "scale=w='min(720,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease",
            '-map_metadata', '-1', '-q:v', '5', $poster,
        ], 20);

        if (! is_file($video) || ! is_file($poster)
            || filesize($video) === 0 || filesize($poster) === 0
            || filesize($video) > 50 * 1024 * 1024) {
            throw new RuntimeException('video_output_invalid');
        }
        // Report the dimensions of the actual derivative, never the original.
        $facts=$this->probe($video);
        if($facts['width']>1280 || $facts['height']>720) throw new RuntimeException('video_output_dimensions');
        return $facts + ['playback_file' => $video, 'poster_file' => $poster];
    }

    private function probe(string $input): array
    {
        $probe = new Process([
            'ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
            '-show_entries', 'format=duration:stream=codec_type,codec_name,width,height',
            '-of', 'json', $input,
        ]);
        $probe->setTimeout(20);
        $probe->run();
        if (! $probe->isSuccessful() || strlen($probe->getOutput()) > 32 * 1024) {
            throw new RuntimeException('video_probe_failed');
        }

        $json = json_decode($probe->getOutput(), true);
        if (! is_array($json)) throw new RuntimeException('invalid_video_probe_json');
        return app(ListingVideoProcessingPolicy::class)->inspect($json);
    }

    private function run(array $arguments, int $seconds): void
    {
        $process = new Process($arguments);
        $process->setTimeout($seconds);
        $process->run();
        if (! $process->isSuccessful()) {
            // Never log raw ffmpeg stderr: a file name may contain user data.
            throw new RuntimeException('video_transcoding_failed');
        }
    }
}

