<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UatCloudBackendApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_health_contract_includes_database_and_postgis_state(): void
    {
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('database', true)
            ->assertJsonPath('postgis', true);
    }

    public function test_cloud_asset_storage_keeps_local_fallback_for_development(): void
    {
        Config::set('services.supabase_storage.enabled', false);
        Storage::fake('public');

        $service = app(CloudAssetStorageService::class);
        $file = UploadedFile::fake()->create('property.jpg', 4, 'image/jpeg');
        $path = $service->storePublic($file, 'properties/77');

        $this->assertStringStartsWith('properties/77/', $path);
        $this->assertTrue($service->existsPublic($path));
        $service->deletePublic($path);
        $this->assertFalse($service->existsPublic($path));
    }

    public function test_supabase_new_secret_key_is_server_only_and_uses_storage_rest_api(): void
    {
        Config::set('services.supabase_storage', [
            'enabled' => true,
            'url' => 'https://example.supabase.co',
            'server_key' => 'sb_secret_test_server_only',
            'bucket' => 'real-estate-uat',
            'public_prefix' => 'public',
            'private_prefix' => 'private',
            'connect_timeout' => 5,
            'timeout' => 30,
        ]);
        Http::fake([
            'https://example.supabase.co/*' => Http::response(['Key' => 'ok'], 200),
        ]);

        $service = app(CloudAssetStorageService::class);
        $file = UploadedFile::fake()->create('id-front.jpg', 4, 'image/jpeg');
        $path = $service->storePrivate($file, 'broker_kyc/42');
        $this->assertStringStartsWith('broker_kyc/42/', $path);
        $service->deletePrivate($path);

        Http::assertSent(function (HttpRequest $request): bool {
            return $request->method() === 'POST'
                && str_contains($request->url(), '/storage/v1/object/real-estate-uat/private/broker_kyc/42/')
                && $request->hasHeader('apikey', 'sb_secret_test_server_only')
                && ! $request->hasHeader('Authorization');
        });
        Http::assertSent(function (HttpRequest $request): bool {
            return $request->method() === 'DELETE'
                && str_contains($request->url(), '/storage/v1/object/real-estate-uat/private/broker_kyc/42/')
                && $request->hasHeader('apikey', 'sb_secret_test_server_only');
        });
    }

    public function test_property_and_broker_uploads_use_the_cloud_storage_abstraction(): void
    {
        $property = (string) file_get_contents(app_path('Http/Controllers/Api/PropertyController.php'));
        $broker = (string) file_get_contents(app_path('Http/Controllers/Api/BrokerAccountVerificationController.php'));
        $review = (string) file_get_contents(app_path('Http/Controllers/Api/ListingReviewController.php'));

        $this->assertStringContainsString('CloudAssetStorageService', $property);
        $this->assertStringContainsString('storePublic', $property);
        $this->assertStringContainsString('storePrivate', $property);
        $this->assertStringContainsString('responsePublic', $property);
        $this->assertStringNotContainsString("Storage::disk('public')", $property);
        $this->assertStringNotContainsString("Storage::disk('local')", $property);

        $this->assertStringContainsString('CloudAssetStorageService', $broker);
        $this->assertStringContainsString('storePrivate', $broker);
        $this->assertStringContainsString('responsePrivate', $broker);
        $this->assertStringNotContainsString("Storage::disk('local')", $broker);

        $this->assertStringContainsString('CloudAssetStorageService', $review);
        $this->assertStringContainsString('existsPrivate', $review);
        $this->assertStringContainsString('downloadPrivate', $review);
        $this->assertStringNotContainsString("Storage::disk('local')", $review);
    }

    public function test_render_blueprint_and_docker_context_are_secret_free_templates(): void
    {
        $render = (string) file_get_contents(base_path('../render.yaml'));
        $dockerignore = (string) file_get_contents(base_path('.dockerignore'));
        $entrypoint = (string) file_get_contents(base_path('docker/uat-entrypoint.sh'));

        foreach (['SUPABASE_STORAGE_SERVER_KEY', 'DB_URL', 'APP_KEY', 'UAT_TEST_OTP_CODE', 'UAT_TEST_PHONE_NUMBERS'] as $key) {
            $this->assertStringContainsString($key, $render);
            $this->assertStringNotContainsString($key.'=', $render);
        }
        $this->assertStringContainsString('sync: false', $render);
        $this->assertStringContainsString('envVarKey: RENDER_EXTERNAL_URL', $render);
        $this->assertStringNotContainsString("key: APP_URL\n        sync: false", $render);
        $this->assertStringContainsString('.env', $dockerignore);
        $this->assertStringContainsString('${PORT:-10000}', $entrypoint);
        $this->assertStringContainsString('uat:cloud-check', $entrypoint);
    }

    public function test_cloud_check_requires_https_postgis_and_storage_probe_without_printing_secrets(): void
    {
        $source = (string) file_get_contents(base_path('routes/console.php'));
        $this->assertStringContainsString("Artisan::command('uat:cloud-check'", $source);
        $this->assertStringContainsString('PostGIS is not enabled', $source);
        $this->assertStringContainsString('SUPABASE_STORAGE_SERVER_KEY is missing', $source);
        $this->assertStringContainsString('$storage->probe()', $source);
        $this->assertStringNotContainsString('server_key)', $source);
    }
}
