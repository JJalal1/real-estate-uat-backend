<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatFreeServicesHubApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_verified_owner_receives_current_marketplace_service_contract(): void
    {
        [, $headers] = $this->user('owner', '+967700000101', 'owner');

        $response = $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.ui_version', 'free_services_v2')
            ->assertJsonPath('data.pricing_model', 'free')
            ->assertJsonPath('data.paid_features_enabled', false)
            ->assertJsonPath('data.account_type', 'owner')
            ->assertJsonPath('data.verified_professional', true)
            ->assertJsonPath('data.capabilities.create_listing', true)
            ->assertJsonPath('data.capabilities.rental_contracts', true)
            ->assertJsonPath('data.availability.create_listing', 'available')
            ->assertJsonPath('data.availability.rental_contracts', 'planned');

        $capabilities = $response->json('data.capabilities');
        $availability = $response->json('data.availability');
        $this->assertArrayNotHasKey('create_property_request', $capabilities);
        $this->assertArrayNotHasKey('view_property_requests', $capabilities);
        $this->assertArrayNotHasKey('view_researcher_requests', $capabilities);
        $this->assertArrayNotHasKey('property_requests', $availability);
        $this->assertArrayNotHasKey('researcher_requests', $availability);
    }

    public function test_verified_broker_and_office_share_the_same_launch_service_contract(): void
    {
        [, $brokerHeaders] = $this->user('broker', '+967700000102', 'broker');
        [, $officeHeaders] = $this->user('office', '+967700000103', 'office');

        foreach ([$brokerHeaders, $officeHeaders] as $headers) {
            $response = $this->withHeaders($headers)
                ->getJson('/api/services/hub')
                ->assertOk()
                ->assertJsonPath('data.paid_features_enabled', false)
                ->assertJsonPath('data.capabilities.create_listing', true)
                ->assertJsonPath('data.capabilities.rental_contracts', true);

            $this->assertArrayNotHasKey(
                'view_researcher_requests',
                $response->json('data.capabilities'),
            );
        }
    }

    public function test_pending_professional_profile_cannot_use_professional_capabilities(): void
    {
        [, $headers] = $this->user(
            'pending',
            '+967700000104',
            'broker',
            AccountVerificationProfile::STATUS_PENDING,
        );

        $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.account_type', 'broker')
            ->assertJsonPath('data.verification_status', 'pending')
            ->assertJsonPath('data.verified_professional', false)
            ->assertJsonPath('data.capabilities.create_listing', false)
            ->assertJsonPath('data.capabilities.rental_contracts', false)
            ->assertJsonPath('data.availability.create_listing', 'requires_verification');
    }

    public function test_basic_account_keeps_non_professional_information_capabilities(): void
    {
        [, $headers] = $this->user('basic', '+967700000105');

        $response = $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.account_type', 'basic')
            ->assertJsonPath('data.pricing_model', 'free')
            ->assertJsonPath('data.capabilities.create_listing', false)
            ->assertJsonPath('data.capabilities.rental_contracts', false)
            ->assertJsonPath('data.capabilities.price_indicators', true)
            ->assertJsonPath('data.capabilities.property_valuation', true)
            ->assertJsonPath('data.capabilities.real_estate_guide', true)
            ->assertJsonPath('data.capabilities.legal_library', true);

        $this->assertArrayNotHasKey(
            'create_property_request',
            $response->json('data.capabilities'),
        );
    }

    private function user(
        string $key,
        string $phone,
        ?string $profileType = null,
        string $profileStatus = AccountVerificationProfile::STATUS_APPROVED,
    ): array {
        $user = User::query()->create([
            'name' => 'Services Test User',
            'email' => $key . '@example.test',
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make(str_repeat($key, 8)),
        ]);

        if ($profileType !== null) {
            AccountVerificationProfile::query()->create([
                'user_id' => $user->id,
                'type' => $profileType,
                'status' => $profileStatus,
                'submitted_at' => now()->subHour(),
                'reviewed_at' => $profileStatus === AccountVerificationProfile::STATUS_APPROVED ? now() : null,
            ]);
        }

        $plain = 'test_' . substr(hash('sha512', $key . $phone), 0, 80);
        $user->apiTokens()->create([
            'name' => 'services-hub-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user->fresh(), [
            'Authorization' => 'Bearer ' . $plain,
            'Accept' => 'application/json',
        ]];
    }
}
