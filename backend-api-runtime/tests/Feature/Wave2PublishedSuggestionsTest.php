<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The mobile suggestion client reuses this existing, public paginated API. */
class Wave2PublishedSuggestionsTest extends TestCase
{
    use RefreshDatabase;

    public function test_first_arabic_character_returns_real_public_listing_summaries_with_a_six_row_page(): void
    {
        $owner = $this->owner();
        for ($i = 0; $i < 9; $i++) $this->listing($owner, ['title' => 'شقة معلنة '.$i]);
        $this->listing($owner, ['title' => 'جامع قريب', 'address' => 'تعز', 'description' => 'عقار آخر']);
        $response = $this->getJson('/api/properties?'.http_build_query(['search' => 'ش', 'per_page' => 6, 'page' => 1, 'sort' => 'latest']))
            ->assertOk()->assertJsonCount(6, 'data')->assertJsonPath('meta.total', 9)->assertJsonPath('meta.per_page', 6);
        foreach ($response->json('data') as $row) {
            $this->assertGreaterThan(0, $row['id']);
            $this->assertStringContainsString('شقة معلنة', $row['title']);
            foreach (['title', 'purpose', 'price', 'currency', 'address', 'main_image'] as $key) $this->assertArrayHasKey($key, $row);
            foreach (['contact_phone', 'contact_whatsapp', 'documents', 'proof_documents', 'owner_key', 'user_email'] as $key) $this->assertArrayNotHasKey($key, $row);
        }
    }

    public function test_other_character_and_negative_query_never_invent_an_area_or_property(): void
    {
        $owner = $this->owner();
        $match = $this->listing($owner, ['title' => 'جوار الجامعة', 'description' => 'عقار عائلي']);
        $this->listing($owner, ['title' => 'شقة بعيدة', 'description' => 'حي هادئ']);
        $this->getJson('/api/properties?'.http_build_query(['search' => 'ج', 'per_page' => 6]))
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $match->id);
        $this->getJson('/api/properties?'.http_build_query(['search' => 'ظظغيرموجود', 'per_page' => 6]))
            ->assertOk()->assertJsonCount(0, 'data')->assertJsonPath('meta.total', 0);
    }

    public function test_drafts_rejected_and_unavailable_listings_are_excluded_before_suggestion_pagination(): void
    {
        $owner = $this->owner();
        $public = $this->listing($owner, ['title' => 'شقة متاحة']);
        foreach (['draft', 'rejected', 'pending', 'archived'] as $status) {
            $this->listing($owner, ['title' => 'شقة خاصة', 'status' => $status, 'review_status' => $status === 'rejected' ? 'rejected' : 'draft']);
        }
        $this->listing($owner, ['title' => 'شقة انتهى توفرها', 'availability_status' => 'confirmation_paused']);
        $this->listing($owner, ['title' => 'شقة تجاوزت المهلة', 'availability_notified_at' => now()->subDays(3)]);
        $this->getJson('/api/properties?'.http_build_query(['search' => 'ش', 'per_page' => 6]))
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $public->id);
    }

    public function test_purpose_type_governorate_and_visible_bounds_use_one_public_filter_contract(): void
    {
        $owner = $this->owner();
        $target = $this->listing($owner, ['title' => 'شقة في النطاق', 'purpose' => 'rent', 'monthly_rent' => 180000]);
        $this->listing($owner, ['title' => 'شقة للبيع']);
        $this->listing($owner, ['title' => 'شقة خارج النطاق', 'purpose' => 'rent', 'monthly_rent' => 180000, 'latitude' => 16.5]);
        $this->listing($owner, ['title' => 'شقة محافظة أخرى', 'purpose' => 'rent', 'monthly_rent' => 180000, 'address' => 'تعز']);
        $this->listing($owner, ['title' => 'شقة في وصف أرض', 'type' => 'land', 'purpose' => 'rent', 'monthly_rent' => 180000]);
        $params = ['search' => 'ش', 'purpose' => 'rent', 'type' => 'apartment', 'governorate' => 'صنعاء',
            'south' => 15.3, 'west' => 44.1, 'north' => 15.5, 'east' => 44.3, 'per_page' => 6];
        $this->getJson('/api/properties?'.http_build_query($params))->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $target->id);
        $this->assertSame('شقة في النطاق', $target->fresh()->title);
    }

    private function owner(): User
    {
        return User::create(['name' => 'Synthetic Wave2 owner', 'email' => 'wave2-search@example.test',
            'password' => 'fixture-only', 'account_status' => 'active', 'phone_verified_at' => now()]);
    }
    private function listing(User $owner, array $values): Property
    {
        return Property::forceCreate(array_merge(['user_id' => $owner->id, 'title' => 'شقة', 'description' => 'وصف الإعلان',
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 45000000, 'currency' => 'YER',
            'address' => 'صنعاء', 'latitude' => 15.36, 'longitude' => 44.19,
            'status' => 'published', 'review_status' => 'approved', 'availability_status' => 'available', 'published_at' => now()], $values));
    }
}
