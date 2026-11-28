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

    public function test_regular_user_can_prepare_multiple_drafts_and_enroll_only_at_second_publication(): void
    {
        [$owner, $headers] = $this->actor('personal', 'owner');
        $owner->accountVerificationProfile()->delete();
        $this->withHeaders($headers)->getJson('/api/listing-access')->assertOk()
            ->assertJsonPath('data.listing_limit', 1)->assertJsonPath('data.can_create', true);

        $first = $this->create($headers);
        $second = $this->create($headers, ['longitude' => 44.25, 'title' => 'عقار ثان']);
        [, $outsiderHeaders] = $this->actor('publication-outsider', 'broker');
        $this->withHeaders($outsiderHeaders)->postJson("/api/properties/$first/submit", [
            'publish_now' => true,
            'upgrade_to_broker' => true,
        ])->assertForbidden();
        $this->withHeaders($headers)->getJson('/api/listing-access')->assertOk()
            ->assertJsonPath('data.listing_count', 0)->assertJsonPath('data.upgrade_required', false);
        $this->withHeaders($headers)->postJson("/api/properties/$first/submit", ['publish_now' => true])
            ->assertOk()->assertJsonPath('data.status', 'pending')->assertJsonPath('data.review_status', 'submitted');
        $this->assertQueuedForReview($first);
        $this->assertSame('distinct', Property::findOrFail($first)->duplicate_check_status);
        [$moderator, $modHeaders] = $this->actor('marketplace-support', 'owner');
        $moderator->roles()->attach(Role::where('key', 'support_agent')->firstOrFail()->id, ['created_at' => now()]);
        $this->withHeaders($modHeaders)->getJson('/api/admin/listing-review/queue')
            ->assertOk()->assertJsonPath('data.0.id', $first);
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$first/start")->assertOk();
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$first/approve")
            ->assertOk()->assertJsonPath('data.status', 'published');
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$first")->assertOk();
        $this->withHeaders($headers)->post("/api/properties/$first", [
            'title' => 'منزل للعائلة في حدة بعد التعديل',
            'submit_for_review' => true,
            'publish_now' => true,
        ])->assertOk()->assertJsonPath('data.id', $first)->assertJsonPath('data.status', 'pending');
        $this->assertSame($first, (int) $owner->fresh()->first_marketplace_listing_id);
        $this->withHeaders($headers)->postJson("/api/properties/$first/submit", ['publish_now' => true])
            ->assertOk()->assertJsonPath('data.status', 'pending')->assertJsonPath('data.review_status', 'submitted');
        $this->assertNull($owner->fresh()->broker_enrolled_at);
        $this->assertQueuedForReview($first);
        $this->assertSame(2, Property::findOrFail($first)->reviews()->where('action', 'submitted')->count());
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$first/start")->assertOk();
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$first/approve")->assertOk();
        $this->withHeaders($headers)->deleteJson("/api/properties/$first")->assertOk();

        $publish = "/api/properties/$second/submit";
        $this->withHeaders($headers)->postJson($publish, ['publish_now' => true])
            ->assertConflict()->assertJsonPath('code', 'broker_upgrade_required');
        $this->assertDatabaseHas('properties', ['id' => $second, 'status' => 'draft']);
        $this->assertNull($owner->fresh()->broker_enrolled_at);
        $this->withHeaders($headers)->postJson($publish, ['publish_now' => true, 'upgrade_to_broker' => true])
            ->assertOk()->assertJsonPath('data.status', 'pending')->assertJsonPath('data.review_status', 'submitted')
            ->assertJsonPath('session.user.account_type', 'broker')->assertJsonPath('session.user.broker_enrolled', true);
        $this->assertQueuedForReview($second);
        $this->withHeaders($headers)->postJson($publish, ['publish_now' => true, 'upgrade_to_broker' => true])
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertSame(1, Property::findOrFail($second)->reviews()->where('action', 'submitted')->count());
        $this->withHeaders($headers)->getJson('/api/auth/me')->assertOk()
            ->assertJsonPath('data.user.account_type', 'broker')->assertJsonPath('data.user.broker_enrolled', true);
        $owner->refresh();
        $this->assertNotNull($owner->broker_enrolled_at);
        $this->assertFalse($owner->isBrokerVerified());
        $this->assertFalse($owner->hasPermission('listings.moderate'));
        $this->assertFalse($owner->hasApprovedVerificationProfile());
        $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertOk();
        $this->withHeaders($headers)->getJson('/api/listing-sai-policy?purpose=sale')->assertOk()
            ->assertJsonPath('data.advertiser_type', 'broker');
        $this->withHeaders($headers)->getJson("/api/properties/$second/sai-management")->assertOk()
            ->assertJsonPath('data.sai_management.advertiser_type', 'broker')
            ->assertJsonPath('data.sai_management.requested_broker_rate_percent', 2)
            ->assertJsonPath('data.sai_management.configured', true);

        $third = $this->create($headers, ['longitude' => 44.30, 'title' => 'عقار ثالث']);
        $this->withHeaders($headers)->postJson("/api/properties/$third/submit", ['publish_now' => true])
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertQueuedForReview($third);
    }

    public function test_existing_professionals_keep_the_workspace_and_pending_accounts_can_draft(): void
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
        $this->withHeaders($headers)->post('/api/properties', $this->payload())->assertCreated();
    }

    public function test_legacy_owner_is_an_individual_publicly_and_keeps_property_actions_but_not_crm(): void
    {
        [$owner, $headers] = $this->actor('owner-tools', 'owner');
        $id = $this->create($headers);
        Property::findOrFail($id)->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();
        $this->getJson("/api/advertisers/{$owner->id}/profile")->assertOk()
            ->assertJsonPath('data.account_type', 'individual')
            ->assertJsonPath('data.verified', false);
        $this->getJson("/api/properties/$id")->assertOk()
            ->assertJsonPath('data.advertiser.verification_type', null)
            ->assertJsonPath('data.advertiser.verification_label', 'معلن')
            ->assertJsonPath('data.advertiser.verification_status', 'not_submitted')
            ->assertJsonPath('data.advertiser.verification_flags.identity_reviewed', false)
            ->assertJsonPath('data.advertiser.verification_flags.relationship_document_reviewed', false);
        foreach (['/api/broker/workspace', '/api/broker/customers'] as $path) {
            $this->withHeaders($headers)->getJson($path)->assertForbidden();
        }
        $this->withHeaders($headers)->getJson('/api/broker/finance')->assertOk();
        $this->withHeaders($headers)->getJson('/api/broker/listings/availability')->assertOk();
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability', ['property_ids' => [$id], 'state' => 'available'])->assertOk();
        $this->assertDatabaseHas('properties', ['id' => $id, 'availability_status' => 'available']);
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

    public function test_legacy_owner_enrolls_from_second_publication_without_changing_verification(): void
    {
        [$owner, $headers] = $this->actor('legacy-owner-enroll', 'owner');
        $verification = $owner->verificationProfile()->getRawOriginal();
        $first = $this->create($headers);
        $second = $this->create($headers, ['longitude' => 44.25, 'title' => 'إعلان إضافي']);

        $this->withHeaders($headers)->postJson("/api/properties/$first/submit", ['publish_now' => true])
            ->assertOk()->assertJsonPath('data.status', 'pending')->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($headers)->postJson("/api/properties/$second/submit", ['publish_now' => true])
            ->assertConflict()->assertJsonPath('code', 'broker_upgrade_required');
        $this->assertNull($owner->fresh()->broker_enrolled_at);

        $this->withHeaders($headers)->postJson("/api/properties/$second/submit", [
            'publish_now' => true,
            'upgrade_to_broker' => true,
        ])->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertQueuedForReview($first);
        $this->assertQueuedForReview($second);

        $owner->refresh();
        $this->assertNotNull($owner->broker_enrolled_at);
        $this->assertSame($first, (int) $owner->first_marketplace_listing_id);
        $this->assertSame($verification, $owner->verificationProfile()->getRawOriginal());
        $this->assertFalse($owner->hasPermission('listings.moderate'));
        $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertOk();
    }

    public function test_old_personal_account_can_submit_for_review_without_proof(): void
    {
        [$user, $headers] = $this->actor('version-zero', 'owner');
        $user->accountVerificationProfile()->delete();
        $user->forceFill(['identity_policy_version' => 0])->save();

        $created = $this->withHeaders($headers)->post('/api/properties', $this->payload([
            'submit_for_review' => true,
        ]))->assertCreated()->assertJsonPath('data.review_status', 'submitted');

        $id = (int) $created->json('data.id');
        $this->assertSame($id, (int) $user->fresh()->first_marketplace_listing_id);
        $this->assertDatabaseMissing('listing_documents', ['property_id' => $id]);
    }

    public function test_legacy_review_request_still_validates_documents_independently_of_enrollment(): void
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

    private function assertQueuedForReview(int $id): void
    {
        $this->assertDatabaseHas('properties', [
            'id' => $id, 'review_status' => 'submitted', 'status' => 'pending', 'published_at' => null,
        ]);
        $this->assertDatabaseHas('support_tasks', ['source_type' => 'listing_review', 'source_id' => $id, 'status' => 'new']);
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$id")->assertNotFound();
        $public = $this->getJson('/api/properties')->assertOk()->json('data');
        $this->assertNotContains($id, array_column($public, 'id'));
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
        $id = (int) $this->withHeaders($headers)->post('/api/properties', $this->payload($changes))->assertCreated()->json('data.id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", [
            'broker_sai_rate_percent' => 2,
            'platform_terms_decision' => 'accept',
        ])->assertOk();
        return $id;
    }
}
