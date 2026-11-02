<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\AccessControlService;
use App\Services\PropertyIdentityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\ConfirmsListingImages;
use Tests\TestCase;

/** A full HTTP-kernel journey with synthetic users, media and database only. */
class BrokerSupportHttpJourneyTest extends TestCase
{
    use RefreshDatabase;
    use ConfirmsListingImages;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_authenticated_broker_submission_survives_screening_failure_and_support_correction(): void
    {
        [$broker, $brokerHeaders] = $this->login('+967733202001', 'Broker Journey User One');
        [, $otherHeaders] = $this->login('+967733202002', 'Other Journey User Two');
        $support = User::query()->create([
            'name' => 'Support Journey Agent One',
            'email' => 'journey-support@example.test',
            'phone' => '+967733202003',
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('synthetic-test-only-password'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($support);
        $role = Role::query()->where('key', 'support_agent')->firstOrFail();
        $support->roles()->syncWithoutDetaching([
            $role->id => ['assigned_by_user_id' => null, 'created_at' => now()],
        ]);
        [, $supportHeaders] = $this->login($support->phone);

        $this->withHeaders($brokerHeaders)->post('/api/account-verification', [
            'type' => 'broker',
            'governorate' => 'Sanaa',
            'district' => 'Sanaa District',
            'work_areas_json' => json_encode(['Sanaa']),
            'specialties_json' => json_encode(['houses']),
            'identity_document' => UploadedFile::fake()->image('broker-id.jpg'),
            'selfie' => UploadedFile::fake()->image('broker-selfie.jpg'),
        ])->assertOk()->assertJsonPath('data.status', 'pending');

        $queue = $this->withHeaders($supportHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=account_verification')->assertOk();
        $task = collect($queue->json('data'))->first(
            fn (array $item): bool => (int) $item['source_id'] === $broker->id,
        );
        $this->assertNotNull($task);
        $this->withHeaders($supportHeaders)
            ->postJson('/api/admin/workspace/tasks/'.(int) $task['id'].'/claim')->assertOk();
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/account-verifications/{$broker->id}/approve")
            ->assertOk()->assertJsonPath('data.status', 'approved');

        $listingId = (int) $this->withHeaders($brokerHeaders)->post('/api/properties', [
            'listing_input_version' => 3,
            'title' => 'Synthetic broker journey home',
            'description' => 'A synthetic house submitted for isolated HTTP acceptance.',
            'purpose' => 'sale',
            'type' => 'house',
            'tenure_type' => 'freehold',
            'price' => 50000000,
            'currency' => 'YER',
            'area_m2' => 220,
            'area_value' => 220,
            'area_unit' => 'sqm',
            'bedrooms' => 4,
            'bathrooms' => 3,
            'address' => 'Synthetic Sanaa house 202001',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
            'images' => [UploadedFile::fake()->image('house.jpg')],
        ])->assertCreated()->json('data.id');

        $this->withHeaders($brokerHeaders)->putJson("/api/properties/$listingId/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 0,
        ])->assertOk()->assertJsonPath('data.sai_management.source_mode', 'platform_fallback');

        $identity = new class extends PropertyIdentityService {
            public bool $fail = true;

            public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
            {
                if ($this->fail) {
                    throw new \RuntimeException('Synthetic screening failure');
                }

                return parent::evaluate($listing, $actor, $persist);
            }
        };
        $this->app->instance(PropertyIdentityService::class, $identity);

        $this->withHeaders($brokerHeaders)->postJson("/api/properties/$listingId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted')
            ->assertJsonPath('data.duplicate_check_status', 'check_failed');
        $this->assertDatabaseHas('properties', [
            'id' => $listingId, 'status' => 'pending', 'review_status' => 'submitted',
        ]);
        $this->assertDatabaseHas('property_images', ['property_id' => $listingId]);
        $imagePath = (string) DB::table('property_images')->where('property_id', $listingId)->value('path');
        $this->assertNotSame('', $imagePath);
        Storage::disk('local')->assertExists($imagePath);
        $imageBytes = Storage::disk('local')->get($imagePath);
        $this->assertNotEmpty($imageBytes);
        $this->withHeaders($otherHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/approve")->assertForbidden();
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/approve")->assertStatus(409);
        $this->withHeaders($otherHeaders)
            ->postJson("/api/properties/$listingId/identity/check")->assertForbidden();
        $this->withHeaders($otherHeaders)
            ->postJson("/api/properties/$listingId", ['title' => 'Unauthorized edit'])->assertForbidden();

        $identity->fail = false;
        $this->withHeaders($brokerHeaders)
            ->postJson("/api/properties/$listingId/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'distinct');
        $this->withHeaders($brokerHeaders)
            ->postJson("/api/properties/$listingId/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'distinct');
        $this->assertSame(1, DB::table('property_identity_checks')->where('property_id', $listingId)->count());
        $this->assertSame(1, DB::table('support_tasks')->where('source_type', 'listing_review')
            ->where('source_id', $listingId)->count());

        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/start")->assertOk();
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/return", [
                'reason' => 'Please clarify the synthetic house address before approval.',
            ])->assertOk()->assertJsonPath('data.review_status', 'returned_for_correction');
        $this->assertDatabaseHas('property_images', ['property_id' => $listingId]);
        Storage::disk('local')->assertExists($imagePath);
        $this->assertSame($imageBytes, Storage::disk('local')->get($imagePath));
        $this->withHeaders($brokerHeaders)
            ->postJson("/api/properties/$listingId", ['address' => 'Corrected synthetic Sanaa house 202001'])
            ->assertOk();
        $this->withHeaders($brokerHeaders)
            ->postJson("/api/properties/$listingId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/start")->assertOk();
        $this->confirmListingImages($listingId, $supportHeaders);
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$listingId/approve", [
                'reason' => 'The corrected synthetic listing was reviewed.',
            ])->assertOk()->assertJsonPath('data.status', 'published');

        $this->assertDatabaseHas('property_representation_claims', [
            'property_id' => $listingId,
            'advertiser_user_id' => $broker->id,
            'status' => 'active',
        ]);
        $this->assertDatabaseHas('properties', [
            'id' => $listingId, 'status' => 'published', 'review_status' => 'approved',
        ]);
    }

    public function test_two_authenticated_brokers_can_submit_the_same_asset_but_only_one_can_publish(): void
    {
        $supportHeaders = $this->supportLogin();
        [, $firstHeaders] = $this->verifiedBroker('+967733202011', $supportHeaders);
        [, $secondHeaders] = $this->verifiedBroker('+967733202012', $supportHeaders);
        $firstId = $this->brokerListing($firstHeaders, 'First synthetic representation');

        $this->withHeaders($firstHeaders)->postJson("/api/properties/$firstId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$firstId/start")->assertOk();
        $this->confirmListingImages($firstId, $supportHeaders);
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$firstId/approve", [
                'reason' => 'The first synthetic representation was reviewed.',
            ])->assertOk()->assertJsonPath('data.status', 'published');

        $secondId = $this->brokerListing($secondHeaders, 'Second synthetic representation');
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$secondId/start")->assertOk();
        $this->confirmListingImages($secondId, $supportHeaders);
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$secondId/approve", [
                'duplicate_review_reason' => 'Same physical house and unit as the first published listing.',
            ])->assertStatus(409);

