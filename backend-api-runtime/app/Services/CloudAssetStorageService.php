<?php

namespace App\Services;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response as HttpResponse;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Symfony\Component\HttpFoundation\HeaderUtils;
use Symfony\Component\HttpFoundation\Response;

class CloudAssetStorageService
{
    public function cloudEnabled(): bool
    {
        return (bool) config('services.supabase_storage.enabled', false);
    }

    public function storePublic(UploadedFile $file, string $directory): string
    {
        return $this->store($file, $directory, false);
    }

    public function storePrivate(UploadedFile $file, string $directory): string
    {
        return $this->store($file, $directory, true);
    }

    /** Application-owned paths only; originals and safe display derivatives stay in the private bucket. */
    public function writePrivate(string $path, string $bytes, string $mime): void
    {
        if (! $this->cloudEnabled()) {
            if (! Storage::disk('local')->put($path, $bytes)) throw new RuntimeException('Image storage failed.');
            return;
        }
        $response = $this->request()->withHeaders(['x-upsert'=>'true'])->withBody($bytes, $mime)
            ->post($this->objectUrl($this->objectPath($path, true)));
        $this->assertRemoteSuccess($response, 'Image storage failed.');
    }

    /**
     * Stream an accepted video from PHP's upload temp file to private storage.
     * Unlike storePrivate(), this avoids loading a 50 MiB video into PHP memory.
     */
    public function storePrivateStreamed(UploadedFile $file, string $directory): string
    {
        $path = $file->hashName(trim($directory, '/'));
        $source = $file->getRealPath();
        if (! is_string($source) || ! is_file($source)) {
            throw new RuntimeException('Video source is unavailable.');
        }

        $this->writePrivateFromFile($path, $source, (string) $file->getMimeType());
        return $path;
    }

    /**
     * Use resource-backed requests and filesystem streams. Called by the
     * isolated video processing job for private derivative uploads too.
     */
    public function writePrivateFromFile(string $path, string $source, string $mime): void
    {
        if (! is_file($source)) throw new RuntimeException('Private media source is missing.');
        $stream = fopen($source, 'rb');
        if ($stream === false) throw new RuntimeException('Cannot open private media source.');
        try {
            if (! $this->cloudEnabled()) {
                if (! Storage::disk('local')->put($path, $stream)) {
                    throw new RuntimeException('Private media write failed.');
                }
                return;
            }

            $response = $this->request()
                ->withHeaders(['x-upsert' => 'false'])
                ->withBody($stream, $mime)
                ->post($this->objectUrl($this->objectPath($path, true)));
            $this->assertRemoteSuccess($response, 'Private media upload failed.');
        } finally {
            fclose($stream);
        }
    }

    /** Download private media to a sandboxed temporary file without buffering. */
    public function downloadPrivateToPath(string $path, string $target): void
    {
        if (! $this->cloudEnabled()) {
            $input = Storage::disk('local')->readStream($path);
            if (! is_resource($input)) throw new RuntimeException('Private media is unavailable.');
            $output = fopen($target, 'wb');
            if ($output === false) {
                fclose($input);
                throw new RuntimeException('Temporary media file is unavailable.');
            }
            try {
                if (stream_copy_to_stream($input, $output) === false) {
                    throw new RuntimeException('Private media download failed.');
                }
            } finally {
                fclose($input);
                fclose($output);
            }
            return;
        }

        $response = $this->request()
            ->withOptions(['sink' => $target])
            ->get($this->privateAuthenticatedGetUrl($path));
        $this->assertRemoteSuccess($response, 'Private media download failed.');
    }

    /** Bounded partial read; never fetch the entire video to satisfy a seek. */
    public function readPrivateRange(string $path, int $start, int $end): string
    {
        if ($start < 0 || $end < $start || $end - $start >= 2 * 1024 * 1024) {
            throw new RuntimeException('Invalid private media range.');
        }

        if (! $this->cloudEnabled()) {
            $stream = Storage::disk('local')->readStream($path);
            if (! is_resource($stream)) throw new RuntimeException('Private media unavailable.');
            try {
                if (fseek($stream, $start) !== 0) throw new RuntimeException('Private media seek failed.');
                $bytes = stream_get_contents($stream, $end - $start + 1);
                if (! is_string($bytes) || strlen($bytes) !== $end - $start + 1) {
                    throw new RuntimeException('Private media range incomplete.');
                }
                return $bytes;
            } finally {
                fclose($stream);
            }
        }

        $response = $this->request()
            ->withHeaders(['Range' => 'bytes='.$start.'-'.$end])
            ->get($this->privateAuthenticatedGetUrl($path));
        if ($response->status() !== 206) {
            throw new RuntimeException('Private storage did not honor byte range.');
        }
        if (! str_starts_with((string) $response->header('Content-Range'), 'bytes '.$start.'-'.$end.'/')) {
            throw new RuntimeException('Private storage returned unexpected range.');
        }
        $bytes = $response->body();
        if (strlen($bytes) !== $end - $start + 1) {
            throw new RuntimeException('Private media range incomplete.');
        }
        return $bytes;
    }

