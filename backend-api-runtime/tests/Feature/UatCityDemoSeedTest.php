<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Services\MarketplaceContextService;
use App\Services\PropertyDiscoveryFilterService;
use Database\Seeders\UatCityDemoSeeder;
use Database\Seeders\UatDemoSeeder;
use Database\Seeders\UatTestAccountsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UatCityDemoSeedTest extends TestCase
{
    use RefreshDatabase;

    public function test_additive_city_ads_are_public_private_files_stay_private_and_existing_history_is_unchanged(): void
    {
        Storage::fake('local'); Storage::fake('public');
        config(['services.uat_wave3.enabled' => true, 'services.uat_city_demo.enabled' => true]);
        $this->seed(UatTestAccountsSeeder::class);
        $this->seed(UatDemoSeeder::class);
        $before = [];
        foreach (['users', 'account_verification_profiles', 'properties', 'property_assets', 'property_images', 'property_sai_terms',
            'broker_deal_outcomes', 'property_deal_financial_terms', 'property_payments', 'property_payment_allocations',
            'property_manual_payment_confirmations', 'property_platform_receivables', 'property_financial_ledger_entries',
            'property_financial_ledger_lines', 'property_financial_holds', 'property_financial_disputes', 'property_sai_attestations',
            'property_sai_settlements', 'property_agreements', 'property_agreement_revisions', 'property_agreement_acceptances',
            'private_messages', 'message_threads', 'viewing_bookings', 'advertiser_ratings'] as $table) {
            $rows = DB::table($table)->orderBy('id')->get();
            $before[$table] = [$rows->pluck('id')->all(), json_encode($rows)];
        }
        $this->seed(UatCityDemoSeeder::class);
        $marker = json_decode(DB::table('platform_settings')->where('key', UatCityDemoSeeder::MARKER)->value('value'), true);
        $ids = $marker['property_ids'];
        $this->assertCount(24, $ids);
        $this->assertDatabaseCount('properties', 51);
        $this->assertDatabaseCount('users', 15);
        foreach ($before as $table => [$oldIds, $snapshot]) {
            $this->assertSame($snapshot, json_encode(DB::table($table)->whereIn('id', $oldIds)->orderBy('id')->get()), $table.' existing rows must not change');
            if (! in_array($table, ['properties', 'property_assets', 'property_images', 'property_sai_terms'], true)) {
                $this->assertSame(count($oldIds), DB::table($table)->count(), $table.' must not gain fake activity');
            }
        }
        $this->assertSame(24, app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids)->count());
        foreach (['صنعاء', 'ذمار', 'إب'] as $city) {
            $query = app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids);
            app(PropertyDiscoveryFilterService::class)->apply($query, ['governorate' => $city]);
            $this->assertSame(8, $query->count());
            $this->getJson('/api/marketplace?'.http_build_query(['governorate' => $city]))->assertOk()->assertJsonPath('data.context.label', $city);
        }
        foreach (Property::query()->with(['images', 'documents', 'currentSaiTerm'])->whereIn('id', $ids)->get() as $property) {
            $this->assertStringContainsString('تجريبي', $property->title);
            $this->assertSame('fixed', $property->currentSaiTerm->sai_amount_type);
            $this->assertSame('accepted', $property->currentSaiTerm->platform_terms_status);
            $this->assertSame(1, $property->images->count());
            $this->assertSame(1, $property->documents->count());
            Storage::disk('public')->assertExists($property->images->first()->path);
            Storage::disk('local')->assertExists($property->documents->first()->path);
            $this->get('/api/listing-documents/'.$property->documents->first()->id)->assertUnauthorized();
            $this->get('/api/property-media/'.$property->images->first()->id)->assertOk();
            if ($property->type === 'apartment') $this->assertContains($property->floor_number, ['0', '1', '7']);
        }
        $locations = collect(app(MarketplaceContextService::class)->locations())->keyBy('label');
        foreach (['صنعاء', 'ذمار', 'إب'] as $city) $this->assertTrue($locations->has($city));
        $this->assertSame('ذمار', app(MarketplaceContextService::class)->resolve(['latitude' => 14.55, 'longitude' => 44.40])['label']);
        $files = [Storage::disk('public')->allFiles(), Storage::disk('local')->allFiles()];
        $this->seed(UatCityDemoSeeder::class);
        $this->assertDatabaseCount('properties', 51);
        $this->assertSame($ids, json_decode(DB::table('platform_settings')->where('key', UatCityDemoSeeder::MARKER)->value('value'), true)['property_ids']);
        $this->assertSame($files, [Storage::disk('public')->allFiles(), Storage::disk('local')->allFiles()]);
    }

    public function test_seeding_refuses_production_wrong_project_and_missing_opt_in_before_any_write(): void
    {
        $settingsCount = DB::table('platform_settings')->count();
        foreach ([['production', true, 'https://ipxsgxsqzthpgthwvdno.supabase.co'], ['uat', true, 'https://other-project.supabase.co'], ['testing', false, null]] as [$environment, $enabled, $url]) {
            app()->instance('env', $environment);
            config(['services.uat_city_demo.enabled' => $enabled, 'services.supabase_storage.url' => $url]);
            try {
                app(UatCityDemoSeeder::class)->run();
                $this->fail('Unapproved city-demo execution must be refused.');
            } catch (\RuntimeException $error) {
                $this->assertStringContainsString('UAT', $error->getMessage());
            } finally { app()->instance('env', 'testing'); }
            $this->assertDatabaseCount('properties', 0);
            $this->assertDatabaseCount('platform_settings', $settingsCount);
        }
    }

    public function test_location_fallback_ignores_private_ads_and_partial_city_names(): void
    {
        $user = \App\Models\User::create(['name' => 'UAT', 'email' => 'location@example.invalid', 'password' => 'test-only']);
        foreach ([['draft', 'إب، حي خاص'], ['published', 'شارع إبراهيم، منطقة أخرى']] as [$status, $address]) {
            Property::create(['user_id' => $user->id, 'title' => 'اختبار', 'purpose' => 'rent', 'type' => 'shop', 'price' => 100000,
                'currency' => 'YER', 'address' => $address, 'latitude' => 13.96, 'longitude' => 44.18, 'status' => $status, 'availability_status' => 'available']);
        }
        $this->assertSame([], app(MarketplaceContextService::class)->locations());
        Property::create(['user_id' => $user->id, 'title' => 'اختبار', 'purpose' => 'rent', 'type' => 'shop', 'price' => 100000,
            'currency' => 'YER', 'address' => 'إب، موقع تجريبي', 'latitude' => 13.96, 'longitude' => 44.18, 'status' => 'published', 'availability_status' => 'available']);
        $this->getJson('/api/marketplace/locations')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.label', 'إب');
        $this->assertDatabaseCount('geo_cells', 0);
    }
}
