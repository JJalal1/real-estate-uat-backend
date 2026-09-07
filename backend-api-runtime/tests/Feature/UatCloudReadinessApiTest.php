<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UatCloudReadinessApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_multiple_device_sessions_survive_independent_logins_and_current_logout_only(): void
    {
        $user = $this->activeUser('uat-sessions@example.test', '+12025550990');

        $first = $this->postJson('/api/auth/login', [
            'phone' => $user->phone,
            'password' => 'password',
        ])->assertOk()->json('token');

        $second = $this->postJson('/api/auth/login', [
            'phone' => $user->phone,
            'password' => 'password',
        ])->assertOk()->json('token');

        $this->assertNotSame($first, $second);

        $this->withHeader('Authorization', 'Bearer '.$first)
            ->getJson('/api/auth/me')
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$second)
            ->getJson('/api/auth/me')
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$first)
            ->postJson('/api/auth/logout')
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$first)
            ->getJson('/api/auth/me')
            ->assertUnauthorized();
        $this->withHeader('Authorization', 'Bearer '.$second)
            ->getJson('/api/auth/me')
            ->assertOk();
    }

    public function test_login_for_another_user_does_not_revoke_existing_user_session(): void
    {
        $firstUser = $this->activeUser('uat-first@example.test', '+12025550991');
        $secondUser = $this->activeUser('uat-second@example.test', '+12025550992');

        $firstToken = $this->postJson('/api/auth/login', [
            'phone' => $firstUser->phone,
            'password' => 'password',
        ])->assertOk()->json('token');

        $this->postJson('/api/auth/login', [
            'phone' => $secondUser->phone,
            'password' => 'password',
        ])->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$firstToken)
            ->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.id', $firstUser->id);
    }

    public function test_uat_test_otp_is_allowlisted_and_production_guarded(): void
    {
        $source = (string) file_get_contents(app_path('Services/WhatsAppOtpService.php'));

        $this->assertStringContainsString('UAT_TEST_OTP_ENABLED', $source);
        $this->assertStringContainsString('UAT_TEST_OTP_ALLOWLIST', $source);
        $this->assertStringContainsString("app()->environment('production')", $source);
        $this->assertStringNotContainsString("env('UAT_TEST_OTP_CODE')", $source);
    }

    public function test_storage_config_keeps_local_defaults_and_cloud_storage_is_server_side_only(): void
    {
        Storage::fake('public');
        Storage::fake('local');

        $this->assertSame('local', config('filesystems.default'));

        $services = (string) file_get_contents(config_path('services.php'));
        $cloudStorage = (string) file_get_contents(app_path('Services/CloudAssetStorageService.php'));

        $this->assertStringContainsString('UAT_CLOUD_STORAGE_ENABLED', $services);
        $this->assertStringContainsString('SUPABASE_STORAGE_SERVER_KEY', $services);
        $this->assertStringContainsString('UAT_PRIVATE_STORAGE_PREFIX', $services);
        $this->assertStringContainsString('UAT_PUBLIC_STORAGE_PREFIX', $services);
        $this->assertStringContainsString('/storage/v1', $cloudStorage);
        $this->assertStringNotContainsString('AwsS3V3Adapter', $cloudStorage);
    }

    public function test_uat_deployment_files_are_secret_free_templates(): void
    {
        foreach (['Dockerfile.uat', 'docker/uat-apache.conf', 'docker/uat-entrypoint.sh', 'docker/uat-mpm-prefork.conf', 'docker/uat-php.ini'] as $relative) {
            $path = base_path($relative);
            $this->assertFileExists($path);
            $contents = (string) file_get_contents($path);
            $this->assertStringNotContainsString('AWS_SECRET_ACCESS_KEY=', $contents);
            $this->assertStringNotContainsString('DB_PASSWORD=', $contents);
            $this->assertStringNotContainsString('WHATSAPP_ACCESS_TOKEN=', $contents);
        }

        $mpm = (string) file_get_contents(base_path('docker/uat-mpm-prefork.conf'));
        $this->assertStringContainsString('MaxRequestWorkers 12', $mpm);
        $this->assertStringContainsString('MaxConnectionsPerChild 250', $mpm);

        $dockerfile = (string) file_get_contents(base_path('Dockerfile.uat'));
        $this->assertStringContainsString('uat-mpm-prefork.conf', $dockerfile);
    }

    private function activeUser(string $email, string $phone): User
    {
        $user = User::query()->create([
            'name' => 'UAT Readiness User',
            'email' => $email,
            'phone' => $phone,
            'password' => Hash::make('password'),
            'status' => 'active',
            'phone_verified_at' => now(),
        ]);

        return $user;
    }
}
