<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class DiscoverySearchQualityTest extends TestCase
{
    use RefreshDatabase;

    public function test_arabic_search_normalizes_alef_diacritics_and_matches_tokens_across_fields(): void
    {
        $owner = $this->owner();

        $match = $this->listing($owner, [
            'title' => 'شَقَّة عائلية',
            'description' => 'سكن هادئ',
            'address' => 'صنعاء، حَدَّة',
        ]);
        $this->listing($owner, [
            'title' => 'فيلا مستقلة',
            'description' => 'في منطقة أخرى',
            'address' => 'تعز',
        ]);

        $this->getJson('/api/properties?search=شقه%20حده')
            ->assertOk()
            ->assertJsonPath('meta.total', 0);

        $this->getJson('/api/properties?search=شقة%20حدة')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $match->id);

        $ibb = $this->listing($owner, [
            'title' => 'أرض في إب',
            'description' => 'فرصة استثمارية',
            'address' => 'إب',
        ]);

        $this->getJson('/api/properties?search=ارض%20اب')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $ibb->id);
    }

    public function test_exact_normalized_title_ranks_before_newer_description_match(): void
    {
        $owner = $this->owner();

        $exact = $this->listing($owner, [
            'title' => 'إب',
            'description' => 'عقار في وسط المدينة',
            'address' => 'اليمن',
        ]);
        $this->listing($owner, [
            'title' => 'عرض أحدث',
            'description' => 'عقار مميز في إب',
            'address' => 'اليمن',
        ]);

        $this->getJson('/api/properties?search=اب&sort=latest')
            ->assertOk()
            ->assertJsonPath('meta.total', 2)
            ->assertJsonPath('data.0.id', $exact->id);
    }

    private function owner(): User
    {
        return User::query()->create([
            'name' => 'Discovery Search Owner',
            'email' => 'discovery-search@example.test',
            'phone' => '+967711111111',
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
    }

    private function listing(User $owner, array $overrides): Property
    {
        return Property::query()->create(array_merge([
            'user_id' => $owner->id,
            'title' => 'عقار تجريبي',
            'description' => 'وصف الإعلان',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 50000000,
            'currency' => 'YER',
            'area_m2' => 200,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'صنعاء',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'availability_status' => 'available',
            'published_at' => now(),
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ], $overrides));
    }
}
