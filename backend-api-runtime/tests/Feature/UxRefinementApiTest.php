<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UxRefinementApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_policy_is_account_private_and_uses_authoritative_sale_and_rental_limits(): void
    {
        $this->getJson('/api/listing-sai-policy?purpose=sale')->assertUnauthorized();
        [, $headers] = $this->advertiser('policy');
        $this->withHeaders($headers)->getJson('/api/listing-sai-policy?purpose=sale')->assertOk()
            ->assertJsonPath('data.payer', 'buyer')->assertJsonPath('data.broker_max_rate_percent', 5)
            ->assertJsonPath('data.professional_platform_share_percent', 20)->assertJsonPath('data.fixed_rate_percent', 1);
        $this->withHeaders($headers)->getJson('/api/listing-sai-policy?purpose=rent')->assertOk()
            ->assertJsonPath('data.payer', 'tenant')->assertJsonPath('data.broker_max_rate_percent', 100)
            ->assertJsonPath('data.fixed_rate_percent', 20);
        $this->withHeaders($headers)->getJson('/api/listing-sai-policy?purpose=other')->assertUnprocessable();
        $this->assertDatabaseCount('property_sai_terms', 0);
    }

    public function test_new_sai_terms_default_to_customer_and_reject_seller_or_landlord_without_rewriting_terms(): void
    {
        [, $headers] = $this->advertiser('payer');
        $id = $this->listing($headers, ['type' => 'house']);
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", ['broker_sai_rate_percent' => 0])->assertOk()
            ->assertJsonPath('data.sai.payer', 'buyer')->assertJsonPath('data.sai.rate_percent', 1);
        $first = Property::findOrFail($id)->current_sai_term_id;
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", [
            'sai_payer' => 'seller', 'broker_sai_rate_percent' => 2, 'platform_terms_decision' => 'accept',
        ])->assertUnprocessable()->assertJsonValidationErrors('sai_payer');
        $this->assertSame($first, Property::findOrFail($id)->current_sai_term_id);
        $this->assertDatabaseCount('property_sai_terms', 1);
        $rent = $this->listing($headers, ['type' => 'house', 'purpose' => 'rent', 'price' => 300000,
            'monthly_rent' => 100000, 'rental_term_months' => 12, 'advance_months' => 3]);
        $this->withHeaders($headers)->putJson("/api/properties/$rent/sai", ['broker_sai_rate_percent' => 0])->assertOk()
            ->assertJsonPath('data.sai.payer', 'tenant');
        $this->withHeaders($headers)->putJson("/api/properties/$rent/sai", [
            'sai_payer' => 'landlord', 'broker_sai_rate_percent' => 0,
        ])->assertUnprocessable();
    }

    public function test_published_sai_editor_data_is_owner_only_and_does_not_leak_through_public_response(): void
    {
        [, $headers] = $this->advertiser('management');
        [, $otherHeaders] = $this->advertiser('other');
        $id = $this->listing($headers);
        $this->configure($headers, $id);
        $this->publish($id);
        $this->withHeaders($headers)->getJson("/api/properties/$id/sai-management")->assertOk()
            ->assertJsonPath('data.sai_management.requested_broker_rate_percent', 2);
        $this->withHeaders($otherHeaders)->getJson("/api/properties/$id/sai-management")->assertForbidden();
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$id/sai-management")->assertUnauthorized();
        $this->getJson("/api/properties/$id/sai")->assertOk()->assertJsonMissingPath('data.sai_management');
        $this->assertDatabaseCount('property_sai_terms', 1);
    }

    public function test_floor_and_building_do_not_require_an_apartment_number_and_stale_fields_are_cleared(): void
    {
        [, $headers] = $this->advertiser('scope');
        $floor = $this->listing($headers, ['type' => 'floor', 'floor_number' => 'الثالث', 'unit_number' => 'stale']);
        $property = Property::findOrFail($floor);
        $this->assertNull($property->unit_number);
        $this->assertSame('unit', $property->propertyAsset->identity_kind);
        $this->assertSame('@whole_floor', $property->propertyAsset->unit_number);
        $this->assertSame('3', $property->propertyAsset->floor_number);
        $building = $this->listing($headers, ['type' => 'building', 'floor_number' => '3', 'unit_number' => 'stale']);
        $this->assertNull(Property::findOrFail($building)->floor_number);
        $this->assertNull(Property::findOrFail($building)->unit_number);
        $this->assertNull(Property::findOrFail($building)->bedrooms);
        $this->withHeaders($headers)->postJson('/api/properties', $this->payload([
            'type' => 'floor', 'floor_number' => null,
        ]))->assertUnprocessable()->assertJsonValidationErrors('floor_number');
    }

    public function test_unnamed_building_keeps_exact_unit_protection_and_allows_another_unit(): void
    {
        [, $headers] = $this->advertiser('units');
        $first = $this->listing($headers, ['type' => 'apartment', 'unit_number' => '٧', 'floor_number' => '٣']);
        $this->configure($headers, $first);
        $this->withHeaders($headers)->postJson("/api/properties/$first/submit")->assertOk();
        $same = $this->listing($headers, ['type' => 'apartment', 'unit_number' => '7', 'floor_number' => '3', 'area_value' => 180]);
        $this->withHeaders($headers)->postJson("/api/properties/$same/identity/check")->assertOk()
            ->assertJsonPath('data.decision', 'confirmed_duplicate');
        $different = $this->listing($headers, ['type' => 'apartment', 'unit_number' => '8', 'floor_number' => '3']);
        $this->withHeaders($headers)->postJson("/api/properties/$different/identity/check")->assertOk()
            ->assertJsonPath('data.decision', 'distinct');
        $this->withHeaders($headers)->postJson('/api/properties', $this->payload([
            'type' => 'apartment', 'unit_number' => '///', 'floor_number' => '3',
        ]))->assertUnprocessable()->assertJsonValidationErrors('unit_number');
    }

    public function test_omitting_the_old_building_name_and_moving_pin_still_requires_duplicate_review(): void
    {
        [, $headers] = $this->advertiser('legacy-unit');
        $first = $this->listing($headers, ['listing_input_version' => 3, 'type' => 'apartment',
            'building_reference' => 'عمارة النور', 'unit_number' => '7', 'floor_number' => '3']);
        $this->configure($headers, $first);
        $this->withHeaders($headers)->postJson("/api/properties/$first/submit")->assertOk();
        $second = $this->listing($headers, ['type' => 'apartment', 'unit_number' => '7',
            'floor_number' => '3', 'latitude' => 15.36945]);
        $this->configure($headers, $second);
        $this->withHeaders($headers)->postJson("/api/properties/$second/identity/check")->assertOk()
            ->assertJsonPath('data.decision', 'possible_duplicate');
        $this->withHeaders($headers)->postJson("/api/properties/$second/submit")->assertUnprocessable();
    }

    public function test_rental_budget_filters_monthly_rent_and_currency_instead_of_advance_amount(): void
    {
        [, $headers] = $this->advertiser('rent-search');
        $within = $this->listing($headers, ['type' => 'house', 'purpose' => 'rent', 'price' => 600000,
            'monthly_rent' => 100000, 'rental_term_months' => 12, 'advance_months' => 6]);
        $above = $this->listing($headers, ['type' => 'house', 'purpose' => 'rent', 'price' => 200000,
            'monthly_rent' => 200000, 'rental_term_months' => 12, 'advance_months' => 1, 'longitude' => 44.3]);
        foreach ([$within, $above] as $id) { $this->configure($headers, $id); $this->publish($id); }
        $this->getJson('/api/properties?purpose=rent&max_monthly_rent=150000&currency=YER')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $within);
        $this->getJson('/api/properties?purpose=rent&max_monthly_rent=150000&currency=USD')->assertOk()->assertJsonCount(0, 'data');
    }

    private function advertiser(string $key): array
    {
        $user = User::query()->create(['name' => 'UX '.$key, 'email' => $key.'@ux.example.test',
            'phone' => '+96777'.substr(hash('sha256', $key), 0, 10), 'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE, 'password' => Hash::make('fixture-'.$key)]);
        $role = Role::query()->where('key', 'registered_user')->firstOrFail();
        $user->roles()->sync([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
        AccountVerificationProfile::query()->create(['user_id' => $user->id, 'type' => 'broker',
            'status' => AccountVerificationProfile::STATUS_APPROVED, 'submitted_at' => now()->subHour(), 'reviewed_at' => now()]);
        $plain = 'ux_'.hash('sha256', $key);
        $user->apiTokens()->create(['name' => 'ux-test', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }

    private function payload(array $changes = []): array
    {
        return array_merge(['listing_input_version' => 4, 'title' => 'عقار جولة التحسين', 'purpose' => 'sale',
            'type' => 'house', 'tenure_type' => 'freehold', 'price' => 50000000, 'currency' => 'YER',
            'area_value' => 160, 'area_unit' => 'sqm', 'bedrooms' => 3, 'bathrooms' => 2,
            'has_parking' => false, 'building_facade' => 'north', 'address' => 'صنعاء حدة شارع 14',
            'latitude' => 15.3694, 'longitude' => 44.1910], $changes);
    }

    private function listing(array $headers, array $changes = []): int
    {
        return (int) $this->withHeaders($headers)->post('/api/properties',
            $this->payload(array_merge(['images' => [UploadedFile::fake()->image('listing.jpg')]], $changes)))
            ->assertCreated()->json('data.id');
    }

    private function configure(array $headers, int $id): void
    {
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", [
            'broker_sai_rate_percent' => 2, 'platform_terms_decision' => 'accept',
        ])->assertOk();
    }

    private function publish(int $id): void
    {
        Property::findOrFail($id)->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();
    }
}
