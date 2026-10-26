<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Str;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/** Only re-encoded public-safe JPEGs reach the advertiser-photo endpoint. */
class ProfessionalPhotoService
{
    private const PREFIX = 'professional-display/v1/';

    public function __construct(private readonly ListingImageService $images, private readonly CloudAssetStorageService $storage) {}

    public function store(UploadedFile $file, int $actorId): string
    {
        $source = file_get_contents($file->getRealPath());
        if (! is_string($source)) throw new RuntimeException('Professional photo unavailable.');
        $encoded = $this->images->sanitizedProfessionalPhoto($source);
        $path = self::PREFIX.$actorId.'/'.Str::uuid().'-'.hash('sha256',$encoded).'.jpg';
        $this->storage->writePrivate($path,$encoded,'image/jpeg');
        return $path;
    }

    /** Caller checks active approved public profile before any cached bytes. */
    public function response(string $path): Response
    {
        $headers = ['Content-Type'=>'image/jpeg','Cache-Control'=>'public, max-age=3600','X-Content-Type-Options'=>'nosniff'];
        if (str_starts_with($path,self::PREFIX)) return $this->storage->responsePrivate($path,null,$headers);
        // Historical explicitly public uploads may still contain EXIF/GPS.
        // Sanitize once on authorized access; never fall back to raw bytes.
        $target = $this->legacyDisplayPath($path);
        $cached = $this->storage->responsePrivateIfExists($target,null,$headers);
        if ($cached !== null) return $cached;
        $encoded = $this->images->sanitizedProfessionalPhoto($this->storage->readBytes($path,false));
        $this->storage->writePrivate($target,$encoded,'image/jpeg');
        return response($encoded,200,$headers);
    }

    public function remove(string $path): void
    {
        if (str_starts_with($path,self::PREFIX)) {
            $this->storage->deletePrivate($path);
            return;
        }
        $this->storage->deletePublic($path);
        $this->storage->deletePrivate($path);
        $this->storage->deletePrivate($this->legacyDisplayPath($path));
    }

    private function legacyDisplayPath(string $path): string
    {
        return self::PREFIX.'legacy/'.hash('sha256',$path).'.jpg';
    }
}
