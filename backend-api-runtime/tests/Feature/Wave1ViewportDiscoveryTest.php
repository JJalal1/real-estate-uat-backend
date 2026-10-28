<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Wave1ViewportDiscoveryTest extends TestCase
{
    use RefreshDatabase;

    public function test_viewport_covers_the_visible_rectangle_beyond_the_old_radius_without_exposing_private_rows(): void
    {
        $owner = User::create(['name' => 'Synthetic viewport owner', 'email' => 'wave1-viewport@example.test',
            'password' => 'fixture-only', 'account_status' => 'active', 'phone_verified_at' => now()]);
        $make = fn (string $title, float $latitude, float $longitude, string $status = 'published', string $purpose = 'sale') =>
            Property::create(['user_id' => $owner->id, 'title' => $title, 'type' => 'house', 'purpose' => $purpose,
                'price' => 10000000, 'currency' => 'YER', 'latitude' => $latitude, 'longitude' => $longitude,
                'status' => $status, 'review_status' => $status === 'published' ? 'approved' : 'draft',
                'published_at' => $status === 'published' ? now() : null]);
        $near = $make('Synthetic near', 15.36, 44.19);
        $far = $make('Synthetic visible far', 15.90, 44.19);
        $outside = $make('Synthetic outside', 17.0, 45.0);
        $private = $make('Synthetic private', 15.50, 44.20, 'draft');
        $rent = $make('Synthetic other purpose', 15.55, 44.20, 'published', 'rent');
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('UPDATE properties SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography WHERE user_id = ?', [$owner->id]);
        }
        $query = ['latitude' => 15.36, 'longitude' => 44.19, 'radius_km' => 1,
            'south' => 15.30, 'west' => 44.10, 'north' => 16.0, 'east' => 44.30, 'purpose' => 'sale'];
        $legacy = $this->getJson('/api/properties/nearby?'.http_build_query($query))->assertOk();
        $this->assertSame([$near->id], array_column($legacy->json('data'), 'id'));
        $viewport = $this->getJson('/api/properties/nearby?'.http_build_query($query + ['viewport' => 1]))->assertOk();
        $this->assertEqualsCanonicalizing([$near->id, $far->id], array_column($viewport->json('data'), 'id'));
        foreach ([$outside, $private, $rent] as $hidden) {
            $this->assertNotContains($hidden->id, array_column($viewport->json('data'), 'id'));
        }
        $viewport->assertJsonMissingPath('data.0.user_id')->assertJsonMissingPath('data.0.last_review_reason');
    }

    public function test_viewport_requires_complete_valid_bounds_and_does_not_relax_other_filters(): void
    {
        $this->getJson('/api/properties/nearby?latitude=15&longitude=44&viewport=1')->assertUnprocessable();
        $this->getJson('/api/properties/nearby?latitude=15&longitude=44&viewport=1&south=16&north=15&west=44&east=45')->assertUnprocessable();
        $this->getJson('/api/properties/nearby?latitude=15&longitude=44&viewport=invalid')->assertUnprocessable();
        $this->getJson('/api/properties/nearby?latitude=15&longitude=44&viewport=1&south=14&north=16&west=43&east=45&type=not-real')->assertUnprocessable();
    }
}
