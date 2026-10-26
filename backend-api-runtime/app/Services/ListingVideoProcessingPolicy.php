<?php

namespace App\Services;

use RuntimeException;

/**
 * Strict server-side media metadata gate after ffprobe. Header admission is
 * insufficient: only a successful probe with bounded video may be processed.
 */
final class ListingVideoProcessingPolicy
{
    public const MAX_SECONDS = 90;
    public const MAX_WIDTH = 3840;
    public const MAX_HEIGHT = 2160;
    public const MAX_PIXELS = 3840 * 2160;

    /** @return array{duration_ms:int,width:int,height:int} */
    public function inspect(array $probe): array
    {
        $format = $probe['format'] ?? null;
        $streams = $probe['streams'] ?? null;
        if (! is_array($format) || ! is_array($streams)) {
            throw new RuntimeException('invalid_video_probe');
        }

        $videos = array_values(array_filter($streams, fn ($s) =>
            is_array($s) && ($s['codec_type'] ?? null) === 'video'
        ));

        if (count($videos) !== 1 || count($streams) > 5) {
            throw new RuntimeException('unsupported_video_streams');
        }

        $stream = $videos[0];
        $codec = (string) ($stream['codec_name'] ?? '');
        if (! in_array($codec, ['h264', 'hevc', 'mpeg4'], true)) {
            throw new RuntimeException('unsupported_video_codec');
        }

        $width = filter_var($stream['width'] ?? null, FILTER_VALIDATE_INT);
        $height = filter_var($stream['height'] ?? null, FILTER_VALIDATE_INT);
        if ($width === false || $height === false || $width < 16 || $height < 16
            || $width > self::MAX_WIDTH || $height > self::MAX_HEIGHT
            || $width * $height > self::MAX_PIXELS) {
            throw new RuntimeException('invalid_video_dimensions');
        }

        $seconds = $format['duration'] ?? null;
        if (! is_scalar($seconds) || ! is_numeric($seconds)) {
            throw new RuntimeException('missing_video_duration');
        }
        $duration = (float) $seconds;
        if (! is_finite($duration) || $duration < 0.25 || $duration > self::MAX_SECONDS) {
            throw new RuntimeException('invalid_video_duration');
        }

        foreach ($streams as $other) {
            if (! is_array($other)) throw new RuntimeException('invalid_video_stream');
            $kind = (string) ($other['codec_type'] ?? '');
            if (! in_array($kind, ['video', 'audio'], true)) {
                throw new RuntimeException('unsupported_video_stream');
            }
            if ($kind === 'audio' && ! in_array((string) ($other['codec_name'] ?? ''), ['aac', 'mp3', 'pcm_s16le'], true)) {
                throw new RuntimeException('unsupported_audio_codec');
            }
        }

        return [
            'duration_ms' => (int) round($duration * 1000),
            'width' => $width,
            'height' => $height,
        ];
    }
}

