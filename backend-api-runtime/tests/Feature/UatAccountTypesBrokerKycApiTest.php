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


    public function test_kyc_migration_preserves_multiple_non_owner_users_on_sqlite(): void
    {
        User::query()->create([
            'name' => 'First Regular User',
            'email' => 'sqlite-regular-1@example.test',
            'phone' => '+967711111181',
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        User::query()->create([
            'name' => 'Second Regular User',
            'email' => 'sqlite-regular-2@example.test',
            'phone' => '+967711111182',
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);

        $this->assertDatabaseHas('users', ['email' => 'sqlite-regular-1@example.test']);
        $this->assertDatabaseHas('users', ['email' => 'sqlite-regular-2@example.test']);
    }

    public function test_whatsapp_registration_enforces_account_specific_full_name_length(): void
    {
        $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'register',
            'account_type' => 'regular',
            'name' => 'أحمد محمد',
            'phone' => '+967711111105',
        ])->assertStatus(422)->assertJsonValidationErrors('name');

        $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'register',
            'account_type' => 'broker',
            'name' => 'محمد أحمد',
            'phone' => '+967711111106',
        ])->assertStatus(422)->assertJsonValidationErrors('name');

        $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'register',
            'account_type' => 'broker',
            'name' => 'محمد أحمد علي صالح حسن',
            'phone' => '+967711111107',
        ])->assertStatus(422)->assertJsonValidationErrors('name');
    }

    public function test_regular_whatsapp_account_requires_four_owner_documents_before_submit(): void
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'register',
            'account_type' => 'regular',
            'name' => 'أحمد محمد علي',
            'phone' => '+967711111101',
        ])->assertOk()->assertJsonPath('data.account_type', 'regular');
        $code = (string) $start->json('data.debug_code');
        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'account_type' => 'regular',
            'phone' => '+967711111101',
            'code' => $code,
        ])->assertOk()->assertJsonPath('data.user.account_type', 'regular');
        $headers = $this->bearer((string) $verify->json('data.token'));

        $listingId = (int) $this->withHeaders($headers)->post('/api/properties', $this->listingPayload('Regular missing docs'))
            ->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/properties/$listingId/submit")
            ->assertStatus(422)->assertJsonValidationErrors('proof_documents');

        $strictPayload = $this->listingPayload('Regular verified ownership') + [
            'owner_id_front' => UploadedFile::fake()->image('id-front.jpg'),
            'owner_id_back' => UploadedFile::fake()->image('id-back.jpg'),
            'owner_selfie' => UploadedFile::fake()->image('selfie.jpg'),
            'ownership_proof' => UploadedFile::fake()->image('ownership.jpg'),
        ];
        $second = (int) $this->withHeaders($headers)->post('/api/properties', $strictPayload)
            ->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/properties/$second/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $this->assertDatabaseHas('users', [
            'phone' => '+967711111101',
            'account_type' => 'regular',
            'identity_policy_version' => 1,
        ]);
        foreach (['owner_id_front', 'owner_id_back', 'owner_selfie', 'ownership_proof'] as $kind) {
            $this->assertDatabaseHas('listing_documents', ['property_id' => $second, 'kind' => $kind]);
        }
    }

    public function test_broker_can_browse_but_cannot_create_until_support_approves_account_kyc(): void
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'register',
            'account_type' => 'broker',
            'name' => 'محمد أحمد علي صالح',
            'phone' => '+967711111102',
        ])->assertOk();
        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'account_type' => 'broker',
            'phone' => '+967711111102',
            'code' => (string) $start->json('data.debug_code'),
        ])->assertOk();
        $brokerId = (int) $verify->json('data.user.id');
        $brokerHeaders = $this->bearer((string) $verify->json('data.token'));

        $this->getJson('/api/properties')->assertOk();
        $this->withHeaders($brokerHeaders)->post('/api/properties', $this->listingPayload('Blocked broker'))
            ->assertStatus(409);

        $this->withHeaders($brokerHeaders)->post('/api/broker/account-verification', [
            'id_front' => UploadedFile::fake()->image('broker-front.jpg'),
            'id_back' => UploadedFile::fake()->image('broker-back.jpg'),
            'selfie' => UploadedFile::fake()->image('broker-selfie.jpg'),
        ])->assertOk()->assertJsonPath('data.status', 'pending');

        [, $supportHeaders] = $this->supportUser();
        $this->withHeaders($supportHeaders)->getJson('/api/admin/broker-account-verifications')
            ->assertOk()->assertJsonPath('data.0.user_id', $brokerId);
        foreach (['id_front', 'id_back', 'selfie'] as $kind) {
            $this->withHeaders($supportHeaders)
                ->get("/api/broker/account-verification/users/$brokerId/documents/$kind")
                ->assertOk();
        }
        $this->withHeaders($supportHeaders)->postJson("/api/admin/broker-account-verifications/$brokerId/approve")
            ->assertOk()->assertJsonPath('data.status', 'approved');

        $listingId = (int) $this->withHeaders($brokerHeaders)->post('/api/properties', $this->listingPayload('Verified broker listing'))
            ->assertCreated()->json('data.id');
        $this->withHeaders($brokerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('users', [
            'id' => $brokerId,
            'account_type' => 'broker',
            'broker_verification_status' => 'approved',
        ]);
    }

    public function test_duplicate_published_physical_property_is_rejected_for_another_listing(): void
    {
        [$broker, $brokerHeaders] = $this->verifiedBroker('duplicate-broker@example.test', '+967711111103');
        [, $supportHeaders] = $this->supportUser('duplicate-support@example.test', '+967711111104');

        $first = (int) $this->withHeaders($brokerHeaders)->post('/api/properties', $this->listingPayload('First publication'))
            ->assertCreated()->json('data.id');
        $this->withHeaders($brokerHeaders)->postJson("/api/properties/$first/submit")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$first/approve")
            ->assertOk()->assertJsonPath('data.status', 'published');

        $duplicatePayload = $this->listingPayload('Same physical property');
        $duplicatePayload['purpose'] = 'rent';
        $second = (int) $this->withHeaders($brokerHeaders)->post('/api/properties', $duplicatePayload)
            ->assertCreated()->json('data.id');
        $this->withHeaders($brokerHeaders)->postJson("/api/properties/$second/submit")
            ->assertStatus(409);

        $this->assertSame($broker->id, User::query()->findOrFail($broker->id)->id);
    }

    private function listingPayload(string $title): array
    {
        return [
            'listing_input_version' => 2,
            'title' => $title,
            'description' => 'Account type and KYC workflow test.',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 45000000,
            'currency' => 'YER',
            'area_value' => 220,
            'area_unit' => 'sqm',
            'bedrooms' => 4,
            'bathrooms' => 3,
            'has_parking' => true,
            'building_facade' => 'east',
            'address' => 'Sanaa, Test Property',
            'latitude' => 15.401234,
            'longitude' => 44.401234,
            'images' => [UploadedFile::fake()->image('home.jpg')],
        ];
    }

    private function supportUser(string $email = 'kyc-support@example.test', string $phone = '+967711119999'): array
    {
        return $this->legacyUser($email, $phone, ['support_agent']);
    }

    private function verifiedBroker(string $email, string $phone): array
    {
        [$user, $headers] = $this->legacyUser($email, $phone, ['broker']);
        $user->forceFill([
            'account_type' => User::ACCOUNT_TYPE_BROKER,
            'broker_verification_status' => User::BROKER_VERIFICATION_APPROVED,
            'broker_verified_at' => now(),
        ])->save();
        return [$user->fresh(), $headers];
    }

    private function legacyUser(string $email, string $phone, array $roles): array
    {
        $user = User::query()->create([
            'name' => 'Legacy Test User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);
        foreach ($roles as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $user->roles()->syncWithoutDetaching([
                $role->id => ['assigned_by_user_id' => null, 'created_at' => now()],
            ]);
        }
        $plain = 're6_'.substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'kyc-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), $this->bearer($plain)];
    }

    private function bearer(string $token): array
    {
        return ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json'];
    }
}
