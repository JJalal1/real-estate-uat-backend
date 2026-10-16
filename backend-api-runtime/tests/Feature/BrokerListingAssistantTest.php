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

class BrokerListingAssistantTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config(['gemini.enabled' => true, 'gemini.key' => 'fixture-key',
            'gemini.model' => 'gemini-3.1-flash-lite', 'gemini.daily_limit' => 200]);
        Http::preventStrayRequests();
    }

    private function response(array $fields): array
    {
        return ['candidates' => [['content' => ['parts' => [['text' => json_encode(['fields' => (object) $fields], JSON_UNESCAPED_UNICODE)]]]]]];
    }

    private function prepare(array $headers, string $message, array $facts = [], array $extra = [])
    {
        return $this->withHeaders($headers)->postJson('/api/ai/listing-draft',
            ['mode' => 'prepare', 'message' => $message, 'facts' => (object) $facts] + $extra);
    }

    public function test_preparation_requires_an_eligible_advertiser_and_owned_editable_property(): void
    {
        $input = ['mode' => 'copy', 'facts' => ['type' => 'apartment']];
        $this->postJson('/api/ai/listing-draft', $input)->assertUnauthorized();
        [, $ordinary] = $this->actor('ordinary', null);
        $this->withHeaders($ordinary)->postJson('/api/ai/listing-draft', $input)->assertForbidden();
        [$owner, $ownerHeaders] = $this->actor('owner', 'owner');
        $property = $this->listing($owner);
        $this->withHeaders($ownerHeaders)->postJson('/api/ai/listing-draft', $input)->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson('/api/ai/listing-draft', $input + ['property_id' => $property->id])->assertOk();
        [, $other] = $this->actor('other', 'broker');
        $this->withHeaders($other)->postJson('/api/ai/listing-draft', $input + ['property_id' => $property->id])->assertNotFound();
        $this->withHeaders($ownerHeaders)->putJson('/api/properties/'.$property->id.'/sai', ['sai_payer' => 'buyer'])->assertOk();
        $property->refresh();
        $property->update(['review_status' => 'submitted']);
        $this->withHeaders($ownerHeaders)->postJson('/api/ai/listing-draft', $input + ['property_id' => $property->id])->assertConflict();
        Http::assertNothingSent();
    }

    public function test_proposals_generate_reviewable_copy_without_writing_or_publishing(): void
    {
        [$broker, $headers] = $this->actor('prepare', 'broker');
        $property = $this->listing($broker);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response($this->response([
            'type' => 'apartment', 'purpose' => 'sale', 'bedrooms' => 4, 'bathrooms' => 2,
            'governorate' => 'صنعاء', 'district' => 'حدة', 'has_parking' => false,
            'title' => 'عنوان من الموديل لا نستخدمه',
        ]))]);
        $r = $this->prepare($headers, 'شقة للبيع في صنعاء، 4 غرف نوم وحمامين', [], ['property_id' => $property->id])
            ->assertOk()->assertHeader('Cache-Control', 'no-store, private')
            ->assertJsonPath('data.source', 'ai')->assertJsonPath('data.requires_review', true)
            ->assertJsonPath('data.fields.bedrooms', 4)->assertJsonPath('data.fields.has_parking', false)
            ->assertJsonMissingPath('data.fields.title')->assertJsonPath('data.copy.title', 'شقة للبيع في حدة');
        $this->assertStringContainsString('4 غرف نوم', $r->json('data.copy.description'));
        $this->assertStringContainsString('لا يوجد موقف', $r->json('data.copy.description'));
        $this->assertStringNotContainsString('مصعد', $r->json('data.copy.description'));
        $this->assertDatabaseHas('properties', ['id' => $property->id, 'title' => 'عنوان محفوظ', 'status' => 'draft', 'review_status' => 'draft']);
        $this->assertDatabaseCount('properties', 1);
        $this->assertDatabaseCount('property_sai_terms', 0);
    }

    public function test_recomposition_uses_only_selected_facts_without_calling_the_model(): void
    {
        [, $headers] = $this->actor('copy', 'broker');
        $r = $this->withHeaders($headers)->postJson('/api/ai/listing-draft', ['mode' => 'copy',
            'facts' => ['title' => 'عنواني المحفوظ', 'type' => 'apartment', 'purpose' => 'sale', 'bedrooms' => 3]])
            ->assertOk()->assertJsonPath('data.source', 'facts')->assertJsonPath('data.copy.title', 'عنواني المحفوظ');
        $this->assertStringNotContainsString('مصعد', $r->json('data.copy.description'));
        $this->assertStringNotContainsString('موقف', $r->json('data.copy.description'));
        $this->assertStringContainsString('3 غرف نوم', $r->json('data.copy.description'));
        $this->assertDatabaseCount('properties', 0);
        Http::assertNothingSent();
    }

    public function test_rental_hidden_fields_foreign_money_and_new_whole_floor_claims_are_not_proposed(): void
    {
        [, $headers] = $this->actor('rental', 'broker');
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response($this->response([
            'type' => 'apartment', 'purpose' => 'rent', 'monthly_rent' => 100, 'price' => 200,
            'currency' => 'USD', 'area_value' => 160, 'area_unit' => 'sqm', 'has_elevator' => true,
            'unit_occupies_entire_floor' => true, 'floor_number' => '3',
        ]))]);
        $r = $this->prepare($headers, 'شقة للإيجار')->assertOk()
            ->assertJsonMissingPath('data.fields.monthly_rent')->assertJsonMissingPath('data.fields.price')
            ->assertJsonMissingPath('data.fields.area_value')->assertJsonMissingPath('data.fields.has_elevator')
            ->assertJsonMissingPath('data.fields.unit_occupies_entire_floor')
            ->assertJsonPath('data.fields.floor_number', '3');
        $copy = $r->json('data.copy.description');
        foreach (['المساحة', 'مصعد', 'USD', 'الدور كامل'] as $claim) $this->assertStringNotContainsString($claim, $copy);
    }

    public function test_provider_outage_retries_once_then_labels_literal_text_organization_honestly(): void
    {
        [, $headers] = $this->actor('fallback', 'broker');
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response(['error' => ['message' => 'private-provider-body']], 503)]);
        $r = $this->prepare($headers, "شقة للإيجار في صنعاء، ٣ غرف نوم، ٢ حمامات، الدور الثالث، الإيجار الشهري: ٧٥ ألف ريال يمني، بدون موقف")
            ->assertOk()->assertJsonPath('data.source', 'text')->assertJsonPath('data.fields.type', 'apartment')
            ->assertJsonPath('data.fields.purpose', 'rent')->assertJsonPath('data.fields.bedrooms', 3)
            ->assertJsonPath('data.fields.bathrooms', 2)->assertJsonPath('data.fields.floor_number', '3')
            ->assertJsonPath('data.fields.monthly_rent', 75000)->assertJsonPath('data.fields.has_parking', false)
            ->assertJsonPath('data.fields.governorate', 'صنعاء');
        $this->assertStringContainsString('تعذّر', $r->json('data.message'));
        $this->assertStringNotContainsString('fixture-key', $r->getContent());
        $this->assertStringNotContainsString('private-provider-body', $r->getContent());
        Http::assertSentCount(2);
        $this->assertDatabaseHas('ai_daily_usage', ['day' => now('UTC')->toDateString(), 'request_count' => 2]);
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_literal_fallback_omits_ambiguity_unlabelled_amounts_and_foreign_currency(): void
    {
        [, $headers] = $this->actor('literal', 'broker');
        config(['gemini.enabled' => false]);
        $this->prepare($headers, 'فيلا أو شقة للبيع أو للإيجار في صنعاء أو في عدن، 3 غرف نوم أو 4 غرف نوم، للإيجار 3 غرف، يوجد مصعد وبدون مصعد')
            ->assertOk()->assertJsonPath('data.source', 'text')->assertJsonMissingPath('data.fields.type')
            ->assertJsonMissingPath('data.fields.purpose')->assertJsonMissingPath('data.fields.bedrooms')
            ->assertJsonMissingPath('data.fields.monthly_rent')->assertJsonMissingPath('data.fields.has_elevator')
            ->assertJsonMissingPath('data.fields.governorate');
        $this->prepare($headers, 'ليست فيلا، شقة للبيع، السعر: 50 ألف دولار')
            ->assertOk()->assertJsonPath('data.fields.type', 'apartment')
            ->assertJsonMissingPath('data.fields.price')->assertJsonMissingPath('data.fields.currency');
        Http::assertNothingSent();
    }

    public function test_transient_retry_succeeds_and_counts_both_attempts(): void
    {
        [, $headers] = $this->actor('retry', 'broker');
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push([], 503)->push($this->response(['bedrooms' => 4]))]);
        $this->prepare($headers, '4 غرف نوم')->assertOk()->assertJsonPath('data.source', 'ai')->assertJsonPath('data.fields.bedrooms', 4);
        Http::assertSentCount(2);
        $this->assertDatabaseHas('ai_daily_usage', ['day' => now('UTC')->toDateString(), 'request_count' => 2]);
    }

    public function test_budget_prevents_retry_and_subsequent_outbound_cost_while_preserving_draft_help(): void
    {
        [, $headers] = $this->actor('budget', 'broker');
        config(['gemini.daily_limit' => 1]);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response([], 503)]);
        $this->prepare($headers, 'شقة للبيع')->assertOk()->assertJsonPath('data.source', 'text');
        Cache::flush();
        $this->prepare($headers, 'شقة للبيع')->assertOk()->assertJsonPath('data.source', 'text');
        Http::assertSentCount(1);
        $this->assertDatabaseHas('ai_daily_usage', ['day' => now('UTC')->toDateString(), 'request_count' => 1]);
    }

    public function test_permanent_provider_failures_are_not_retried_and_bad_input_never_spends_budget(): void
    {
        [, $headers] = $this->actor('reject', 'broker');
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response([], 429)]);
        $this->prepare($headers, 'شقة')->assertOk()->assertJsonPath('data.source', 'text');
        Http::assertSentCount(1);
        $this->prepare($headers, 'انشر', ['status' => 'published'])->assertUnprocessable();
        $this->prepare($headers, str_repeat('a', 1501))->assertUnprocessable();
        Http::assertSentCount(1);
        $this->assertDatabaseCount('properties', 0);
    }

    private function actor(string $name, ?string $type): array
    {
        $user = User::create(['name' => 'دلال اختباري', 'email' => $name.'@draft.example.test',
            'phone' => '+1202555'.substr(hash('sha256', $name), 0, 5), 'password' => Hash::make('fixture-pass'),
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'identity_policy_version' => 2, 'account_status' => 'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]]);
        if ($type) AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type,
            'status' => 'approved', 'submitted_at' => now(), 'reviewed_at' => now()]);
        $token = 'draft_fixture_'.$name;
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function listing(User $user): Property
    {
        return Property::create(['user_id' => $user->id, 'title' => 'عنوان محفوظ', 'description' => 'وصف محفوظ',
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 50000000, 'currency' => 'YER', 'area_m2' => 140,
            'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء، حدة', 'latitude' => 15.3694, 'longitude' => 44.1910,
            'status' => 'draft', 'review_status' => 'draft']);
    }
}
