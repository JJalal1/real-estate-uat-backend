<?php

namespace Tests\Feature;

use App\Models\Governorate;
use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class Wave3MarketplacePurposeTest extends TestCase
{
    use RefreshDatabase;

    public function test_every_home_section_applies_the_requested_purpose_before_limiting_rows(): void
    {
        Governorate::create(['code' => 'W3-SYN', 'name_ar' => 'صنعاء', 'is_active' => true]);
        $owner = User::create(['name' => 'Synthetic Wave3 owner', 'email' => 'wave3@example.test',
            'password' => 'fixture-only', 'account_status' => 'active', 'phone_verified_at' => now()]);
        foreach (['rent', 'sale'] as $purpose) {
            for ($i = 0; $i < 9; $i++) $this->listing($owner, $purpose);
            $this->listing($owner, $purpose, ['status' => 'draft']);
            $this->listing($owner, $purpose, ['availability_status' => 'confirmation_paused']);
        }
        foreach (['rent', 'sale'] as $purpose) {
            $response = $this->getJson('/api/marketplace?'.http_build_query([
                'purpose' => $purpose, 'latitude' => 15.36, 'longitude' => 44.19,
            ]))->assertOk()->assertJsonPath('data.context.purpose', $purpose);
            $sections = $response->json('data.sections');
            $this->assertNotEmpty($sections['latest']);
            $this->assertNotEmpty($sections['nearby']);
            $this->assertNotEmpty($sections['spotlight']);
            $this->assertEmpty($sections[$purpose === 'rent' ? 'sale' : 'rent']);
            foreach ($sections as $rows) {
                $this->assertLessThanOrEqual(6, count($rows));
                foreach ($rows as $row) {
                    $this->assertSame($purpose, $row['purpose']);
                    $this->assertSame('published', Property::findOrFail($row['id'])->status);
                    foreach (['contact_phone', 'contact_whatsapp', 'proof_documents', 'user_email'] as $private) {
                        $this->assertArrayNotHasKey($private, $row);
                    }
                }
            }
        }
    }

    public function test_missing_purpose_keeps_the_existing_public_feed_and_invalid_purpose_is_rejected(): void
    {
        $this->getJson('/api/marketplace')->assertOk()->assertJsonPath('data.context.purpose', null);
        $this->getJson('/api/marketplace?purpose=invalid')->assertUnprocessable()->assertJsonValidationErrors('purpose');
    }

    private function listing(User $owner, string $purpose, array $overrides = []): Property
    {
        return Property::forceCreate(array_merge(['user_id' => $owner->id, 'title' => 'عقار '.$purpose,
            'description' => 'بيانات اصطناعية للاختبار فقط', 'purpose' => $purpose, 'type' => 'apartment',
            'price' => 500000, 'monthly_rent' => $purpose === 'rent' ? 100000 : null, 'currency' => 'YER',
            'address' => 'صنعاء', 'latitude' => 15.36, 'longitude' => 44.19,
            'status' => 'published', 'review_status' => 'approved', 'availability_status' => 'available',
            'published_at' => now(), 'spotlight_until' => now()->addDay()], $overrides));
    }
}
