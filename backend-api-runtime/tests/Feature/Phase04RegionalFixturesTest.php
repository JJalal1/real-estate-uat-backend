<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Services\PropertyDiscoveryFilterService;
use App\Services\YemenGovernorateCatalog;
use Database\Seeders\UatDemoSeeder;
use Database\Seeders\UatPhase04RegionalSeeder;
use Database\Seeders\UatTestAccountsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Phase04RegionalFixturesTest extends TestCase
{
    use RefreshDatabase;

    public function test_sixty_additive_ads_have_three_public_images_valid_governorates_and_no_old_history_mutations(): void
    {
        Storage::fake('local');
        Storage::fake('public');
        config(['services.uat_wave3.enabled' => true, 'services.uat_phase04.regional_run' => UatPhase04RegionalSeeder::RUN]);
        $this->seed(UatTestAccountsSeeder::class);
        $this->seed(UatDemoSeeder::class);
        $snapshots = [];
        $tables = ['users', 'account_verification_profiles', 'properties', 'property_assets', 'property_images', 'property_sai_terms',
            'property_payments', 'property_payment_allocations', 'property_platform_receivables', 'property_financial_ledger_entries',
            'property_financial_ledger_lines', 'property_sai_settlements', 'property_agreements', 'private_messages', 'message_threads', 'viewing_bookings'];
        foreach ($tables as $table) {
            $rows = DB::table($table)->orderBy('id')->get();
            $snapshots[$table] = [$rows->pluck('id')->all(), $rows->toJson()];
        }
        $this->seed(UatPhase04RegionalSeeder::class);
        $marker = json_decode(DB::table('platform_settings')->where('key', UatPhase04RegionalSeeder::MARKER)->value('value'), true);
        $ids = $marker['property_ids'];
        $this->assertCount(60, $ids);
        $this->assertCount(60, array_unique($ids));
        $this->assertSame(60, app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids)->count());
        foreach ($snapshots as $table => [$oldIds, $json]) {
            $this->assertSame($json, DB::table($table)->whereIn('id', $oldIds)->orderBy('id')->get()->toJson(), $table);
            if (! in_array($table, ['properties', 'property_assets', 'property_images', 'property_sai_terms'], true)) {
                $this->assertDatabaseCount($table, count($oldIds));
            }
        }
        foreach ($marker['by_governorate'] as $code => $regionalIds) {
            $this->assertCount(20, $regionalIds);
            $query = app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids);
            app(PropertyDiscoveryFilterService::class)->apply($query, ['governorate_code' => $code]);
            $this->assertSame(20, $query->count());
            foreach (Property::with(['images', 'documents', 'currentSaiTerm'])->whereIn('id', $regionalIds)->get() as $property) {
                $this->assertSame($code, app(YemenGovernorateCatalog::class)->locate((float) $property->latitude, (float) $property->longitude, 5)['code']);
                $this->assertStringContainsString('تجريبي', $property->title);
                $this->assertStringContainsString('الصور توضيحية', $property->description);
                $this->assertCount(3, $property->images);
                $this->assertCount(3, $property->images->pluck('path')->unique());
                $this->assertSame(1, $property->images->where('is_primary', true)->count());
                $this->assertSame([0, 1, 2], $property->images->sortBy('sort_order')->pluck('sort_order')->all());
                $this->assertSame('accepted', $property->currentSaiTerm->platform_terms_status);
                foreach ($property->images as $image) {
                    Storage::disk('public')->assertExists($image->path);
                }
                Storage::disk('local')->assertExists($property->documents->first()->path);
            }
            $sample = Property::with(['images', 'documents'])->findOrFail($regionalIds[0]);
            foreach ($sample->images as $image) {
                $this->get('/api/property-media/'.$image->id)->assertOk();
            }
            $this->get('/api/listing-documents/'.$sample->documents->first()->id)->assertUnauthorized();
        }
        $this->assertDatabaseCount('geo_cells', 0);
        $files = [Storage::disk('public')->allFiles(), Storage::disk('local')->allFiles()];
        $count = Property::count();
        $this->seed(UatPhase04RegionalSeeder::class);
        $this->assertSame($count, Property::count());
        $this->assertSame($files, [Storage::disk('public')->allFiles(), Storage::disk('local')->allFiles()]);
    }

    public function test_fixture_run_refuses_missing_opt_in_production_and_wrong_uat_origin_before_writing(): void
    {
        $count = DB::table('platform_settings')->count();
        foreach ([['testing', '', 'https://real-estate-uat-api-frankfurt.onrender.com'], ['production', UatPhase04RegionalSeeder::RUN, 'https://real-estate-uat-api-frankfurt.onrender.com'], ['uat', UatPhase04RegionalSeeder::RUN, 'https://other.invalid']] as [$env, $run, $origin]) {
            app()->instance('env', $env);
            config(['services.uat_phase04.regional_run' => $run, 'app.url' => $origin, 'services.supabase_storage.url' => 'https://ipxsgxsqzthpgthwvdno.supabase.co']);
            try {
                app(UatPhase04RegionalSeeder::class)->run();
                $this->fail('Unexpected fixture execution');
            } catch (\RuntimeException $error) {
                $this->assertStringContainsString('UAT', $error->getMessage());
            } finally {
                app()->instance('env', 'testing');
            }
            $this->assertDatabaseCount('properties', 0);
            $this->assertDatabaseCount('platform_settings', $count);
        }
    }
}
