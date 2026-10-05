<?php

namespace Tests\Postgres;

use App\Models\Property;
use App\Models\PropertyFavorite;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class W4aFavoritesPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // Refuse any environment other than the existing disposable CI target.
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_postgres_favorite_requests_preserve_privacy_persistence_and_cascade(): void
    {
        DB::beginTransaction();
        try {
            [$owner] = $this->account('owner', '+967700004101');
            [$buyerA, $headersA] = $this->account('buyer-a', '+967700004102');
            [, $headersB] = $this->account('buyer-b', '+967700004103');
            $property = Property::query()->create([
                'user_id' => $owner->id, 'title' => 'Public PG favorite',
                'description' => 'Public description', 'purpose' => 'sale', 'type' => 'house',
                'price' => 15000000, 'currency' => 'YER', 'address' => 'صنعاء',
                'latitude' => 15.3694, 'longitude' => 44.1910,
                'status' => 'published', 'review_status' => 'approved',
            ]);
            $url = "/api/properties/{$property->id}/favorite";
            for ($i = 0; $i < 2; $i++) {
                $this->withHeaders($headersA)->putJson($url)->assertOk()
                    ->assertJsonPath('data.availability', 'available');
            }
            $saved = PropertyFavorite::query()->where('user_id', $buyerA->id)->sole();
            $savedAt = $saved->created_at->toIso8601String();
            $this->withHeaders($headersA)->getJson('/api/favorites')->assertOk()
                ->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.property.id', $property->id)
                ->assertJsonPath('data.0.availability', 'available');

            $property->update([
                'status' => 'draft', 'review_status' => 'returned_for_correction',
                'title' => 'PRIVATE PG EDIT', 'price' => 987654321, 'address' => 'PRIVATE PG ADDRESS',
            ]);
            $property->images()->create([
                'path' => 'private/pg-edit.jpg', 'cdn_url' => 'https://private.example.test/pg-edit.jpg',
            ]);
            $this->withHeaders($headersA)->getJson('/api/favorites')->assertOk()
                ->assertJsonPath('meta.total', 1)->assertExactJson([
                    'data' => [[
                        'property_id' => $property->id, 'is_favorited' => true,
                        'favorited_at' => $savedAt, 'availability' => 'unavailable',
                        'message' => 'هذا العقار محفوظ في المفضلة لكنه غير متاح حالياً.',
                    ]],
                    'meta' => ['current_page' => 1, 'last_page' => 1, 'per_page' => 20, 'total' => 1],
                ]);
            $this->withHeaders($headersA)->getJson('/api/favorites/ids')->assertOk()
                ->assertExactJson(['data' => ['property_ids' => [$property->id]]]);
            $this->withHeaders($headersA)->getJson($url)->assertOk()->assertExactJson([
                'data' => ['property_id' => $property->id, 'is_favorited' => true, 'availability' => 'unavailable'],
            ]);
            $this->withHeaders($headersA)->putJson($url)->assertNotFound();
            $this->withHeaders($headersB)->getJson('/api/favorites')->assertOk()->assertJsonPath('meta.total', 0);
            $this->withHeaders($headersB)->getJson('/api/favorites/ids')->assertOk()
                ->assertExactJson(['data' => ['property_ids' => []]]);
            $private = $this->withHeaders($headersB)->getJson($url)->assertNotFound();
            $missing = $this->withHeaders($headersB)->getJson('/api/properties/99999999/favorite')->assertNotFound();
            $this->assertSame($missing->json(), $private->json());
            $this->withHeaders($headersB)->deleteJson($url)->assertOk();
            $this->assertSame($saved->id, PropertyFavorite::query()->where('user_id', $buyerA->id)->sole()->id);

            $property->update(['status' => 'published', 'review_status' => 'approved']);
            $this->withHeaders($headersA)->getJson('/api/favorites')->assertOk()
                ->assertJsonPath('data.0.availability', 'available')
                ->assertJsonPath('data.0.property.id', $property->id)
                ->assertJsonPath('data.0.favorited_at', $savedAt);
            $this->assertSame($saved->id, PropertyFavorite::query()->where('user_id', $buyerA->id)->sole()->id);

            $property->update(['status' => 'draft']);
            for ($i = 0; $i < 2; $i++) {
                $this->withHeaders($headersA)->deleteJson($url)->assertOk()->assertJsonPath('data.is_favorited', false);
            }
            $this->assertSame(0, PropertyFavorite::query()->where('user_id', $buyerA->id)->count());
            $property->update(['status' => 'published', 'review_status' => 'approved']);
            $this->withHeaders($headersA)->putJson($url)->assertOk();
            $property->update(['status' => 'draft']);
            $this->assertSame(1, PropertyFavorite::query()->where('user_id', $buyerA->id)->count());
            $property->delete();
            $this->assertSame(0, PropertyFavorite::query()->where('user_id', $buyerA->id)->count());
            $this->withHeaders($headersA)->deleteJson($url)->assertOk();
        } finally {
            DB::rollBack();
        }
    }

    private function account(string $name, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'W4a PG '.$name, 'email' => 'w4a-pg-'.$name.'@example.test', 'phone' => $phone,
            'phone_verified_at' => now(), 'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('W4aFixtureOnly!'),
        ]);
        $plain = 're6_'.substr(hash('sha512', 'w4a-pg-'.$name), 0, 80);
        $user->apiTokens()->create([
            'name' => 'w4a-pg-fixture', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour(),
        ]);

        return [$user, ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }
}
