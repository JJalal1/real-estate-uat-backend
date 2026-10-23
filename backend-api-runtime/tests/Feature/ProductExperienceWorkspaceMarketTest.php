<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ProductExperienceWorkspaceMarketTest extends TestCase
{
    use RefreshDatabase;

    public function test_verified_professional_workspace_uses_real_activity_and_listing_state(): void
    {
        [$broker, $headers] = $this->user('workspace-broker@example.test', '+967770002001');
        AccountVerificationProfile::query()->create([
            'user_id' => $broker->id,
            'type' => AccountVerificationProfile::TYPE_BROKER,
            'status' => AccountVerificationProfile::STATUS_APPROVED,
            'details' => ['governorate' => 'صنعاء'],
            'submitted_at' => now()->subDay(),
            'reviewed_at' => now(),
        ]);

        $published = $this->property($broker, 'إعلان منشور', 'sale', 'villa', 60000000, 200, 'published');
        $draft = $this->property($broker, 'مسودة', 'sale', 'villa', 55000000, 190, 'draft');
        $this->assertNotSame($published->id, $draft->id);

        $response = $this->withHeaders($headers)->getJson('/api/professional/workspace')
            ->assertOk()
            ->assertJsonPath('data.publisher_label', 'دلال موثق')
            ->assertJsonPath('data.listings.total', 2)
            ->assertJsonPath('data.listings.published', 1)
            ->assertJsonPath('data.listings.draft', 1)
            ->assertJsonPath('data.customer_activity.favorites', 0)
            ->assertJsonPath('data.customer_activity.conversations', 0);

        $this->assertSame([], $response->json('data.needs_attention.correction_listings'));
    }

    public function test_market_context_requires_enough_published_comparables_and_uses_median(): void
    {
        [$owner] = $this->user('market-owner@example.test', '+967770002002');
        $target = $this->property($owner, 'العقار الهدف', 'sale', 'apartment', 52000000, 100, 'published');

        $this->getJson('/api/properties/'.$target->id.'/market-context')
            ->assertOk()
            ->assertJsonPath('data.sufficient_data', false)
            ->assertJsonPath('data.minimum_sample_size', 5);

        foreach ([48000000, 50000000, 51000000, 53000000, 55000000] as $index => $price) {
            $this->property(
                $owner,
                'مقارنة '.($index + 1),
                'sale',
                'apartment',
                $price,
                100 + $index,
                'published',
                15.3694 + ($index * 0.001),
                44.1910 + ($index * 0.001),
            );
        }

        $this->getJson('/api/properties/'.$target->id.'/market-context')
            ->assertOk()
            ->assertJsonPath('data.sufficient_data', true)
            ->assertJsonPath('data.sample_count', 5)
            ->assertJsonPath('data.market.median_price', 51000000)
            ->assertJsonPath('data.basis.source', 'published_platform_listings');
    }

    public function test_market_context_never_uses_unpublished_comparables(): void
    {
        [$owner] = $this->user('market-private@example.test', '+967770002003');
        $target = $this->property($owner, 'هدف خاص', 'rent', 'house', 200000, 150, 'published');
        for ($i = 0; $i < 8; $i++) {
            $this->property($owner, 'مسودة '.$i, 'rent', 'house', 180000 + $i, 150, 'draft');
        }
        $this->getJson('/api/properties/'.$target->id.'/market-context')
            ->assertOk()
            ->assertJsonPath('data.sufficient_data', false)
            ->assertJsonPath('data.sample_count', 0);
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Experience User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $plain = 'experience_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'experience-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(
        User $owner,
        string $title,
        string $purpose,
        string $type,
        float $price,
        float $area,
        string $status,
        float $lat = 15.3694,
        float $lng = 44.1910,
    ): Property {
        return Property::query()->create([
            'user_id' => $owner->id,
            'title' => $title,
            'description' => 'Experience market fixture',
            'purpose' => $purpose,
            'type' => $type,
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => $area,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'صنعاء',
            'latitude' => $lat,
            'longitude' => $lng,
            'status' => $status,
            'review_status' => $status === 'published' ? 'approved' : 'draft',
            'published_at' => $status === 'published' ? now() : null,
        ]);
    }
}