    /** Video posters are private derivatives; use Supabase's authenticated download endpoint. */
    public function responsePrivateVideoPoster(string $path): Response
    {
        $headers = [
            'Content-Type' => 'image/jpeg',
            'Cache-Control' => 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ];
        if (! $this->cloudEnabled()) {
            return Storage::disk('local')->response($path, null, $headers);
        }
        $remote = $this->request()->get($this->privateAuthenticatedGetUrl($path));
        if (in_array($remote->status(), [400, 404], true)) abort(404);
        $this->assertRemoteSuccess($remote, 'Private video poster unavailable.');
        if (strlen($remote->body()) > 8 * 1024 * 1024) {
            throw new RuntimeException('Private video poster exceeds maximum safe response size.');
        }
        return response($remote->body(), 200, $headers);
    }

    /**
     * A safe synthetic canary for the real private UAT bucket. It never reads,
     * modifies, or logs any user media or server key. Clean up even on error.
     */
    public function probePrivateVideoStorage(): void
    {
        if (! $this->cloudEnabled()) throw new RuntimeException('Cloud storage is disabled.');
        $path = 'uat-health/video-range-'.bin2hex(random_bytes(14)).'.bin';
        $source = tempnam(sys_get_temp_dir(), 'aqer-private-probe-');
        $download = tempnam(sys_get_temp_dir(), 'aqer-private-download-');
        if (! is_string($source) || ! is_string($download)) {
            if (is_string($source)) @unlink($source);
            if (is_string($download)) @unlink($download);
            throw new RuntimeException('Private video probe temporary files unavailable.');
        }
        $bytes = 'aqer-private-video-range-'.bin2hex(random_bytes(30));
        $uploaded = false;
        try {
            if (file_put_contents($source, $bytes) !== strlen($bytes)) {
                throw new RuntimeException('Private video probe write failed.');
            }
            $this->writePrivateFromFile($path, $source, 'application/octet-stream');
            $uploaded = true;
            if ($this->readPrivateRange($path, 5, 15) !== substr($bytes, 5, 11)) {
                throw new RuntimeException('Private video probe range mismatch.');
            }
            $this->downloadPrivateToPath($path, $download);
            if (hash_file('sha256', $download) !== hash('sha256', $bytes)) {
                throw new RuntimeException('Private video probe download mismatch.');
            }
        } finally {
            // A timed-out upload could succeed server-side after a client error,
            // so attempt best-effort deletion even if $uploaded is false.
            try { $this->deletePrivate($path); } catch (\Throwable) {}
            @unlink($source);
            @unlink($download);
        }
    }

