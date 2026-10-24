<?php

namespace App\Services;

use App\Models\ListingEditorDraft;
use App\Models\PropertyImage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use RuntimeException;

/** The database still stores the original path. Only freshly encoded, metadata-free variants are served. */
class ListingImageService
{
    public function __construct(private readonly CloudAssetStorageService $storage) {}

    public static function isPrivate(string $path): bool
    {
        return str_starts_with($path, 'editor-drafts/') || str_starts_with($path, 'listing-originals/');
    }

    public function store(UploadedFile $file, string $directory, ?string $key = null): string
    {
        $bytes = file_get_contents($file->getRealPath());
        if (! is_string($bytes)) throw new RuntimeException('Image unavailable.');
        $info = $this->inspect($bytes);
        $extension = [IMAGETYPE_JPEG=>'jpg', IMAGETYPE_PNG=>'png', IMAGETYPE_WEBP=>'webp'][$info[2]];
        $path = trim($directory, '/').'/'.($key ?? (string) Str::uuid()).'-'.hash('sha256', $bytes).'.'.$extension;
        // Encode/validate before touching storage. The original is not recompressed or publicly served.
        $variants = $this->encode($bytes, $info);
        try {
            $this->storage->writePrivate($path, $bytes, $info['mime']);
            foreach ($variants as $variant=>$encoded) $this->storage->writePrivate($this->variantPath($path, $variant), $encoded, 'image/jpeg');
        } catch (\Throwable $error) {
            // Deterministic paths allow an interrupted retry to reuse the same objects safely.
            $this->removeIfUnused($path);
            throw $error;
        }
        return $path;
    }

    public function matches(UploadedFile $file, string $path): bool
    {
        if (preg_match('/-([a-f0-9]{64})\.(?:jpg|png|webp)$/D', $path, $match)) return hash_equals($match[1], hash_file('sha256', $file->getRealPath()));
        // Old image keys predate content fingerprints. Preserve their existing retry behavior.
        return true;
    }

    public function variantPath(string $path, string $variant): string
    {
        abort_unless(array_key_exists($variant, config('listing_media.variants')), 422, 'نسخة الصورة غير صالحة.');
        return 'listing-display/'.app(ListingWatermarkService::class)->version().'/'.hash('sha256', $path).'/'.$variant.'.jpg';
    }

    public function response(string $path, string $variant, bool $published = false)
    {
        $target = $this->variantPath($path, $variant);
        $headers = [
            'Content-Type'=>'image/jpeg', 'X-Content-Type-Options'=>'nosniff',
            'Cache-Control'=>$published ? 'public, max-age=86400' : 'private, no-store',
            'X-Aqer-Image-Variant'=>$variant,
        ];
        if ($published) {
            $headers['ETag'] = '"'.hash('sha256', $target.json_encode(config('listing_media.variants.'.$variant))).'"';
            if (request()->header('If-None-Match') === $headers['ETag']) {
                return response('', 304, $headers);
            }
        }
        $cached = $this->storage->responsePrivateIfExists($target, null, $headers);
        if ($cached !== null) return $cached;
        // Compatibility for historical internal images: sanitize on demand, never return the raw original.
        $bytes = $this->storage->readBytes($path, self::isPrivate($path));
        foreach ($this->encode($bytes, $this->inspect($bytes), [$variant]) as $name=>$encoded) {
            $this->storage->writePrivate($this->variantPath($path, $name), $encoded, 'image/jpeg');
        }
        return $this->storage->responsePrivate($target, null, $headers);
    }

