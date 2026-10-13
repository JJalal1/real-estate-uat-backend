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

class Wave3MarketplaceApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_personal_owner_has_one_listing_and_can_continue_editing_it(): void
    {
        [$owner, $headers] = $this->actor('personal', 'owner');
        $this->withHeaders($headers)->getJson('/api/listing-access')->assertOk()
            ->assertJsonPath('data.listing_limit', 1)->assertJsonPath('data.can_create', true);
        $id = $this->create($headers);
        $this->withHeaders($headers)->post('/api/properties', $this->payload(['title' => 'عقار ثان']))
            ->assertConflict()->assertJsonPath('code', 'personal_listing_limit');
        $this->withHeaders($headers)->post("/api/properties/$id", $this->payload(['title' => 'تحديث عقاري']))->assertOk();
        $this->assertDatabaseHas('properties', ['id' => $id, 'user_id' => $owner->id, 'title' => 'تحديث عقاري']);
        $this->assertDatabaseCount('properties', 1);
        $this->withHeaders($headers)->getJson('/api/listing-access')->assertOk()
            ->assertJsonPath('data.upgrade_required', true)->assertJsonPath('data.can_create', false);
    }

    public function test_only_approved_broker_and_office_can_create_multiple_listings_and_use_workspace(): void
    {
        foreach (['broker', 'office'] as $type) {
            [, $headers] = $this->actor('multi-'.$type, $type);
            $this->create($headers);
            $this->create($headers, ['longitude' => 44.23, 'title' => 'عقار إضافي']);
            $this->withHeaders($headers)->getJson('/api/listing-access')->assertOk()->assertJsonPath('data.listing_limit', null);
            $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertOk();
        }
        [$pending, $headers] = $this->actor('pending', 'broker');
        $pending->accountVerificationProfile()->update(['status' => 'pending']);
        $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertForbidden();
        $this->withHeaders($headers)->post('/api/properties', $this->payload())->assertConflict();
    }

    public function test_personal_owner_keeps_property_actions_but_cannot_open_crm(): void
    {
        [, $headers] = $this->actor('owner-tools', 'owner');
        $id = $this->create($headers);
        Property::findOrFail($id)->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();
        foreach (['/api/broker/workspace', '/api/broker/customers'] as $path) {
            $this->withHeaders($headers)->getJson($path)->assertForbidden();
        }
        $this->withHeaders($headers)->getJson('/api/broker/finance')->assertOk();
        $this->withHeaders($headers)->getJson('/api/broker/listings/availability')->assertOk();
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability', ['property_ids' => [$id], 'state' => 'paused'])->assertOk();
        $this->assertDatabaseHas('properties', ['id' => $id, 'availability_status' => 'paused']);
    }

    public function test_apartment_whole_floor_keeps_legacy_identity_and_search_compatibility(): void
    {
        [, $headers] = $this->actor('scope', 'broker');
        $legacy = $this->create($headers, ['listing_input_version' => 4, 'type' => 'floor', 'floor_number' => 'الثالث']);
        $modern = $this->create($headers, ['type' => 'apartment', 'floor_number' => '٣', 'unit_number' => 'stale', 'unit_occupies_entire_floor' => 1]);
        $old = Property::findOrFail($legacy); $new = Property::findOrFail($modern);
        $this->assertSame($old->property_asset_id, $new->property_asset_id);
        $this->assertSame('@whole_floor', $new->propertyAsset->unit_number);
        $this->assertTrue($new->unit_occupies_entire_floor);
        $this->assertNull($new->unit_number);
        $new->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();
        $this->getJson('/api/properties?type=apartment')->assertOk()->assertJsonPath('data.0.id', $modern);
        $this->getJson('/api/properties?type=floor')->assertOk()->assertJsonPath('data.0.id', $modern);
        $this->withHeaders($headers)->post('/api/properties', $this->payload(['type' => 'apartment', 'unit_occupies_entire_floor' => 1]))
            ->assertUnprocessable()->assertJsonValidationErrors('floor_number');
    }

    public function test_whole_building_and_house_discard_irrelevant_unit_scope(): void
    {
        [, $headers] = $this->actor('whole', 'broker');
        foreach (['building', 'house', 'villa'] as $type) {
            $id = $this->create($headers, ['type' => $type, 'floor_number' => '3', 'unit_number' => '7', 'unit_occupies_entire_floor' => 1]);
            $property = Property::findOrFail($id);
            $this->assertNull($property->floor_number);
            $this->assertNull($property->unit_number);
            $this->assertFalse($property->unit_occupies_entire_floor);
        }
    }

    public function test_owner_upgrade_requires_fresh_documents_and_review(): void
    {
        [$owner, $headers] = $this->actor('upgrade', 'owner');
        $this->withHeaders($headers)->post('/api/account-verification', ['type' => 'broker', 'governorate' => 'صنعاء', 'district' => 'حدة'])
            ->assertUnprocessable();
        $this->assertSame('owner', $owner->fresh()->verificationProfileType());
        $this->withHeaders($headers)->post('/api/account-verification', ['type' => 'broker', 'governorate' => 'صنعاء', 'district' => 'حدة',
            'identity_document' => UploadedFile::fake()->image('id.jpg'), 'selfie' => UploadedFile::fake()->image('selfie.jpg'),
            'work_areas_json' => json_encode(['حدة'])])->assertOk()->assertJsonPath('data.status', 'pending');
        $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertForbidden();
        $this->assertFalse(app(\App\Services\ListingAccessService::class)->isProfessional($owner->fresh()));
    }

    private function actor(string $key, string $type): array
    {
        $user = User::create(['name' => 'أحمد محمد علي صالح', 'email' => $key.'@wave3.example.test',
            'phone' => '+96777'.substr(hash('sha256', $key), 0, 10), 'password' => Hash::make('fixture-'.$key),
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'identity_policy_version' => 2, 'account_status' => 'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]]);
        AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type, 'status' => 'approved', 'submitted_at' => now()->subDay(), 'reviewed_at' => now()]);
        $token = 'wave3_'.hash('sha256', $key);
        $user->apiTokens()->create(['name' => 'wave3-test', 'token_hash' => hash('sha256', $token), 'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function payload(array $changes = []): array
    {
        return array_merge(['listing_input_version' => 5, 'title' => 'منزل للعائلة في حدة', 'purpose' => 'sale', 'type' => 'house',
            'tenure_type' => 'freehold', 'price' => 50000000, 'currency' => 'YER', 'area_value' => 160, 'area_unit' => 'sqm',
            'bedrooms' => 3, 'bathrooms' => 2, 'has_parking' => 0, 'building_facade' => 'north', 'address' => 'صنعاء حدة شارع 14',
            'latitude' => 15.3694, 'longitude' => 44.191, 'images' => [UploadedFile::fake()->image('listing.jpg')]], $changes);
    }

    private function create(array $headers, array $changes = []): int
    {
        return (int) $this->withHeaders($headers)->post('/api/properties', $this->payload($changes))->assertCreated()->json('data.id');
    }
}
