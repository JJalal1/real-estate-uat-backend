<?php

namespace Tests\Feature;

use App\Models\Governorate;
use App\Models\Property;
use App\Models\User;
use App\Services\SmartSearchService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SpokenSearchCityTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config(['gemini.enabled' => true, 'gemini.key' => 'fixture-server-key',
            'gemini.model' => 'gemini-3.1-flash-lite', 'gemini.daily_limit' => 200]);
        Http::preventStrayRequests();
    }

    public function test_complete_spoken_city_names_use_existing_active_canonical_names(): void
    {
        $service = app(SmartSearchService::class);
        foreach ([['اب', 'إب'], ['مدينة اب', 'إب'], ['مدينة اب،', 'إب'], ['مدينه إب', 'إب'], ['مَدِينَة إِب', 'إب'],
            ['مدينةإب', 'إب'], [' محافظة   اب ', 'إب'], ['مدينة ذمار', 'ذمار'],
            ['مدينه صنعاء', 'صنعاء'], ['محافظة مارب', 'مأرب']] as [$spoken, $canonical]) {
            $this->assertSame($canonical, $service->validate(['search' => $spoken])['search'], $spoken);
        }
        Http::assertNothingSent();
    }

    public function test_neighborhoods_unknown_places_and_read_only_source_constraints_are_not_broadened(): void
    {
        $service = app(SmartSearchService::class);
        foreach (['شارع تعز في إب', 'مدينة غير معروفة', 'باب اليمن', 'إب شارع الجامعة'] as $keyword) {
            $this->assertSame($keyword, $service->validate(['search' => $keyword])['search']);
        }
        $source = ['governorate' => 'تعز', 'latitude' => 13.58, 'longitude' => 44.02, 'radius_km' => 10,
            'advertiser_id' => 25, 'type' => 'house', 'purpose' => 'rent', 'currency' => 'USD', 'max_price' => 400];
        $next = $service->validate($source + ['search' => 'مدينة اب']);
        foreach ($source as $key => $value) $this->assertSame($value, $next[$key], $key);
        $this->assertSame('إب', $next['search']);
        Http::assertNothingSent();
    }

    public function test_inactive_city_names_do_not_become_new_canonical_coverage(): void
    {
        Governorate::query()->where('name_ar', 'إب')->update(['is_active' => false]);
        $this->assertSame('مدينة اب', app(SmartSearchService::class)->validate(['search' => 'مدينة اب'])['search']);
        Http::assertNothingSent();
    }

    public function test_explicit_spoken_search_for_an_apartment_in_dhamar_works_without_the_model(): void
    {
        config(['gemini.enabled' => false]);
        Http::fake();
        $bounds = ['south' => 14.5, 'west' => 44.35, 'north' => 14.6, 'east' => 44.45];
        $this->postJson('/api/ai/search', [
            'message' => 'ابحث لي عن شقه للايجار في ذمار',
            'filters' => $bounds + ['max_price' => 80000, 'types' => ['apartment', 'house']],
            'revision' => 7,
        ])->assertOk()->assertJsonPath('data.revision', 7)
            ->assertJson(['data' => ['filters' => [
                'type' => 'apartment', 'purpose' => 'rent', 'search' => 'ذمار', 'max_price' => 80000,
            ] + $bounds]])
            ->assertJsonMissingPath('data.filters.types')
            ->assertJsonPath('data.changed', true);

        $this->postJson('/api/ai/search', [
            'message' => 'شقة للإيجار',
            'filters' => ['search' => 'ذمار'],
            'revision' => 8,
        ])->assertOk()->assertJsonPath('data.filters.type', 'apartment')
            ->assertJsonPath('data.filters.purpose', 'rent')
            ->assertJsonPath('data.filters.search', 'ذمار');
        Http::assertNothingSent();
    }

    public function test_complete_spoken_city_search_preserves_rooms_and_the_monthly_price_ceiling(): void
    {
        config(['gemini.enabled' => false]);
        Http::fake();
        $this->postJson('/api/ai/search', [
            'message' => 'أبغى شقة للإيجار في ذمار فيها ثلاث غرف وبحد أقصى ٨٠٬٠٠٠ ريال شهرياً',
            'filters' => (object) [],
            'revision' => 3,
        ])->assertOk()->assertJson(['data' => ['filters' => [
            'type' => 'apartment', 'purpose' => 'rent', 'search' => 'ذمار',
            'min_bedrooms' => 3, 'max_price' => 80000, 'currency' => 'YER',
        ], 'revision' => 3]]);
        Http::assertNothingSent();
    }

    public function test_spoken_city_search_with_more_criteria_passes_the_complete_text_to_the_model(): void
    {
        $message = 'أبغى شقة للإيجار في ذمار فيها ثلاث غرف وموقف سيارة';
        $this->model(['set' => ['type' => 'apartment', 'types' => ['apartment'], 'purpose' => 'rent',
            'search' => 'ذمار', 'min_bedrooms' => 3, 'has_parking' => true], 'remove' => []]);
        $this->postJson('/api/ai/search', ['message' => $message, 'filters' => (object) [], 'revision' => 2])
            ->assertOk()->assertJsonPath('data.filters.min_bedrooms', 3)
            ->assertJsonPath('data.filters.type', 'apartment')->assertJsonMissingPath('data.filters.types')
            ->assertJsonPath('data.filters.search', 'ذمار')->assertJsonPath('data.filters.has_parking', true);
        Http::assertSent(function (\Illuminate\Http\Client\Request $request) use ($message): bool {
            $data = $request->data();
            $input = json_decode($data['contents'][0]['parts'][0]['text'], true, flags: JSON_THROW_ON_ERROR);
            $properties = $data['generationConfig']['responseFormat']['text']['schema']['properties']['set']['properties'];
            return $input['follow_up'] === $message && isset($properties['types']) && ! isset($properties['type']);
        });
    }

    public function test_spoken_ibb_then_price_and_new_type_reuses_real_public_filters_without_writes(): void
    {
        $user = User::create(['name' => 'Fictional search fixture', 'email' => 'spoken-city@example.invalid', 'password' => 'fixture-only',
            'account_status' => 'active', 'identity_policy_version' => 2, 'phone_verified_at' => now(), 'profile_completed_at' => now()]);
        $expensive = $this->listing($user, 'إب', 150000000, 13.9667, 44.1833);
        $cheap = $this->listing($user, 'إب', 80000000, 13.97, 44.18);
        $this->listing($user, 'صنعاء', 150000000, 15.3694, 44.191);
        $before = DB::table('properties')->orderBy('id')->get()->toJson();

        $this->model(['set' => ['search' => 'مدينة اب'], 'remove' => []]);
        $first = $this->postJson('/api/ai/search', ['message' => 'ابحث لي عن عقارات داخل مدينة اب',
            'filters' => (object) [], 'revision' => 0])
            ->assertOk()->assertJsonPath('data.filters.search', 'إب')->json('data.filters');
        $ids = $this->getJson('/api/properties?'.http_build_query($first))->assertOk()->assertJsonPath('meta.total', 2)->json('data');
        $this->assertEqualsCanonicalizing([$expensive->id, $cheap->id], array_column($ids, 'id'));

        $this->model(['set' => ['min_price' => 100000000, 'currency' => 'YER'], 'remove' => []]);
        $next = $this->postJson('/api/ai/search', ['message' => 'خلي السعر أكثر من ١٠٠ مليون', 'filters' => $first, 'revision' => 1])
            ->assertOk()->assertJsonPath('data.filters.search', 'إب')->assertJsonPath('data.filters.min_price', 100000000)->json('data.filters');
        $this->getJson('/api/properties?'.http_build_query($next))->assertOk()->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $expensive->id);

        $this->model(['set' => ['type' => 'land', 'purpose' => 'sale'], 'remove' => []]);
        $last = $this->postJson('/api/ai/search', ['message' => 'خلها أرض للبيع', 'filters' => $next, 'revision' => 2])
            ->assertOk()->assertJsonPath('data.filters.search', 'إب')->assertJsonPath('data.filters.min_price', 100000000)
            ->assertJsonPath('data.filters.type', 'land')->assertJsonPath('data.filters.purpose', 'sale')->json('data.filters');
        Http::assertSent(function (\Illuminate\Http\Client\Request $request) use ($next): bool {
            $input = json_decode($request->data()['contents'][0]['parts'][0]['text'], true, flags: JSON_THROW_ON_ERROR);
            return $input['current_filters'] === $next && $input['follow_up'] === 'خلها أرض للبيع';
        });
        $this->getJson('/api/properties?'.http_build_query($last))->assertOk()->assertJsonPath('meta.total', 0);
        $this->assertSame($before, DB::table('properties')->orderBy('id')->get()->toJson());
        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseCount('properties', 3);
    }

    public function test_type_followups_complete_clear_literal_purpose_without_losing_context(): void
    {
        foreach ([['خلها أرض للبيع', 'land', 'sale'], ['خليها فيلا للإيجار', 'villa', 'rent'],
            ['أريد منزل لِلْبَيْع', 'house', 'sale']] as [$message, $type, $purpose]) {
            $this->model(['set' => ['type' => $type], 'remove' => []]);
            $this->postJson('/api/ai/search', ['message' => $message,
                'filters' => ['search' => 'إب', 'min_price' => 100000000], 'revision' => 2])
                ->assertOk()->assertJsonPath('data.filters.type', $type)
                ->assertJsonPath('data.filters.purpose', $purpose)
                ->assertJsonPath('data.filters.search', 'إب')
                ->assertJsonPath('data.filters.min_price', 100000000);
        }
    }

    public function test_literal_purpose_does_not_override_negation_questions_or_alternatives(): void
    {
        foreach (['ما أريد أرض للبيع', 'مو للبيع أبغى أرض', 'ألغ شرط للبيع وأبغى أرض',
            'أرض للبيع أو للإيجار', 'هل تقصد أرض للبيع؟', 'land but NOT للبيع'] as $message) {
            $this->model(['set' => ['type' => 'land'], 'remove' => []]);
            $this->postJson('/api/ai/search', ['message' => $message,
                'filters' => ['search' => 'إب', 'purpose' => 'rent'], 'revision' => 1])
                ->assertOk()->assertJsonPath('data.filters.purpose', 'rent')
                ->assertJsonPath('data.filters.search', 'إب');
        }
        $this->model(['set' => ['type' => 'land'], 'remove' => ['purpose']]);
        $this->postJson('/api/ai/search', ['message' => 'ألغ شرط للبيع وأبغى أرض',
            'filters' => ['search' => 'إب', 'purpose' => 'sale'], 'revision' => 1])
            ->assertOk()->assertJsonMissingPath('data.filters.purpose');
    }

    private function listing(User $user, string $city, int $price, float $latitude, float $longitude): Property
    {
        $property = Property::create(['user_id' => $user->id, 'title' => 'عقار تجريبي في '.$city,
            'type' => 'house', 'purpose' => 'sale', 'price' => $price, 'currency' => 'YER', 'area_m2' => 200,
            'address' => $city.'، حي تجريبي', 'latitude' => $latitude, 'longitude' => $longitude,
            'status' => 'published', 'review_status' => 'approved', 'published_at' => now()]);
        // Availability timestamps are guarded model fields. Initialize the
        // fixture explicitly so the pre-existing public sweep has no work.
        $property->forceFill(['availability_status' => 'available',
            'availability_confirmed_at' => now(), 'availability_due_at' => now()->addDays(14)])->saveQuietly();
        if (DB::getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        return $property;
    }

    private function model(array $value): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::preventStrayRequests();
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response([
            'candidates' => [['content' => ['parts' => [['text' => json_encode($value, JSON_UNESCAPED_UNICODE)]]]]],
        ])]);
    }
}
