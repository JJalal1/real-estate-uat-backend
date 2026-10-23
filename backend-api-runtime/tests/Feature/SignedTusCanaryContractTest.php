<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class SignedTusCanaryContractTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->app['env'] = 'staging';
        config([
            'services.supabase_storage.enabled' => true,
            'services.supabase_storage.url' => 'https://sampleproj.supabase.co',
            'services.supabase_storage.bucket' => 'real-estate-uat',
            'services.supabase_storage.server_key' => 'private-server-only-test-key',
            'services.supabase_storage.publishable_key' => 'sb_publishable_testonly',
        ]);
    }

    public function test_signed_tus_uses_provider_sign_route_and_resumes_exact_bytes(): void
    {
        $offset = 0;
        $received = '';
        $requests = [];
        Http::fake(function (Request $request) use (&$offset, &$received, &$requests) {
            $url = $request->url();
            $requests[] = [$request->method(), $url];
            if (str_contains($url, '/object/upload/sign/')) {
                return Http::response(['token' => 'one-object-signature'], 200);
            }
            if ($request->method() === 'POST' && str_ends_with($url, '/upload/resumable/sign')) {
                if ($request->hasHeader('x-signature', 'invalid-uat-canary')) {
                    return Http::response('', 403);
                }
                $this->assertTrue($request->hasHeader('x-signature', 'one-object-signature'));
                $this->assertTrue($request->hasHeader('apikey', 'sb_publishable_testonly'));
                $this->assertFalse($request->hasHeader('apikey', 'private-server-only-test-key'));
                return Http::response('', 201, ['Location' => '/storage/v1/upload/resumable/test-session']);
            }
            if (str_contains($url, '/upload/resumable/test-session')) {
                if ($request->method() === 'HEAD') {
                    return Http::response('', 200, ['Upload-Offset' => (string) $offset]);
                }
                if ($request->method() === 'PATCH') {
                    $this->assertSame((string) $offset, $request->header('Upload-Offset')[0] ?? null);
                    $received .= $request->body();
                    $offset = strlen($received);
                    return Http::response('', 204, ['Upload-Offset' => (string) $offset]);
                }
            }
            if ($request->method() === 'GET' && str_contains($url, '/object/authenticated/')) {
                return Http::response($received, 200, ['Content-Type' => 'application/octet-stream']);
            }
            if ($request->method() === 'DELETE' && str_contains($url, '/object/')) {
                return Http::response('', 200);
            }
            return Http::response('', 599);
        });

        app(CloudAssetStorageService::class)->probePrivateSignedTusStorage();
        $this->assertGreaterThan(6 * 1024 * 1024, $offset);
        $this->assertSame('A', $received[0]);
        $this->assertStringContainsString('aqer-uat-tus-tail-', substr($received, -75));
        $this->assertTrue(collect($requests)->contains(fn (array $r) =>
            $r[0] === 'POST' && str_ends_with($r[1], '/upload/resumable/sign')));
        $this->assertTrue(collect($requests)->contains(fn (array $r) => $r[0] === 'HEAD'));
        $this->assertTrue(collect($requests)->contains(fn (array $r) => $r[0] === 'DELETE'));
    }

    public function test_failed_creation_is_not_masked_by_secondary_cleanup_error(): void
    {
        Http::fake(function (Request $request) {
            $url = $request->url();
            if (str_contains($url, '/object/upload/sign/')) {
                return Http::response(['token' => 'one-object-signature'], 200);
            }
            if ($request->method() === 'POST' && str_ends_with($url, '/upload/resumable/sign')) {
                return $request->hasHeader('x-signature', 'invalid-uat-canary')
                    ? Http::response('', 403) : Http::response('', 422);
            }
            if ($request->method() === 'DELETE') {
                return Http::response('', 400);
            }
            return Http::response('', 599);
        });
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('Signed TUS creation returned HTTP 422');
        app(CloudAssetStorageService::class)->probePrivateSignedTusStorage();
    }
}