        $this->assertDatabaseHas('properties', [
            'id' => $secondId, 'status' => 'pending', 'review_status' => 'under_review',
        ]);
        $this->assertSame(1, DB::table('properties')->where('status', 'published')->count());
        $this->assertSame(1, DB::table('property_representation_claims')->where('status', 'active')->count());
    }

    private function supportLogin(): array
    {
        $support = User::query()->create([
            'name' => 'Support Journey Agent Two',
            'email' => 'journey-support-two@example.test',
            'phone' => '+967733202013',
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('synthetic-test-only-password'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($support);
        $role = Role::query()->where('key', 'support_agent')->firstOrFail();
        $support->roles()->syncWithoutDetaching([
            $role->id => ['assigned_by_user_id' => null, 'created_at' => now()],
        ]);

        return $this->login($support->phone)[1];
    }

    private function verifiedBroker(string $phone, array $supportHeaders): array
    {
        [$broker, $headers] = $this->login($phone, 'Verified Broker Journey User');
        $this->withHeaders($headers)->post('/api/account-verification', [
            'type' => 'broker',
            'governorate' => 'Sanaa',
            'district' => 'Sanaa District',
            'work_areas_json' => json_encode(['Sanaa']),
            'specialties_json' => json_encode(['houses']),
            'identity_document' => UploadedFile::fake()->image('broker-id.jpg'),
            'selfie' => UploadedFile::fake()->image('broker-selfie.jpg'),
        ])->assertOk();
        $queue = $this->withHeaders($supportHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=account_verification')->assertOk();
        $task = collect($queue->json('data'))->first(
            fn (array $item): bool => (int) $item['source_id'] === $broker->id,
        );
        $this->assertNotNull($task);
        $this->withHeaders($supportHeaders)
            ->postJson('/api/admin/workspace/tasks/'.(int) $task['id'].'/claim')->assertOk();
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/account-verifications/{$broker->id}/approve")->assertOk();

        return [$broker, $headers];
    }

    private function brokerListing(array $headers, string $title): int
    {
        $id = (int) $this->withHeaders($headers)->post('/api/properties', [
            'listing_input_version' => 3,
            'title' => $title,
            'description' => 'A synthetic house for the representation approval guard.',
            'purpose' => 'sale', 'type' => 'house', 'tenure_type' => 'freehold',
            'price' => 50000000, 'currency' => 'YER',
            'area_m2' => 220, 'area_value' => 220, 'area_unit' => 'sqm',
            'bedrooms' => 4, 'bathrooms' => 3,
            'address' => 'Synthetic Sanaa house 202011',
            'latitude' => 15.3694, 'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
            'images' => [UploadedFile::fake()->image('house.jpg')],
        ])->assertCreated()->json('data.id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", [
            'sai_payer' => 'buyer', 'broker_sai_rate_percent' => 0,
        ])->assertOk();

        return $id;
    }

    private function login(string $phone, ?string $name = null): array
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'continue', 'phone' => $phone,
        ]);
        $this->assertSame(200, $start->status(), "WhatsApp start failed for synthetic phone $phone");
        $code = (string) $start->json('data.debug_code');
        $this->assertMatchesRegularExpression('/^[0-9]{6}$/D', $code);
        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'phone' => $phone, 'code' => $code,
        ]);
        $this->assertSame(200, $verify->status(), "WhatsApp verify failed for synthetic phone $phone");
        $headers = [
            'Authorization' => 'Bearer '.(string) $verify->json('data.token'),
            'Accept' => 'application/json',
        ];
        if ($name !== null) {
            $profile = $this->withHeaders($headers)->patchJson('/api/auth/profile', ['name' => $name]);
            $this->assertSame(200, $profile->status(), "Profile completion failed for synthetic phone $phone");
        }

        return [User::query()->where('phone', $phone)->firstOrFail(), $headers];
    }
}
