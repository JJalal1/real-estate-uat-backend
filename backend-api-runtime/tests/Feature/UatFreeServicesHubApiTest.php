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

    public function test_hub_is_free_and_owner_does_not_receive_researcher_requests(): void
    {
        [, $headers] = $this->user('free-owner@example.test', '+967733410001', 'owner');

        $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.pricing_model', 'free')
            ->assertJsonPath('data.paid_features_enabled', false)
            ->assertJsonPath('data.account_type', 'owner')
            ->assertJsonPath('data.verified_professional', true)
            ->assertJsonPath('data.capabilities.create_listing', true)
            ->assertJsonPath('data.capabilities.view_researcher_requests', false)
            ->assertJsonPath('data.availability.create_listing', 'available');
    }

    public function test_verified_broker_and_office_receive_researcher_request_capability(): void
    {
        [, $brokerHeaders] = $this->user('free-broker@example.test', '+967733410002', 'broker');
        [, $officeHeaders] = $this->user('free-office@example.test', '+967733410003', 'office');

        foreach ([$brokerHeaders, $officeHeaders] as $headers) {
            $this->withHeaders($headers)
                ->getJson('/api/services/hub')
                ->assertOk()
                ->assertJsonPath('data.paid_features_enabled', false)
                ->assertJsonPath('data.capabilities.view_researcher_requests', true)
                ->assertJsonPath('data.availability.researcher_requests', 'available');
        }
    }

    public function test_pending_professional_profile_cannot_use_verified_professional_capabilities(): void
    {
        [, $headers] = $this->user(
            'free-pending-broker@example.test',
            '+967733410004',
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
            ->assertJsonPath('data.capabilities.view_researcher_requests', false)
            ->assertJsonPath('data.availability.create_listing', 'requires_verification');
    }

    public function test_basic_account_keeps_free_search_and_information_capabilities(): void
    {
        [, $headers] = $this->user('free-basic@example.test', '+967733410005');

        $this->withHeaders($headers)
            ->getJson('/api/services/hub')
            ->assertOk()
            ->assertJsonPath('data.account_type', 'basic')
            ->assertJsonPath('data.pricing_model', 'free')
            ->assertJsonPath('data.capabilities.create_property_request', true)
            ->assertJsonPath('data.capabilities.price_indicators', true)
            ->assertJsonPath('data.capabilities.property_valuation', true)
            ->assertJsonPath('data.capabilities.real_estate_guide', true)
            ->assertJsonPath('data.capabilities.legal_library', true)
            ->assertJsonPath('data.capabilities.view_researcher_requests', false);
    }

    private function user(
        string $email,
        string $phone,
        ?string $profileType = null,
        string $profileStatus = AccountVerificationProfile::STATUS_APPROVED,
    ): array {
        $user = User::query()->create([
            'name' => 'Free Services User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
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

        $plain = 'free_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'free-services-hub-test',
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
