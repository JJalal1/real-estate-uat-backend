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

class UatChangePhase3BrokerVerificationApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_old_main_broker_confirmation_is_retired_and_support_can_review_directly(): void
    {
        [, $ownerHeaders] = $this->user('retired-owner@example.test', '+967700003001');
        [, $supportHeaders] = $this->user('retired-support@example.test', '+967700003002', ['support_agent']);

        $listingId = $this->readyListing($ownerHeaders, 'Retired broker verification listing');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $detail = $this->withHeaders($supportHeaders)
            ->getJson("/api/admin/listing-review/listings/$listingId")
            ->assertOk();
        $detail->assertJsonPath('data.broker_verification.required', false)
            ->assertJsonPath('data.broker_verification.approval_allowed', true)
            ->assertJsonPath('data.broker_verification.reason', 'broker_region_verification_retired');

        $this->withHeaders($supportHeaders)->postJson(
            "/api/admin/listing-review/listings/$listingId/broker-verification/request"
        )->assertNotFound();
        $this->withHeaders($supportHeaders)->getJson('/api/broker/listing-verifications')->assertNotFound();

        $queue = $this->withHeaders($supportHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=listing_review')
            ->assertOk();
        $task = collect($queue->json('data'))->first(
            fn (array $item): bool => (int) $item['source_id'] === $listingId,
        );
        $this->assertNotNull($task);
        $this->withHeaders($supportHeaders)
            ->postJson('/api/admin/workspace/tasks/'.(int) $task['id'].'/claim')
            ->assertOk();

        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'published')
            ->assertJsonPath('data.review_status', 'approved');
    }

    public function test_broker_role_has_no_local_verification_permission_after_new_policy(): void
    {
        [$broker] = $this->user('retired-broker@example.test', '+967700003003', ['broker']);
        $this->assertFalse($broker->fresh()->hasPermission('listings.verify_local'));
    }

    private function readyListing(array $headers, string $title): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', [
            'listing_input_version' => 2,
            'title' => $title,
            'description' => 'Broker-region verification is retired.',
            'purpose' => 'sale',
            'type' => 'house',
            'tenure_type' => 'freehold',
            'price' => 50000000,
            'currency' => 'YER',
            'area_value' => 220,
            'area_unit' => 'sqm',
            'bedrooms' => 4,
            'bathrooms' => 3,
            'has_parking' => true,
            'building_facade' => 'east',
            'address' => 'Sanaa',
            'latitude' => 15.4050,
            'longitude' => 44.4050,
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ]);
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Policy Test User',
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
            'name' => 'policy-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }
}
