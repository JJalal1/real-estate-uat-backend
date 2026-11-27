<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\ListingEditorDraftService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Tests\TestCase;

class CategoryPropertyFiltersTest extends TestCase
{
    use RefreshDatabase;

    public function test_house_filters_use_known_facts_and_keep_visibility_purpose_and_pagination(): void
    {
        $owner = $this->owner();
        $facts = [
            'purpose' => 'rent', 'type' => 'house', 'bedrooms' => 4,
            'has_parking' => true, 'parking_spaces' => 2,
            'has_separate_majlis' => true, 'has_majlis_bathroom' => true,
        ];
        $first = $this->listing($owner, $facts);
        $latest = $this->listing($owner, $facts);
        $legacy = $this->listing($owner, array_replace($facts, [
            'parking_spaces' => null, 'has_separate_majlis' => null, 'has_majlis_bathroom' => null,
        ]));
        $this->listing($owner, array_replace($facts, ['purpose' => 'sale']));
        $this->listing($owner, array_replace($facts, ['status' => 'draft', 'review_status' => 'draft']));
        $this->listing($owner, array_replace($facts, ['parking_spaces' => 1, 'has_majlis_bathroom' => false]));
        $this->listing($owner, array_replace($facts, ['bedrooms' => 2]));

        $strict = [
            'type' => 'house', 'purpose' => 'rent', 'min_bedrooms' => 3, 'min_parking_spaces' => 2,
            'has_separate_majlis' => 1, 'has_majlis_bathroom' => 1, 'per_page' => 1,
        ];
        $this->getJson('/api/properties?'.http_build_query($strict))
            ->assertOk()->assertHeader('X-Aqer-Category-Filters', '1')
            ->assertJsonPath('meta.total', 2)->assertJsonPath('meta.last_page', 2)
            ->assertJsonPath('data.0.id', $latest->id)
            ->assertJsonPath('data.0.parking_spaces', 2)
            ->assertJsonPath('data.0.has_majlis_bathroom', true)
            ->assertJsonMissingPath('data.0.contact_phone');
        $this->getJson('/api/properties?'.http_build_query($strict + ['page' => 2]))
            ->assertOk()->assertJsonPath('data.0.id', $first->id);
        $atLeastOne = $this->ids(['type' => 'house', 'purpose' => 'rent', 'min_parking_spaces' => 1]);
        $atLeastTwo = $this->ids(['type' => 'house', 'purpose' => 'rent', 'min_parking_spaces' => 2]);
        $this->assertContains($legacy->id, $atLeastOne);
        $this->assertNotContains($legacy->id, $atLeastTwo);
    }

    public function test_filters_are_type_specific_and_combine_with_shared_facets(): void
    {
        $owner = $this->owner();
        $cases = [
            ['apartment', ['section_elevator' => true, 'floor_number' => '2'], ['section_elevator' => false], [
                'has_section_elevator' => 1, 'floor_number' => '2',
            ]],
            ['villa', ['has_yard' => true, 'bedrooms' => 5], ['has_yard' => null], [
                'has_yard' => 1, 'min_bedrooms' => 5,
            ]],
            ['building', ['floors_count' => 3, 'units_per_floor' => [3, 2, 2]], ['units_per_floor' => [1, 2, 1]], [
                'min_floors' => 3, 'min_total_units' => 7,
            ]],
            ['land', ['land_use' => 'residential', 'area_m2' => 400, 'street_width_m' => 12.50, 'building_facade' => 'east'],
                ['land_use' => 'commercial'], [
                    'land_use' => 'residential', 'min_area_m2' => 360, 'max_area_m2' => 420,
                    'min_street_width' => 12.5, 'building_facade' => 'east',
                ]],
            ['farm', ['farm_water_source' => 'well', 'farm_crop_type' => 'fruit'], ['farm_water_source' => 'network'], [
                'farm_water_source' => 'well', 'farm_crop_type' => 'fruit',
            ]],
            ['office', ['office_rooms' => 3, 'section_elevator' => true], ['office_rooms' => 2], [
                'min_office_rooms' => 3, 'has_section_elevator' => 1,
            ]],
            ['shop', ['shop_openings' => 2, 'street_width_m' => 15], ['street_width_m' => 8], [
                'min_shop_openings' => 2, 'min_street_width' => 10,
            ]],
        ];

        foreach ($cases as [$type, $facts, $mismatch, $filters]) {
            $listing = $this->listing($owner, ['type' => $type] + $facts);
            $this->listing($owner, ['type' => $type] + array_replace($facts, $mismatch));
            $this->listing($owner, ['type' => $type]); // No advertised values.
            $this->assertSame([$listing->id], $this->ids(['type' => $type, 'purpose' => 'sale'] + $filters));
        }

        $land = $this->ids(['type' => 'land', 'land_use' => 'residential']);
        $this->assertCount(1, $land);
        $this->assertSame($land, $this->ids(['type' => 'land', 'land_use' => 'residential', 'has_yard' => 1]));
    }

