<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\CurrentProductPolicy;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class FinancialV1CompletionTest extends TestCase
{
    use RefreshDatabase;

    public function test_current_product_policy_keeps_finance_and_sai_disabled(): void
    {
        $this->assertFalse(CurrentProductPolicy::financeEnabled());
        $this->assertFalse(CurrentProductPolicy::saiEnabled());
    }

    public function test_free_services_hub_remains_free_while_admin_finance_routes_are_absent(): void
    {
        [, $headers] = $this->user();

        $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.pricing_model', 'free')
            ->assertJsonPath('data.paid_features_enabled', false);

        $this->withHeaders($headers)->getJson('/api/admin/finance/summary')->assertNotFound();
        $this->withHeaders($headers)->getJson('/api/admin/finance/workspace')->assertNotFound();
        $this->withHeaders($headers)->getJson('/api/admin/finance/payment-methods')->assertNotFound();
    }

    private function user(): array
    {
        $user = User::query()->create([
            'name' => 'W4b Hub User',
            'email' => 'w4b-hub@example.test',
            'phone' => '+967772100011',
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('w4b-hub-password'),
        ]);

        $plain = 'w4bhub_'.substr(hash('sha512', $user->email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'w4b-hub',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }
}