    /**
     * Disposable UAT-only signed TUS protocol canary. Unlike the existing
     * private storage probe it verifies the *unprivileged*, signed TUS flow:
     * rejected invalid signature, POST creation, 6 MiB PATCH, HEAD resume,
     * final PATCH, authenticated byte verification, and cleanup.
     *
     * Deliberately does not interact with listing data or DB migrations.
     */
    public function probePrivateSignedTusStorage(): void
    {
        if (! $this->cloudEnabled() || ! app()->environment('staging')) {
            throw new RuntimeException('Signed TUS probe requires private Cloud UAT.');
        }

        $logicalPath = 'uat-health/tus-'.bin2hex(random_bytes(14)).'.bin';
        $objectPath = $this->objectPath($logicalPath, true);
        $bucket = $this->bucket();

        $rawHost = (string) parse_url((string) config('services.supabase_storage.url'), PHP_URL_HOST);
        if (! preg_match('/^([a-z0-9-]+)\\.supabase\\.co$/D', $rawHost, $matches)) {
            throw new RuntimeException('Signed TUS UAT probe requires a verified Supabase project host.');
        }
        $origin = 'https://'.$matches[1].'.storage.supabase.co';
        $endpoint = $origin.'/storage/v1/upload/resumable';

        $chunk = str_repeat('A', 6 * 1024 * 1024);
        $tail = 'aqer-uat-tus-tail-'.bin2hex(random_bytes(14));
        $total = strlen($chunk) + strlen($tail);
        $hash = hash_init('sha256');
        hash_update($hash, $chunk);
        hash_update($hash, $tail);
        $expectedHash = hash_final($hash);
        $metadata = implode(',', [
            'bucketName '.base64_encode($bucket),
            'objectName '.base64_encode($objectPath),
            'contentType '.base64_encode('application/octet-stream'),
            'cacheControl '.base64_encode('0'),
        ]);

        $cleaned = false;
        try {
            $sign = $this->request()->post(
                $this->storageBaseUrl().'/object/upload/sign/'
                    .rawurlencode($bucket).'/'.$this->encodePath($objectPath),
                (object) [],
            );
            $this->assertRemoteSuccess($sign, 'Signed TUS authorization failed.');

            // Storage SDKs return both token and a path with ?token=...;
            // neither value is ever emitted into application logs.
            $signature = $sign->json('token');
            if (! is_string($signature) || $signature === '') {
                $signedUrl = $sign->json('url');
                if (! is_string($signedUrl)) {
                    throw new RuntimeException('Signed TUS authorization returned no token.');
                }
                parse_str((string) parse_url($signedUrl, PHP_URL_QUERY), $parameters);
                $signature = $parameters['token'] ?? null;
            }
            if (! is_string($signature) || $signature === '') {
                throw new RuntimeException('Signed TUS authorization returned no token.');
            }

            $createHeaders = [
                'Tus-Resumable' => '1.0.0',
                'Upload-Length' => (string) $total,
                'Upload-Metadata' => $metadata,
            ];
            $connect = fn (array $headers) => Http::withHeaders($headers)
                ->connectTimeout(15)->timeout(90)
                ->withOptions(['allow_redirects' => false]);

            // A forged signature MUST be denied, even on the private bucket.
            $denied = $connect($createHeaders + ['x-signature' => 'invalid-uat-canary'])
                ->withBody('', 'application/offset+octet-stream')->post($endpoint);
            if ($denied->status() < 400 || $denied->status() >= 500) {
                throw new RuntimeException('Signed TUS rejected-token security probe failed.');
            }

            $created = $connect($createHeaders + ['x-signature' => $signature])
                ->withBody('', 'application/offset+octet-stream')->post($endpoint);
            if ($created->status() !== 201) {
                throw new RuntimeException('Signed TUS creation did not return HTTP 201.');
            }
            $location = $created->header('Location');
            if (! is_string($location) || $location === '') {
                throw new RuntimeException('Signed TUS creation supplied no session location.');
            }

            if (str_starts_with($location, '/storage/v1/upload/resumable/')) {
                $sessionUrl = $origin.$location;
            } else {
                $sessionUrl = $location;
            }
            if (! str_starts_with($sessionUrl, $origin.'/storage/v1/upload/resumable/')
                || parse_url($sessionUrl, PHP_URL_QUERY) !== null
                || parse_url($sessionUrl, PHP_URL_FRAGMENT) !== null) {
                throw new RuntimeException('Signed TUS session changed origin or path.');
            }

            $tusHeaders = ['Tus-Resumable' => '1.0.0', 'x-signature' => $signature];
            $first = $connect($tusHeaders + ['Upload-Offset' => '0'])
                ->withBody($chunk, 'application/offset+octet-stream')->patch($sessionUrl);
            if ($first->status() !== 204 || $first->header('Upload-Offset') !== (string) strlen($chunk)) {
                throw new RuntimeException('Signed TUS initial chunk was not acknowledged.');
            }
            // Model interruption between chunks: the second request must use
            // the server's HEAD result, not the client's remembered count.
            $head = $connect($tusHeaders)->head($sessionUrl);
            if (! $head->successful() || $head->header('Upload-Offset') !== (string) strlen($chunk)) {
                throw new RuntimeException('Signed TUS HEAD did not preserve offset.');
            }
            $last = $connect($tusHeaders + ['Upload-Offset' => $head->header('Upload-Offset')])
                ->withBody($tail, 'application/offset+octet-stream')->patch($sessionUrl);
            if ($last->status() !== 204 || $last->header('Upload-Offset') !== (string) $total) {
                throw new RuntimeException('Signed TUS resumed chunk was not acknowledged.');
            }

            $download = $this->request()->get($this->privateAuthenticatedGetUrl($logicalPath));
            $this->assertRemoteSuccess($download, 'Signed TUS private verification failed.');
            $result = $download->body();
            if (strlen($result) !== $total || hash('sha256', $result) !== $expectedHash) {
                throw new RuntimeException('Signed TUS private bytes mismatch.');
            }
        } finally {
            // A failed PATCH can still commit server-side. Delete even when
            // we did not receive a completion acknowledgement.
            try {
                $this->deletePrivate($logicalPath);
                $cleaned = true;
            } catch (\\Throwable) {
                throw new RuntimeException('Signed TUS canary cleanup failed.');
            }
        }

        if (! $cleaned) throw new RuntimeException('Signed TUS canary did not clean up.');
    }

