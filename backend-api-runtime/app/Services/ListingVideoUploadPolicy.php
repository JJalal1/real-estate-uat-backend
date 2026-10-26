<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;

/**
 * Admission gate for approved listing videos (#3).
 *
 * Security: do not trust the client filename or Content-Type; check the real
 * MIME and the container signature before admitting a file to private storage.
 * A passing signature is NOT proof of a decodable/safe stream: the asynchronous
 * ffprobe/ffmpeg processing gate must still reject corrupt and oversized media.
 */
final class ListingVideoUploadPolicy
{
    public const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;

    public function assertAcceptable(UploadedFile $file): void
    {
        if (! $file->isValid() || $file->getSize() === false) {
            $this->reject('تعذر استلام ملف الفيديو. حاول مرة أخرى.');
        }

        $size = (int) $file->getSize();
        if ($size < 16 || $size > self::MAX_UPLOAD_BYTES) {
            $this->reject('حجم الفيديو غير صالح. الحد الأقصى 50 ميجابايت.');
        }

        $actualMime = (string) $file->getMimeType();
        if (! in_array($actualMime, ['video/mp4', 'video/quicktime', 'application/mp4'], true)) {
            $this->reject('صيغة الفيديو غير مدعومة. استخدم MP4 أو MOV.');
        }

        $source = $file->getRealPath();
        if (! is_string($source) || ! is_file($source)) {
            $this->reject('تعذر قراءة ملف الفيديو.');
        }

        $stream = fopen($source, 'rb');
        if ($stream === false) {
            $this->reject('تعذر قراءة ملف الفيديو.');
        }

        try {
            $header = fread($stream, 16);
        } finally {
            fclose($stream);
        }

        // ISO-BMFF / QuickTime: 32-bit box size, then "ftyp" at offset 4.
        // Keep this intentionally strict until the transcoding pipeline
        // supports and tests more container formats.
        if (! is_string($header) || strlen($header) < 16 || substr($header, 4, 4) !== 'ftyp') {
            $this->reject('ملف الفيديو لا يحتوي على ترويسة MP4/MOV صحيحة.');
        }

        $boxSize = unpack('N', substr($header, 0, 4))[1] ?? 0;
        if ($boxSize < 16 || $boxSize > $size) {
            $this->reject('ترويسة الفيديو غير صالحة.');
        }
    }

    private function reject(string $message): never
    {
        throw ValidationException::withMessages(['video' => [$message]]);
    }
}
