<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class Wave3AiAssistantTest extends TestCase
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

    private function model(array $value): void
    {
        // A fresh factory prevents a previous fake callback from answering a
        // later follow-up. Keep the different responses and all assertions.
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::preventStrayRequests();
        Http::fake(['generativelanguage.googleapis.com/*' => function ($request) use ($value) {
            // generateContent uses a protobuf enum, unlike Interactions' MIME string.
            $this->assertSame('APPLICATION_JSON', $request['generationConfig']['responseFormat']['text']['mimeType']);
            $this->assertStringNotContainsString('fixture-server-key', $request->url());
            return Http::response(['candidates' => [['content' => ['parts' => [['text' => json_encode($value, JSON_UNESCAPED_UNICODE)]]]]]]);
        }]);
    }

    public function test_followups_keep_context_add_a_budget_and_remove_only_rooms(): void
    {
        $this->model(['set' => ['type' => 'apartment', 'purpose' => 'rent', 'search' => 'صنعاء', 'min_bedrooms' => 3], 'remove' => []]);
        $first = $this->postJson('/api/ai/search', ['message' => 'شقة للإيجار في صنعاء ثلاث غرف', 'filters' => (object) [], 'revision' => 0])
            ->assertOk()->assertJsonPath('data.revision', 0)->json('data.filters');
        $this->model(['set' => ['min_price' => 50000, 'max_price' => 100000], 'remove' => []]);
        $next = $this->postJson('/api/ai/search', ['message' => 'خلي السعر بين 50 ألف و100 ألف', 'filters' => $first, 'revision' => 1])
            ->assertOk()->assertJsonPath('data.filters.type', 'apartment')->assertJsonPath('data.filters.purpose', 'rent')
            ->assertJsonPath('data.filters.search', 'صنعاء')->assertJsonPath('data.filters.min_bedrooms', 3)->json('data.filters');
        Http::assertSent(function ($r) use ($first): bool {
            $input = json_decode($r['contents'][0]['parts'][0]['text'], true);
            return $input['current_filters'] === $first && $r->hasHeader('x-goog-api-key', 'fixture-server-key')
                && ! str_contains($r->url(), 'fixture-server-key') && ! isset($r['tools']);
        });
        $this->model(['set' => (object) [], 'remove' => ['min_bedrooms']]);
        $this->postJson('/api/ai/search', ['message' => 'شيل شرط الثلاث غرف', 'filters' => $next, 'revision' => 2])
            ->assertOk()->assertJsonMissingPath('data.filters.min_bedrooms')->assertJsonPath('data.filters.min_price', 50000)
            ->assertJsonPath('data.filters.max_price', 100000)->assertJsonPath('data.filters.search', 'صنعاء');
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_unknown_model_fields_and_invalid_ranges_never_change_data(): void
    {
        foreach ([['set' => ['publish' => true], 'remove' => []],
            ['set' => ['min_price' => 100000, 'max_price' => 50000], 'remove' => []],
            ['set' => ['user_id' => 1], 'remove' => []]] as $bad) {
            $this->model($bad);
            $this->postJson('/api/ai/search', ['message' => 'ابحث', 'filters' => ['purpose' => 'rent'], 'revision' => 3])
                ->assertStatus(503)->assertJsonPath('code', 'ai_unavailable');
        }
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_contextual_suggestions_and_manual_filters_are_checked_server_side(): void
    {
        $this->model(['set' => ['type' => 'land'], 'remove' => []]);
        $this->postJson('/api/ai/search', ['message' => 'خلها أرض', 'filters' => ['purpose' => 'sale', 'min_bedrooms' => 3, 'has_elevator' => true], 'revision' => 5])
            ->assertOk()->assertJsonMissingPath('data.filters.min_bedrooms')->assertJsonMissingPath('data.filters.has_elevator')
            ->assertJsonPath('data.filters.purpose', 'sale')->assertJsonPath('data.suggestions.0', 'min_area_m2');
        $this->postJson('/api/ai/search', ['message' => 'تابع', 'filters' => ['status' => 'draft'], 'revision' => 6])->assertUnprocessable();
    }

    public function test_disabled_provider_and_quota_failures_keep_manual_path_and_hide_secrets(): void
    {
        config(['gemini.enabled' => false]);
        $this->getJson('/api/ai/capabilities')->assertOk()->assertExactJson(['data' => ['available' => false, 'manual_filters_available' => true]]);
        $this->postJson('/api/ai/search', ['message' => 'شقة', 'filters' => (object) [], 'revision' => 0])->assertStatus(503);
        Http::assertNothingSent();
        config(['gemini.enabled' => true]);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response(['error' => ['message' => 'private-provider-details']], 429)]);
        $r = $this->postJson('/api/ai/search', ['message' => 'شقة', 'filters' => (object) [], 'revision' => 0])->assertStatus(503);
        $this->assertStringNotContainsString('fixture-server-key', $r->getContent());
        $this->assertStringNotContainsString('private-provider-details', $r->getContent());
    }

    public function test_shared_budget_stops_outbound_requests_before_provider_cost(): void
    {
        config(['gemini.daily_limit' => 1]);
        $this->model(['set' => (object) [], 'remove' => []]);
        $request = ['message' => 'شقة', 'filters' => (object) [], 'revision' => 0];
        $this->postJson('/api/ai/search', $request)->assertOk();
        \Illuminate\Support\Facades\Cache::flush();
        $this->postJson('/api/ai/search', $request)->assertStatus(429);
        Http::assertSentCount(1);
        $this->assertDatabaseHas('ai_daily_usage', ['day' => now('UTC')->toDateString(), 'request_count' => 1]);
        $this->travel(1)->days();
        $this->postJson('/api/ai/search', $request)->assertOk();
        Http::assertSentCount(2);
    }

    public function test_listing_helper_is_owned_authorized_and_non_mutating(): void
    {
        [$owner, $headers] = $this->actor('owner', 'owner');
        $property = $this->listing($owner, ['status' => 'draft', 'review_status' => 'draft']);
        $this->model(['fields' => ['title' => 'شقة مضاءة في صنعاء', 'bedrooms' => 3]]);
        $this->withHeaders($headers)->postJson('/api/ai/listing-fields', ['message' => 'شقة مضاءة في صنعاء ثلاث غرف', 'facts' => ['type' => 'apartment']])
            ->assertConflict();
        $this->withHeaders($headers)->postJson('/api/ai/listing-fields', ['message' => 'شقة مضاءة في صنعاء ثلاث غرف',
            'property_id' => $property->id, 'facts' => ['type' => 'apartment']])->assertOk()->assertJsonPath('data.requires_review', true);
        $this->assertDatabaseHas('properties', ['id' => $property->id, 'title' => 'شقة في صنعاء', 'status' => 'draft']);
        [$other, $otherHeaders] = $this->actor('other', 'broker');
        $this->withHeaders($otherHeaders)->postJson('/api/ai/listing-fields', ['message' => 'غيّر', 'property_id' => $property->id, 'facts' => (object) []])->assertNotFound();
        $this->model(['fields' => ['status' => 'published', 'current_sai_term_id' => 1]]);
        $this->withHeaders($otherHeaders)->postJson('/api/ai/listing-fields', ['message' => 'انشر', 'facts' => (object) []])->assertStatus(503);
        $this->assertDatabaseCount('properties', 1);
    }

    public function test_description_is_composed_only_from_verified_facts(): void
    {
        [, $headers] = $this->actor('description', 'broker');
        $this->model(['fact_order' => ['type', 'purpose', 'area_value', 'bedrooms'], 'tone' => 'direct']);
        $r = $this->withHeaders($headers)->postJson('/api/ai/listing-description', ['facts' => ['type' => 'apartment', 'purpose' => 'sale',
            'area_value' => 150, 'area_unit' => 'sqm', 'bedrooms' => 3]])->assertOk()->assertJsonPath('data.requires_review', true);
        $this->assertStringContainsString('المساحة: 150 م²', $r->json('data.description'));
        $this->assertStringContainsString('غرف النوم: 3', $r->json('data.description'));
        $this->assertStringNotContainsString('مصعد', $r->json('data.description'));
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_property_answers_reject_invented_quotes_and_private_properties(): void
    {
        [$owner] = $this->actor('answers', 'broker');
        $property = $this->listing($owner);
        $this->model(['keys' => [], 'quote' => 'يوجد مسبح وحديقة واسعة']);
        $this->postJson('/api/properties/'.$property->id.'/ask', ['question' => 'هل يوجد مسبح؟'])->assertOk()->assertJsonPath('data.not_mentioned', true);
        $this->model(['keys' => ['bedrooms', 'area_value'], 'quote' => '']);
        $r = $this->postJson('/api/properties/'.$property->id.'/ask', ['question' => 'كم الغرف والمساحة؟'])->assertOk();
        $this->assertStringContainsString('غرف النوم: 3', $r->json('data.answer'));
        $this->assertStringContainsString('المساحة: 140', $r->json('data.answer'));
        $draft = $this->listing($owner, ['status' => 'draft', 'review_status' => 'draft']);
        $this->postJson('/api/properties/'.$draft->id.'/ask', ['question' => 'ما المعلومات؟'])->assertNotFound();
        Http::assertSentCount(1);
    }

    private function actor(string $name, string $type): array
    {
        $user = User::create(['name' => 'معلن خيالي', 'email' => $name.'@ai.example.test', 'phone' => '+1202666'.substr(hash('sha256', $name), 0, 5),
            'password' => Hash::make('fixture-pass'), 'phone_verified_at' => now(), 'profile_completed_at' => now(),
            'identity_policy_version' => 2, 'account_status' => 'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]]);
        AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type, 'status' => 'approved', 'submitted_at' => now(), 'reviewed_at' => now()]);
        $token = 'ai_fixture_'.$name;
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token), 'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function listing(User $owner, array $changes = []): Property
    {
        return Property::create(array_merge(['user_id' => $owner->id, 'title' => 'شقة في صنعاء', 'description' => 'موقع قريب من الخدمات.',
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 50000000, 'currency' => 'YER', 'area_m2' => 140,
            'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء، حدة', 'latitude' => 15.3694, 'longitude' => 44.1910,
            'status' => 'published', 'review_status' => 'approved'], $changes));
    }
}
