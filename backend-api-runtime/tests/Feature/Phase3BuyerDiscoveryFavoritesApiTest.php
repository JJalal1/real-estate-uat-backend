<?php

namespace Tests\Feature;

use App\Models\Property;
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
