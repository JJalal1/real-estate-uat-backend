<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Phase2ListingJourneyApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_likely_duplicate_requires_explainable_human_clearance_before_approval(): void
    {
        [$firstOwner, $firstHeaders] = $this->user('p2-first@example.test', '+967711100001');
        [$secondOwner, $secondHeaders] = $this->user('p2-second@example.test', '+967711100002');
        [, $supportHeaders] = $this->user('p2-support@example.test', '+967711100003', ['support_agent']);

        $firstId = $this->createReady($firstHeaders, [
            'title' => 'المنزل الأول',
            'address' => 'صنعاء حدة شارع المدرسة',
            'latitude' => 15.369400,
            'longitude' => 44.191000,
            'area_m2' => 200,
            'bedrooms' => 4,
            'bathrooms' => 3,
        ]);
        $secondId = $this->createReady($secondHeaders, [
            'title' => 'المنزل الثاني',
            'address' => 'صنعاء - حدة - شارع المدرسة',
            'latitude' => 15.369520,
            'longitude' => 44.191080,
            'area_m2' => 202,
            'bedrooms' => 4,
            'bathrooms' => 3,
        ]);

        $this->withHeaders($firstHeaders)
            ->postJson("/api/properties/$firstId/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($secondHeaders)
            ->postJson("/api/properties/$secondId/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');

        $detail = $this->withHeaders($supportHeaders)
            ->getJson("/api/admin/listing-review/listings/$secondId")
            ->assertOk();

        $this->assertSame($firstId, (int) $detail->json('data.likely_duplicate_candidates.0.listing_id'));
        $this->assertGreaterThanOrEqual(5, (int) $detail->json('data.likely_duplicate_candidates.0.score'));

        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$secondId/start")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'under_review');

        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$secondId/approve")
            ->assertStatus(422)
            ->assertJsonValidationErrors('duplicate_review_reason');

        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$secondId/approve", [
                'reason' => 'تمت مراجعة المستندات والموقع.',
                'duplicate_review_reason' => 'العقاران متجاوران لكن مستند العلاقة ورقم الوحدة والوصف يثبتان أنهما عقاران مختلفان.',
            ])
            ->assertOk()
            ->assertJsonPath('data.review_status', 'approved')
            ->assertJsonPath('data.status', 'published');

        $this->assertDatabaseHas('listing_reviews', [
            'listing_id' => $secondId,
            'action' => 'duplicate_review_cleared',
        ]);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $secondOwner->id,
            'type' => 'listing_approved',
            'entity_type' => 'property',
            'entity_id' => $secondId,
        ]);
        $this->getJson('/api/properties')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $secondId);

        $this->assertDatabaseMissing('user_notifications', [
            'user_id' => $firstOwner->id,
            'type' => 'listing_approved',
        ]);
    }

    public function test_returned_listing_stays_private_preserves_reason_and_notifies_before_resubmit(): void
    {
        [$owner, $ownerHeaders] = $this->user('p2-correction@example.test', '+967711100004');
        [, $supportHeaders] = $this->user('p2-correction-support@example.test', '+967711100005', ['support_agent']);
        $id = $this->createReady($ownerHeaders, ['title' => 'إعلان يحتاج تصحيح']);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->withHeaders($supportHeaders)->postJson(
            "/api/admin/listing-review/listings/$id/return",
            ['reason' => 'حدد الشارع بدقة وأضف وصفاً أوضح لمدخل العقار.'],
        )->assertOk()->assertJsonPath('data.review_status', 'returned_for_correction');

        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $owner->id,
            'type' => 'listing_returned_for_correction',
            'entity_type' => 'property',
            'entity_id' => $id,
        ]);
        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 0);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id", [
            'address' => 'صنعاء حدة شارع 14 أكتوبر مدخل رقم 2',
            'description' => 'تم توضيح مدخل العقار والشارع بناءً على ملاحظة فريق الدعم.',
        ])->assertOk()
            ->assertJsonPath('data.review_status', 'returned_for_correction')
            ->assertJsonPath('data.last_review_reason', 'حدد الشارع بدقة وأضف وصفاً أوضح لمدخل العقار.');

        $this->withHeaders($ownerHeaders)
            ->postJson("/api/properties/$id/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted')
            ->assertJsonPath('data.last_review_reason', null);

        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 0);
    }

    public function test_exact_physical_property_cannot_be_published_twice(): void
    {
        [, $firstHeaders] = $this->user('p2-exact-first@example.test', '+967711100006');
        [, $secondHeaders] = $this->user('p2-exact-second@example.test', '+967711100007');
        [, $supportHeaders] = $this->user('p2-exact-support@example.test', '+967711100008', ['support_agent']);

        $identity = [
            'address' => 'صنعاء شارع الزبيري عقار 22',
            'latitude' => 15.350111,
            'longitude' => 44.200222,
            'area_m2' => 180,
            'bedrooms' => 3,
            'bathrooms' => 2,
        ];
        $firstId = $this->createReady($firstHeaders, array_merge($identity, ['title' => 'الإعلان الأصلي']));

        $this->withHeaders($firstHeaders)->postJson("/api/properties/$firstId/submit")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$firstId/start")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$firstId/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'published');

        $secondId = $this->createReady($secondHeaders, array_merge($identity, ['title' => 'محاولة تكرار نفس العقار']));
        $this->withHeaders($secondHeaders)
            ->postJson("/api/properties/$secondId/submit")
            ->assertStatus(409);

        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 1);
    }

    public function test_final_rejection_notifies_owner_and_never_becomes_public(): void
    {
        [$owner, $ownerHeaders] = $this->user('p2-reject@example.test', '+967711100009');
        [, $supportHeaders] = $this->user('p2-reject-support@example.test', '+967711100010', ['support_agent']);
        $id = $this->createReady($ownerHeaders, ['title' => 'إعلان مرفوض نهائياً']);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->withHeaders($supportHeaders)->postJson(
            "/api/admin/listing-review/listings/$id/reject-final",
            ['reason' => 'مستند العلاقة بالعقار غير صالح وبعد التحقق يلزم منع نشر هذه الهوية لهذا الغرض.'],
        )->assertOk()->assertJsonPath('data.review_status', 'rejected_blocked');

        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $owner->id,
            'type' => 'listing_rejected',
            'entity_type' => 'property',
            'entity_id' => $id,
        ]);
        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 0);
    }

    private function createReady(array $headers, array $overrides = []): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', $this->payload(array_merge([
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ], $overrides)));
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Phase 2 User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make(hash('sha256', $email . '|phase2')),
        ]);

        $ids = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $ids[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($ids);

        $plain = 'p2_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'phase2-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, ['Authorization' => 'Bearer ' . $plain, 'Accept' => 'application/json']];
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title' => 'Phase 2 property',
            'description' => 'Phase 2 hardened listing journey property.',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 50000000,
            'currency' => 'YER',
            'area_m2' => 220,
            'bedrooms' => 4,
            'bathrooms' => 3,
            'address' => 'صنعاء حدة شارع رئيسي',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ], $overrides);
    }
}
