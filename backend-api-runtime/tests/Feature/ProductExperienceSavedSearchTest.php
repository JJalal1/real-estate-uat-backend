<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\SavedSearchAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ProductExperienceSavedSearchTest extends TestCase
{
    use RefreshDatabase;

    public function test_saved_search_is_account_bound_deduplicated_and_matches_filters(): void
    {
        [$user, $headers] = $this->user('searcher@example.test', '+967770001001');
        [, $otherHeaders] = $this->user('other@example.test', '+967770001002');
        $this->property('matching villa', 'sale', 'villa', 50000000, 'published');
        $this->property('too expensive villa', 'sale', 'villa', 90000000, 'published');

        $payload = [
            'name' => 'فلل مناسبة',
            'alert_frequency' => 'instant',
            'filters' => [
                'purpose' => 'sale',
                'type' => 'villa',
                'max_price' => 60000000,
            ],
        ];

        $created = $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)
            ->assertCreated()
            ->assertJsonPath('data.name', 'فلل مناسبة')
            ->assertJsonPath('data.matching_count', 1);
        $id = (int) $created->json('data.id');

        $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)
            ->assertOk()
            ->assertJsonPath('data.id', $id);

        $this->withHeaders($otherHeaders)->patchJson('/api/saved-searches/'.$id, [
            'name' => 'لا يجب أن يتغير',
        ])->assertNotFound();

        $this->withHeaders($headers)->patchJson('/api/saved-searches/'.$id, [
            'alert_frequency' => 'daily',
        ])->assertOk()->assertJsonPath('data.alert_frequency', 'daily');

        $this->assertDatabaseHas('saved_property_searches', [
            'id' => $id,
            'user_id' => $user->id,
            'alert_frequency' => 'daily',
        ]);
    }

    public function test_instant_saved_search_alert_does_not_notify_listing_owner(): void
    {
        [$searcher, $headers] = $this->user('alert@example.test', '+967770001003');
        [$owner] = $this->user('owner@example.test', '+967770001004');

        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'شقق إيجار',
            'alert_frequency' => 'instant',
            'filters' => ['purpose' => 'rent', 'type' => 'apartment'],
        ])->assertCreated();

        $listing = $this->property('شقة جديدة', 'rent', 'apartment', 150000, 'published', $owner);
        $count = app(SavedSearchAlertService::class)->notifyPublishedProperty($listing->id);

        $this->assertSame(1, $count);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $searcher->id,
            'type' => 'saved_search_match',
            'entity_type' => 'property',
            'entity_id' => $listing->id,
        ]);
        $this->assertDatabaseMissing('user_notifications', [
            'user_id' => $owner->id,
            'type' => 'saved_search_match',
            'entity_id' => $listing->id,
        ]);
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Experience User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $plain = 'experience_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'experience-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(
        string $title,
        string $purpose,
        string $type,
        float $price,
        string $status,
        ?User $owner = null,
    ): Property {
        $owner ??= User::query()->create([
            'name' => 'Listing Owner '.$title,
            'email' => substr(hash('sha256', $title), 0, 20).'@example.test',
            'phone' => '+967'.substr(preg_replace('/\D/', '', (string) crc32($title)), 0, 9),
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);

        return Property::query()->create([
            'user_id' => $owner->id,
            'title' => $title,
            'purpose' => $purpose,
            'type' => $type,
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => 180,
            'address' => 'صنعاء',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => $status,
            'review_status' => $status === 'published' ? 'approved' : 'draft',
            'published_at' => $status === 'published' ? now() : null,
        ]);
    }
}
