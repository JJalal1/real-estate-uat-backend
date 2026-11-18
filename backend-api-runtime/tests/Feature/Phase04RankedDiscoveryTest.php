<?php

namespace Tests\Feature;

use App\Models\GeoCell;
use App\Models\Governorate;
use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Phase04RankedDiscoveryTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private array $ring = [[44.18, 15.36], [44.20, 15.36], [44.20, 15.38], [44.18, 15.38], [44.18, 15.36]];

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::create(['name' => 'Phase04 synthetic owner', 'email' => 'phase04@example.invalid',
            'password' => 'fixture-only', 'account_status' => 'active', 'phone_verified_at' => now()]);
    }

    public function test_all_exact_pages_precede_nearby_with_no_duplicates_and_identical_map_contract(): void
    {
        $exact = [];
        for ($i = 0; $i < 23; $i++) {
            $exact[] = $this->listing(['price' => 100000])->id;
        }
        $near = $this->listing(['price' => 110000]);
        $this->listing(['price' => 110000, 'purpose' => 'sale']);
        $this->listing(['price' => 110000, 'currency' => 'USD']);
        $this->listing(['price' => 110000, 'type' => 'office']);
        $this->listing(['price' => 110000, 'status' => 'draft', 'review_status' => 'draft']);
        $filters = ['ranked_search' => 1, 'purpose' => 'rent', 'type' => 'house', 'currency' => 'YER', 'max_price' => 100000, 'per_page' => 10];
        $seen = [];
        foreach ([1, 2, 3] as $page) {
            $query = $filters + ['page' => $page];
            $list = $this->getJson('/api/properties?'.http_build_query($query))->assertOk()
                ->assertHeader('X-Aqer-Ranked-Contract', '1')->assertJsonPath('meta.exact_total', 23)->assertJsonPath('meta.total', 24)->json();
            $map = $this->getJson('/api/properties/nearby?'.http_build_query($query))->assertOk()->json();
            $this->assertSame($list, $map);
            foreach ($list['data'] as $row) {
                $seen[] = [$row['id'], $row['discovery_match']['kind']];
            }
        }
        $this->assertCount(24, array_unique(array_column($seen, 0)));
        $this->assertSame(array_fill(0, 23, 'exact'), array_slice(array_column($seen, 1), 0, 23));
        $this->assertSame([$near->id, 'nearby'], $seen[23]);
        $this->getJson('/api/properties?'.http_build_query($filters + ['page' => 4]))->assertOk()->assertJsonCount(0, 'data');
        // Existing clients retain exact-only results and their original header.
        unset($filters['ranked_search']);
        $this->getJson('/api/properties?'.http_build_query($filters))->assertOk()->assertJsonPath('meta.total', 23)->assertJsonMissingPath('data.0.discovery_match');
    }

    public function test_match_degree_precedes_point_distance_globally_and_equal_degree_uses_distance(): void
    {
        $nearExact = $this->listing(['latitude' => 15.377]);
        $tiedExact = $this->listing(['latitude' => 15.377]);
        $farExact = $this->listing(['latitude' => 15.388]);
        $farOneMiss = $this->listing(['latitude' => 15.382, 'bedrooms' => 2]);
        $nearOneMiss = $this->listing(['latitude' => 15.3709, 'bedrooms' => 2]);
        $closestTwoMisses = $this->listing(['latitude' => 15.3704, 'bedrooms' => 2, 'price' => 110000]);
        $this->listing(['latitude' => 15.3701, 'purpose' => 'sale']);
        $this->listing(['latitude' => 15.3701, 'type' => 'office']);
        $this->listing(['latitude' => 15.3701, 'currency' => 'USD']);
        $filters = ['ranked_search' => 1, 'purpose' => 'rent', 'type' => 'house', 'currency' => 'YER',
            'latitude' => 15.37, 'longitude' => 44.19, 'radius_km' => 3, 'max_price' => 100000, 'min_bedrooms' => 3, 'per_page' => 2];

        foreach ([[], ['south' => 15.35, 'west' => 44.15, 'north' => 15.42, 'east' => 44.23]] as $viewport) {
            $rows = [];
            foreach ([1, 2, 3] as $page) {
                $query = http_build_query($filters + $viewport + ['page' => $page]);
                $list = $this->getJson('/api/properties?'.$query)->assertOk()
                    ->assertJsonPath('meta.current_page', $page)->assertJsonPath('meta.last_page', 3)
                    ->assertJsonPath('meta.ranking_distance_reference', 'point')->assertJsonCount(2, 'data')->json();
                $this->assertSame($list, $this->getJson('/api/properties/nearby?'.$query)->assertOk()->json());
                array_push($rows, ...$list['data']);
            }

            $this->assertSame([$tiedExact->id, $nearExact->id, $farExact->id, $nearOneMiss->id, $farOneMiss->id, $closestTwoMisses->id],
                array_column($rows, 'id'));
            $matches = array_column($rows, 'discovery_match');
            $this->assertSame([0, 0, 0, 1, 1, 2], array_column($matches, 'criteria_misses'));
            $this->assertSame(['exact', 'exact', 'exact', 'nearby', 'nearby', 'nearby'], array_column($matches, 'kind'));
            $this->assertEqualsWithDelta(2000, $matches[2]['rank_distance_m'], 30);
            $this->assertEqualsWithDelta(100, $matches[3]['rank_distance_m'], 3);
            $this->assertLessThan($matches[4]['rank_distance_m'], $matches[3]['rank_distance_m']);
            $this->assertLessThan($matches[3]['rank_distance_m'], $matches[5]['rank_distance_m']);
            $this->assertEquals(0, $matches[3]['distance_m']);
            $this->assertCount(2, $matches[5]['reasons']);
        }
    }

    public function test_alternative_limit_is_applied_after_match_degree_and_distance(): void
    {
        $preferred = $this->listing(['latitude' => 15.39, 'bedrooms' => 2]);
        for ($i = 0; $i < 12; $i++) {
            $this->listing(['latitude' => 15.3705 + $i / 100000, 'bedrooms' => 2, 'price' => 110000]);
        }
        $query = http_build_query(['ranked_search' => 1, 'latitude' => 15.37, 'longitude' => 44.19,
            'radius_km' => 3, 'max_price' => 100000, 'min_bedrooms' => 3]);
        $this->getJson('/api/properties?'.$query)->assertOk()->assertJsonPath('meta.alternative_total', 12)
            ->assertJsonPath('data.0.id', $preferred->id)->assertJsonPath('data.0.discovery_match.criteria_misses', 1)
            ->assertJsonPath('data.11.discovery_match.criteria_misses', 2);
    }

    public function test_camera_or_unresolved_text_does_not_assume_a_position(): void
    {
        $nearCenter = $this->listing(['latitude' => 15.37, 'title' => 'مجمع الياسمين الجديد']);
        $newer = $this->listing(['latitude' => 15.38, 'title' => 'مجمع الياسمين الجديد']);
        $this->listing(['title' => 'مبنى آخر']);
        $filters = ['ranked_search' => 1, 'search' => 'مجمع الياسمين الجديد', 'south' => 15.35,
            'west' => 44.17, 'north' => 15.39, 'east' => 44.21];
        $rows = $this->getJson('/api/properties?'.http_build_query($filters))->assertOk()
            ->assertJsonPath('meta.ranking_distance_reference', null)->assertJsonPath('data.0.discovery_match.rank_distance_m', null)->json('data');
        $this->assertSame([$newer->id, $nearCenter->id], array_column($rows, 'id'));
    }

    public function test_registry_alias_and_typo_are_explained_without_merging_valid_similar_names(): void
    {
        $city = Governorate::firstOrCreate(['name_ar' => 'صنعاء'], ['code' => 'p4-sanaa', 'is_active' => true]);
        $city->update(['name_en' => 'Sanaa', 'is_active' => true]);
        $row = $this->listing(['address' => 'صنعاء', 'price' => 100000]);
        foreach (['صنعاء', 'صنعا', 'Sanaa'] as $name) {
            $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => $name, 'purpose' => 'rent']))
                ->assertOk()->assertJsonPath('data.0.id', $row->id)->assertJsonPath('data.0.discovery_match.kind', 'exact');
        }
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => 'سنعا', 'purpose' => 'rent']))
            ->assertOk()->assertJsonPath('meta.exact_total', 0)->assertJsonPath('data.0.id', $row->id)
            ->assertJsonPath('data.0.discovery_match.kind', 'nearby')->assertJsonPath('data.0.discovery_match.reasons.0.field', 'search');
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => 'سنعا', 'purpose' => 'rent', 'governorate' => 'أمانة العاصمة']))
            ->assertOk()->assertJsonPath('data.0.id', $row->id)->assertJsonPath('data.0.discovery_match.kind', 'nearby');
        Governorate::create(['code' => 'p4-valid', 'name_ar' => 'سنعا', 'is_active' => true]);
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => 'سنعا', 'purpose' => 'rent']))
            ->assertOk()->assertJsonPath('meta.total', 0);
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => 'سنعا', 'purpose' => 'rent', 'governorate' => 'صنعاء']))
            ->assertOk()->assertJsonPath('meta.total', 0);
        $city->update(['is_active' => false]);
    }

    public function test_polygon_boundary_is_exact_and_nearby_is_sorted_by_distance_to_boundary_not_centroid(): void
    {
        $ring = [[44.0, 15.36], [44.5, 15.36], [44.5, 15.38], [44.0, 15.38], [44.0, 15.36]];
        $inside = $this->listing(['latitude' => 15.37, 'longitude' => 44.19]);
        $boundary = $this->listing(['latitude' => 15.36, 'longitude' => 44.18]);
        $near = $this->listing(['latitude' => 15.37, 'longitude' => 44.5005]);
        $further = $this->listing(['latitude' => 15.382, 'longitude' => 44.25]);
        $this->listing(['latitude' => 15.37, 'longitude' => 45.0]);
        $q = ['ranked_search' => 1, 'purpose' => 'rent', 'area_polygon' => json_encode($ring)];
        $before = DB::table('properties')->orderBy('id')->get()->toJson();
        $data = $this->getJson('/api/properties?'.http_build_query($q))->assertOk()->assertJsonPath('meta.exact_total', 2)->json('data');
        $this->assertEqualsCanonicalizing([$inside->id, $boundary->id], array_column(array_slice($data, 0, 2), 'id'));
        $this->assertSame([$near->id, $further->id], array_column(array_slice($data, 2), 'id'));
        $this->assertSame('drawn_boundary', $data[2]['discovery_match']['distance_reference']);
        $this->assertLessThan(100, $data[2]['discovery_match']['distance_m']);
        $this->assertSame('خارج المنطقة المرسومة', $data[2]['discovery_match']['reasons'][0]['message']);
        $this->assertSame($before, DB::table('properties')->orderBy('id')->get()->toJson());
        // Match degree takes priority when the nearer property also misses the budget.
        $near->update(['price' => 110000]);
        $data = $this->getJson('/api/properties?'.http_build_query($q + ['max_price' => 100000]))
            ->assertOk()->json('data');
        $this->assertSame([$further->id, $near->id], array_column(array_slice($data, 2), 'id'));
        $this->assertSame(1, $data[2]['discovery_match']['criteria_misses']);
        $this->assertSame(2, $data[3]['discovery_match']['criteria_misses']);
        $this->assertCount(2, $data[3]['discovery_match']['reasons']);
        $this->assertEquals(0, $data[0]['discovery_match']['rank_distance_m']);
        $this->assertEquals(0, $data[1]['discovery_match']['rank_distance_m']);
        $this->assertLessThan($data[2]['discovery_match']['rank_distance_m'], $data[3]['discovery_match']['rank_distance_m']);
    }

    public function test_empty_named_neighborhood_uses_recorded_boundary_and_same_name_other_city_stays_scoped(): void
    {
        $sanaa = Governorate::firstOrCreate(['name_ar' => 'صنعاء'], ['code' => 'p4-sanaa', 'is_active' => true]);
        $taiz = Governorate::firstOrCreate(['name_ar' => 'تعز'], ['code' => 'p4-taiz', 'is_active' => true]);
        $a = $this->cell(['governorate_id' => $sanaa->id, 'code' => 'p4-a', 'name_ar' => 'حي المرحلة الرابعة', 'name_en' => 'Old quarter',
            'is_active' => true, 'boundary_json' => ['type' => 'Polygon', 'coordinates' => [$this->ring]]]);
        $this->cell(['governorate_id' => $taiz->id, 'code' => 'p4-b', 'name_ar' => 'حي المرحلة الرابعة', 'is_active' => true,
            'boundary_json' => ['type' => 'Polygon', 'coordinates' => [array_map(fn ($point) => [$point[0] - .17, $point[1] - 1.79], $this->ring)]]]);
        $near = $this->listing(['latitude' => 15.37, 'longitude' => 44.2005, 'geo_cell_id' => null]);
        $this->listing(['address' => 'تعز حي المرحلة الرابعة', 'latitude' => 13.58, 'longitude' => 44.02]);
        $q = ['ranked_search' => 1, 'purpose' => 'rent', 'search' => 'حي المرحلة الرابعة', 'governorate' => 'صنعاء'];
        $data = $this->getJson('/api/properties?'.http_build_query($q))->assertOk()->assertJsonPath('meta.exact_total', 0)
            ->assertJsonPath('meta.ranking_distance_reference', 'recorded_area')->assertJsonPath('data.0.id', $near->id)->json('data');
        $this->assertEqualsWithDelta(54, $data[0]['discovery_match']['rank_distance_m'], 3);
        $withoutGovernorate = array_diff_key($q, ['governorate' => true]);
        $this->getJson('/api/properties?'.http_build_query($withoutGovernorate))->assertOk()
            ->assertJsonPath('meta.ranking_distance_reference', null);
        config(['discovery_ranked.place_aliases' => ['الاسم المحلي المثبت' => 'حي المرحلة الرابعة']]);
        $in = $this->listing(['geo_cell_id' => $a->id]);
        $q['search'] = 'الاسم المحلي المثبت';
        $this->getJson('/api/properties?'.http_build_query($q))->assertOk()->assertJsonPath('data.0.id', $in->id)->assertJsonPath('data.0.discovery_match.kind', 'exact');
    }

    public function test_nearest_filter_relaxation_explains_price_rooms_and_does_not_fill_with_irrelevant_rows(): void
    {
        $rooms = $this->listing(['price' => 95000, 'bedrooms' => 2]);
        $price = $this->listing(['price' => 110000, 'bedrooms' => 3]);
        $this->listing(['price' => 1000000, 'bedrooms' => 3]);
        $q = ['ranked_search' => 1, 'purpose' => 'rent', 'currency' => 'YER', 'max_price' => 100000, 'min_bedrooms' => 3];
        $data = $this->getJson('/api/properties?'.http_build_query($q))->assertOk()->assertJsonPath('meta.exact_total', 0)
            ->assertJsonPath('meta.ranking_distance_reference', null)->assertJsonPath('data.0.discovery_match.rank_distance_m', null)
            ->assertJsonCount(2, 'data')->json('data');
        $this->assertSame([$rooms->id, $price->id], array_column($data, 'id'));
        $this->assertSame('min_bedrooms', $data[0]['discovery_match']['reasons'][0]['field']);
        $this->assertSame(10000.0, (float) $data[1]['discovery_match']['reasons'][0]['difference']);
        $q['search'] = 'منطقة مجهولة بلا سجل أو عقار';
        $this->getJson('/api/properties?'.http_build_query($q))->assertOk()->assertJsonPath('meta.total', 0);
    }

    public function test_purpose_conflict_is_visible_instead_of_silent_relaxation(): void
    {
        $this->listing();
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'purpose' => 'rent', 'search' => 'صنعاء للبيع']))
            ->assertUnprocessable()->assertJsonValidationErrors('search');
    }

    public function test_monthly_rent_alternatives_cannot_escape_to_sale_when_purpose_was_implicit(): void
    {
        $rent = $this->listing(['price' => 110000, 'monthly_rent' => 110000]);
        $this->listing(['purpose' => 'sale', 'price' => 110000, 'monthly_rent' => 110000]);
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'max_monthly_rent' => 100000]))
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.id', $rent->id);
    }

    public function test_recorded_english_place_alias_preserves_a_legacy_english_address(): void
    {
        $city = Governorate::firstOrCreate(['name_ar' => 'إب'], ['code' => 'p4-ibb', 'is_active' => true]);
        $city->update(['name_en' => 'Ibb', 'is_active' => true]);
        $row = $this->listing(['address' => 'Ibb central district']);
        $arabic = $this->listing(['address' => 'اب، الحي المركزي']);
        $this->getJson('/api/properties?'.http_build_query(['ranked_search' => 1, 'search' => 'Ibb', 'purpose' => 'rent']))
            ->assertOk()->assertJsonPath('meta.exact_total', 2)->assertJsonFragment(['id' => $row->id])->assertJsonFragment(['id' => $arabic->id]);
    }

    private function listing(array $overrides = []): Property
    {
        $property = Property::create(array_merge(['user_id' => $this->owner->id, 'title' => 'عقار تجريبي المرحلة الرابعة',
            'description' => 'بيانات اختبار', 'purpose' => 'rent', 'type' => 'house', 'price' => 100000, 'monthly_rent' => 100000, 'currency' => 'YER',
            'area_m2' => 200, 'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء', 'latitude' => 15.37, 'longitude' => 44.19,
            'status' => 'published', 'review_status' => 'approved', 'published_at' => now()], $overrides));
        $property->forceFill(['availability_status' => 'available', 'availability_confirmed_at' => now(), 'availability_due_at' => now()->addDays(14)])->saveQuietly();
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        }

        return $property;
    }

    private function cell(array $values): GeoCell
    {
        if (DB::getDriverName() !== 'pgsql') {
            return GeoCell::create($values);
        }
        $json = json_encode($values['boundary_json'], JSON_THROW_ON_ERROR);
        $row = DB::selectOne('INSERT INTO geo_cells (governorate_id,code,name_ar,name_en,boundary_json,is_active,boundary,created_at,updated_at) VALUES (?,?,?,?,?::jsonb,TRUE,ST_GeomFromGeoJSON(?),?,?) RETURNING id',
            [$values['governorate_id'], $values['code'], $values['name_ar'], $values['name_en'] ?? null, $json, $json, now(), now()]);

        return GeoCell::findOrFail($row->id);
    }
}
