<?php

namespace Tests\Feature;

use App\Models\User;
use Closure;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

class NotificationPreferencePersistenceIntegrityTest extends TestCase
{
    use RefreshDatabase;

    public function test_default_read_cannot_recreate_preferences_after_account_deactivation(): void
    {
        $this->assertDeactivatedRequestRejected('GET');
    }

    public function test_preference_write_cannot_recreate_preferences_after_account_deactivation(): void
    {
        $this->assertDeactivatedRequestRejected('PATCH');
    }

    private function assertDeactivatedRequestRejected(string $method): void
    {
        $actor = User::create(['name' => 'Synthetic preference actor',
            'email' => 'preferences-integrity@example.invalid', 'phone' => '+12025550301',
            'phone_verified_at' => now(), 'account_status' => User::STATUS_ACTIVE,
            'password' => 'synthetic-test-password']);
        $plain = 'synthetic-preference-integrity-token';
        $actor->apiTokens()->create(['name' => 'disposable-only', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour()]);
        $route = app('router')->getRoutes()->match(Request::create('/api/notification-preferences', $method));
        $route->middleware(DeactivatePreferenceActor::class);

        $this->withHeaders(['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json'])
            ->json($method, '/api/notification-preferences', $method === 'PATCH' ? ['messages' => false] : [])
            ->assertForbidden();

        $this->assertDatabaseCount('user_notification_preferences', 0);
        $this->assertSame(User::STATUS_SUSPENDED, $actor->fresh()->account_status);
    }
}

class DeactivatePreferenceActor
{
    public function handle(Request $request, Closure $next): Response
    {
        $request->user()->forceFill(['account_status' => User::STATUS_SUSPENDED])->save();
        return $next($request);
    }
}
