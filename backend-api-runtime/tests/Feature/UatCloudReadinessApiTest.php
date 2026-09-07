<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AccessControlService;
use App\Services\UatTestOtpService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Hash;
use RuntimeException;
use Tests\TestCase;

class UatCloudReadinessApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_multiple_device_sessions_survive_independent_logins_and_current_logout_only(): void
    {
        $user = $this->activeUser('multi-session@example.test', '+967711119001');

        $first = $this->postJson('/api/auth/login', [
            'login' => $user->email,
            'password' => 'StrongPass123!',
        ])->assertOk();
        $second = $this->postJson('/api/auth/login', [
            'login' => $user->email,
            'password' => 'StrongPass123!',
        ])->assertOk();

        $tokenA = (string) $first->json('data.token');
        $tokenB = (string) $second->json('data.token');
        $this->assertNotSame($tokenA, $tokenB);
        $this->assertSame(2, $user->apiTokens()->count());

        $this->withHeaders($this->bearer($tokenA))->getJson('/api/auth/me')->assertOk();
        $this->withHeaders($this->bearer($tokenB))->getJson('/api/auth/me')->assertOk();

        $this->withHeaders($this->bearer($tokenA))->postJson('/api/auth/logout')->assertOk();
        $this->withHeaders($this->bearer($tokenA))->getJson('/api/auth/me')->assertUnauthorized();
        $this->withHeaders($this->bearer($tokenB))->getJson('/api/auth/me')->assertOk();
        $this->assertSame(1, $user->apiTokens()->count());
    }

    public function test_login_for_another_user_does_not_revoke_existing_user_session(): void
    {
        $firstUser = $this->activeUser('first-device@example.test', '+967711119002');
        $secondUser = $this->activeUser('second-device@example.test', '+967711119003');

        $firstToken = (string) $this->postJson('/api/auth/login', [
            'login' => $firstUser->email,
            'password' => 'StrongPass123!',
        ])->assertOk()->json('data.token');

        $this->postJson('/api/auth/login', [
            'login' => $secondUser->email,
            'password' => 'StrongPass123!',
        ])->assertOk();

        $this->withHeaders($this->bearer($firstToken))
            ->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.user.id', $firstUser->id);
    }

    public function test_uat_test_otp_is_allowlisted_and_production_guarded(): void
    {
        Config::set('services.whatsapp.uat_test_otp', [
            'enabled' => true,
            'code' => '654321',
            'phone_numbers' => ['+967711119010'],
        ]);

        $policy = app(UatTestOtpService::class);
        $this->assertSame('654321', $policy->codeFor('+967711119010'));
        $this->assertNull($policy->codeFor('+967711119011'));
        $this->assertTrue($policy->shouldBypassDelivery('+967711119010', '654321'));
        $this->assertFalse($policy->shouldBypassDelivery('+967711119010', '111111'));

        $previous = $this->app->environment();
        $threw = false;
        try {
            $this->app->detectEnvironment(static fn () => 'production');
            $policy->codeFor('+967711119010');
        } catch (RuntimeException $e) {
            $threw = str_contains($e->getMessage(), 'must never be enabled in production');
        } finally {
            $this->app->detectEnvironment(static fn () => $previous);
        }
        $this->assertTrue($threw, 'Production must fail closed when UAT test OTP is enabled.');
    }

    public function test_storage_config_keeps_local_defaults_and_cloud_storage_is_server_side(): void
    {
        $this->assertSame('local', config('filesystems.disks.local.driver'));
        $this->assertSame('local', config('filesystems.disks.public.driver'));

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
        $this->assertStringContainsString('MaxRequestWorkers 10', $mpm);
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
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);

        return $user->fresh();
    }

    private function bearer(string $token): array
    {
        return ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json'];
    }
}
