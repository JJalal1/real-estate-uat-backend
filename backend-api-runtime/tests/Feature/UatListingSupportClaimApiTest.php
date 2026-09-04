<?php
namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UatListingSupportClaimApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_listing_is_shared_until_one_support_agent_claims_it(): void
    {
        [, $ownerHeaders] = $this->user('claim-owner@example.test', '+967711100001');
        [$agentA, $agentAHeaders] = $this->user('claim-a@example.test', '+967711100002', ['support_agent']);
        [, $agentBHeaders] = $this->user('claim-b@example.test', '+967711100003', ['support_agent']);
        [, $managerHeaders] = $this->user('claim-manager@example.test', '+967711100004', ['support_manager']);

        $id = $this->createReady($ownerHeaders, 'Support claim property');
        $this->withHeaders($ownerHeaders)
            ->postJson("/api/properties/$id/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');

        $this->withHeaders($agentAHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $id);

        $this->withHeaders($agentBHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $id);

        $this->withHeaders($agentAHeaders)
            ->postJson("/api/admin/listing-review/listings/$id/start")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'under_review');

        $this->assertDatabaseHas('properties', [
            'id' => $id,
            'review_assigned_to_user_id' => $agentA->id,
        ]);

        $this->withHeaders($agentBHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 0);

        $this->withHeaders($agentAHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.review_status', 'under_review');

        $this->withHeaders($agentBHeaders)
            ->postJson("/api/admin/listing-review/listings/$id/start")
            ->assertStatus(409);

        $this->withHeaders($agentBHeaders)
            ->postJson("/api/admin/listing-review/listings/$id/approve")
            ->assertStatus(409);

        $this->withHeaders($managerHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 1);

        $this->withHeaders($agentAHeaders)
            ->postJson("/api/admin/listing-review/listings/$id/approve", [
                'reason' => 'Support agent completed the claimed investigation.',
            ])
            ->assertOk()
            ->assertJsonPath('data.review_status', 'approved');
    }

    public function test_return_for_correction_releases_claim_for_next_submission(): void
    {
        [, $ownerHeaders] = $this->user('claim-return-owner@example.test', '+967711100011');
        [, $agentAHeaders] = $this->user('claim-return-a@example.test', '+967711100012', ['support_agent']);
        [, $agentBHeaders] = $this->user('claim-return-b@example.test', '+967711100013', ['support_agent']);

        $id = $this->createReady($ownerHeaders, 'Claim return property');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($agentAHeaders)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->withHeaders($agentAHeaders)->postJson("/api/admin/listing-review/listings/$id/return", [
            'reason' => 'Please correct the listing details before another investigation.',
        ])->assertOk()->assertJsonPath('data.review_status', 'returned_for_correction');

        $this->assertDatabaseHas('properties', [
            'id' => $id,
            'review_assigned_to_user_id' => null,
        ]);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id", [
            'address' => 'Corrected claim test address',
        ])->assertOk();
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();

        $this->withHeaders($agentBHeaders)
            ->getJson('/api/admin/listing-review/queue')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $id);
    }

    private function createReady(array $headers, string $title): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', $this->payload([
            'title' => $title,
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ]));
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Support Claim Test User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $ids = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $ids[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($ids);
        $plain = 'claim_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'listing-claim-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, [
            'Authorization' => 'Bearer ' . $plain,
            'Accept' => 'application/json',
        ]];
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title' => 'Support claim property',
            'description' => 'Listing support claim workflow test',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 60000000,
            'currency' => 'YER',
            'area_m2' => 230,
            'bedrooms' => 4,
            'bathrooms' => 3,
            'address' => 'Support claim test address',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ], $overrides);
    }
}
