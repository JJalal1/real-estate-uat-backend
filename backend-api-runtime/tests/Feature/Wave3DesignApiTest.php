<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\AccountVerificationProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Wave3DesignApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_home_sections_remain_public_local_and_published_with_editorial_badge(): void
    {
        $owner = User::factory()->create();
        $sale = $this->listing($owner, ['purpose' => 'sale']);
        $rent = $this->listing($owner, ['purpose' => 'rent', 'monthly_rent' => 90000]);
        $elsewhere = $this->listing($owner, ['address' => 'تعز، الحوبان']);
        $draft = $this->listing($owner, ['status' => 'draft', 'review_status' => 'draft']);
        DB::table('properties')->where('id', $sale->id)->update(['spotlight_until' => now()->addDays(5)]);
        DB::table('properties')->where('id', $draft->id)->update(['spotlight_until' => now()->addDays(5)]);
        PropertyImage::create(['property_id' => $sale->id, 'path' => 'public/fake-one.jpg', 'sort_order' => 0, 'is_primary' => true]);
        PropertyImage::create(['property_id' => $sale->id, 'path' => 'public/fake-two.jpg', 'sort_order' => 1, 'is_primary' => false]);
        $r = $this->getJson('/api/marketplace')->assertOk()->assertJsonPath('data.context.label', 'صنعاء')
            ->assertJsonPath('data.context.source', 'default')->assertJsonPath('data.sections.spotlight.0.id', $sale->id)
            ->assertJsonPath('data.sections.spotlight.0.is_spotlight', true)->assertJsonCount(2, 'data.sections.spotlight.0.image_urls');
        foreach ($r->json('data.sections') as $rows) {
            $ids = array_column($rows, 'id');
            $this->assertNotContains($elsewhere->id, $ids); $this->assertNotContains($draft->id, $ids);
        }
        $this->assertSame([$rent->id], array_column($r->json('data.sections.rent'), 'id'));
        $this->getJson('/api/marketplace?latitude=0&longitude=0')->assertOk()->assertJsonPath('data.context.source', 'default');
        $this->getJson('/api/marketplace?latitude=15.3')->assertUnprocessable();
    }

    public function test_search_budget_uses_monthly_rent_and_filters_optional_facts_without_guessing(): void
    {
        $owner = User::factory()->create();
        $matching = $this->listing($owner, ['purpose' => 'rent', 'monthly_rent' => 80000, 'price' => 800000, 'has_elevator' => false]);
        $this->listing($owner, ['purpose' => 'rent', 'monthly_rent' => 150000, 'price' => 150000, 'has_elevator' => false]);
        $this->listing($owner, ['purpose' => 'rent', 'monthly_rent' => 80000, 'has_elevator' => null]);
        $r = $this->getJson('/api/properties?purpose=rent&min_monthly_rent=50000&max_monthly_rent=100000&has_elevator=0')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $matching->id)->assertJsonPath('data.0.monthly_rent', 80000);
        $this->assertSame(1, $r->json('meta.total'));
    }

    public function test_expired_and_irrelevant_spotlights_never_appear_in_featured_results(): void
    {
        $owner = User::factory()->create();
        $valid = $this->listing($owner);
        $expired = $this->listing($owner);
        $elsewhere = $this->listing($owner, ['address' => 'عدن، المنصورة']);
        DB::table('properties')->whereIn('id', [$valid->id, $elsewhere->id])->update(['spotlight_until' => now()->addDay()]);
        DB::table('properties')->where('id', $expired->id)->update(['spotlight_until' => now()->subMinute()]);
        $this->getJson('/api/properties?spotlight=1&governorate=صنعاء')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $valid->id);
        $this->assertNotContains('spotlight_until', (new Property)->getFillable());
    }

    public function test_home_brokers_are_approved_local_professionals_without_changing_directory_ordering(): void
    {
        $professionals = [];
        foreach (['local' => ['أمانة العاصمة', 'approved'], 'foreign' => ['تعز', 'approved'],
            'serves_local' => ['عدن', 'approved'], 'pending' => ['صنعاء', 'pending']] as $name => [$governorate, $status]) {
            $user = User::factory()->create(['account_status' => 'active', 'phone_verified_at' => now()]);
            AccountVerificationProfile::create(['user_id' => $user->id, 'type' => 'broker', 'status' => $status,
                'reviewed_at' => $status === 'approved' ? now() : null, 'details' => ['governorate' => $governorate, 'work_areas' => []]]);
            $professionals[$name] = $user;
        }
        $this->listing($professionals['serves_local']);
        $this->listing($professionals['foreign'], ['status' => 'draft', 'review_status' => 'draft']);
        $r = $this->getJson('/api/marketplace')->assertOk();
        $ids = array_column($r->json('data.brokers'), 'id');
        $this->assertEqualsCanonicalizing([$professionals['local']->id, $professionals['serves_local']->id], $ids);
        $this->assertContains($professionals['foreign']->id, app(\App\Services\BrokerRankingService::class)->query()->pluck('users.id')->all());
    }

    private function listing(User $owner, array $changes = []): Property
    {
        return Property::create(array_merge(['user_id' => $owner->id, 'title' => 'عقار خيالي في صنعاء', 'purpose' => 'sale',
            'type' => 'apartment', 'price' => 50000000, 'currency' => 'YER', 'area_m2' => 140, 'bedrooms' => 3, 'bathrooms' => 2,
            'address' => 'صنعاء، حدة', 'latitude' => 15.3694, 'longitude' => 44.1910, 'status' => 'published', 'review_status' => 'approved'], $changes));
    }
}
