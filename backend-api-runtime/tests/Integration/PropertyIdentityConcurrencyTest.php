<?php

namespace Tests\Integration;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\Process\Process;
use Tests\Concerns\ConfirmsListingImages;
use Tests\TestCase;

/** Run explicitly against aqer_identity_race_test on loopback; never UAT. */
class PropertyIdentityConcurrencyTest extends TestCase
{
    use ConfirmsListingImages;

    private array $receipt = [];

    protected function setUp(): void
    {
        if (getenv('DB_CONNECTION') !== 'pgsql'
            || getenv('DB_HOST') !== '127.0.0.1'
            || getenv('DB_PORT') !== '55441'
            || getenv('DB_DATABASE') !== 'aqer_identity_race_test') {
            throw new \RuntimeException('Identity race test requires the named loopback test database.');
        }
        parent::setUp();
        $this->assertSame('aqer_identity_race_test', DB::selectOne('SELECT current_database() AS name')->name);
        $this->assertSame(0, DB::table('properties')->count(), 'Start with a fresh synthetic race database.');
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_two_process_submission_retry_and_representation_races(): void
    {
        [$ownerA, $headersA] = $this->user('race-owner-a@example.test', '+967733002001');
        [$ownerB, $headersB] = $this->user('race-owner-b@example.test', '+967733002002');
        $firstId = $this->createReady($headersA, ['title' => 'Synthetic competing house A']);
        $secondId = $this->createReady($headersB, ['title' => 'Synthetic competing house B']);
        $assetId = (int) Property::query()->findOrFail($firstId)->property_asset_id;
        Property::query()->findOrFail($secondId)->forceFill(['property_asset_id' => $assetId])->save();

        $submitted = $this->runPair('submit_fail', [[$ownerA->id, $firstId], [$ownerB->id, $secondId]],
            ['row', 'property_assets', $assetId]);
        foreach ($submitted['results'] as $result) {
            $this->assertTrue($result['ok']);
            $this->assertSame('pending', $result['status']);
            $this->assertSame('submitted', $result['review_status']);
            $this->assertSame('check_failed', $result['duplicate_check_status']);
        }
        $this->assertSame(2, DB::table('listing_reviews')->where('action', 'submitted')->count());
        $this->assertSame(0, DB::table('property_identity_checks')->count());
        foreach ([$firstId, $secondId] as $id) {
            $this->assertSame(1, DB::table('support_tasks')->where('source_type', 'listing_review')
                ->where('source_id', $id)->count());
            $this->assertSame(1, DB::table('listing_reviews')->where('listing_id', $id)
                ->where('action', 'identity_check_unavailable')->count());
        }

        $retried = $this->runPair('retry', [[$ownerB->id, $secondId], [$ownerB->id, $secondId]],
            ['row', 'properties', $secondId]);
        foreach ($retried['results'] as $result) {
            $this->assertTrue($result['ok']);
            $this->assertSame('confirmed_duplicate', $result['decision']);
        }
        $this->assertSame(1, DB::table('property_identity_checks')->where('property_id', $secondId)->count());
        $this->assertSame(1, DB::table('listing_reviews')->where('listing_id', $secondId)
            ->where('action', 'duplicate_suspected_after_submission')->count());
        $this->assertSame(1, DB::table('support_tasks')->where('source_type', 'listing_review')
            ->where('source_id', $secondId)->count());

        // Approval calls run this guard only after human and identity checks.
        // The two submitted listings above are both confirmed duplicates, so
        // the route would stop before this claim race. Exercise its DB arbiter.
        $claims = $this->runPair('claim', [[$ownerA->id, $firstId], [$ownerB->id, $secondId]],
            ['table', 'property_representation_claims', 0]);
        $this->assertSame(1, count(array_filter($claims['results'],
            static fn (array $result): bool => $result['ok'])));
        $this->assertSame(1, DB::table('property_representation_claims')
            ->where('property_asset_id', $assetId)->where('status', 'active')->count());
        $loser = collect($claims['results'])->firstWhere('ok', false);
        $this->assertSame(409, $loser['http_status']);
        $winnerIndex = $claims['results'][0]['ok'] ? 0 : 1;
        $this->assertSame([$ownerA->id, $ownerB->id][$winnerIndex],
            (int) DB::table('property_representation_claims')->where('property_asset_id', $assetId)
                ->where('status', 'active')->value('advertiser_user_id'));

        [$unitA, $unitHeadersA] = $this->user('race-unit-a@example.test', '+967733002003');
        [$unitB, $unitHeadersB] = $this->user('race-unit-b@example.test', '+967733002004');
        $unitBase = [
            'type' => 'apartment', 'address' => 'Synthetic Tower 20',
            'building_reference' => 'Synthetic Tower 20', 'floor_number' => '2',
            'latitude' => 15.380000, 'longitude' => 44.195000,
            'area_m2' => 120, 'bedrooms' => 3, 'bathrooms' => 2,
        ];
        $unitAId = $this->createReady($unitHeadersA, array_merge($unitBase,
            ['title' => 'Synthetic unit 3', 'unit_number' => '3']));
        $unitBId = $this->createReady($unitHeadersB, array_merge($unitBase,
            ['title' => 'Synthetic unit 4', 'unit_number' => '4']));
        $this->assertNotSame((int) Property::findOrFail($unitAId)->property_asset_id,
            (int) Property::findOrFail($unitBId)->property_asset_id);

        $unitsSubmitted = $this->runPair('submit', [[$unitA->id, $unitAId], [$unitB->id, $unitBId]],
            ['table', 'property_assets', 0]);
        foreach ($unitsSubmitted['results'] as $result) {
            $this->assertTrue($result['ok']);
            $this->assertSame('submitted', $result['review_status']);
            $this->assertNotSame('confirmed_duplicate', $result['duplicate_check_status']);
        }
        $unitClaims = $this->runPair('claim', [[$unitA->id, $unitAId], [$unitB->id, $unitBId]],
            ['table', 'property_representation_claims', 0]);
        $this->assertTrue($unitClaims['results'][0]['ok']);
        $this->assertTrue($unitClaims['results'][1]['ok']);
        $this->assertSame(2, DB::table('property_representation_claims')
            ->whereIn('property_id', [$unitAId, $unitBId])->where('status', 'active')->count());

        $this->receipt['final'] = [
            'same_asset_submitted' => DB::table('properties')->whereIn('id', [$firstId, $secondId])
                ->where('review_status', 'submitted')->count(),
            'same_asset_active_claims' => DB::table('property_representation_claims')
                ->where('property_asset_id', $assetId)->where('status', 'active')->count(),
            'retry_identity_checks' => DB::table('property_identity_checks')->where('property_id', $secondId)->count(),
            'different_unit_active_claims' => DB::table('property_representation_claims')
                ->whereIn('property_id', [$unitAId, $unitBId])->where('status', 'active')->count(),
        ];
        $receiptPath = getenv('AQER_RACE_RECEIPT');
        if (is_string($receiptPath) && $receiptPath !== '') {
            file_put_contents($receiptPath, json_encode($this->receipt, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
        }
    }

    public function test_two_authenticated_http_approvals_keep_one_asset_safe_and_allow_distinct_units(): void
    {
        [$ownerA, $headersA] = $this->user('http-owner-a@example.test', '+967733002011');
        [$ownerB, $headersB] = $this->user('http-owner-b@example.test', '+967733002012');
        [$moderator, $moderatorHeaders] = $this->user('http-moderator@example.test',
            '+967733002013', ['content_moderator']);
        $firstId = $this->createReady($headersA, ['title' => 'First reviewable synthetic house']);
        $secondId = $this->createReady($headersB, ['title' => 'Second reviewable synthetic house']);
        $assetId = (int) Property::query()->findOrFail($firstId)->property_asset_id;
        Property::query()->findOrFail($secondId)->forceFill(['property_asset_id' => $assetId])->save();

        $this->withHeaders($headersA)->postJson("/api/properties/$firstId/submit")->assertOk();
        $this->withHeaders($headersB)->postJson("/api/properties/$secondId/submit")->assertOk()
            ->assertJsonPath('data.duplicate_check_status', 'confirmed_duplicate');
        $this->confirmListingImages($firstId, $moderatorHeaders);
        $this->confirmListingImages($secondId, $moderatorHeaders);
        $this->withHeaders($headersA)->postJson("/api/admin/listing-review/listings/$firstId/approve")
            ->assertForbidden();
        $this->withHeaders(['Authorization' => ''])->postJson(
            "/api/admin/listing-review/listings/$firstId/approve")->assertUnauthorized();

        $attempts = $this->runPair('approve_http', [[$moderator->id, $firstId], [$moderator->id, $secondId]],
            ['row', 'property_assets', $assetId]);
        foreach ($attempts['results'] as $result) {
            $this->assertFalse($result['ok']);
            $this->assertSame(409, $result['http_status']);
        }
        $this->assertSame(0, DB::table('property_representation_claims')
            ->where('property_asset_id', $assetId)->where('status', 'active')->count());
        $this->assertSame(0, DB::table('properties')->whereIn('id', [$firstId, $secondId])
            ->where('status', 'published')->count());

        // Support returns the competing request. The remaining legitimate
        // request is then re-evaluated and can be published without a bypass.
        $this->withHeaders($moderatorHeaders)->postJson(
            "/api/admin/listing-review/listings/$secondId/return", [
                'reason' => 'Competing synthetic request must clarify representation.',
            ])->assertOk()->assertJsonPath('data.review_status', 'returned_for_correction');
        $this->withHeaders($moderatorHeaders)->postJson(
            "/api/admin/listing-review/listings/$firstId/approve", [
                'reason' => 'Synthetic support confirmed the remaining request.',
            ])->assertOk()->assertJsonPath('data.status', 'published');
        $this->assertSame(1, DB::table('property_representation_claims')
            ->where('property_asset_id', $assetId)->where('status', 'active')->count());
        $this->assertSame($firstId, (int) DB::table('property_representation_claims')
            ->where('property_asset_id', $assetId)->where('status', 'active')->value('property_id'));
        $this->assertSame('draft', Property::query()->findOrFail($secondId)->status);

        [$unitOwnerA, $unitHeadersA] = $this->user('http-unit-a@example.test', '+967733002014');
        [$unitOwnerB, $unitHeadersB] = $this->user('http-unit-b@example.test', '+967733002015');
        $unitBase = [
            'type' => 'apartment', 'address' => 'Synthetic Tower 30',
            'building_reference' => 'Synthetic Tower 30', 'floor_number' => '2',
            'latitude' => 15.390000, 'longitude' => 44.205000,
            'area_m2' => 120, 'bedrooms' => 3, 'bathrooms' => 2,
        ];
        $unitAId = $this->createReady($unitHeadersA, array_merge($unitBase,
            ['title' => 'Synthetic apartment 3', 'unit_number' => '3']));
        $unitBId = $this->createReady($unitHeadersB, array_merge($unitBase,
            ['title' => 'Synthetic apartment 4', 'unit_number' => '4']));
        $this->assertNotSame((int) Property::findOrFail($unitAId)->property_asset_id,
            (int) Property::findOrFail($unitBId)->property_asset_id);
        $this->withHeaders($unitHeadersA)->postJson("/api/properties/$unitAId/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'distinct');
        $this->withHeaders($unitHeadersB)->postJson("/api/properties/$unitBId/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'distinct');
        $this->confirmListingImages($unitAId, $moderatorHeaders);
        $this->confirmListingImages($unitBId, $moderatorHeaders);
        $unitApprovals = $this->runPair('approve_http', [
            [$moderator->id, $unitAId], [$moderator->id, $unitBId],
        ], ['table', 'property_representation_claims', 0]);
        foreach ($unitApprovals['results'] as $result) {
            $this->assertTrue($result['ok']);
            $this->assertSame(200, $result['http_status']);
            $this->assertSame('published', $result['status']);
        }
        $this->assertSame(2, DB::table('property_representation_claims')
            ->whereIn('property_id', [$unitAId, $unitBId])->where('status', 'active')->count());
        $this->assertSame(2, DB::table('properties')->whereIn('id', [$unitAId, $unitBId])
            ->where('status', 'published')->where('review_status', 'approved')->count());
        $this->receipt['http_final'] = [
            'same_asset_simultaneous_approvals' => array_column($attempts['results'], 'http_status'),
            'same_asset_published_after_support_return' => DB::table('properties')
                ->whereIn('id', [$firstId, $secondId])->where('status', 'published')->count(),
            'same_asset_active_claims' => DB::table('property_representation_claims')
                ->where('property_asset_id', $assetId)->where('status', 'active')->count(),
            'different_unit_simultaneous_approvals' => array_column($unitApprovals['results'], 'http_status'),
            'different_unit_active_claims' => DB::table('property_representation_claims')
                ->whereIn('property_id', [$unitAId, $unitBId])->where('status', 'active')->count(),
        ];
        $receiptPath = getenv('AQER_RACE_RECEIPT');
        if (is_string($receiptPath) && $receiptPath !== '') {
            file_put_contents($receiptPath, json_encode($this->receipt, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
        }
    }

    private function runPair(string $action, array $targets, array $lock): array
    {
        $gate = sys_get_temp_dir() . '/aqer-race-' . bin2hex(random_bytes(8));
        mkdir($gate, 0700);
        $processes = [];
        try {
            DB::beginTransaction();
            if ($lock[0] === 'row') {
                DB::table($lock[1])->where('id', $lock[2])->lockForUpdate()->firstOrFail();
            } else {
                if (! in_array($lock[1], ['property_assets', 'property_representation_claims'], true)) {
                    throw new \RuntimeException('Unrecognized synthetic lock table.');
                }
                DB::statement('LOCK TABLE ' . $lock[1] . ' IN ACCESS EXCLUSIVE MODE');
            }

            foreach (['a', 'b'] as $i => $slot) {
                $processes[$slot] = new Process([
                    PHP_BINARY, __DIR__ . '/identity_race_worker.php', $action,
                    (string) $targets[$i][0], (string) $targets[$i][1], $gate, $slot,
                ], dirname(__DIR__, 2));
                $processes[$slot]->setTimeout(30);
                $processes[$slot]->start();
            }
            $this->waitUntil(static fn () => is_file($gate . '/ready-a.json')
                && is_file($gate . '/ready-b.json'), 8, 'Worker readiness');
            $pids = [];
            foreach (['a', 'b'] as $slot) {
                $ready = json_decode(file_get_contents($gate . '/ready-' . $slot . '.json'), true, 512, JSON_THROW_ON_ERROR);
                $this->assertSame($action, $ready['action']);
                $pids[] = (int) $ready['pid'];
            }
            $this->assertNotSame($pids[0], $pids[1]);
            file_put_contents($gate . '/go', 'go');
            $this->waitUntil(static fn () => DB::table('pg_stat_activity')
                ->whereIn('pid', $pids)->where('wait_event_type', 'Lock')->count() === 2,
                8, 'Two PostgreSQL lock waiters');
            $waits = DB::table('pg_stat_activity')->whereIn('pid', $pids)
                ->orderBy('pid')->get(['pid', 'wait_event_type', 'wait_event'])->toArray();
            DB::commit();

            $results = [];
            foreach (['a', 'b'] as $slot) {
                $processes[$slot]->wait();
                $results[] = json_decode(trim($processes[$slot]->getOutput()), true, 512, JSON_THROW_ON_ERROR);
            }
            $this->receipt[$action . '_' . count($this->receipt)] = [
                'processes' => 2, 'barrier' => $lock[0] . ':' . $lock[1],
                'backend_pids' => $pids, 'lock_waiters_before_release' => count($waits),
                'wait_events' => array_map(static fn ($w) => $w->wait_event, $waits),
                'results' => $results,
            ];
            return ['results' => $results];
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($processes as $process) {
                if ($process->isRunning()) $process->stop(1);
            }
            foreach (glob($gate . '/*') ?: [] as $file) unlink($file);
            rmdir($gate);
        }
    }

    private function waitUntil(callable $condition, int $seconds, string $label): void
    {
        $deadline = microtime(true) + $seconds;
        while (! $condition()) {
            if (microtime(true) > $deadline) $this->fail($label . ' did not occur.');
            usleep(20000);
        }
    }

    private function createReady(array $headers, array $overrides): int
    {
        $payload = array_merge([
            'listing_input_version' => 3, 'title' => 'Synthetic race property',
            'description' => 'Synthetic local race fixture.', 'purpose' => 'sale',
            'type' => 'house', 'tenure_type' => 'freehold', 'price' => 50000000,
            'currency' => 'YER', 'area_m2' => 220, 'area_value' => 220, 'area_unit' => 'sqm',
            'bedrooms' => 4, 'bathrooms' => 3, 'has_parking' => true,
            'building_facade' => 'north', 'address' => 'Synthetic house number 18',
            'latitude' => 15.369400, 'longitude' => 44.191000,
            'contact_phone' => '+967700000000', 'contact_whatsapp' => '+967700000000',
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ], $overrides);
        return (int) $this->withHeaders($headers)->post('/api/properties', $payload)
            ->assertCreated()->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = ['registered_user']): array
    {
        $user = User::query()->create([
            'name' => 'Synthetic Race Owner', 'email' => $email, 'phone' => $phone,
            'phone_verified_at' => now(), 'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make(hash('sha256', $email . '|race')),
        ]);
        foreach ($roles as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $user->roles()->attach($role->id, ['assigned_by_user_id' => null, 'created_at' => now()]);
        }
        $plain = 'race_' . substr(hash('sha512', $email), 0, 76);
        $user->apiTokens()->create([
            'name' => 'synthetic-race', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer ' . $plain, 'Accept' => 'application/json']];
    }
}
