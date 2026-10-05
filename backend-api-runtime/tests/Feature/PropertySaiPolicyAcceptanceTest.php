<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PropertySaiPolicyAcceptanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_sai_api_is_not_exposed_for_owner_broker_or_office_in_current_product(): void
    {
        foreach (['owner', 'broker', 'office'] as $index => $type) {
            [$user, $headers] = $this->user(
                "w4b-sai-$type@example.test",
                '+9677721000'.(20 + $index),
            );
            $property = $this->property($user, "W4b $type Sai-disabled property");

            $this->withHeaders($headers)
                ->putJson("/api/properties/{$property->id}/sai", [
                    'sai_payer' => 'seller',
                    'broker_sai_rate_percent' => 1,
                    'platform_terms_decision' => 'accept',
                ])
                ->assertNotFound();

            $this->withHeaders($headers)
                ->getJson("/api/properties/{$property->id}/sai")
                ->assertNotFound();
        }

        $this->assertDatabaseCount('property_sai_terms', 0);
    }

    public function test_public_property_payload_has_no_active_sai_contract(): void
    {
        [$user] = $this->user('w4b-public-sai@example.test', '+967772100030');
        $property = $this->property($user, 'W4b public free-core property');
        $historical = PropertySaiTerm::query()->create([
            'property_id' => $property->id,
            'version' => 1,
            'advertiser_type' => 'owner',
            'purpose' => 'sale',
            'source_mode' => 'owner_fixed',
            'requested_broker_rate_percent' => null,
            'sai_rate_percent' => 1,
            'payer' => 'seller',
            'calculation_basis' => 'final_sale_value',
            'platform_share_percent' => 100,
            'broker_share_percent' => 0,
            'platform_terms_status' => 'not_required',
            'created_by_user_id' => $user->id,
        ]);
        $property->forceFill(['current_sai_term_id' => $historical->id])->saveQuietly();

        $this->getJson("/api/properties/{$property->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $property->id)
            ->assertJsonMissingPath('data.sai')
            ->assertJsonMissingPath('data.sai_management')
            ->assertJsonMissingPath('data.sai_attestation_required');

        $this->assertDatabaseHas('property_sai_terms', ['id' => $historical->id]);
        $this->assertDatabaseHas('properties', [
            'id' => $property->id,
            'current_sai_term_id' => $historical->id,
        ]);
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'W4b Sai-disabled User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('w4b-sai-disabled'),
        ]);

        $plain = 'w4bsai_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'w4b-sai-disabled',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(User $user, string $title): Property
    {
        return Property::query()->create([
            'user_id' => $user->id,
            'title' => $title,
            'description' => 'W4b Sai-disabled fixture',
            'purpose' => 'sale',
            'type' => 'apartment',
            'price' => 20_000_000,
            'currency' => 'YER',
            'area_m2' => 120,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'Sanaa',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'published_at' => now(),
        ]);
    }
}
