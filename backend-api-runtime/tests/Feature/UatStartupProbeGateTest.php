<?php

namespace Tests\Feature;

use App\Services\CloudAssetStorageService;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Mockery;
use Tests\TestCase;

class UatStartupProbeGateTest extends TestCase
{
    private function prepareCloudCheck(CloudAssetStorageService $storage): void
    {
        $this->assertSame(realpath(dirname(__DIR__, 2)), realpath(base_path()));
        $this->app->instance('env', 'staging');
        Config::set('app.url', 'https://uat.example.test');
        Config::set('app.key', 'base64:synthetic-test-key');
        Config::set('database.default', 'pgsql');
        Config::set('database.connections.pgsql.search_path', 'public');
        Config::set('services.supabase_storage', [
            'enabled' => true,
            'url' => 'https://synthetic.supabase.test',
            'server_key' => 'synthetic-test-key',
            'bucket' => 'synthetic-test-bucket',
        ]);
        Config::set('services.whatsapp.uat_test_otp.enabled', false);

        DB::shouldReceive('select')->once()->with('select 1')->andReturn([]);
        DB::shouldReceive('selectOne')->once()->andReturn((object) ['schema_name' => 'public']);
        $this->app->instance(CloudAssetStorageService::class, $storage);
    }

    public function test_startup_cloud_check_can_validate_configuration_without_writing_storage(): void
    {
        $storage = Mockery::mock(CloudAssetStorageService::class);
        $storage->shouldNotReceive('probe');
        $this->prepareCloudCheck($storage);

        $this->artisan('uat:cloud-check', ['--skip-storage-probe' => true])
            ->expectsOutputToContain('remote Storage was not probed')
            ->assertExitCode(0);
    }

    public function test_explicit_cloud_check_still_verifies_storage_connectivity(): void
    {
        $storage = Mockery::mock(CloudAssetStorageService::class);
        $storage->shouldReceive('probe')->once();
        $this->prepareCloudCheck($storage);

        $this->artisan('uat:cloud-check')
            ->expectsOutputToContain('Supabase Storage')
            ->assertExitCode(0);
    }
}
