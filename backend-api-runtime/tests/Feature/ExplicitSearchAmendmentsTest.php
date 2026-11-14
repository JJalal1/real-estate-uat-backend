<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\ExplicitSearchAmendments;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ExplicitSearchAmendmentsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config(['gemini.enabled' => true, 'gemini.key' => 'synthetic-search-key',
            'gemini.model' => 'gemini-3.1-flash-lite', 'gemini.daily_limit' => 200]);
        Http::preventStrayRequests();
    }

    private function model(array $patch): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::preventStrayRequests();
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response([
            'candidates' => [['content' => ['parts' => [['text' => json_encode($patch, JSON_UNESCAPED_UNICODE)]]]]],
        ])]);
    }

    private function context(): array
    {
        return ['types' => ['apartment', 'villa'], 'purpose' => 'rent',
            'south' => 15.3, 'west' => 44.1, 'north' => 15.4, 'east' => 44.2,
            'area_polygon' => '[[44.1,15.3],[44.2,15.3],[44.2,15.4],[44.1,15.4],[44.1,15.3]]'];
    }

    public function test_native_regression_keeps_types_and_maps_a_clear_ceiling_and_dual_bathrooms_to_matching_public_rows(): void
    {
        $apartment = $this->listing('apartment', 175000);
        $villa = $this->listing('villa', 190000);
        $this->listing('villa', 225000);
        $this->listing('house', 150000);
        $before = DB::table('properties')->orderBy('id')->get()->toJson();
        $current = $this->context();
        $this->model(['set' => ['type' => 'apartment', 'min_price' => 200000, 'min_bedrooms' => 3],
            'remove' => ['types', 'min_bathrooms']]);
        $filters = $this->postJson('/api/ai/search', [
            'message' => 'أضف ثلاث غرف نوم وحمامين وحد أقصى للإيجار الشهري 200000 ريال يمني.',
            'filters' => $current, 'revision' => 7,
        ])->assertOk()->assertJsonPath('data.revision', 7)
            ->assertJsonPath('data.filters.types', ['apartment', 'villa'])
            ->assertJsonMissingPath('data.filters.type')->assertJsonMissingPath('data.filters.min_price')
            ->assertJsonPath('data.filters.min_bedrooms', 3)->assertJsonPath('data.filters.min_bathrooms', 2)
            ->assertJsonPath('data.filters.currency', 'YER')->json('data.filters');
        $this->assertEquals(200000, $filters['max_price']);
        foreach ($current as $key => $value) $this->assertSame($value, $filters[$key], $key);
        $query = $filters;
        $query['max_monthly_rent'] = $query['max_price'];
        unset($query['max_price']);
        $rows = $this->getJson('/api/properties?'.http_build_query($query))->assertOk()
            ->assertHeader('X-Aqer-Filter-Contract', '2')->json('data');
        $this->assertEqualsCanonicalizing([$apartment->id, $villa->id], array_column($rows, 'id'));
        $this->assertSame($before, DB::table('properties')->orderBy('id')->get()->toJson());
        Http::assertSentCount(1);
    }

    public function test_clear_upper_bounds_support_arabic_digits_cardinals_and_explicit_currency(): void
    {
        foreach ([
            ['بحد أقصى للإيجار الشهري ٢٠٠٬٠٠٠ ريال يمني', 200000, 'YER'],
            ['الإيجار لا يزيد عن مئتين ألف ريال', 200000, 'YER'],
            ['حتى 400 دولار', 400, 'USD'],
        ] as [$message, $amount, $currency]) {
            $this->model(['set' => ['type' => 'apartment', 'min_price' => $amount], 'remove' => []]);
            $filters = $this->postJson('/api/ai/search', ['message' => $message, 'filters' => $this->context(), 'revision' => 1])
                ->assertOk()->assertJsonMissingPath('data.filters.min_price')
                ->assertJsonPath('data.filters.types', ['apartment', 'villa'])->json('data.filters');
            $this->assertEquals($amount, $filters['max_price']);
            $this->assertSame($currency, $filters['currency']);
        }
    }

    public function test_new_bound_preserves_an_unmentioned_existing_opposite_bound(): void
    {
        $this->model(['set' => ['min_price' => 200000], 'remove' => ['min_price']]);
        $filters = $this->postJson('/api/ai/search', ['message' => 'حد أقصى 200000 ريال',
            'filters' => $this->context() + ['min_price' => 100000], 'revision' => 1])
            ->assertOk()->assertJsonPath('data.filters.min_price', 100000)->json('data.filters');
        $this->assertEquals(200000, $filters['max_price']);
        $this->model(['set' => ['max_price' => 150000], 'remove' => []]);
        $filters = $this->postJson('/api/ai/search', ['message' => 'بحد أدنى 150 ألف ريال',
            'filters' => $this->context() + ['max_price' => 200000], 'revision' => 2])
            ->assertOk()->assertJsonPath('data.filters.max_price', 200000)->json('data.filters');
        $this->assertEquals(150000, $filters['min_price']);
    }

    public function test_questions_alternatives_withdrawals_and_advance_money_do_not_create_literal_constraints(): void
    {
        $reconciler = app(ExplicitSearchAmendments::class);
        foreach (['هل تقصد ثلاث غرف وحمامين؟', 'حمامين أو ثلاثة حمامات',
            'بدون حمامين', 'ألغ شرط الحمامين', 'مقدم لا يزيد عن 200000 ريال',
            'لا أريد حد أقصى 200000 ريال'] as $message) {
            $patch = $reconciler->reconcile($message, ['set' => [], 'remove' => []]);
            $this->assertSame([], $patch['set'], $message);
        }
        $this->model(['set' => (object) [], 'remove' => ['min_bathrooms']]);
        $this->postJson('/api/ai/search', ['message' => 'ألغ شرط الحمامين',
            'filters' => $this->context() + ['min_bathrooms' => 2], 'revision' => 1])
            ->assertOk()->assertJsonMissingPath('data.filters.min_bathrooms')
            ->assertJsonPath('data.filters.types', ['apartment', 'villa']);
    }

    public function test_explicit_english_and_arabic_accusative_type_followups_are_not_discarded_by_the_grounding_guard(): void
    {
        foreach ([['change type to LAND', 'land'], ['أريد أرضًا', 'land'], ['أريد بيتًا للإيجار', 'house']] as [$message, $type]) {
        $this->model(['set' => ['type' => $type], 'remove' => []]);
        $filters = $this->postJson('/api/ai/search', ['message' => $message,
            'filters' => $this->context(), 'revision' => 1])
            ->assertOk()->assertJsonPath('data.filters.type', $type)
            ->assertJsonMissingPath('data.filters.types')->assertJsonPath('data.filters.purpose', 'rent')->json('data.filters');
        $this->assertSame($this->context()['area_polygon'], $filters['area_polygon']);
        }
    }

    public function test_invalid_model_values_still_fail_before_literal_reconciliation(): void
    {
        foreach ([
            ['type' => 'unknown'], ['types' => ['villa', 'villa']], ['type' => 'land', 'types' => ['villa']],
            ['min_price' => 300000, 'max_price' => 100000], ['min_bathrooms' => 99],
        ] as $bad) {
            $this->model(['set' => $bad, 'remove' => []]);
            $this->postJson('/api/ai/search', ['message' => 'أضف ثلاث غرف وحمامين وحد أقصى 200000 ريال',
                'filters' => $this->context(), 'revision' => 1])->assertStatus(503)->assertJsonPath('code', 'ai_unavailable');
        }
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_provider_failure_never_becomes_a_successful_literal_fallback(): void
    {
        config(['gemini.enabled' => false]);
        $this->postJson('/api/ai/search', ['message' => 'أضف ثلاث غرف وحمامين وحد أقصى 200000 ريال',
            'filters' => $this->context(), 'revision' => 1])->assertStatus(503)->assertJsonPath('code', 'ai_unavailable');
        Http::assertNothingSent();
    }

    private function listing(string $type, int $rent): Property
    {
        $owner = User::factory()->create(['phone_verified_at' => now(), 'account_status' => 'active']);
        $property = Property::create([
            'user_id' => $owner->id, 'title' => 'Synthetic search '.$type, 'type' => $type, 'purpose' => 'rent',
            'price' => $rent, 'monthly_rent' => $rent, 'currency' => 'YER', 'bedrooms' => 3, 'bathrooms' => 2,
            'area_m2' => 160, 'address' => 'صنعاء، موقع اصطناعي', 'latitude' => 15.3694, 'longitude' => 44.191,
            'status' => 'published', 'review_status' => 'approved', 'published_at' => now(),
        ]);
        $property->forceFill(['availability_status' => 'available', 'availability_confirmed_at' => now(),
            'availability_due_at' => now()->addDays(7)])->saveQuietly();
        if (DB::getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        return $property;
    }
}
