<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\AccessControlService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\ConfirmsListingImages;
use Tests\TestCase;

/**
 * CI-only HTTP-kernel acceptance using the existing BrokerSupportHttpJourneyTest
 * fixtures. Copied into tests/Feature only in the disposable PostgreSQL job.
 * No live API, production data, forced asset identity or mocked approval guard.
 */
class Phase23CrossPurposeDuplicateTest extends TestCase
{
    use RefreshDatabase;
    use ConfirmsListingImages;

    protected function setUp(): void
    {
        // Refuse other databases before RefreshDatabase can run migrations.
        foreach ([
            'PHASE23_ISOLATED_PURPOSE_TEST' => 'true',
            'APP_ENV' => 'testing',
            'DB_CONNECTION' => 'pgsql',
            'DB_HOST' => '127.0.0.1',
            'DB_PORT' => '5432',
            'DB_DATABASE' => 'phase23_purpose_ci',
            'DB_URL' => '',
        ] as $name => $expected) {
            if (getenv($name) !== $expected) {
                throw new \RuntimeException('Isolated purpose acceptance environment required: '.$name);
            }
        }

        parent::setUp();
        Http::preventStrayRequests();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_another_broker_cannot_publish_a_rental_for_the_same_asset_as_a_published_sale(): void
    {
        $supportHeaders = $this->supportLogin();
        [$saleBroker, $saleHeaders] = $this->verifiedBroker('+967733202011', $supportHeaders);
        [$rentBroker, $rentHeaders] = $this->verifiedBroker('+967733202012', $supportHeaders);
        $this->assertNotSame($saleBroker->id, $rentBroker->id);

        $saleId = $this->brokerListing($saleHeaders, 'sale');
        $this->withHeaders($saleHeaders)->postJson("/api/properties/$saleId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$saleId/start")->assertOk();
        $this->confirmListingImages($saleId, $supportHeaders);
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$saleId/approve", [
                'reason' => 'The synthetic sale listing has been reviewed.',
            ])->assertOk()->assertJsonPath('data.status', 'published');

        // Only the account, purpose and applicable financial fields differ.
        // The real identity resolver must recognize the same physical house.
        $rentId = $this->brokerListing($rentHeaders, 'rent');
        $sale = Property::query()->findOrFail($saleId);
        $rent = Property::query()->findOrFail($rentId);
        $this->assertSame('sale', $sale->purpose);
        $this->assertSame('rent', $rent->purpose);
        $this->assertSame($saleBroker->id, $sale->user_id);
        $this->assertSame($rentBroker->id, $rent->user_id);
        $this->assertNotNull($sale->property_asset_id);
        $this->assertSame($sale->property_asset_id, $rent->property_asset_id);
        $assetId = $sale->property_asset_id;

        // Current policy admits the second listing to review. It must refuse
        // publication for duplicate identity, not for incomplete rent/media.
        $this->withHeaders($rentHeaders)->postJson("/api/properties/$rentId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$rentId/start")->assertOk();
        $this->confirmListingImages($rentId, $supportHeaders);
        $this->withHeaders($supportHeaders)
            ->postJson("/api/admin/listing-review/listings/$rentId/approve", [
                'duplicate_review_reason' => 'Same synthetic house and unit; another advertiser now requests rent instead of sale.',
            ])->assertStatus(409)->assertJsonPath(
                'message',
                'This physical property is already published. Duplicate publication is not allowed.',
            );

        $this->assertDatabaseHas('properties', [
            'id' => $saleId, 'user_id' => $saleBroker->id,
            'purpose' => 'sale', 'status' => 'published', 'review_status' => 'approved',
        ]);
        $this->assertDatabaseHas('properties', [
            'id' => $rentId, 'user_id' => $rentBroker->id,
            'purpose' => 'rent', 'status' => 'pending', 'review_status' => 'under_review',
        ]);
        $this->assertSame(1, DB::table('properties')->where('property_asset_id', $assetId)
            ->where('status', 'published')->count());
        $this->assertSame(1, DB::table('property_representation_claims')->where('property_asset_id', $assetId)
            ->where('status', 'active')->count());
        $this->assertDatabaseHas('property_representation_claims', [
            'property_asset_id' => $assetId, 'property_id' => $saleId,
            'advertiser_user_id' => $saleBroker->id, 'status' => 'active',
        ]);
        $this->assertDatabaseMissing('property_representation_claims', [
            'property_id' => $rentId, 'status' => 'active',
        ]);
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

    private function brokerListing(array $headers, string $purpose): int
    {
        $payload = [
            'listing_input_version' => 3,
            'title' => 'Synthetic cross-purpose representation',
            'description' => 'A synthetic house for isolated cross-purpose publication acceptance.',
            'purpose' => $purpose, 'type' => 'house', 'tenure_type' => 'freehold',
            'price' => 50000000, 'currency' => 'YER',
            'area_m2' => 220, 'area_value' => 220, 'area_unit' => 'sqm',
            'bedrooms' => 4, 'bathrooms' => 3,
            'address' => 'Synthetic Sanaa house 202011',
            'latitude' => 15.3694, 'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
            'images' => [UploadedFile::fake()->image('house.jpg')],
        ];
        if ($purpose === 'rent') {
            $payload += ['monthly_rent' => 200000, 'rental_term_months' => 12, 'advance_months' => 1];
        }
        $id = (int) $this->withHeaders($headers)->post('/api/properties', $payload)
            ->assertCreated()->json('data.id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", [
            'sai_payer' => $purpose === 'rent' ? 'tenant' : 'buyer',
            'broker_sai_rate_percent' => 0,
        ])->assertOk();

        return $id;
    }

    private function login(string $phone, ?string $name = null): array
    {
        $start = $this->postJson('/api/auth/whatsapp/start', [
            'intent' => 'continue', 'phone' => $phone,
        ]);
        $this->assertSame(200, $start->status(), 'Synthetic WhatsApp start failed');
        $code = (string) $start->json('data.debug_code');
        $this->assertMatchesRegularExpression('/^[0-9]{6}$/D', $code);
        $verify = $this->postJson('/api/auth/whatsapp/verify', [
            'phone' => $phone, 'code' => $code,
        ]);
        $this->assertSame(200, $verify->status(), 'Synthetic WhatsApp verify failed');
        $headers = [
            'Authorization' => 'Bearer '.(string) $verify->json('data.token'),
            'Accept' => 'application/json',
        ];
        if ($name !== null) {
            $profile = $this->withHeaders($headers)->patchJson('/api/auth/profile', ['name' => $name]);
            $this->assertSame(200, $profile->status(), 'Synthetic profile completion failed');
        }

        return [User::query()->where('phone', $phone)->firstOrFail(), $headers];
    }
}
