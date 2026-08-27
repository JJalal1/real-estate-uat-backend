<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class UatDemoSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            UatTestAccountsSeeder::class,
            UatDemoPropertiesSeeder::class,
        ]);
    }
}