    public function readBytes(string $path, bool $private): string
    {
        if (! $this->cloudEnabled()) {
            $bytes = Storage::disk($private ? 'local' : 'public')->get($path);
            if (! is_string($bytes)) throw new RuntimeException('Image unavailable.');
            return $bytes;
        }
        $response = $this->request()->get($this->objectUrl($this->objectPath($path, $private)));
        $this->assertRemoteSuccess($response, 'Image unavailable.');
        return $response->body();
    }

    public function existsPublic(string $path): bool
    {
        return $this->exists($path, false);
    }

    public function existsPrivate(string $path): bool
    {
        return $this->exists($path, true);
    }

    public function deletePublic(string $path): void
    {
        $this->delete($path, false);
    }

    public function deletePrivate(string $path): void
    {
        $this->delete($path, true);
    }

    public function responsePublic(string $path, ?string $downloadName = null, array $headers = []): Response
    {
        return $this->response($path, false, $downloadName, $headers);
    }

    public function responsePrivate(string $path, ?string $downloadName = null, array $headers = []): Response
    {
        return $this->response($path, true, $downloadName, $headers);
    }

    public function downloadPrivate(string $path, string $downloadName, array $headers = []): Response
    {
        if (! $this->cloudEnabled()) {
            return Storage::disk('local')->download($path, $downloadName, $headers);
        }

        return $this->response($path, true, $downloadName, $headers);
    }

    /**
     * Verify upload, read and delete against the configured UAT bucket without
     * disclosing the server key or object contents to logs.
     */
    public function probe(): void
    {
        if (! $this->cloudEnabled()) {
            throw new RuntimeException('Cloud asset storage is not enabled.');
        }

        $logicalPath = 'uat-health/'.bin2hex(random_bytes(8)).'.txt';
        $objectPath = $this->objectPath($logicalPath, false);
        $payload = 'real-estate-uat-storage-probe';

        $upload = $this->request()
            ->withHeaders(['x-upsert' => 'false'])
            ->withBody($payload, 'text/plain')
            ->post($this->objectUrl($objectPath));
        $this->assertRemoteSuccess($upload, 'Storage write probe failed.');

        try {
            $read = $this->request()->get($this->objectUrl($objectPath));
            $this->assertRemoteSuccess($read, 'Storage read probe failed.');
            if ($read->body() !== $payload) {
                throw new RuntimeException('Storage read probe returned unexpected content.');
            }
        } finally {
            $this->deleteRemoteObject($objectPath);
        }
    }

    private function store(UploadedFile $file, string $directory, bool $private): string
    {
        if (! $this->cloudEnabled()) {
            $disk = $private ? 'local' : 'public';
            $path = $file->store($directory, $disk);
            if (! is_string($path) || $path === '') {
                throw new RuntimeException('The uploaded file could not be stored.');
            }

            return $path;
        }

        $logicalPath = $file->hashName(trim($directory, '/'));
        $source = $file->getRealPath();
        if (! is_string($source) || $source === '' || ! is_file($source)) {
            throw new RuntimeException('The uploaded file is unavailable for cloud storage.');
        }

        $body = file_get_contents($source);
        if ($body === false) {
            throw new RuntimeException('The uploaded file could not be read for cloud storage.');
        }

        $mime = $file->getMimeType() ?: 'application/octet-stream';
        $response = $this->request()
            ->withHeaders(['x-upsert' => 'false'])
            ->withBody($body, $mime)
            ->post($this->objectUrl($this->objectPath($logicalPath, $private)));

        $this->assertRemoteSuccess($response, 'Cloud storage upload failed.');

        return $logicalPath;
    }

