<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class UatDemoSeeder extends Seeder
{
    public function run(): void
    {
        if (config('services.uat_wave3.enabled')) {
            $this->call(UatWave3MarketplaceSeeder::class);
            $this->call(UatWave3DesignSeeder::class);
            return;
        }
        // Once Wave3 has run, legacy fixture accounts must never be recreated.
        if (\Illuminate\Support\Facades\DB::table('platform_settings')->where('key', UatWave3MarketplaceSeeder::MARKER)->exists()) return;
        $this->call([
            UatTestAccountsSeeder::class,
            UatDemoPropertiesSeeder::class,
        ]);
    }
}
