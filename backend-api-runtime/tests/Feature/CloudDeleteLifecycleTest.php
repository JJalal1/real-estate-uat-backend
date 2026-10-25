<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use App\Services\ListingImageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CloudDeleteLifecycleTest extends TestCase
{
    use RefreshDatabase;

    public function test_missing_legacy_variants_do_not_prevent_deleting_live_variants_and_original(): void
    {
        $this->cloud();
        $path = 'editor-drafts/synthetic/original.jpg';
        $service = app(ListingImageService::class);
        $live = $service->variantPath($path, 'thumb');
        $objects = ['private/'.$path => 'original', 'private/'.$live => 'safe-display'];
        Http::fake(function ($request) use (&$objects) {
            if ($request->method() === 'DELETE' && $request->url() === $this->bucketUrl()) {
                $this->assertCount(1, $request['prefixes']);
                $target = $request['prefixes'][0];
                $deleted = isset($objects[$target]); unset($objects[$target]);
                return Http::response($deleted ? [['name'=>$target]] : [], 200);
            }
            // The deployed single-object API returned 400 for an absent v1
            // derivative. Reproduce that response instead of accepting any URL.
            return Http::response(['error'=>'NoSuchKey'], 400);
        });
        $service->removeIfUnused($path);
        $this->assertSame([], $objects);
        $service->removeIfUnused($path); // An acknowledged missing key is idempotent.
        Http::assertNotSent(fn ($r) => $r->method() === 'DELETE' && $r->url() !== $this->bucketUrl());
    }

    public function test_public_and_private_deletes_send_only_the_exact_requested_object(): void
    {
        $this->cloud();
        Http::fake([$this->bucketUrl()=>Http::response([],200)]);
        $storage = app(CloudAssetStorageService::class);
        $storage->deletePrivate('proofs/synthetic.jpg');
        $storage->deletePublic('professional-photos/synthetic.jpg');
        Http::assertSentCount(2);
        foreach (['private/proofs/synthetic.jpg','public/professional-photos/synthetic.jpg'] as $path) {
            Http::assertSent(fn ($r) => $r->method() === 'DELETE' && $r->url() === $this->bucketUrl()
                && $r['prefixes'] === [$path] && $r->hasHeader('apikey','sb_secret_synthetic_only'));
        }
    }

    public function test_bucket_or_authorization_errors_are_never_treated_as_successful_object_deletion(): void
    {
        $this->cloud();
        Http::fake([$this->bucketUrl()=>Http::sequence()
            ->push([],400)->push([],403)->push([],404)->push([],500)]);
        foreach ([400,403,404,500] as $status) {
            try {
                app(CloudAssetStorageService::class)->deletePrivate('proofs/synthetic.jpg');
                $this->fail('Provider error must not acknowledge deletion.');
            } catch (\RuntimeException $error) {
                $this->assertStringContainsString('HTTP '.$status, $error->getMessage());
            }
        }
        Http::assertSentCount(4);
    }

    private function cloud(): void
    {
        config(['services.supabase_storage.enabled'=>true,'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private','services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
    }

    private function bucketUrl(): string
    {
        return 'https://synthetic-storage.example/storage/v1/object/synthetic-private';
    }
}
