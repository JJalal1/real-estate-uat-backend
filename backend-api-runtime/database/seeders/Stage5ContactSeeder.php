<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class Stage5ContactSeeder extends Seeder
{
    public function run(): void
    {
        if (! Schema::hasColumn('properties', 'contact_phone')
            || ! Schema::hasColumn('properties', 'contact_whatsapp')) {
            return;
        }

        // Stage 5 stores contact details on each listing. The users table does
        // not contain phone/whatsapp columns until the authentication stage.
        DB::table('properties')
            ->whereNull('contact_phone')
            ->update(['contact_phone' => '+967700000000']);

        DB::table('properties')
            ->whereNull('contact_whatsapp')
            ->update(['contact_whatsapp' => '+967700000000']);
    }
}
