<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;

class PropertySeeder extends Seeder
{
    public function run(): void
    {
        DB::transaction(function (): void {
            $now = now();
            $email = 'demo-advertiser@example.test';

            $requiredColumns = [
                'id', 'user_id', 'title', 'purpose', 'type', 'price',
                'currency', 'status', 'latitude', 'longitude', 'location',
                'created_at', 'updated_at',
            ];

            $columns = Schema::getColumnListing('properties');
            $missing = array_values(array_diff($requiredColumns, $columns));

            if ($missing !== []) {
                throw new \RuntimeException(
                    'Required properties columns are missing: ' . implode(', ', $missing)
                );
            }

            $allowedPropertyColumns = array_flip($columns);

            DB::table('users')->updateOrInsert(
                ['email' => $email],
                [
                    'name' => "\u{645}\u{639}\u{644}\u{646} \u{62A}\u{62C}\u{631}\u{64A}\u{628}\u{64A}",
                    'password' => Hash::make('Demo1234!'),
                    'email_verified_at' => $now,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]
            );

            $userId = DB::table('users')->where('email', $email)->value('id');

            if (!$userId) {
                throw new \RuntimeException('Demo advertiser user could not be created.');
            }

            $rows = [
            [
                'title' => "\u{634}\u{642}\u{629} \u{644}\u{644}\u{625}\u{64A}\u{62C}\u{627}\u{631} \u{641}\u{64A} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'description' => "\u{634}\u{642}\u{629} \u{62A}\u{62C}\u{631}\u{64A}\u{628}\u{64A}\u{629} \u{642}\u{631}\u{64A}\u{628}\u{629} \u{645}\u{646} \u{645}\u{631}\u{643}\u{632} \u{635}\u{646}\u{639}\u{627}\u{621}.",
                'purpose' => 'rent',
                'type' => 'apartment',
                'price' => 180000,
                'currency' => 'YER',
                'area_m2' => 120,
                'bedrooms' => 3,
                'bathrooms' => 2,
                'address' => "\u{62D}\u{62F}\u{629}\u{60C} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'latitude' => 15.3694000,
                'longitude' => 44.1910000,
            ],
            [
                'title' => "\u{645}\u{646}\u{632}\u{644} \u{644}\u{644}\u{628}\u{64A}\u{639} \u{641}\u{64A} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'description' => "\u{645}\u{646}\u{632}\u{644} \u{62A}\u{62C}\u{631}\u{64A}\u{628}\u{64A} \u{645}\u{639} \u{645}\u{648}\u{642}\u{639} \u{645}\u{62D}\u{641}\u{648}\u{638} \u{641}\u{64A} PostGIS.",
                'purpose' => 'sale',
                'type' => 'house',
                'price' => 42000000,
                'currency' => 'YER',
                'area_m2' => 260,
                'bedrooms' => 5,
                'bathrooms' => 3,
                'address' => "\u{627}\u{644}\u{633}\u{646}\u{64A}\u{646}\u{629}\u{60C} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'latitude' => 15.3555000,
                'longitude' => 44.1762000,
            ],
            [
                'title' => "\u{623}\u{631}\u{636} \u{633}\u{643}\u{646}\u{64A}\u{629} \u{644}\u{644}\u{628}\u{64A}\u{639}",
                'description' => "\u{623}\u{631}\u{636} \u{633}\u{643}\u{646}\u{64A}\u{629} \u{62A}\u{62C}\u{631}\u{64A}\u{628}\u{64A}\u{629}.",
                'purpose' => 'sale',
                'type' => 'land',
                'price' => 25000000,
                'currency' => 'YER',
                'area_m2' => 450,
                'bedrooms' => null,
                'bathrooms' => null,
                'address' => "\u{634}\u{627}\u{631}\u{639} \u{62A}\u{639}\u{632}\u{60C} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'latitude' => 15.3820000,
                'longitude' => 44.2050000,
            ],
            [
                'title' => "\u{641}\u{64A}\u{644}\u{627} \u{644}\u{644}\u{625}\u{64A}\u{62C}\u{627}\u{631} \u{627}\u{644}\u{634}\u{647}\u{631}\u{64A}",
                'description' => "\u{641}\u{64A}\u{644}\u{627} \u{62A}\u{62C}\u{631}\u{64A}\u{628}\u{64A}\u{629} \u{644}\u{644}\u{625}\u{64A}\u{62C}\u{627}\u{631}.",
                'purpose' => 'rent',
                'type' => 'villa',
                'price' => 600000,
                'currency' => 'YER',
                'area_m2' => 300,
                'bedrooms' => 4,
                'bathrooms' => 4,
                'address' => "\u{628}\u{64A}\u{62A} \u{628}\u{648}\u{633}\u{60C} \u{635}\u{646}\u{639}\u{627}\u{621}",
                'latitude' => 15.3470000,
                'longitude' => 44.2000000,
            ]
            ];

            foreach ($rows as $row) {
                $data = $row + [
                    'user_id' => $userId,
                    'status' => 'published',
                    'created_at' => $now,
                    'updated_at' => $now,
                ];

                // Only send columns that actually exist in PostgreSQL.
                // The previous failure came from trying to insert a non-existent "floor" column.
                $data = array_intersect_key($data, $allowedPropertyColumns);

                DB::table('properties')->updateOrInsert(
                    ['title' => $row['title']],
                    $data
                );
            }

            DB::statement(
                'UPDATE properties
                 SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
                 WHERE latitude IS NOT NULL AND longitude IS NOT NULL'
            );
        });
    }
}
