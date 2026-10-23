<?php

namespace Tests\Feature;

use App\Models\BrokerCellAssignment;
use App\Models\GeoCell;
use App\Models\Role;
use App\Models\User;
use App\Services\AccessControlService;
use App\Services\RegionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class Stage8RegionsBrokerApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_broker_assignment_admin_routes_are_retired_but_region_management_remains_available(): void
    {
        [$owner, $headers] = $this->verifiedUser('stage8-owner@example.test', '+967700000301');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        [$broker] = $this->verifiedBroker('stage8-broker@example.test', '+967700000302');

        $gov = $this->withHeaders($headers)->postJson('/api/admin/regions/governorates', [
            'code' => 'S8_SANAA', 'name_ar' => 'اختبار صنعاء', 'name_en' => 'Stage 8 Sanaa',
        ])->assertCreated()->json('data');

        $cell = $this->withHeaders($headers)->postJson('/api/admin/regions/cells', [
            'governorate_id' => $gov['id'], 'code' => 'S8_CELL_A', 'name_ar' => 'خلية أ',
            'points' => $this->square(15.3600, 44.1800, 0.0100),
        ])->assertCreated()->json('data');

        $this->withHeaders($headers)->getJson('/api/admin/regions/brokers')->assertNotFound();
        $this->withHeaders($headers)->putJson('/api/admin/regions/cells/'.$cell['id'].'/broker', [
            'broker_user_id' => $broker->id, 'reason' => 'retired policy check',
        ])->assertNotFound();
        $this->withHeaders($headers)->deleteJson('/api/admin/regions/cells/'.$cell['id'].'/broker')->assertNotFound();

        $this->assertDatabaseMissing('broker_cell_assignments', [
            'geo_cell_id' => $cell['id'], 'broker_user_id' => $broker->id, 'ends_at' => null,
        ]);
    }

    public function test_historical_broker_territory_assignments_no_longer_restrict_listing_locations(): void
    {
        [$owner, $ownerHeaders] = $this->verifiedUser('stage8-owner2@example.test', '+967700000303');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        [$brokerA, $headersA] = $this->verifiedBroker('stage8-broker-a@example.test', '+967700000304');
        [$brokerB] = $this->verifiedBroker('stage8-broker-b@example.test', '+967700000305');
        [, $plainHeaders] = $this->verifiedUser('stage8-user@example.test', '+967700000306');

        $govId = (int) $this->withHeaders($ownerHeaders)->postJson('/api/admin/regions/governorates', [
            'code' => 'S8_GOV2', 'name_ar' => 'محافظة الاختبار الثانية',
        ])->assertCreated()->json('data.id');

        $a = $this->createCell($ownerHeaders, $govId, 'S8_A', 'خلية أ', 15.3600, 44.1800);
        $b = $this->createCell($ownerHeaders, $govId, 'S8_B', 'خلية ب', 15.3600, 44.2100);
        $c = $this->createCell($ownerHeaders, $govId, 'S8_C', 'خلية ثالثة', 15.3900, 44.1800);

        // Preserve a historical active assignment row to prove that old Stage 8
        // data no longer controls who may publish in a cell.
        BrokerCellAssignment::query()->create([
            'geo_cell_id' => $b,
            'broker_user_id' => $brokerB->id,
            'assigned_by_user_id' => $owner->id,
            'starts_at' => now(),
            'reason' => 'historical assignment retained for audit',
        ]);

        $own = $this->withHeaders($headersA)->postJson('/api/properties', $this->listingPayload(15.3650, 44.1850, 'Broker first cell'));
        $own->assertCreated()->assertJsonPath('data.geo_cell_id', $a);
        $ownId = (int) $own->json('data.id');

        $this->withHeaders($headersA)->postJson('/api/properties/'.$ownId, [
            'latitude' => 15.3650, 'longitude' => 44.2150,
        ])->assertOk()->assertJsonPath('data.geo_cell_id', $b);

        $free = $this->withHeaders($headersA)->postJson('/api/properties', $this->listingPayload(15.3950, 44.1850, 'Broker third cell'));
        $free->assertCreated()->assertJsonPath('data.geo_cell_id', $c);

        $otherBrokerCell = $this->withHeaders($headersA)->postJson('/api/properties', $this->listingPayload(15.3650, 44.2150, 'Broker may list in historical broker cell'));
        $otherBrokerCell->assertCreated()->assertJsonPath('data.geo_cell_id', $b);

        $plain = $this->withHeaders($plainHeaders)->postJson('/api/properties', $this->listingPayload(15.3650, 44.2150, 'Registered user allowed'));
        $plain->assertCreated()->assertJsonPath('data.geo_cell_id', $b);

        $this->assertTrue(BrokerCellAssignment::query()->where('geo_cell_id', $b)->where('broker_user_id', $brokerB->id)->exists());
        $this->assertNotSame($brokerA->id, $brokerB->id);
    }

    public function test_public_cells_expose_reserved_state_without_admin_history(): void
    {
        [$owner, $headers] = $this->verifiedUser('stage8-owner4@example.test', '+967700000310');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        $govId = (int) $this->withHeaders($headers)->postJson('/api/admin/regions/governorates', [
            'code' => 'S8_GOV4', 'name_ar' => 'محافظة عامة',
        ])->assertCreated()->json('data.id');
        $cellId = $this->createCell($headers, $govId, 'S8_PUBLIC', 'خلية عامة', 15.4500, 44.1800);

        $this->getJson('/api/regions/cells?governorate_id='.$govId)
            ->assertOk()
            ->assertJsonPath('data.0.id', $cellId)
            ->assertJsonPath('data.0.is_reserved', false)
            ->assertJsonMissingPath('data.0.assignment_history');
    }

    public function test_public_point_resolve_returns_governorate_and_cell(): void
    {
        [$owner, $headers] = $this->verifiedUser('stage8-resolve-owner@example.test', '+967700000312');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        $gov = $this->withHeaders($headers)->postJson('/api/admin/regions/governorates', [
            'code' => 'S8_RESOLVE', 'name_ar' => 'محافظة تحديد الموقع', 'name_en' => 'Resolve Governorate',
        ])->assertCreated()->json('data');
        $cellId = $this->createCell($headers, (int) $gov['id'], 'S8_RESOLVE_CELL', 'حي الاختبار', 15.5000, 44.2000);

        $this->getJson('/api/regions/resolve?latitude=15.505&longitude=44.205')
            ->assertOk()
            ->assertJsonPath('data.governorate.id', (int) $gov['id'])
            ->assertJsonPath('data.governorate.name_ar', 'محافظة تحديد الموقع')
            ->assertJsonPath('data.cell.id', $cellId)
            ->assertJsonPath('data.cell.name_ar', 'حي الاختبار');

        $this->getJson('/api/regions/resolve?latitude=14.0&longitude=46.0')
            ->assertOk()
            ->assertJsonPath('data.governorate', null)
            ->assertJsonPath('data.cell', null);
    }

    public function test_reverse_address_uses_server_geocoder_and_keeps_fields_editable_client_side(): void
    {
        Http::fake([
            'https://nominatim.openstreetmap.org/*' => Http::response([
                'display_name' => 'شارع الاختبار، حي الاختبار، أمانة العاصمة، اليمن',
                'address' => [
                    'road' => 'شارع الاختبار',
                    'neighbourhood' => 'حي الاختبار',
                    'state' => 'أمانة العاصمة',
                ],
            ], 200),
        ]);

        $this->getJson('/api/regions/reverse-address?latitude=15.3694&longitude=44.1910')
            ->assertOk()
            ->assertJsonPath('data.governorate', 'أمانة العاصمة')
            ->assertJsonPath('data.district', 'حي الاختبار')
            ->assertJsonPath('data.street', 'شارع الاختبار')
            ->assertJsonPath('data.provider_status', 'nominatim');

        Http::assertSent(fn ($request) => str_contains($request->url(), 'nominatim.openstreetmap.org/reverse'));
        Http::assertNotSent(fn ($request) => str_contains($request->url(), 'photon.komoot.io/reverse'));
    }

    public function test_reverse_address_falls_back_to_photon_when_nominatim_is_unavailable(): void
    {
        Http::fake([
            'https://nominatim.openstreetmap.org/*' => Http::response([], 429),
            'https://photon.komoot.io/*' => Http::response([
                'features' => [[
                    'type' => 'Feature',
                    'geometry' => ['type' => 'Point', 'coordinates' => [44.1910, 15.3694]],
                    'properties' => [
                        'state' => 'أمانة العاصمة',
                        'district' => 'حدة',
                        'street' => 'شارع حدة',
                        'name' => 'شارع حدة',
                        'osm_key' => 'highway',
                    ],
                ]],
            ], 200),
        ]);

        $this->getJson('/api/regions/reverse-address?latitude=15.3694&longitude=44.1910')
            ->assertOk()
            ->assertJsonPath('data.governorate', 'أمانة العاصمة')
            ->assertJsonPath('data.district', 'حدة')
            ->assertJsonPath('data.street', 'شارع حدة')
            ->assertJsonPath('data.provider_status', 'photon')
            ->assertJsonPath('data.provider_attempts.nominatim', 'http_429')
            ->assertJsonPath('data.provider_attempts.photon', 'ok');

        Http::assertSent(fn ($request) => str_contains($request->url(), 'nominatim.openstreetmap.org/reverse'));
        Http::assertSent(fn ($request) => str_contains($request->url(), 'photon.komoot.io/reverse')
            && ! str_contains($request->url(), 'lang=ar')
            && str_contains($request->url(), 'radius=10'));
    }

    public function test_postgis_rejects_interior_overlap_but_allows_touching_borders(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            $this->markTestSkipped('PostGIS overlap trigger is verified by the live Stage 8 smoke on PostgreSQL.');
        }
        [$owner, $headers] = $this->verifiedUser('stage8-owner5@example.test', '+967700000311');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        $govId = (int) $this->withHeaders($headers)->postJson('/api/admin/regions/governorates', [
            'code' => 'S8_GOV5', 'name_ar' => 'محافظة التداخل',
        ])->assertCreated()->json('data.id');
        $firstId = $this->createCell($headers, $govId, 'S8_OVERLAP_A', 'أ', 15.4800, 44.1800);
        $this->withHeaders($headers)->postJson('/api/admin/regions/cells', [
            'governorate_id' => $govId, 'code' => 'S8_OVERLAP_B', 'name_ar' => 'ب',
            'points' => $this->square(15.4850, 44.1850, 0.0100),
        ])->assertUnprocessable();

        $touchingId = $this->createCell($headers, $govId, 'S8_TOUCHING', 'حد مشترك', 15.4800, 44.1900);
        $this->assertGreaterThan($firstId, $touchingId);
        $resolved = app(RegionService::class)->resolveCell(15.4850, 44.1900);
        $this->assertSame($firstId, $resolved?->id);
    }

    private function verifiedUser(string $email, string $phone): array
    {
        // Stage 6 already regression-tests registration and phone verification.
        // Stage 8 fixtures are created directly so region/broker tests are not
        // coupled to auth-route throttle counters that can persist across tests.
        $user = User::query()->create([
            'name' => 'Stage Eight User',
            'email' => $email,
            'phone' => $phone,
            'password' => 'StrongPass123!',
            'account_status' => User::STATUS_ACTIVE,
            'phone_verified_at' => now(),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);

        $token = 're6_'.Str::random(80);
        $user->apiTokens()->create([
            'name' => 'stage8-test',
            'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12),
            'expires_at' => now()->addDay(),
        ]);

        return [$user->fresh(), ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function grantRole(User $user, string $key): void
    {
        $role = Role::query()->where('key', $key)->firstOrFail();
        $user->roles()->syncWithoutDetaching([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
    }

    private function verifiedBroker(string $email, string $phone): array
    {
        [$user, $headers] = $this->verifiedUser($email, $phone);
        $this->grantRole($user, 'broker');
        $user->forceFill([
            'account_type' => User::ACCOUNT_TYPE_BROKER,
            'broker_verification_status' => User::BROKER_VERIFICATION_APPROVED,
            'broker_verified_at' => now(),
        ])->save();
        return [$user->fresh(), $headers];
    }

    private function createCell(array $headers, int $governorateId, string $code, string $name, float $lat, float $lng): int
    {
        return (int) $this->withHeaders($headers)->postJson('/api/admin/regions/cells', [
            'governorate_id' => $governorateId, 'code' => $code, 'name_ar' => $name,
            'points' => $this->square($lat, $lng, 0.0100),
        ])->assertCreated()->json('data.id');
    }


    private function square(float $south, float $west, float $size): array
    {
        return [
            ['latitude' => $south, 'longitude' => $west],
            ['latitude' => $south, 'longitude' => $west + $size],
            ['latitude' => $south + $size, 'longitude' => $west + $size],
            ['latitude' => $south + $size, 'longitude' => $west],
        ];
    }

    private function listingPayload(float $lat, float $lng, string $title): array
    {
        return [
            'title' => $title, 'description' => 'Stage 8 geographic rule test',
            'purpose' => 'sale', 'type' => 'house', 'price' => 50000000, 'currency' => 'YER',
            'area_m2' => 220, 'bedrooms' => 4, 'bathrooms' => 3, 'address' => 'Sanaa',
            'latitude' => $lat, 'longitude' => $lng,
            'contact_phone' => '+967700000000', 'contact_whatsapp' => '+967700000000',
        ];
    }
}

