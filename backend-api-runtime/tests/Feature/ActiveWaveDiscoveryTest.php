<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\SavedPropertySearch;
use App\Models\User;
use App\Models\UserNotification;
use App\Models\UserNotificationPreference;
use App\Services\ListingDescriptionComposer;
use App\Services\SavedSearchAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ActiveWaveDiscoveryTest extends TestCase
{
    use RefreshDatabase;

    public function test_copy_is_a_natural_fact_bound_paragraph_and_sparse_inputs_stay_short(): void
    {
        $composer = app(ListingDescriptionComposer::class);
        $copy = $composer->compose(['title' => 'شقة، شقة للإيجار، معروض للإيجار', 'type' => 'apartment', 'purpose' => 'rent',
            'governorate' => 'ذمار', 'district' => 'المجمع الطبي', 'floor_number' => '3', 'bedrooms' => 3, 'bathrooms' => 1,
            'has_parking' => true, 'building_facade' => 'north'], true);
        $text = $copy['description'];
        foreach (['فرصة لاستئجار شقة', 'المجمع الطبي', 'محافظة ذمار', 'الدور الثالث', '3 غرف نوم', 'حمامًا واحدًا', 'موقف للسيارة', 'شمالية'] as $fact) $this->assertStringContainsString($fact, $text);
        foreach (['غرف النوم:', 'الدور:', 'تعرّف على هذا العقار', 'واسعة', 'جديدة', 'مفروشة', 'فاخرة', 'الخدمات', 'مصعد'] as $claim) $this->assertStringNotContainsString($claim, $text);
        $this->assertSame(1, mb_substr_count($text, 'شقة'));
        $this->assertGreaterThanOrEqual(2, count(preg_split('/(?<=\.)\s+/u', $text)));
        $this->assertLessThanOrEqual(4, count(preg_split('/(?<=\.)\s+/u', $text)));
        $this->assertSame('شقة للإيجار.', $composer->compose(['type' => 'apartment', 'purpose' => 'rent'])['description']);
        $this->assertTrue($copy['requires_review']);
        $this->assertDatabaseCount('properties', 0);
    }

    public function test_saved_ai_filters_keep_currency_monthly_budget_and_explicit_false_and_use_discovery_results(): void
    {
        [$owner] = $this->actor('owner'); [, $headers] = $this->actor('searcher');
        $match = $this->listing($owner, ['monthly_rent' => 500, 'currency' => 'USD', 'has_parking' => false, 'floor_number' => '3']);
        $this->listing($owner, ['monthly_rent' => 500, 'currency' => 'YER', 'has_parking' => false, 'floor_number' => '3']);
        $this->listing($owner, ['monthly_rent' => 500, 'currency' => 'USD', 'has_parking' => true, 'floor_number' => '3']);
        $this->listing($owner, ['monthly_rent' => 900, 'currency' => 'USD', 'has_parking' => false, 'floor_number' => '3']);
        $filters = ['type' => 'apartment', 'purpose' => 'rent', 'max_monthly_rent' => 600, 'currency' => 'USD', 'has_parking' => false, 'floor_number' => '3'];
        $r = $this->withHeaders($headers)->postJson('/api/saved-searches', ['name' => 'بحث بالدولار', 'filters' => $filters])
            ->assertCreated()->assertJsonPath('data.matching_count', 1)->assertJsonPath('data.filters.has_parking', false)
            ->assertJsonPath('data.filters.currency', 'USD')->assertJsonPath('data.filters.max_monthly_rent', 600);
        $this->getJson('/api/properties?'.http_build_query($filters))->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $match->id);
        $this->assertSame(1, SavedPropertySearch::query()->count());
        $this->withHeaders($headers)->patchJson('/api/saved-searches/'.$r->json('data.id'), ['filters' => $filters + ['has_elevator' => false]])->assertOk()->assertJsonPath('data.filters.has_elevator', false);
    }

    public function test_polygon_and_radius_apply_to_results_counts_and_alerts_without_rectangular_false_matches(): void
    {
        [$owner] = $this->actor('geo-owner'); [$searcher, $headers] = $this->actor('geo-search');
        $inside = $this->listing($owner, ['latitude' => 15.1, 'longitude' => 44.1]);
        $outside = $this->listing($owner, ['latitude' => 15.8, 'longitude' => 44.8]);
        $ring = json_encode([[44,15],[45,15],[44,16],[44,15]]);
        $filters = ['purpose' => 'rent', 'south' => 15, 'west' => 44, 'north' => 16, 'east' => 45, 'area_polygon' => $ring];
        $r = $this->withHeaders($headers)->postJson('/api/saved-searches', ['name' => 'داخل الرسم', 'filters' => $filters])
            ->assertCreated()->assertJsonPath('data.matching_count', 1)->assertJsonPath('data.filters.area_polygon', $ring);
        $this->getJson('/api/properties?'.http_build_query($filters))->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $inside->id);
        $this->assertSame(0, app(SavedSearchAlertService::class)->notifyPublishedProperty($outside->id));
        $this->assertSame(1, app(SavedSearchAlertService::class)->notifyPublishedProperty($inside->id));
        $this->assertSame(0, app(SavedSearchAlertService::class)->notifyPublishedProperty($inside->id));
        $this->assertDatabaseHas('user_notifications', ['user_id' => $searcher->id, 'type' => 'saved_search_match', 'entity_id' => $inside->id]);
        $circle = ['latitude' => 15.1, 'longitude' => 44.1, 'radius_km' => 2];
        $this->getJson('/api/properties?'.http_build_query($circle))->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $inside->id);
    }

    public function test_invalid_or_incomplete_geometry_and_unknown_saved_filters_are_rejected(): void
    {
        [, $headers] = $this->actor('validation');
        foreach ([['south' => 15], ['south' => 17, 'north' => 15, 'west' => 44, 'east' => 45], ['latitude' => 15, 'longitude' => 44],
            ['radius_km' => 3], ['area_polygon' => '[[44,15],[45,15],[44,16]]'], ['secret_role' => 'admin'], ['min_price' => 20, 'max_price' => 10]] as $filters) {
            $this->withHeaders($headers)->postJson('/api/saved-searches', ['name' => 'غير صالح', 'filters' => $filters])->assertUnprocessable();
        }
        $this->assertDatabaseCount('saved_property_searches', 0);
    }

    public function test_notifications_respect_availability_and_user_preferences(): void
    {
        [$owner] = $this->actor('availability-owner'); [$searcher, $headers] = $this->actor('availability-search');
        $this->withHeaders($headers)->postJson('/api/saved-searches', ['name' => 'متاح فقط', 'filters' => ['type' => 'apartment']])->assertCreated();
        $listing = $this->listing($owner);
        $listing->forceFill(['availability_status' => 'paused'])->saveQuietly();
        $this->assertSame(0, app(SavedSearchAlertService::class)->notifyPublishedProperty($listing->id));
        $this->withHeaders($headers)->getJson('/api/saved-searches')->assertJsonPath('data.0.matching_count', 0);
        $listing->forceFill(['availability_status' => 'available'])->saveQuietly();
        UserNotificationPreference::query()->updateOrCreate(['user_id' => $searcher->id], ['discovery_alerts' => false]);
        $this->assertSame(0, app(SavedSearchAlertService::class)->notifyPublishedProperty($listing->id));
        $this->assertDatabaseCount('user_notifications', 0);
    }

    public function test_contact_reveals_only_explicit_listing_phone_for_an_active_authenticated_viewer(): void
    {
        [$owner] = $this->actor('contact-owner'); [$viewer, $headers] = $this->actor('contact-viewer');
        $listing = $this->listing($owner, ['contact_phone' => '+967 770-123456']);
        $url = '/api/properties/'.$listing->id.'/contact';
        $this->getJson($url)->assertUnauthorized();
        $this->withHeaders($headers)->getJson($url)->assertOk()->assertHeader('Cache-Control', 'no-store, private')->assertExactJson(['data' => ['property_id' => $listing->id, 'phone' => '+967770123456']]);
        $listing->forceFill(['contact_phone' => null])->saveQuietly();
        $this->withHeaders($headers)->getJson($url)->assertUnprocessable();
        $listing->forceFill(['availability_status' => 'sold'])->saveQuietly();
        $this->withHeaders($headers)->getJson($url)->assertNotFound();
        $viewer->forceFill(['account_status' => 'suspended'])->saveQuietly();
        $this->withHeaders($headers)->getJson($url)->assertForbidden();
        $this->assertDatabaseCount('message_threads', 0);
        $this->assertDatabaseCount('viewing_bookings', 0);
    }

    public function test_directory_filters_use_public_name_type_regions_and_declared_specialties_only(): void
    {
        [$broker] = $this->actor('دلال شقق', 'broker', ['governorate' => 'صنعاء', 'specialties' => ['شقق']]);
        [$office] = $this->actor('مكتب أراضي', 'office', ['governorate' => 'عدن', 'office_name' => 'مكتب الأمانة', 'work_areas' => ['صنعاء'], 'specialties' => ['أراضٍ']]);
        $this->actor('بعيد', 'broker', ['governorate' => 'تعز', 'specialties' => ['شقق']]);
        $q = http_build_query(['governorate' => 'صنعاء', 'region_only' => 1, 'specialty' => 'شقق', 'account_type' => 'broker']);
        $r = $this->getJson('/api/brokers?'.$q)->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $broker->id);
        foreach (['phone','email','details','documents','identity_number','selfie'] as $private) $r->assertJsonMissingPath('data.0.'.$private);
        $this->getJson('/api/brokers?'.http_build_query(['search' => 'مكتب الأمانة', 'account_type' => 'office', 'region_only' => 1, 'governorate' => 'صنعاء']))
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $office->id);
        $this->getJson('/api/brokers?min_rating=4')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_legacy_public_advertiser_profile_never_reveals_pending_verification_details(): void
    {
        [$user] = $this->actor('معلن فردي');
        AccountVerificationProfile::query()->create(['user_id' => $user->id, 'type' => 'office', 'status' => 'pending',
            'details' => ['office_name' => 'اسم في مستند خاص', 'governorate' => 'عنوان خاص', 'work_areas' => ['عنوان خاص'], 'identity_number' => 'PRIVATE-FIXTURE']]);
        $listing = $this->listing($user);
        $r = $this->getJson('/api/advertisers/'.$user->id.'/profile')->assertOk()->assertJsonPath('data.account_type', 'individual')
            ->assertJsonPath('data.verified', false)->assertJsonPath('data.name', 'معلن فردي')->assertJsonPath('data.work_areas', []);
        $this->assertStringNotContainsString('PRIVATE-FIXTURE', $r->getContent());
        $this->assertStringNotContainsString('عنوان خاص', $r->getContent());
        $listing->forceFill(['availability_status' => 'paused'])->saveQuietly();
        $this->getJson('/api/advertisers/'.$user->id.'/profile')->assertNotFound();
    }

    private function actor(string $name, ?string $type = null, array $details = []): array
    {
        $key = substr(hash('sha256', $name), 0, 16);
        $user = User::query()->create(['name' => $name, 'email' => $key.'@wave.test', 'phone' => '+967'.substr((string)hexdec(substr($key,0,8)),0,9),
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'account_status' => 'active', 'password' => Hash::make('fixture-password')]);
        if ($type) AccountVerificationProfile::query()->create(['user_id' => $user->id, 'type' => $type, 'status' => 'approved', 'reviewed_at' => now(), 'details' => $details]);
        $token = 'active_wave_'.$key;
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token), 'token_prefix' => substr($token,0,12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function listing(User $owner, array $changes = []): Property
    {
        $property = Property::query()->create(array_merge(['user_id' => $owner->id, 'title' => 'شقة اختبار', 'type' => 'apartment', 'purpose' => 'rent',
            'price' => 6000, 'monthly_rent' => 500, 'currency' => 'USD', 'latitude' => 15.3, 'longitude' => 44.2,
            'status' => 'published', 'review_status' => 'approved', 'published_at' => now()], $changes));
        if (DB::connection()->getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        return $property;
    }
}
