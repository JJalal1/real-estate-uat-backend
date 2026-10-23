<?php

namespace Tests\Unit;

use App\Services\CloudAssetStorageService;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class PrivateResumableImageTicketTest extends TestCase
{
    public function test_ticket_is_scoped_to_private_image_and_never_returns_server_key(): void
    {
        config([
            'services.supabase_storage.enabled' => true,
            'services.supabase_storage.url' => 'https://exampleproj.supabase.co',
            'services.supabase_storage.bucket' => 'real-estate-uat',
            'services.supabase_storage.server_key' => 'secret-used-server-side-only',
            'services.supabase_storage.publishable_key' => 'sb_publishable_fake_public',
        ]);
        Http::fake(['*' => Http::response([
            'url' => '/storage/v1/object/upload/sign/real-estate-uat/private/editor-drafts/2/mock?token=short-lived-upload-token',
        ], 200)]);

        $path = 'editor-drafts/2/11111111-1111-4111-8111-111111111111/'
            .'22222222-2222-4222-8222-222222222222-'.str_repeat('a', 64).'.jpg';
        $ticket = app(CloudAssetStorageService::class)->createPrivateResumableTicket($path);

        $this->assertSame('https://exampleproj.storage.supabase.co/storage/v1/upload/resumable/sign', $ticket['endpoint']);
        $this->assertSame('real-estate-uat', $ticket['bucket']);
        $this->assertSame('sb_publishable_fake_public', $ticket['publishable_key']);
        $this->assertSame('private/'.$path, $ticket['object_name']);
        $this->assertSame('short-lived-upload-token', $ticket['signature']);
        $this->assertSame(6 * 1024 * 1024, $ticket['chunk_size']);
        $this->assertStringNotContainsString('secret-used-server-side-only', json_encode($ticket));

        Http::assertSentCount(1);
        Http::assertSent(fn ($request) =>
            $request->method() === 'POST'
            && str_contains($request->url(), '/object/upload/sign/real-estate-uat/private/editor-drafts/2/')
        );
    }

    public function test_caller_cannot_request_an_arbitrary_path(): void
    {
        config(['services.supabase_storage.enabled' => true]);
        Http::fake();
        $this->expectException(RuntimeException::class);
        app(CloudAssetStorageService::class)->createPrivateResumableTicket('../public/users/7/secrets.jpg');
    }
}