    private function exists(string $path, bool $private): bool
    {
        if (! $this->cloudEnabled()) {
            return Storage::disk($private ? 'local' : 'public')->exists($path);
        }

        $response = $this->request()->get($this->objectUrl($this->objectPath($path, $private)));
        if ($response->successful()) {
            return true;
        }
        if (in_array($response->status(), [400, 404], true)) {
            return false;
        }

        throw new RuntimeException('Cloud storage availability check failed with HTTP '.$response->status().'.');
    }

    private function delete(string $path, bool $private): void
    {
        if (! $this->cloudEnabled()) {
            Storage::disk($private ? 'local' : 'public')->delete($path);
            return;
        }

        $this->deleteRemoteObject($this->objectPath($path, $private));
    }

    private function response(string $path, bool $private, ?string $downloadName, array $headers): Response
    {
        if (! $this->cloudEnabled()) {
            return Storage::disk($private ? 'local' : 'public')->response($path, $downloadName, $headers);
        }

        $remote = $this->request()->get($this->objectUrl($this->objectPath($path, $private)));
        if (in_array($remote->status(), [400, 404], true)) {
            abort(404);
        }
        $this->assertRemoteSuccess($remote, 'Cloud storage download failed.');

        $headers['Content-Type'] = $remote->header('Content-Type') ?: 'application/octet-stream';
        if ($downloadName !== null && $downloadName !== '') {
            $headers['Content-Disposition'] = HeaderUtils::makeDisposition(
                HeaderUtils::DISPOSITION_ATTACHMENT,
                basename($downloadName),
            );
        }

        return response($remote->body(), 200, $headers);
    }

    private function deleteRemoteObject(string $objectPath): void
    {
        $response = $this->request()->delete($this->objectUrl($objectPath));
        if ($response->successful() || $response->status() === 404) {
            return;
        }

        throw new RuntimeException('Cloud storage delete failed with HTTP '.$response->status().'.');
    }

    private function request(): PendingRequest
    {
        $key = trim((string) config('services.supabase_storage.server_key'));
        if ($key === '') {
            throw new RuntimeException('SUPABASE_STORAGE_SERVER_KEY is not configured.');
        }

        $headers = [
            'apikey' => $key,
            'Accept' => '*/*',
            'User-Agent' => 'real-estate-uat-backend/1.0',
        ];

        // New sb_secret_* keys are opaque and must be sent in the apikey header.
        // Legacy service_role keys are JWTs; Storage accepts them as a Bearer token.
        if (! str_starts_with($key, 'sb_secret_')) {
            $headers['Authorization'] = 'Bearer '.$key;
        }

        return Http::withHeaders($headers)
            ->connectTimeout((int) config('services.supabase_storage.connect_timeout', 15))
            ->timeout((int) config('services.supabase_storage.timeout', 90));
    }

    private function objectPath(string $logicalPath, bool $private): string
    {
        $prefix = $private
            ? (string) config('services.supabase_storage.private_prefix', 'private')
            : (string) config('services.supabase_storage.public_prefix', 'public');

        return trim($prefix, '/').'/'.ltrim($logicalPath, '/');
    }

    /** Private GET differs from the POST /object/{bucket}/{path} upload API. */
    private function privateAuthenticatedGetUrl(string $path): string
    {
        return $this->storageBaseUrl().'/object/authenticated/'
            .rawurlencode($this->bucket()).'/'.$this->encodePath($this->objectPath($path, true));
    }

    private function objectUrl(string $objectPath): string
    {
        return $this->storageBaseUrl().'/object/'.rawurlencode($this->bucket()).'/'.$this->encodePath($objectPath);
    }

    private function storageBaseUrl(): string
    {
        $url = rtrim(trim((string) config('services.supabase_storage.url')), '/');
        if ($url === '' || ! str_starts_with($url, 'https://')) {
            throw new RuntimeException('SUPABASE_URL must be a public HTTPS URL.');
        }

        return $url.'/storage/v1';
    }

    private function bucket(): string
    {
        $bucket = trim((string) config('services.supabase_storage.bucket'));
        if ($bucket === '') {
            throw new RuntimeException('SUPABASE_STORAGE_BUCKET is not configured.');
        }

        return $bucket;
    }

    private function encodePath(string $path): string
    {
        return implode('/', array_map('rawurlencode', explode('/', trim($path, '/'))));
    }

    private function assertRemoteSuccess(HttpResponse $response, string $message): void
    {
        if (! $response->successful()) {
            throw new RuntimeException($message.' HTTP '.$response->status().'.');
        }
    }
}
