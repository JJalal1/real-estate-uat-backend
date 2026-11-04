<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\ApiTokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthenticatedThrottleIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_erasure_budget_is_per_account_even_behind_one_proxy_and_cannot_be_reset_by_a_new_token(): void
    {
        [$first, $firstToken] = $this->actor(1);
        [$second, $secondToken] = $this->actor(2);
        $invalid = ['confirm_phrase' => 'invalid'];

        for ($attempt = 0; $attempt < 2; $attempt++) {
            $this->withToken($firstToken)->deleteJson('/api/account', $invalid)
                ->assertUnprocessable()->assertHeader('X-RateLimit-Limit', '2');
        }
        $limited = $this->withToken($firstToken)->deleteJson('/api/account', $invalid)
            ->assertTooManyRequests()->assertHeader('Retry-After');
        $this->assertGreaterThan(0, (int) $limited->headers->get('Retry-After'));
        $this->assertLessThanOrEqual(3600, (int) $limited->headers->get('Retry-After'));

        $replacementToken = app(ApiTokenService::class)->issue($first, request())['plain_text_token'];
        $this->withServerVariables(['REMOTE_ADDR' => '198.51.100.50'])
            ->withHeaders(['Authorization' => 'Bearer '.$replacementToken, 'X-Forwarded-For' => '203.0.113.8'])
            ->deleteJson('/api/account', $invalid)->assertTooManyRequests();

        $this->flushHeaders();
        $this->withServerVariables(['REMOTE_ADDR' => '127.0.0.1']);
        $this->withToken($secondToken)->deleteJson('/api/account', $invalid)
            ->assertUnprocessable()->assertHeader('X-RateLimit-Remaining', '1');
        $this->withToken($secondToken)->deleteJson('/api/account', ['confirm_phrase' => 'حذف حسابي نهائيًا'])
            ->assertOk()->assertJsonPath('data.account_deleted', true);
        $this->assertSame(User::STATUS_DELETED, $second->fresh()->account_status);
        $this->assertSame(User::STATUS_ACTIVE, $first->fresh()->account_status);
        $this->withToken($secondToken)->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_unauthenticated_requests_cannot_consume_an_authenticated_erasure_budget(): void
    {
        for ($attempt = 0; $attempt < 4; $attempt++) {
            $this->deleteJson('/api/account', ['confirm_phrase' => 'invalid'])->assertUnauthorized();
        }
        [, $token] = $this->actor(3);
        $this->withToken($token)->deleteJson('/api/account', ['confirm_phrase' => 'invalid'])
            ->assertUnprocessable()->assertHeader('X-RateLimit-Remaining', '1');
    }

    public function test_public_authentication_still_has_an_ip_budget_that_forwarded_headers_cannot_bypass(): void
    {
        for ($attempt = 0; $attempt < 6; $attempt++) {
            $this->postJson('/api/auth/whatsapp/start', [])->assertUnprocessable();
        }
        $this->withHeader('X-Forwarded-For', '203.0.113.9')
            ->postJson('/api/auth/whatsapp/start', [])->assertTooManyRequests()
            ->assertHeader('X-RateLimit-Limit', '6')->assertHeader('Retry-After');
    }

    private function actor(int $index): array
    {
        $actor = User::create([
            'name' => 'Synthetic throttle actor '.$index,
            'email' => 'throttle-'.$index.'@example.invalid',
            'phone' => '+96771100000'.$index,
            'password' => 'unusable',
            'account_type' => User::ACCOUNT_TYPE_REGULAR,
            'account_status' => User::STATUS_ACTIVE,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
        ]);
        return [$actor, app(ApiTokenService::class)->issue($actor, request())['plain_text_token']];
    }
}
