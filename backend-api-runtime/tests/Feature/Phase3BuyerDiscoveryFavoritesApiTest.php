<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyFavorite;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase3BuyerDiscoveryFavoritesApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_favorites_are_account_bound_idempotent_and_preserve_unavailable_properties(): void
    {
        [$owner] = $this->activeUser('phase3-owner@example.test', '+967700003001');
        [$buyerA, $buyerAHeaders] = $this->activeUser('phase3-buyer-a@example.test', '+967700003002');
        [, $buyerBHeaders] = $this->activeUser('phase3-buyer-b@example.test', '+967700003003');
        $published = $this->property($owner, 'Published favorite', 'published');
        $other = $this->property($owner, 'Other published', 'published', ['price' => 22000000]);

        foreach (['/api/favorites', '/api/favorites/ids', "/api/properties/{$published->id}/favorite"] as $url) {
            $this->getJson($url)->assertUnauthorized();
        }
        $this->putJson("/api/properties/{$published->id}/favorite")->assertUnauthorized();
        $this->deleteJson("/api/properties/{$published->id}/favorite")->assertUnauthorized();

        for ($i = 0; $i < 2; $i++) {
            $this->withHeaders($buyerAHeaders)->putJson("/api/properties/{$published->id}/favorite")
                ->assertOk()->assertJsonPath('data.is_favorited', true)
                ->assertJsonPath('data.availability', 'available');
        }
        $saved = PropertyFavorite::query()->sole();
        $savedAt = $saved->created_at->toIso8601String();
        $this->assertSame((int) $buyerA->id, (int) $saved->user_id);
        $this->assertSame((int) $published->id, (int) $saved->property_id);
        $this->withHeaders($buyerAHeaders)->getJson("/api/properties/{$published->id}/favorite")
            ->assertOk()->assertExactJson(['data' => [
                'property_id' => $published->id, 'is_favorited' => true, 'availability' => 'available',
            ]]);
        $this->withHeaders($buyerBHeaders)->getJson("/api/properties/{$published->id}/favorite")
            ->assertOk()->assertJsonPath('data.is_favorited', false)
            ->assertJsonPath('data.availability', 'available');

        $this->withHeaders($buyerAHeaders)->getJson('/api/favorites')
            ->assertOk()->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.availability', 'available')
            ->assertJsonPath('data.0.property.id', $published->id)
            ->assertJsonPath('data.0.property.price', 15000000)
            ->assertJsonMissingPath('data.0.property.review_status')
            ->assertJsonMissingPath('data.0.property.property_asset_id')
            ->assertJsonMissingPath('data.0.property.geo_cell_id');
        $this->withHeaders($buyerAHeaders)->putJson("/api/properties/{$other->id}/favorite")->assertOk();

        $published->update([
            'status' => 'draft', 'review_status' => 'returned_for_correction',
            'title' => 'PRIVATE UNPUBLISHED EDIT', 'description' => 'PRIVATE DESCRIPTION',
            'price' => 987654321, 'address' => 'PRIVATE PRECISE ADDRESS',
            'latitude' => 16.123456, 'longitude' => 45.654321,
            'contact_phone' => '+967799999999', 'last_review_reason' => 'PRIVATE REVIEW',
            'document_owner_name' => 'PRIVATE OWNER', 'owner_relationship_note' => 'PRIVATE EVIDENCE',
        ]);
        $published->images()->create([
            'path' => 'private/current-edit.jpg', 'cdn_url' => 'https://private.example.test/current-edit.jpg',
        ]);

        // Pagination and IDs represent account rows, ordered by favorite ID.
        $this->withHeaders($buyerAHeaders)->getJson('/api/favorites?per_page=1')
            ->assertOk()->assertJsonPath('meta.total', 2)->assertJsonPath('meta.last_page', 2)
            ->assertJsonPath('data.0.property_id', $other->id);
        $unavailable = $this->withHeaders($buyerAHeaders)->getJson('/api/favorites?per_page=1&page=2')
            ->assertOk()->assertJsonPath('meta.total', 2);
        $this->assertUnavailable($unavailable->json('data.0'), $published->id, $savedAt);
        foreach (['PRIVATE UNPUBLISHED EDIT', 'PRIVATE DESCRIPTION', 'PRIVATE PRECISE ADDRESS',
            'private.example.test', 'PRIVATE REVIEW', 'PRIVATE OWNER', 'PRIVATE EVIDENCE'] as $secret) {
            $this->assertStringNotContainsString($secret, $unavailable->getContent());
        }
        $this->withHeaders($buyerAHeaders)->getJson('/api/favorites/ids')->assertOk()
            ->assertExactJson(['data' => ['property_ids' => [$other->id, $published->id]]]);
        $this->withHeaders($buyerAHeaders)->getJson("/api/properties/{$published->id}/favorite")
            ->assertOk()->assertExactJson(['data' => [
                'property_id' => $published->id, 'is_favorited' => true, 'availability' => 'unavailable',
            ]]);
        $this->assertDatabaseCount('property_favorites', 2);
        $this->assertSame($saved->id, PropertyFavorite::query()->where('property_id', $published->id)->sole()->id);

        $this->withHeaders($buyerBHeaders)->getJson('/api/favorites')->assertOk()
            ->assertJsonPath('meta.total', 0)->assertJsonCount(0, 'data');
        $this->withHeaders($buyerBHeaders)->getJson('/api/favorites/ids')->assertOk()
            ->assertExactJson(['data' => ['property_ids' => []]]);

        // Republishing is the existing listing workflow's decision. No re-save.
        $published->update(['status' => 'published', 'review_status' => 'approved']);
        $this->withHeaders($buyerAHeaders)->getJson('/api/favorites?per_page=1&page=2')
            ->assertOk()->assertJsonPath('meta.total', 2)
            ->assertJsonPath('data.0.availability', 'available')
            ->assertJsonPath('data.0.property.id', $published->id)
            ->assertJsonPath('data.0.property.title', 'PRIVATE UNPUBLISHED EDIT')
            ->assertJsonPath('data.0.favorited_at', $savedAt);
        $restored = PropertyFavorite::query()->where('property_id', $published->id)->sole();
        $this->assertSame($saved->id, $restored->id);
        $this->assertSame($savedAt, $restored->created_at->toIso8601String());
        $this->withHeaders($buyerAHeaders)->putJson("/api/properties/{$published->id}/favorite")->assertOk();
        $this->assertDatabaseCount('property_favorites', 2);
    }

    public function test_all_nonpublished_states_keep_only_safe_favorite_metadata_and_block_actions(): void
    {
        [$owner] = $this->activeUser('w4a-states-owner@example.test', '+967700004001');
        [, $headers] = $this->activeUser('w4a-states-buyer@example.test', '+967700004002');
        $property = $this->property($owner, 'Saved property', 'published');
        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/favorite")->assertOk();
        $saved = PropertyFavorite::query()->sole();
        $image = $property->images()->create(['path' => 'private/edit.jpg']);

        foreach ([
            ['draft', 'draft'], ['draft', 'returned_for_correction'],
            ['pending', 'submitted'], ['rejected', 'rejected_blocked'],
        ] as [$status, $reviewStatus]) {
            $property->update(['status' => $status, 'review_status' => $reviewStatus]);
            $list = $this->withHeaders($headers)->getJson('/api/favorites')->assertOk()
                ->assertJsonPath('meta.total', 1);
            $this->assertUnavailable($list->json('data.0'), $property->id, $saved->created_at->toIso8601String());
            $this->withHeaders($headers)->getJson('/api/favorites/ids')->assertOk()
                ->assertExactJson(['data' => ['property_ids' => [$property->id]]]);
            $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/favorite")->assertNotFound();
            $this->withHeaders($headers)->getJson("/api/properties/{$property->id}")->assertNotFound();
            $this->withHeaders($headers)->getJson("/api/property-media/{$image->id}")->assertNotFound();
            $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/conversation")->assertNotFound();
            $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/viewings", [
                'starts_at' => now()->addDay()->toIso8601String(),
            ])->assertNotFound();
            $this->assertDatabaseCount('property_favorites', 1);
            $this->assertDatabaseHas('property_favorites', ['id' => $saved->id, 'property_id' => $property->id]);
            $this->assertDatabaseCount('message_threads', 0);
            $this->assertDatabaseCount('viewing_bookings', 0);
        }
    }

    public function test_unowned_private_and_unknown_ids_do_not_form_a_favorite_enumeration_oracle(): void
    {
        [$owner, $ownerHeaders] = $this->activeUser('w4a-oracle-owner@example.test', '+967700004011');
        [$buyerA, $headersA] = $this->activeUser('w4a-oracle-a@example.test', '+967700004012');
        [, $headersB] = $this->activeUser('w4a-oracle-b@example.test', '+967700004013');
        $property = $this->property($owner, 'Private property', 'published');
        $draft = $this->property($owner, 'Never public', 'draft');
        $this->withHeaders($headersA)->putJson("/api/properties/{$property->id}/favorite")->assertOk();
        $property->update(['status' => 'draft']);
        $missingId = 99999999;

        foreach ([$headersB, $ownerHeaders] as $headers) {
            $missingStatus = $this->withHeaders($headers)->getJson("/api/properties/{$missingId}/favorite")->assertNotFound();
            $missingAdd = $this->withHeaders($headers)->putJson("/api/properties/{$missingId}/favorite")->assertNotFound();
            foreach ([$property->id, $draft->id] as $id) {
                $privateStatus = $this->withHeaders($headers)->getJson("/api/properties/{$id}/favorite")->assertNotFound();
                $this->assertSame($missingStatus->json(), $privateStatus->json());
                $privateAdd = $this->withHeaders($headers)->putJson("/api/properties/{$id}/favorite")->assertNotFound();
                $this->assertSame($missingAdd->json(), $privateAdd->json());
                // Same no-op shape for a private ID or an absent ID; only echo input.
                $this->withHeaders($headers)->deleteJson("/api/properties/{$id}/favorite")->assertOk()
                    ->assertExactJson(['message' => 'Property removed from favorites.', 'data' => [
                        'property_id' => $id, 'is_favorited' => false,
                    ]]);
            }
            $this->withHeaders($headers)->deleteJson("/api/properties/{$missingId}/favorite")->assertOk()
                ->assertExactJson(['message' => 'Property removed from favorites.', 'data' => [
                    'property_id' => $missingId, 'is_favorited' => false,
                ]]);
        }
        $this->assertDatabaseCount('property_favorites', 1);
        $this->assertDatabaseHas('property_favorites', ['user_id' => $buyerA->id, 'property_id' => $property->id]);
        $this->assertDatabaseHas('properties', ['id' => $property->id, 'status' => 'draft']);
    }

    public function test_removing_unavailable_favorites_is_idempotent_and_only_affects_the_caller(): void
    {
        [$owner] = $this->activeUser('w4a-remove-owner@example.test', '+967700004021');
        [$buyerA, $headersA] = $this->activeUser('w4a-remove-a@example.test', '+967700004022');
        [$buyerB, $headersB] = $this->activeUser('w4a-remove-b@example.test', '+967700004023');
        $property = $this->property($owner, 'Shared favorite', 'published');
        foreach ([$headersA, $headersB] as $headers) {
            $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/favorite")->assertOk();
            $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/favorite")->assertOk();
        }
        $this->assertDatabaseCount('property_favorites', 2);
        $property->update(['status' => 'draft']);
        for ($i = 0; $i < 2; $i++) {
            $this->withHeaders($headersB)->deleteJson("/api/properties/{$property->id}/favorite")
                ->assertOk()->assertJsonPath('data.is_favorited', false);
        }
        $this->assertDatabaseCount('property_favorites', 1);
        $this->assertDatabaseMissing('property_favorites', ['user_id' => $buyerB->id]);
        $this->assertDatabaseHas('property_favorites', ['user_id' => $buyerA->id, 'property_id' => $property->id]);
        $this->withHeaders($headersB)->getJson("/api/properties/{$property->id}/favorite")->assertNotFound();
        $this->withHeaders($headersA)->getJson('/api/favorites')->assertOk()
            ->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.availability', 'unavailable');
        for ($i = 0; $i < 2; $i++) {
            $this->withHeaders($headersA)->deleteJson("/api/properties/{$property->id}/favorite")
                ->assertOk()->assertJsonPath('data.is_favorited', false);
        }
        $this->assertDatabaseCount('property_favorites', 0);
        $this->withHeaders($headersA)->getJson('/api/favorites/ids')->assertOk()
            ->assertExactJson(['data' => ['property_ids' => []]]);
        $this->withHeaders($headersA)->getJson("/api/properties/{$property->id}/favorite")->assertNotFound();
    }

    public function test_hard_delete_retains_the_existing_cascade_limit_without_a_tombstone(): void
    {
        [$owner] = $this->activeUser('w4a-delete-owner@example.test', '+967700004031');
        [, $headers] = $this->activeUser('w4a-delete-buyer@example.test', '+967700004032');
        $property = $this->property($owner, 'Deleted later', 'published');
        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/favorite")->assertOk();
        $property->update(['status' => 'draft']);
        $this->assertDatabaseCount('property_favorites', 1);
        $property->delete();
        $this->assertDatabaseCount('property_favorites', 0);
        $this->withHeaders($headers)->getJson('/api/favorites')->assertOk()->assertJsonPath('meta.total', 0);
        $this->withHeaders($headers)->getJson('/api/favorites/ids')->assertOk()
            ->assertExactJson(['data' => ['property_ids' => []]]);
        $this->withHeaders($headers)->deleteJson("/api/properties/{$property->id}/favorite")->assertOk();
        $this->withHeaders($headers)->getJson("/api/properties/{$property->id}/favorite")->assertNotFound();
    }

    private function assertUnavailable(array $item, int $propertyId, string $savedAt): void
    {
        $this->assertSame($propertyId, $item['property_id']);
        $this->assertTrue($item['is_favorited']);
        $this->assertSame('unavailable', $item['availability']);
        $this->assertSame($savedAt, $item['favorited_at']);
        $this->assertSame('هذا العقار محفوظ في المفضلة لكنه غير متاح حالياً.', $item['message']);
        $this->assertEqualsCanonicalizing(
            ['property_id', 'is_favorited', 'favorited_at', 'availability', 'message'],
            array_keys($item),
        );
        foreach ([
            'property', 'id', 'user_id', 'title', 'purpose', 'type', 'tenure_type',
            'price', 'base_price', 'display_price', 'currency', 'monthly_rent',
            'address', 'latitude', 'longitude', 'location', 'land_boundary_geojson',
            'main_image', 'images', 'media', 'cdn_url', 'path', 'description',
            'contact_phone', 'contact_whatsapp', 'advertiser', 'owner_key',
            'review_status', 'last_review_reason', 'reviewed_at', 'submitted_at',
            'documents', 'proof_document_count', 'ownership_document_type',
            'document_owner_name', 'owner_relationship_type', 'owner_relationship_note',
            'property_asset_id', 'geo_cell_id', 'current_sai_term_id',
            'duplicate_check_metadata', 'duplicate_self_verification',
            'building_reference', 'unit_number', 'floor_number',
            'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms',
            'financial_hold_at', 'financial_hold_reason', 'status',
        ] as $sensitiveField) {
            $this->assertArrayNotHasKey($sensitiveField, $item);
        }
    }

    public function test_anonymous_discovery_only_exposes_public_property_fields(): void
    {
        [$owner] = $this->activeUser('phase3-public-owner@example.test', '+967700003011');
        $published = $this->property($owner, 'Sanaa apartment', 'published', [
            'purpose' => 'sale',
            'type' => 'apartment',
            'price' => 31000000,
            'address' => 'صنعاء حدة',
            'review_status' => 'approved',
            'last_review_reason' => 'internal support note',
        ]);
        $this->property($owner, 'Hidden draft', 'draft', [
            'purpose' => 'sale',
            'type' => 'apartment',
            'price' => 10000000,
        ]);

        $list = $this->getJson('/api/properties?purpose=sale&type=apartment&search=حدة&sort=price_asc');
        $list->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $published->id);

        foreach ([
            'review_status',
            'property_asset_id',
            'geo_cell_id',
            'last_review_reason',
            'proof_document_count',
            'can_submit',
            'can_edit',
        ] as $internalField) {
            $list->assertJsonMissingPath("data.0.{$internalField}");
        }

        $details = $this->getJson("/api/properties/{$published->id}");
        $details->assertOk()
            ->assertJsonPath('data.id', $published->id)
            ->assertJsonPath('data.status', 'published');

        foreach ([
            'review_status',
            'property_asset_id',
            'geo_cell_id',
            'last_review_reason',
            'proof_document_count',
            'can_submit',
            'can_edit',
        ] as $internalField) {
            $details->assertJsonMissingPath("data.{$internalField}");
        }
    }

    private function activeUser(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Phase 3 User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('Phase3TestPass!'),
        ]);

        $plain = 're6_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'phase3-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer ' . $plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(User $owner, string $title, string $status, array $overrides = []): Property
    {
        return Property::query()->create(array_merge([
            'user_id' => $owner->id,
            'title' => $title,
            'description' => 'Phase 3 discovery property',
            'purpose' => 'rent',
            'type' => 'house',
            'price' => 15000000,
            'currency' => 'YER',
            'area_m2' => 180,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'صنعاء',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => $status,
            'review_status' => $status === 'published' ? 'approved' : 'draft',
            'published_at' => $status === 'published' ? now() : null,
        ], $overrides));
    }
}
