<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\SavedPropertySearchService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class Wave01SharedFiltersTest extends TestCase
{
    use RefreshDatabase;

    private function listing(string $type, string $purpose = 'sale', array $changes = []): Property
    {
        $owner = User::factory()->create(['phone_verified_at' => now(), 'account_status' => 'active']);
        $property = Property::create(array_replace([
            'user_id' => $owner->id, 'title' => 'عقار اصطناعي '.$type, 'description' => 'بيانات اختبار فقط',
            'type' => $type, 'purpose' => $purpose, 'price' => 1000000, 'currency' => 'YER',
            'area_m2' => 160, 'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء، حدة',
            'latitude' => 15.3694, 'longitude' => 44.1910, 'status' => 'published',
            'review_status' => 'approved', 'published_at' => now(), 'availability_status' => 'available',
        ], $changes));
        if (isset($changes['availability_status'])) $property->forceFill(['availability_status' => $changes['availability_status']])->save();
        return $property;
    }

    private function publicGet(string $path, array $filters = [])
    {
        if (isset($filters['types']) && is_array($filters['types'])) {
            $filters['types'] = array_map(fn ($value) => $value === null ? '' : $value, $filters['types']);
        }
        return $this->getJson('/api/'.$path.'?'.http_build_query($filters));
    }

    private function ids(array $rows): array
    {
        $ids = array_column($rows, 'id');
        sort($ids);
        return $ids;
    }

    public function test_empty_selection_includes_both_purposes_and_types_but_never_private_work(): void
    {
        $apartment = $this->listing('apartment', 'rent');
        $land = $this->listing('land');
        $this->listing('villa', 'sale', ['status' => 'draft', 'review_status' => 'draft']);
        $this->listing('shop', 'sale', ['availability_status' => 'unavailable']);
        $rows = $this->publicGet('properties')->assertOk()->assertHeader('X-Aqer-Filter-Contract', '2')->json('data');
        $this->assertSame([$apartment->id, $land->id], $this->ids($rows));
        $this->assertSame([$apartment->id], $this->ids($this->publicGet('properties', ['purpose' => 'rent'])->assertOk()->json('data')));
        $this->assertSame([$apartment->id, $land->id], $this->ids($this->publicGet('properties', ['types' => []])->assertOk()->json('data')));
    }

    public function test_multi_type_or_is_identical_in_list_map_home_and_saved_matching_with_legacy_floor_support(): void
    {
        $apartment = $this->listing('apartment');
        $villa = $this->listing('villa');
        $floor = $this->listing('floor');
        $this->listing('land');
        $this->listing('villa', 'sale', ['status' => 'draft']);
        $filters = ['types' => ['villa', 'apartment'], 'purpose' => 'sale'];
        $expected = [$apartment->id, $villa->id, $floor->id];
        $list = $this->publicGet('properties', $filters)->assertOk()->assertHeader('X-Aqer-Filter-Contract', '2');
        $this->assertSame($expected, $this->ids($list->json('data')));
        $map = $this->publicGet('properties/nearby', $filters + ['latitude' => 15.37, 'longitude' => 44.19, 'radius_km' => 30, 'viewport' => 1, 'south' => 15, 'west' => 44, 'north' => 16, 'east' => 45])
            ->assertOk()->assertHeader('X-Aqer-Filter-Contract', '2');
        $this->assertSame($expected, $this->ids($map->json('data')));
        $home = $this->publicGet('marketplace', $filters + ['governorate' => 'صنعاء'])
            ->assertOk()->assertHeader('X-Aqer-Filter-Contract', '2');
        $this->assertSame($expected, $this->ids($home->json('data.sections.latest')));
        $this->assertSame(['apartment', 'villa'], $home->json('data.context.filters.types'));
        $this->assertSame($expected, app(SavedPropertySearchService::class)->queryFor($filters)->orderBy('id')->pluck('id')->all());
        $this->assertSame([$apartment->id, $floor->id], $this->ids($this->publicGet('properties', ['type' => 'apartment'])->assertOk()->json('data')));
        $this->assertSame([$floor->id], $this->ids($this->publicGet('properties', ['type' => 'floor'])->assertOk()->json('data')));
    }

    public function test_currency_monthly_budget_and_common_schema_do_not_filter_hidden_or_unrelated_facts(): void
    {
        $apartment = $this->listing('apartment', 'rent', ['monthly_rent' => 100000, 'price' => 900000]);
        $villa = $this->listing('villa', 'rent', ['monthly_rent' => 150000, 'price' => 1200000]);
        $land = $this->listing('land', 'rent', ['monthly_rent' => 120000, 'bedrooms' => null]);
        $this->listing('villa', 'rent', ['monthly_rent' => 100, 'currency' => 'USD']);
        $this->listing('villa', 'sale', ['monthly_rent' => 100000]);
        $filters = ['types' => ['apartment', 'villa'], 'purpose' => 'rent', 'currency' => 'YER',
            'min_monthly_rent' => 90000, 'max_monthly_rent' => 160000, 'min_bedrooms' => 3];
        $this->assertSame([$apartment->id, $villa->id], $this->ids($this->publicGet('properties', $filters)->assertOk()->json('data')));
        $mixed = ['types' => ['apartment', 'land'], 'purpose' => 'rent', 'currency' => 'YER', 'min_bedrooms' => 40];
        $this->assertSame([$apartment->id, $land->id], $this->ids($this->publicGet('properties', $mixed)->assertOk()->json('data')));
    }

    public function test_malformed_ambiguous_or_excessive_arrays_never_become_unconstrained_results(): void
    {
        $this->listing('apartment');
        foreach ([['types' => 'apartment,villa'], ['types' => ['apartment', 'apartment']],
            ['types' => ['not-a-type']], ['types' => ['floor']], ['types' => [null]],
            ['types' => ['selected' => 'apartment']], ['types' => array_fill(0, 9, 'villa')],
            ['type' => 'land', 'types' => ['apartment', 'villa']]] as $filters) {
            $this->publicGet('properties', $filters)->assertUnprocessable();
            $this->publicGet('properties/nearby', $filters + ['latitude' => 15.37, 'longitude' => 44.19, 'radius_km' => 30, 'viewport' => 1, 'south' => 15, 'west' => 44, 'north' => 16, 'east' => 45])->assertUnprocessable();
            $this->publicGet('marketplace', $filters)->assertUnprocessable();
        }
    }

    private function actor(): array
    {
        $user = User::factory()->create(['phone_verified_at' => now(), 'account_status' => 'active']);
        $token = 'wave01-synthetic-only-'.$user->id;
        $user->apiTokens()->create(['name' => 'wave01-test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token]];
    }

    public function test_saved_arrays_are_canonical_deduplicated_private_and_validate_before_normalization(): void
    {
        [$owner, $headers] = $this->actor();
        [, $other] = $this->actor();
        $this->listing('apartment');
        $this->listing('villa');
        $payload = ['name' => 'اختبار متعدد', 'filters' => ['types' => ['villa', 'apartment'], 'purpose' => 'sale']];
        $first = $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)->assertCreated()
            ->assertJsonPath('data.filters.types', ['apartment', 'villa'])->assertJsonPath('data.matching_count', 2);
        $id = $first->json('data.id');
        $payload['filters']['types'] = ['apartment', 'villa'];
        $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)->assertOk()->assertJsonPath('data.id', $id);
        $this->withHeaders($other)->patchJson('/api/saved-searches/'.$id, ['name' => 'محاولة حساب آخر'])->assertNotFound();
        $this->withHeaders($other)->deleteJson('/api/saved-searches/'.$id)->assertNotFound();
        $this->withHeaders($headers)->postJson('/api/saved-searches', ['name' => 'غير صالح',
            'filters' => ['type' => 'land', 'types' => ['apartment', 'villa']]])->assertUnprocessable();
        $this->assertDatabaseCount('saved_property_searches', 1);
        $this->assertDatabaseHas('saved_property_searches', ['id' => $id, 'user_id' => $owner->id]);
    }

    private function model(array $patch): void
    {
        Cache::flush();
        config(['gemini.enabled' => true, 'gemini.key' => 'wave01-fixture-key', 'gemini.daily_limit' => 100]);
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::preventStrayRequests();
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response([
            'candidates' => [['content' => ['parts' => [['text' => json_encode($patch)]]]]],
        ])]);
    }

    public function test_ai_type_amendments_preserve_the_other_criteria_and_clear_only_inapplicable_fields(): void
    {
        $context = ['type' => 'apartment', 'purpose' => 'rent', 'max_price' => 200000, 'min_bedrooms' => 3,
            'south' => 15, 'west' => 44, 'north' => 16, 'east' => 45];
        $this->model(['set' => ['types' => ['villa', 'apartment']], 'remove' => []]);
        $current = $this->postJson('/api/ai/search', ['message' => 'شقق وفلل', 'filters' => $context, 'revision' => 1])
            ->assertOk()->assertJsonPath('data.filters.types', ['apartment', 'villa'])
            ->assertJsonMissingPath('data.filters.type')->assertJsonPath('data.filters.min_bedrooms', 3)->json('data.filters');
        foreach (['purpose', 'max_price', 'south', 'west', 'north', 'east'] as $key) $this->assertSame($context[$key], $current[$key]);
        $this->model(['set' => ['types' => ['villa']], 'remove' => []]);
        $current = $this->postJson('/api/ai/search', ['message' => 'شيل الشقق', 'filters' => $current, 'revision' => 2])
            ->assertOk()->assertJsonPath('data.filters.type', 'villa')->assertJsonMissingPath('data.filters.types')->json('data.filters');
        $this->model(['set' => ['type' => 'land'], 'remove' => []]);
        $current = $this->postJson('/api/ai/search', ['message' => 'خلها أرض', 'filters' => $current, 'revision' => 3])
            ->assertOk()->assertJsonPath('data.filters.type', 'land')->assertJsonMissingPath('data.filters.min_bedrooms')->json('data.filters');
        $this->model(['set' => (object) [], 'remove' => ['types']]);
        $this->postJson('/api/ai/search', ['message' => 'احذف شرط النوع', 'filters' => $current, 'revision' => 4])
            ->assertOk()->assertJsonMissingPath('data.filters.type')->assertJsonMissingPath('data.filters.types')
            ->assertJsonPath('data.filters.max_price', 200000)->assertJsonPath('data.filters.purpose', 'rent');
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_invalid_ai_multi_patch_is_rejected_without_persistence(): void
    {
        foreach ([['type' => 'land', 'types' => ['apartment', 'villa']], ['types' => ['villa', 'villa']],
            ['types' => ['unknown']], ['types' => ['advertiser_id' => 9]]] as $set) {
            $this->model(['set' => $set, 'remove' => []]);
            $this->postJson('/api/ai/search', ['message' => 'تابع', 'filters' => ['purpose' => 'sale'], 'revision' => 0])
                ->assertStatus(503)->assertJsonPath('code', 'ai_unavailable');
        }
        $this->assertDatabaseCount('properties', 0);
        $this->assertDatabaseCount('saved_property_searches', 0);
    }
}
