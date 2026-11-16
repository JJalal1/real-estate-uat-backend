<?php

namespace Tests\Feature;

use App\Models\Governorate;
use App\Models\Property;
use App\Models\User;
use App\Services\YemenGovernorateCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Phase04GovernoratesTest extends TestCase
{
    use RefreshDatabase;

    public function test_all_22_governorates_are_selectable_without_any_listings_or_coverage_cells(): void
    {
        $rows = $this->getJson('/api/marketplace/locations')->assertOk()->assertJsonCount(22, 'data')->json('data');
        $this->assertCount(22, array_unique(array_column($rows, 'governorate_code')));
        $this->assertContains('أمانة العاصمة', array_column($rows, 'label'));
        $this->assertContains('صنعاء', array_column($rows, 'label'));
        $catalog = app(YemenGovernorateCatalog::class);
        foreach ($rows as $row) {
            $this->assertSame($row['governorate_code'], $catalog->locate($row['latitude'], $row['longitude'], 5)['code']);
            $this->getJson('/api/marketplace?'.http_build_query(['governorate_code' => $row['governorate_code']]))
                ->assertOk()->assertJsonPath('data.context.governorate_code', $row['governorate_code']);
        }
        $this->assertDatabaseCount('properties', 0);
        $this->assertDatabaseCount('geo_cells', 0);
        Governorate::where('code', 'ADEN')->update(['is_active' => false]);
        $this->getJson('/api/marketplace/locations')->assertOk()->assertJsonCount(21, 'data');
        $this->getJson('/api/properties?governorate_code=ADEN')->assertUnprocessable();
    }

    public function test_gps_uses_reference_boundaries_not_nearest_ads_and_never_defaults_foreign_points_to_sanaa(): void
    {
        foreach ([['AMANAT_AL_ASIMAH', 15.3694, 44.191], ['SANAA', 15.46, 44.36], ['DHAMAR', 14.55, 44.4], ['IBB', 13.9667, 44.1833], ['SOCOTRA', 12.65, 54.02]] as [$code, $lat, $lon]) {
            $this->getJson('/api/marketplace/location-context?'.http_build_query(['latitude' => $lat, 'longitude' => $lon, 'accuracy_m' => 5]))
                ->assertOk()->assertHeader('Cache-Control', 'no-store, private')->assertJsonPath('data.governorate_code', $code)
                ->assertJsonPath('data.source', 'device')->assertJsonPath('data.needs_confirmation', false);
        }
        $this->getJson('/api/marketplace/location-context?latitude=24.7&longitude=46.7&accuracy_m=5')
            ->assertOk()->assertJsonPath('data.governorate', null)->assertJsonPath('data.needs_confirmation', true);
        $this->getJson('/api/marketplace/location-context?latitude=14.55&longitude=44.4')
            ->assertOk()->assertJsonPath('data.location_status', 'accuracy_unknown')->assertJsonPath('data.needs_confirmation', true);
        $this->getJson('/api/marketplace/location-context?latitude=14.55&longitude=44.4&accuracy_m=100000')
            ->assertOk()->assertJsonPath('data.location_status', 'boundary')->assertJsonPath('data.needs_confirmation', true);
        $this->getJson('/api/marketplace/location-context?latitude=100&longitude=44')->assertUnprocessable();
        $this->getJson('/api/marketplace/location-context?latitude=14.5')->assertUnprocessable();
        $this->getJson('/api/marketplace/location-context?latitude=14.5&longitude=44&accuracy_m=-1')->assertUnprocessable();
    }

    public function test_polygon_holes_islands_and_boundary_points_are_not_flattened(): void
    {
        $catalog = app(YemenGovernorateCatalog::class);
        $outer = [[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]];
        $hole = [[1, 1], [3, 1], [3, 3], [1, 3], [1, 1]];
        $island = [[8, 0], [9, 0], [9, 1], [8, 1], [8, 0]];
        $geometry = ['type' => 'MultiPolygon', 'coordinates' => [[$outer, $hole], [$island]]];
        $this->assertTrue($catalog->covers($geometry, .5, .5));
        $this->assertFalse($catalog->covers($geometry, 2, 2));
        $this->assertTrue($catalog->covers($geometry, 1, 2));
        $this->assertTrue($catalog->covers($geometry, 8.5, .5));
        $this->assertFalse($catalog->covers($geometry, 6, .5));
        $vertex = $catalog->feature('AMANAT_AL_ASIMAH')['geometry']['coordinates'][0][0];
        $this->assertTrue($catalog->locate($vertex[1], $vertex[0], 10)['needs_confirmation']);
    }

    public function test_explicit_governorate_filters_are_spatial_consistent_and_cannot_be_spoofed_by_address_text(): void
    {
        $user = User::create(['name' => 'Governorate fixture', 'email' => 'gov@example.invalid', 'password' => 'fixture-only']);
        $ids = [];
        foreach ([[15.3694, 44.191, 'صنعاء'], [15.46, 44.36, 'صنعاء'], [13.9667, 44.1833, 'صنعاء، نص لا يغيّر النقطة']] as [$lat, $lon, $address]) {
            $ids[] = Property::create(['user_id' => $user->id, 'title' => 'تجريبي', 'description' => 'وهمي', 'type' => 'house', 'purpose' => 'rent',
                'price' => 100000, 'monthly_rent' => 100000, 'currency' => 'YER', 'address' => $address,
                'latitude' => $lat, 'longitude' => $lon, 'status' => 'published', 'review_status' => 'approved',
                'availability_status' => 'available', 'availability_confirmed_at' => now(), 'availability_due_at' => now()->addDays(7)])->id;
        }
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography');
        }
        foreach (['AMANAT_AL_ASIMAH', 'SANAA', 'IBB'] as $i => $code) {
            $query = http_build_query(['ranked_search' => 1, 'governorate_code' => $code]);
            $list = $this->getJson('/api/properties?'.$query)->assertOk()->assertJsonPath('meta.exact_total', 1)->assertJsonPath('data.0.id', $ids[$i])->json();
            $this->assertSame(1, app(\App\Services\SavedPropertySearchService::class)->matchingCount(['governorate_code' => $code]));
            $this->assertSame($code, app(\App\Services\SmartSearchService::class)->validate(['governorate_code' => $code])['governorate_code']);
            $this->assertSame($list, $this->getJson('/api/properties/nearby?'.$query)->assertOk()->json());
            $this->getJson('/api/marketplace?governorate_code='.$code)->assertOk()->assertJsonPath('data.sections.latest.0.id', $ids[$i]);
        }
        $before = Property::findOrFail($ids[2]);
        $before->update(['address' => 'محافظة أخرى، شارع افتراضي']);
        $this->getJson('/api/properties?ranked_search=1&governorate_code=IBB')->assertOk()->assertJsonPath('data.0.id', $ids[2]);
        $this->assertSame((string) $before->latitude, (string) $before->fresh()->latitude);
    }
}