    public function removeIfUnused(string $path): void
    {
        if (PropertyImage::query()->where('path', $path)->exists()) return;
        foreach (ListingEditorDraft::query()->select(['id','images'])->cursor() as $draft) {
            if (in_array($path, array_values($draft->images ?? []), true)) return;
        }
        // Cleanup is best effort after the database operation; storage failure cannot undo a confirmed save.
        try {
            // A flag change must not strand derivatives from before activation or rollback.
            $versions = ['v1'];
            $approved = (string) config('listing_media.watermark.approved_sha256');
            if (preg_match('/^[a-f0-9]{64}$/D', $approved)) $versions[] = 'v2-wm-'.substr($approved, 0, 20);
            foreach ($versions as $version) foreach (array_keys(config('listing_media.variants')) as $variant) {
                $this->storage->deletePrivate('listing-display/'.$version.'/'.hash('sha256', $path).'/'.$variant.'.jpg');
            }
            if (self::isPrivate($path)) $this->storage->deletePrivate($path); else $this->storage->deletePublic($path);
        } catch (\Throwable $error) { report($error); }
    }

    private function inspect(string $bytes): array
    {
        $info = @getimagesizefromstring($bytes);
        if (strlen($bytes) > config('listing_media.max_bytes') || !is_array($info) ||
            !in_array($info[2], [IMAGETYPE_JPEG,IMAGETYPE_PNG,IMAGETYPE_WEBP], true) ||
            $info[0] < 1 || $info[1] < 1 || max($info[0],$info[1]) > config('listing_media.max_side') ||
            $info[0] * $info[1] > config('listing_media.max_pixels')) {
            throw ValidationException::withMessages(['image'=>['استخدم صورة JPG أو PNG أو WebP حتى 8 ميجابايت و24 مليون بكسل.']]);
        }
        return $info;
    }

    private function encode(string $bytes, array $info, ?array $only = null): array
    {
        $image = @imagecreatefromstring($bytes);
        if (!$image) throw ValidationException::withMessages(['image'=>['تعذر قراءة الصورة. اختر صورة أخرى.']]);
        try {
            $orientation = $info[2] === IMAGETYPE_JPEG ? $this->orientation($bytes) : 1;
            if (in_array($orientation,[2,4,5,7],true)) imageflip($image, $orientation === 4 ? IMG_FLIP_VERTICAL : IMG_FLIP_HORIZONTAL);
            $angle = [3=>180,5=>90,6=>270,7=>270,8=>90][$orientation] ?? 0;
            if ($angle) { $rotated = imagerotate($image, $angle, 0); imagedestroy($image); $image = $rotated; }
            $width = imagesx($image); $height = imagesy($image); $result = [];
            foreach (config('listing_media.variants') as $variant=>[$edge,$quality]) {
                if ($only !== null && ! in_array($variant, $only, true)) continue;
                $scale = min(1, $edge / max($width,$height));
                $w = max(1,(int)round($width*$scale)); $h = max(1,(int)round($height*$scale));
                $output = imagecreatetruecolor($w,$h);
                try {
                    // Opaque sRGB display JPEGs; transparent sources are composited onto white.
                    imagefill($output,0,0,imagecolorallocate($output,255,255,255));
                    imagecopyresampled($output,$image,0,0,0,0,$w,$h,$width,$height);
                    app(ListingWatermarkService::class)->apply($output);
                    ob_start();
                    try { if (!imagejpeg($output,null,$quality)) throw new RuntimeException('Image encoding failed.'); $result[$variant]=ob_get_contents(); }
                    finally { ob_end_clean(); }
                } finally { imagedestroy($output); }
            }
            return $result;
        } finally { imagedestroy($image); }
    }

    private function orientation(string $bytes): int
    {
        // PHP's bundled EXIF reader inspects a private temporary stream, never an uploaded URL.
        $file = tmpfile();
        if (!$file) throw new RuntimeException('Image processing unavailable.');
        try {
            fwrite($file,$bytes); $path=stream_get_meta_data($file)['uri'];
            $exif = function_exists('exif_read_data') ? @exif_read_data($path,'IFD0',true,false) : false;
            return (int)($exif['IFD0']['Orientation'] ?? 1);
        } finally { fclose($file); }
    }
}
