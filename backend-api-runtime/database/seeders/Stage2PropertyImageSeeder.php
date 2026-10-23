<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class Stage2PropertyImageSeeder extends Seeder
{
    public function run(): void
    {
        if (! Schema::hasTable('properties') || ! Schema::hasTable('property_images')) {
            return;
        }

        $properties = DB::table('properties')
            ->orderBy('id')
            ->limit(4)
            ->get(['id']);

        if ($properties->isEmpty()) {
            return;
        }

        $demoImages = [
            'demo-properties/property-exterior.png',
            'demo-properties/property-interior.png',
            'demo-properties/property-location.png',
        ];

        foreach ($properties as $propertyIndex => $property) {
            foreach ($demoImages as $sortOrder => $path) {
                DB::table('property_images')->updateOrInsert(
                    [
                        'property_id' => $property->id,
                        'path' => $path,
                    ],
                    [
                        'cdn_url' => $path,
                        'sort_order' => $sortOrder,
                        'is_primary' => $sortOrder === 0,
                        'updated_at' => now(),
                        'created_at' => now(),
                    ],
                );
            }
        }
    }
}