    public function test_total_building_units_skips_incomplete_legacy_json(): void
    {
        $owner = $this->owner();
        $valid = $this->listing($owner, ['type' => 'building', 'units_per_floor' => [3, 3]]);
        foreach ([null, '6', [7, null], ['oops', 7], ['unit_count' => 7]] as $legacy) {
            $this->listing($owner, ['type' => 'building', 'units_per_floor' => $legacy]);
        }

        $this->assertSame([$valid->id], $this->ids(['type' => 'building', 'min_total_units' => 5]));
    }

    public function test_owner_can_save_read_and_clear_optional_facts_without_changing_older_clients(): void
    {
        $owner = $this->owner();
        $available = app(ApiTokenService::class)->issue($owner, Request::create('/'));
        $headers = ['Authorization' => 'Bearer '.$available['plain_text_token']];
        $newListing = [
            'title' => 'منزل للاختبار', 'type' => 'house', 'purpose' => 'sale', 'price' => 50000000,
            'latitude' => 15.3694, 'longitude' => 44.1910, 'has_parking' => 1,
            'parking_spaces' => 2, 'has_separate_majlis' => 1, 'has_majlis_bathroom' => 1,
            'land_use' => 'commercial',
        ];
        $created = $this->withHeaders($headers)->postJson('/api/properties', $newListing)
            ->assertCreated()->assertJsonPath('data.parking_spaces', 2)
            ->assertJsonPath('data.has_majlis_bathroom', true)->assertJsonMissingPath('data.land_use');
        $path = '/api/properties/'.$created->json('data.id');

        $this->postJson($path, ['title' => 'تعديل من نسخة سابقة'])
            ->assertOk()->assertJsonPath('data.parking_spaces', 2)->assertJsonPath('data.has_separate_majlis', true);
        $this->postJson($path, ['has_separate_majlis' => false])
            ->assertOk()->assertJsonPath('data.has_separate_majlis', false)->assertJsonMissingPath('data.has_majlis_bathroom');
        $this->postJson($path, ['has_majlis_bathroom' => true])
            ->assertUnprocessable()->assertJsonValidationErrors('has_majlis_bathroom');
        $this->postJson($path, ['has_parking' => false, 'parking_spaces' => 2])
            ->assertUnprocessable()->assertJsonValidationErrors('parking_spaces');
        $this->post($path, ['parking_spaces' => ''], ['Accept' => 'application/json'])
            ->assertOk()->assertJsonMissingPath('data.parking_spaces')->assertJsonPath('data.has_parking', true);
        $this->getJson($path)->assertOk()->assertJsonPath('data.has_separate_majlis', false);
    }

    public function test_draft_preserves_applicable_facts_and_range_inputs_are_validated(): void
    {
        $actual = app(ListingEditorDraftService::class)->clean([
            'type' => 'house', 'purpose' => 'rent',
            'fields' => ['parking_spaces' => '2', 'has_majlis_bathroom' => 'yes', 'land_use' => 'residential'],
        ]);
        $this->assertSame(['parking_spaces' => '2', 'has_majlis_bathroom' => 'yes'], $actual['fields']);

        $this->getJson('/api/properties?type=house&min_parking_spaces=101')
            ->assertUnprocessable()->assertJsonValidationErrors('min_parking_spaces');
        $this->getJson('/api/properties?type=land&min_area_m2=100&max_area_m2=50')
            ->assertUnprocessable()->assertJsonValidationErrors('filters');
        $this->getJson('/api/properties?type=land&land_use=unknown')
            ->assertUnprocessable()->assertJsonValidationErrors('land_use');
    }

    private function owner(): User
    {
        return User::factory()->create([
            'account_status' => User::STATUS_ACTIVE, 'phone_verified_at' => now(),
        ]);
    }

    private function listing(User $owner, array $changes): Property
    {
        return Property::query()->create($changes + [
            'user_id' => $owner->id, 'title' => 'عقار تجريبي', 'purpose' => 'sale', 'type' => 'house',
            'price' => 50000000, 'currency' => 'YER', 'address' => 'صنعاء', 'latitude' => 15.3694, 'longitude' => 44.1910,
            'status' => 'published', 'review_status' => 'approved', 'availability_status' => 'available', 'published_at' => now(),
        ]);
    }

    private function ids(array $filters): array
    {
        $response = $this->getJson('/api/properties?'.http_build_query($filters));
        return array_column($response->assertOk()->json('data'), 'id');
    }
}
