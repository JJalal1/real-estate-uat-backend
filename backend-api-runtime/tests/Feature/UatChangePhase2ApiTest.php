<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatChangePhase2ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_v2_listing_preserves_local_area_unit_and_computes_canonical_square_metres(): void
    {
        [, $headers] = $this->verifiedUser();

        $response = $this->withHeaders($headers)->postJson('/api/properties', $this->v2Payload([
            'area_value' => 2,
            'area_unit' => 'libna_sanaani',
            'has_parking' => false,
            'building_facade' => 'east',
            'contact_phone' => null,
            'contact_whatsapp' => null,
        ]));

        $response->assertCreated()
            ->assertJsonPath('data.area_value', 2)
            ->assertJsonPath('data.area_unit', 'libna_sanaani')
            ->assertJsonPath('data.area_m2', 89)
            ->assertJsonPath('data.has_parking', false)
            ->assertJsonPath('data.building_facade', 'east')
            ->assertJsonPath('data.contact_phone', null);

        $property = Property::query()->findOrFail((int) $response->json('data.id'));
        $this->assertSame(89, $property->area_m2);
        $this->assertSame(2.0, $property->area_value);
        $this->assertSame('libna_sanaani', $property->area_unit);
        $this->assertFalse($property->has_parking);
        $this->assertSame('east', $property->building_facade);
        $this->assertNull($property->contact_phone);
    }

    public function test_v2_structured_listing_requires_required_user_choices(): void
    {
        [, $headers] = $this->verifiedUser('phase2-required@example.test', '+967700002202');

        $payload = $this->v2Payload();
        unset($payload['has_parking'], $payload['building_facade']);

        $this->withHeaders($headers)->postJson('/api/properties', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['has_parking', 'building_facade']);
    }

    public function test_v2_sale_tenure_is_required_only_for_supported_sale_property_types(): void
    {
        [, $headers] = $this->verifiedUser('phase2-tenure@example.test', '+967700002206');

        $missingTenure = $this->v2Payload();
        unset($missingTenure['tenure_type']);
        $this->withHeaders($headers)->postJson('/api/properties', $missingTenure)
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['tenure_type']);

        $rentHouse = $this->v2Payload([
            'purpose' => 'rent',
            'tenure_type' => null,
            'latitude' => 15.3794,
            'longitude' => 44.2010,
        ]);
        $this->withHeaders($headers)->postJson('/api/properties', $rentHouse)
            ->assertCreated()
            ->assertJsonPath('data.tenure_type', null);

        $saleShop = $this->v2Payload([
            'type' => 'shop',
            'tenure_type' => null,
            'bedrooms' => null,
            'bathrooms' => null,
            'latitude' => 15.3894,
            'longitude' => 44.2110,
        ]);
        $this->withHeaders($headers)->postJson('/api/properties', $saleShop)
            ->assertCreated()
            ->assertJsonPath('data.tenure_type', null);
    }

    public function test_v2_residential_listing_requires_bedrooms_and_bathrooms(): void
    {
        [, $headers] = $this->verifiedUser('phase2-rooms@example.test', '+967700002203');

        $payload = $this->v2Payload();
        unset($payload['bedrooms'], $payload['bathrooms']);

        $this->withHeaders($headers)->postJson('/api/properties', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['bedrooms', 'bathrooms']);
    }

    public function test_v2_land_does_not_keep_structure_only_fields(): void
    {
        [, $headers] = $this->verifiedUser('phase2-land@example.test', '+967700002204');

        $response = $this->withHeaders($headers)->postJson('/api/properties', $this->v2Payload([
            'type' => 'land',
            'bedrooms' => 3,
            'bathrooms' => 2,
            'has_parking' => true,
            'building_facade' => 'north',
            'area_value' => 1.5,
            'area_unit' => 'libna_dhamari',
        ]));

        $response->assertCreated()
            ->assertJsonPath('data.area_value', 1.5)
            ->assertJsonPath('data.area_unit', 'libna_dhamari')
            ->assertJsonPath('data.area_m2', 172)
            ->assertJsonPath('data.bedrooms', null)
            ->assertJsonPath('data.bathrooms', null)
            ->assertJsonPath('data.has_parking', null)
            ->assertJsonPath('data.building_facade', null);
    }

    public function test_legacy_area_m2_payload_remains_supported(): void
    {
        [, $headers] = $this->verifiedUser('phase2-legacy@example.test', '+967700002205');

        $payload = $this->v2Payload([
            'listing_input_version' => 1,
            'area_m2' => 220,
        ]);
        unset($payload['area_value'], $payload['area_unit'], $payload['has_parking'], $payload['building_facade'], $payload['tenure_type']);

        $response = $this->withHeaders($headers)->postJson('/api/properties', $payload);
        $response->assertCreated()
            ->assertJsonPath('data.area_m2', 220)
            ->assertJsonPath('data.area_value', 220)
            ->assertJsonPath('data.area_unit', 'sqm');
    }

    private function v2Payload(array $overrides = []): array
    {
        return array_merge([
            'listing_input_version' => 2,
            'title' => 'Phase 2 listing',
            'description' => 'Phase 2 property input contract',
            'purpose' => 'sale',
            'type' => 'house',
            'tenure_type' => 'freehold',
            'price' => 50000000,
            'currency' => 'YER',
            'area_value' => 220,
            'area_unit' => 'sqm',
            'bedrooms' => 4,
            'bathrooms' => 3,
            'has_parking' => true,
            'building_facade' => 'south',
            'address' => 'Sanaa - Phase 2',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
        ], $overrides);
    }

    private function verifiedUser(
        string $email = 'phase2@example.test',
        string $phone = '+967700002201',
    ): array {
        $user = User::query()->create([
            'name' => 'Phase 2 User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $plain = 're6_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'phase2-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, ['Authorization' => 'Bearer ' . $plain, 'Accept' => 'application/json']];
    }
}
