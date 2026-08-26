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
