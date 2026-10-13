<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\BrokerRankingService;
use App\Services\UatWave3CleanupService;
use Database\Seeders\UatDemoSeeder;
use Database\Seeders\UatDemoPropertiesSeeder;
use Database\Seeders\UatTestAccountsSeeder;
use Database\Seeders\UatWave3MarketplaceSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Wave3UatSeedTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public'); Storage::fake('local');
        config(['services.uat_wave3.enabled' => true]);
    }

    public function test_fixture_cleanup_preserves_operations_and_builds_normal_rank_and_finance_evidence_once(): void
    {
        $this->seed(UatTestAccountsSeeder::class);
        $this->seed(UatDemoPropertiesSeeder::class);
        $protected = DB::table('users')->whereIn('phone', ['+12025550106', '+12025550107', '+12025550108', '+12025550109'])->orderBy('id')->get();
        $snapshot = hash('sha256', json_encode($protected));
        $protectedIds = $protected->pluck('id')->all();
        $oldProperty = DB::table('properties')->first();
        DB::table('listing_reviews')->insert(['listing_id' => $oldProperty->id, 'action' => 'uat_old_trial', 'created_at' => now()]);
        $this->seed(UatDemoSeeder::class);
        $this->assertSame($snapshot, hash('sha256', json_encode(DB::table('users')->whereIn('id', $protectedIds)->orderBy('id')->get())));
        $this->assertDatabaseMissing('users', ['email' => 'uat-regular-1@example.invalid']);
        $this->assertDatabaseCount('users', 15);
        $this->assertDatabaseCount('properties', 27);
        $this->assertDatabaseCount('broker_deal_outcomes', 11);
        $this->assertDatabaseCount('property_platform_receivables', 11);
        $this->assertSame(7, DB::table('property_platform_receivables')->where('status', 'paid')->count());
        $this->assertSame(4, DB::table('property_platform_receivables')->where('status', 'open')->count());
        $this->assertDatabaseCount('property_payments', 7);
        $this->assertSame(7, DB::table('property_payments')->where('status', 'confirmed')->count());
        $this->assertDatabaseCount('property_agreements', 0);
        $this->assertDatabaseCount('advertiser_ratings', 10);
        $this->assertDatabaseCount('viewing_bookings', 10);
        $this->assertDatabaseCount('broker_customer_followups', 10);
        $this->assertDatabaseMissing('listing_reviews', ['action' => 'uat_old_trial']);
        $this->assertDatabaseHas('properties', ['review_status' => 'returned_for_correction']);
        $this->assertDatabaseHas('properties', ['review_status' => 'submitted']);
        $this->assertDatabaseHas('properties', ['availability_status' => 'paused']);
        $this->assertDatabaseHas('properties', ['type' => 'apartment', 'unit_occupies_entire_floor' => true]);
        $marker = json_decode(DB::table('platform_settings')->where('key', UatWave3MarketplaceSeeder::MARKER)->value('value'), true);
        Storage::disk('local')->assertExists($marker['cleanup']['private_backup']);
        $backup = Storage::disk('local')->get($marker['cleanup']['private_backup']);
        $this->assertStringNotContainsString('"password"', $backup);
        $this->assertStringNotContainsString('"token_hash"', $backup);
        $ranking = app(BrokerRankingService::class)->query()->get();
        $this->assertSame('أحمد محمد علي الجبري', $ranking->first()->name);
        $strong = $ranking->firstWhere('phone', '+12025550104');
        $medium = $ranking->firstWhere('phone', '+12025550105');
        $new = $ranking->firstWhere('phone', '+12025550103');
        $this->assertSame(6, (int) $strong->completed_deals);
        $this->assertSame(5, (int) $strong->rating_count);
        $this->assertGreaterThan((float) $medium->ranking_score, (float) $strong->ranking_score);
        $this->assertGreaterThan((float) $new->ranking_score, (float) $medium->ranking_score);
        $this->seed(UatDemoSeeder::class);
        config(['services.uat_wave3.enabled' => false]);
        $this->seed(UatDemoSeeder::class);
        $this->assertDatabaseCount('properties', 27);
        $this->assertDatabaseCount('users', 15);
        $this->assertDatabaseCount('broker_deal_outcomes', 11);
        // Delete protection is restored after the one-time fixture cleanup.
        $this->expectException(\Illuminate\Database\QueryException::class);
        DB::table('listing_reviews')->delete();
    }

    public function test_operational_role_excludes_a_named_legacy_fixture_from_cleanup(): void
    {
        $this->seed(UatTestAccountsSeeder::class);
        $user = User::where('phone', '+12025550101')->firstOrFail();
        $user->roles()->attach(DB::table('roles')->where('key', 'support_agent')->value('id'), ['created_at' => now()]);
        $plan = app(UatWave3CleanupService::class)->plan();
        $this->assertNotContains($user->id, $plan['ids']);
        $this->assertCount(4, $plan['ids']);
        $this->assertDatabaseHas('users', ['id' => $user->id]);
    }

    public function test_production_and_wrong_project_stop_before_any_write(): void
    {
        app()->instance('env', 'production');
        try {
            app(UatWave3CleanupService::class)->plan();
            $this->fail('Production cleanup must be refused.');
        } catch (\RuntimeException $error) {
            $this->assertStringContainsString('UAT', $error->getMessage());
        } finally { app()->instance('env', 'testing'); }
        $this->assertDatabaseCount('users', 0);
        app()->instance('env', 'uat');
        config(['services.supabase_storage.url' => 'https://unselected-project.supabase.co']);
        try {
            app(UatWave3CleanupService::class)->plan();
            $this->fail('Unselected database must be refused.');
        } catch (\RuntimeException $error) {
            $this->assertStringContainsString('Frankfurt', $error->getMessage());
        } finally { app()->instance('env', 'testing'); }
        $this->assertDatabaseCount('users', 0);
    }
}
