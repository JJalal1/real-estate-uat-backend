<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase3BuyerDiscoveryFavoritesApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_favorites_are_account_bound_idempotent_and_hide_unpublished_properties(): void
    {
        [$owner] = $this->activeUser('phase3-owner@example.test', '+967700003001');
        [$buyerA, $buyerAHeaders] = $this->activeUser('phase3-buyer-a@example.test', '+967700003002');
        [, $buyerBHeaders] = $this->activeUser('phase3-buyer-b@example.test', '+967700003003');

        $published = $this->property($owner, 'Published favorite', 'published');
        $other = $this->property($owner, 'Other published', 'published', ['price' => 22000000]);
        $draft = $this->property($owner, 'Private draft', 'draft');

        $this->getJson('/api/favorites')->assertUnauthorized();
        $this->putJson("/api/properties/{$published->id}/favorite")->assertUnauthorized();

        $this->withHeaders($buyerAHeaders)
            ->putJson("/api/properties/{$published->id}/favorite")
            ->assertOk()
            ->assertJsonPath('data.is_favorited', true);

        $this->withHeaders($buyerAHeaders)
            ->putJson("/api/properties/{$published->id}/favorite")
            ->assertOk()
            ->assertJsonPath('data.is_favorited', true);

        $this->assertDatabaseCount('property_favorites', 1);
        $this->assertDatabaseHas('property_favorites', [
            'user_id' => $buyerA->id,
            'property_id' => $published->id,
        ]);

        $this->withHeaders($buyerAHeaders)
            ->getJson('/api/favorites/ids')
            ->assertOk()
            ->assertJsonPath('data.property_ids.0', $published->id);

        $this->withHeaders($buyerAHeaders)
            ->getJson('/api/favorites')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.property.id', $published->id)
            ->assertJsonPath('data.0.property.published_at', $published->published_at->toIso8601String())
            ->assertJsonMissingPath('data.0.property.review_status')
            ->assertJsonMissingPath('data.0.property.property_asset_id')
            ->assertJsonMissingPath('data.0.property.geo_cell_id');

        $this->withHeaders($buyerBHeaders)
            ->getJson('/api/favorites')
            ->assertOk()
            ->assertJsonPath('meta.total', 0);

        $this->withHeaders($buyerAHeaders)
            ->putJson("/api/properties/{$other->id}/favorite")
            ->assertOk();
        $this->assertDatabaseCount('property_favorites', 2);

        $this->withHeaders($buyerAHeaders)
            ->putJson("/api/properties/{$draft->id}/favorite")
            ->assertNotFound();

        $published->update(['status' => 'draft']);

        $this->withHeaders($buyerAHeaders)
            ->getJson('/api/favorites')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.property.id', $other->id);

        $this->withHeaders($buyerAHeaders)
            ->getJson("/api/properties/{$published->id}/favorite")
            ->assertNotFound();

        $this->withHeaders($buyerAHeaders)
            ->deleteJson("/api/properties/{$published->id}/favorite")
            ->assertOk()
            ->assertJsonPath('data.is_favorited', false);
        $this->withHeaders($buyerAHeaders)
            ->deleteJson("/api/properties/{$published->id}/favorite")
            ->assertOk()
            ->assertJsonPath('data.is_favorited', false);

        $this->assertDatabaseMissing('property_favorites', [
            'user_id' => $buyerA->id,
            'property_id' => $published->id,
        ]);
    }

    public function test_saved_cards_keep_public_facts_images_and_prices_across_pages(): void
    {
        [$owner] = $this->activeUser('card-owner@example.test', '+967700003030');
        [, $headers] = $this->activeUser('card-buyer@example.test', '+967700003031');
        $sale = $this->property($owner, 'Sale with commission included', 'published', [
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 10000000,
            'floor_number' => 3, 'has_parking' => true, 'listing_input_version' => 5,
        ]);
        $term = PropertySaiTerm::query()->create([
            'property_id' => $sale->id, 'version' => 1, 'advertiser_type' => 'broker',
            'purpose' => 'sale', 'source_mode' => 'broker_custom', 'sai_rate_percent' => 1,
            'payer' => 'buyer', 'calculation_basis' => 'final_sale_value',
            'platform_share_percent' => 10, 'broker_share_percent' => 90,
            'platform_terms_status' => 'not_required', 'created_by_user_id' => $owner->id,
        ]);
        $sale->forceFill(['current_sai_term_id' => $term->id, 'price_display_mode' => 'includes_sai'])->saveQuietly();
        $sale->images()->createMany([
            ['path' => 'listing-originals/unit-a.jpg', 'is_primary' => true, 'sort_order' => 0],
            ['path' => 'listing-originals/unit-b.jpg', 'is_primary' => false, 'sort_order' => 1],
        ]);
        $rent = $this->property($owner, 'Apartment with advance', 'published', [
            'type' => 'apartment', 'price' => 360000, 'monthly_rent' => 120000, 'rental_term_months' => 12, 'advance_months' => 3,
        ]);

        $this->withHeaders($headers)->putJson("/api/properties/{$sale->id}/favorite")->assertOk();
        $this->putJson("/api/properties/{$rent->id}/favorite")->assertOk();

        $this->getJson('/api/favorites?per_page=1')->assertOk()
            ->assertJsonPath('meta.last_page', 2)->assertJsonPath('meta.total', 2)
            ->assertJsonPath('data.0.property.id', $rent->id)
            ->assertJsonPath('data.0.property.monthly_rent', 120000)
            ->assertJsonPath('data.0.property.advance_months', 3);

        $favorite = $this->getJson('/api/favorites?per_page=1&page=2')->assertOk()
            ->assertJsonPath('meta.current_page', 2)
            ->assertJsonPath('data.0.property.id', $sale->id)
            ->assertJsonPath('data.0.property.display_price', 10100000)
            ->assertJsonPath('data.0.property.floor_number', '3')
            ->assertJsonPath('data.0.property.has_parking', true)
            ->assertJsonCount(2, 'data.0.property.image_urls')
            ->json('data.0.property');
        $public = $this->getJson('/api/properties?purpose=sale')->assertOk()->json('data.0');
        foreach (['main_image', 'image_urls', 'floor_number', 'has_parking', 'display_price', 'area_unit'] as $field) {
            $this->assertSame($public[$field], $favorite[$field]);
        }
        foreach (['contact_phone', 'last_review_reason', 'documents', 'sai_attestation_text', 'can_edit'] as $field) {
            $this->assertArrayNotHasKey($field, $favorite);
        }
    }

    public function test_closed_listing_disappears_from_public_links_and_saved_cards_without_erasing_favorites(): void
    {
        [$owner, $ownerHeaders] = $this->activeUser('phase3-closed-owner@example.test', '+967700003020');
        [$buyer, $buyerHeaders] = $this->activeUser('phase3-closed-buyer@example.test', '+967700003021');
        $closed = $this->property($owner, 'Closed property', 'published');
        $open = $this->property($owner, 'Open property', 'published');
        $draft = $this->property($owner, 'Private property', 'draft');
        $this->withHeaders($buyerHeaders)->putJson("/api/properties/{$closed->id}/favorite")->assertOk();

        $closed->forceFill(['availability_status' => 'rented'])->saveQuietly();

        $this->getJson('/api/properties/visible?'.http_build_query(['ids' => [$closed->id, $open->id, $draft->id]]))
            ->assertOk()->assertExactJson(['data' => ['property_ids' => [$open->id]]]);
        $this->getJson('/api/properties/visible?'.http_build_query(['ids' => array_fill(0, 31, $open->id)]))
            ->assertUnprocessable();
        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 1);
        $this->getJson("/api/properties/{$closed->id}")->assertNotFound();
        $this->getJson("/api/properties/{$closed->id}/comments")->assertNotFound();
        $this->getJson("/api/properties/{$closed->id}/sai")->assertNotFound();
        $this->getJson('/api/favorites')->assertOk()->assertJsonPath('meta.total', 0);
        $this->getJson('/api/favorites/ids')->assertOk()->assertJsonPath('data.property_ids', []);
        $this->assertDatabaseHas('property_favorites', ['user_id' => $buyer->id, 'property_id' => $closed->id]);
        $this->withHeaders($ownerHeaders)->getJson("/api/properties/{$closed->id}")
            ->assertOk()->assertJsonPath('data.is_owner', true);
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
            'published_at' => now()->subDays(9)->startOfSecond(),
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
            ->assertJsonPath('data.0.id', $published->id)
            ->assertJsonPath('data.0.published_at', $published->published_at->toIso8601String())
            ->assertJsonMissingPath('data.0.created_at')
            ->assertJsonMissingPath('data.0.updated_at');

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
            ->assertJsonPath('data.status', 'published')
            ->assertJsonPath('data.published_at', $published->published_at->toIso8601String());

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
