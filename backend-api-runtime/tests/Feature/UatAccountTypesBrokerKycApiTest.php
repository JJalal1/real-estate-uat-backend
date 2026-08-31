<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use App\Services\AccessControlService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UatAccountTypesBrokerKycApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_unified_whatsapp_login_creates_base_account_then_requires_exact_four_part_name(): void
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'continue',
            'phone' => '+967711111101',
        ])->assertOk()
            ->assertJsonPath('data.is_new_account', true)
            ->assertJsonPath('data.account_type', 'regular');

        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'phone' => '+967711111101',
            'code' => (string) $start->json('data.debug_code'),
        ])->assertOk()
            ->assertJsonPath('data.user.name', 'مستخدم جديد')
            ->assertJsonPath('data.user.profile_completed_at', null)
            ->assertJsonPath('data.user.verification_profile.type', null)
            ->assertJsonPath('data.user.verification_profile.status', 'not_submitted');

        $headers = $this->bearer((string) $verify->json('data.token'));

        $this->withHeaders($headers)->patchJson('/api/auth/profile', [
            'name' => 'أحمد محمد علي',
        ])->assertStatus(422)->assertJsonValidationErrors('name');

        $this->withHeaders($headers)->patchJson('/api/auth/profile', [
            'name' => 'أحمد محمد علي صالح',
        ])->assertOk()
            ->assertJsonPath('data.user.name', 'أحمد محمد علي صالح');

        $this->assertDatabaseHas('users', [
            'phone' => '+967711111101',
            'account_type' => 'regular',
            'identity_policy_version' => 2,
        ]);
        $this->assertNotNull(User::query()->where('phone', '+967711111101')->value('profile_completed_at'));
    }

    public function test_base_account_cannot_create_listing_until_public_account_type_is_verified(): void
    {
        [, $headers] = $this->unifiedUser('+967711111102', 'أمين أحمد محمد علي');

        $this->withHeaders($headers)->post('/api/properties', $this->listingPayload('Blocked base account'))
            ->assertStatus(409);
    }

    public function test_owner_identity_is_verified_once_and_property_relationship_is_verified_per_listing(): void
    {
        [$owner, $ownerHeaders] = $this->unifiedUser('+967711111103', 'أحمد محمد علي صالح');

        $this->withHeaders($ownerHeaders)->post('/api/account-verification', [
            'type' => 'owner',
            'governorate' => 'صنعاء',
            'district' => 'السبعين',
            'identity_document' => UploadedFile::fake()->image('identity.jpg'),
            'selfie' => UploadedFile::fake()->image('selfie.jpg'),
        ])->assertOk()
            ->assertJsonPath('data.type', 'owner')
            ->assertJsonPath('data.status', 'pending');

        $this->withHeaders($ownerHeaders)->post('/api/properties', $this->listingPayload('Owner before approval'))
            ->assertStatus(409);

        [, $supportHeaders] = $this->supportUser();
        $this->withHeaders($supportHeaders)->getJson('/api/admin/account-verifications?status=pending&type=owner')
            ->assertOk()->assertJsonPath('data.0.user_id', $owner->id);
        foreach (['identity_document', 'selfie'] as $kind) {
            $this->withHeaders($supportHeaders)
                ->get("/api/account-verification/users/{$owner->id}/documents/$kind")
                ->assertOk();
        }
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/account-verifications/{$owner->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'approved')
            ->assertJsonPath('data.verification_flags.identity_reviewed', true);

        $this->withHeaders($ownerHeaders)->patchJson('/api/auth/profile', [
            'name' => 'اسم مختلف بعد التوثيق',
        ])->assertStatus(422)->assertJsonValidationErrors('name');

        $listingId = (int) $this->withHeaders($ownerHeaders)
            ->post('/api/properties', $this->listingPayload('Owner property relation'))
            ->assertCreated()->json('data.id');

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertStatus(422)->assertJsonValidationErrors('ownership_proof');

        $this->withHeaders($ownerHeaders)->post("/api/properties/$listingId", [
            'ownership_document_type' => 'purchase_deed',
            'document_owner_name' => 'شخص مختلف تماماً',
            'owner_relationship_type' => 'owner',
            'ownership_proof' => UploadedFile::fake()->image('purchase-deed.jpg'),
        ])->assertOk();

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertStatus(422)->assertJsonValidationErrors('owner_relationship_type');

        $this->withHeaders($ownerHeaders)->post("/api/properties/$listingId", [
            'ownership_document_type' => 'purchase_deed',
            'document_owner_name' => 'شخص مختلف تماماً',
            'owner_relationship_type' => 'agent',
        ])->assertOk();

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $this->assertDatabaseHas('account_verification_profiles', [
            'user_id' => $owner->id,
            'type' => 'owner',
            'status' => 'approved',
        ]);
        $this->assertDatabaseHas('listing_documents', [
            'property_id' => $listingId,
            'kind' => 'ownership_proof',
        ]);
    }

    public function test_verified_broker_can_publish_without_property_title_document_and_optional_professional_license_is_flagged(): void
    {
        [$broker, $headers] = $this->unifiedUser('+967711111104', 'محمد أحمد علي صالح');

        $this->withHeaders($headers)->post('/api/account-verification', [
            'type' => 'broker',
            'governorate' => 'صنعاء',
            'district' => 'الوحدة',
            'work_areas_json' => json_encode(['صنعاء', 'حدة', 'شملان'], JSON_UNESCAPED_UNICODE),
            'specialties_json' => json_encode(['أراضٍ', 'منازل'], JSON_UNESCAPED_UNICODE),
            'identity_document' => UploadedFile::fake()->image('broker-id.jpg'),
            'selfie' => UploadedFile::fake()->image('broker-selfie.jpg'),
            'professional_license' => UploadedFile::fake()->image('broker-license.jpg'),
        ])->assertOk()->assertJsonPath('data.status', 'pending');

        [, $supportHeaders] = $this->supportUser('broker-support@example.test', '+967711119998');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/account-verifications/{$broker->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.verification_flags.identity_reviewed', true)
            ->assertJsonPath('data.verification_flags.professional_document_reviewed', true);

        $listingResponse = $this->withHeaders($headers)
            ->post('/api/properties', array_merge(
                $this->listingPayload('Professional broker listing'),
                ['submit_for_review' => 1],
            ))
            ->assertCreated()
            ->assertJsonPath('data.review_status', 'submitted')
            ->assertJsonPath('data.status', 'pending');
        $listingId = (int) $listingResponse->json('data.id');

        $this->assertDatabaseMissing('listing_documents', [
            'property_id' => $listingId,
            'kind' => 'ownership_proof',
        ]);
    }

    public function test_real_estate_office_requires_office_identity_registration_license_frontage_and_map_location(): void
    {
        [$office, $headers] = $this->unifiedUser('+967711111105', 'خالد محمد علي حسن');

        $this->withHeaders($headers)->post('/api/account-verification', [
            'type' => 'office',
            'governorate' => 'صنعاء',
            'district' => 'معين',
            'office_name' => 'مكتب الثقة للعقارات',
            'commercial_register_number' => 'UAT-CR-1001',
            'neighborhood' => 'حدة',
            'street' => 'شارع حدة',
            'landmark' => 'جوار المعلم التجريبي',
            'latitude' => 15.3355,
            'longitude' => 44.1762,
            'office_phone' => '+967711223344',
            'responsible_identity' => UploadedFile::fake()->image('responsible-id.jpg'),
            'selfie' => UploadedFile::fake()->image('responsible-selfie.jpg'),
            'commercial_register' => UploadedFile::fake()->image('commercial-register.jpg'),
            'office_license' => UploadedFile::fake()->image('office-license.jpg'),
            'office_frontage' => UploadedFile::fake()->image('frontage.jpg'),
            'office_logo' => UploadedFile::fake()->image('logo.jpg'),
        ])->assertOk()->assertJsonPath('data.status', 'pending');

        [, $supportHeaders] = $this->supportUser('office-support@example.test', '+967711119997');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/account-verifications/{$office->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.verification_flags.commercial_register_reviewed', true)
            ->assertJsonPath('data.verification_flags.office_documents_reviewed', true)
            ->assertJsonPath('data.verification_flags.office_location_registered', true);

        $this->withHeaders($headers)
            ->post('/api/properties', array_merge(
                $this->listingPayload('Office listing'),
                ['submit_for_review' => 1],
            ))
            ->assertCreated()
            ->assertJsonPath('data.review_status', 'submitted')
            ->assertJsonPath('data.status', 'pending');
    }

    private function unifiedUser(string $phone, string $name): array
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'continue',
            'phone' => $phone,
        ])->assertOk();
        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'phone' => $phone,
            'code' => (string) $start->json('data.debug_code'),
        ])->assertOk();
        $headers = $this->bearer((string) $verify->json('data.token'));
        $this->withHeaders($headers)->patchJson('/api/auth/profile', ['name' => $name])->assertOk();
        return [User::query()->where('phone', $phone)->firstOrFail(), $headers];
    }

    private function listingPayload(string $title): array
    {
        return [
            'listing_input_version' => 2,
            'title' => $title,
            'description' => 'Unified account verification workflow test.',
            'purpose' => 'sale',
            'type' => 'house',
            'tenure_type' => 'freehold',
            'price' => 45000000,
            'currency' => 'YER',
            'area_value' => 220,
            'area_unit' => 'sqm',
            'bedrooms' => 4,
            'bathrooms' => 3,
            'has_parking' => true,
            'building_facade' => 'east',
            'address' => 'Sanaa, UAT Property',
            'latitude' => 15.401234 + (random_int(1, 900) / 1000000),
            'longitude' => 44.401234 + (random_int(1, 900) / 1000000),
            'images' => [UploadedFile::fake()->image('home.jpg')],
        ];
    }

    private function supportUser(string $email = 'verification-support@example.test', string $phone = '+967711119999'): array
    {
        return $this->legacyUser($email, $phone, ['support_agent']);
    }

    private function legacyUser(string $email, string $phone, array $roles): array
    {
        $user = User::query()->create([
            'name' => 'مستخدم دعم اختبار',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);
        foreach ($roles as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $user->roles()->syncWithoutDetaching([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
        }
        $plain = 're_verify_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'account-verification-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }

    private function bearer(string $token): array
    {
        return ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json'];
    }
}
