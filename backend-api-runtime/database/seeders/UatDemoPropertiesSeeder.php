<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use RuntimeException;

class UatDemoPropertiesSeeder extends Seeder
{
    public function run(): void
    {
        if (! app()->environment('uat', 'staging', 'testing')) {
            throw new RuntimeException('UAT demo properties may run only in uat/staging/testing.');
        }
        if (! Schema::hasTable('properties') || ! Schema::hasTable('property_assets')) {
            throw new RuntimeException('UAT property tables are not migrated.');
        }

        $owner = DB::table('users')->where('phone', '+12025550101')->first();
        if (! $owner) {
            throw new RuntimeException('UAT regular owner account is missing. Run UatTestAccountsSeeder first.');
        }

        $now = now();
        $columns = array_flip(Schema::getColumnListing('properties'));
        $rows = [
            [
                'title' => '[UAT] شقة للإيجار في صنعاء',
                'description' => 'عقار تجريبي للمحاكاة متعددة الجوالات.',
                'purpose' => 'rent',
                'type' => 'apartment',
                'price' => 180000,
                'currency' => 'YER',
                'area_m2' => 120,
                'bedrooms' => 3,
                'bathrooms' => 2,
                'address' => 'حدة، صنعاء',
                'latitude' => 15.3694000,
                'longitude' => 44.1910000,
            ],
            [
                'title' => '[UAT] منزل للبيع في صنعاء',
                'description' => 'منزل تجريبي لاختبار المراجعة والحجز والتواصل.',
                'purpose' => 'sale',
                'type' => 'house',
                'price' => 42000000,
                'currency' => 'YER',
                'area_m2' => 260,
                'bedrooms' => 5,
                'bathrooms' => 3,
                'address' => 'السنينة، صنعاء',
                'latitude' => 15.3555000,
                'longitude' => 44.1762000,
            ],
            [
                'title' => '[UAT] أرض سكنية للبيع',
                'description' => 'أرض تجريبية لاختبار الخريطة ومنع التكرار.',
                'purpose' => 'sale',
                'type' => 'land',
                'price' => 25000000,
                'currency' => 'YER',
                'area_m2' => 450,
                'bedrooms' => null,
                'bathrooms' => null,
                'address' => 'شارع تعز، صنعاء',
                'latitude' => 15.3820000,
                'longitude' => 44.2050000,
            ],
            [
                'title' => '[UAT] فيلا للإيجار الشهري',
                'description' => 'فيلا تجريبية لاختبار العرض من عدة أجهزة.',
                'purpose' => 'rent',
                'type' => 'villa',
                'price' => 600000,
                'currency' => 'YER',
                'area_m2' => 300,
                'bedrooms' => 4,
                'bathrooms' => 4,
                'address' => 'بيت بوس، صنعاء',
                'latitude' => 15.3470000,
                'longitude' => 44.2000000,
            ],
        ];

        DB::transaction(function () use ($owner, $now, $columns, $rows): void {
            foreach ($rows as $row) {
                $normalizedAddress = Str::lower(trim(preg_replace('/\s+/u', ' ', $row['address']) ?? ''));
                $identityHash = hash('sha256', implode('|', [
                    'v1',
                    Str::lower($row['type']),
                    number_format((float) $row['latitude'], 6, '.', ''),
                    number_format((float) $row['longitude'], 6, '.', ''),
                    (string) ($row['area_m2'] ?? ''),
                    (string) ($row['bedrooms'] ?? ''),
                    (string) ($row['bathrooms'] ?? ''),
                    $normalizedAddress,
                ]));

                DB::table('property_assets')->updateOrInsert(
                    ['identity_hash' => $identityHash],
                    [
                        'created_by_user_id' => $owner->id,
                        'identity_version' => 1,
                        'property_type' => $row['type'],
                        'canonical_address' => $row['address'],
                        'canonical_latitude' => $row['latitude'],
                        'canonical_longitude' => $row['longitude'],
                        'area_m2' => $row['area_m2'],
                        'bedrooms' => $row['bedrooms'],
                        'bathrooms' => $row['bathrooms'],
                        'identity_notes' => 'UAT demo property',
                        'status' => 'active',
                        'created_at' => $now,
                        'updated_at' => $now,
                    ],
                );
                $assetId = DB::table('property_assets')->where('identity_hash', $identityHash)->value('id');

                $data = $row + [
                    'user_id' => $owner->id,
                    'property_asset_id' => $assetId,
                    'status' => 'published',
                    'review_status' => 'approved',
                    'submitted_at' => $now->copy()->subHour(),
                    'published_at' => $now,
                    'reviewed_at' => $now,
                    'last_review_reason' => null,
                    'contact_phone' => $owner->phone,
                    'contact_whatsapp' => $owner->phone,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
                $data = array_intersect_key($data, $columns);

                DB::table('properties')->updateOrInsert(['title' => $row['title']], $data);
                $propertyId = DB::table('properties')->where('title', $row['title'])->value('id');

                if (Schema::hasTable('listing_reviews')
                    && $propertyId
                    && ! DB::table('listing_reviews')->where([
                        'listing_id' => $propertyId,
                        'action' => 'uat_seed_approved',
                    ])->exists()) {
                    DB::table('listing_reviews')->insert([
                        'listing_id' => $propertyId,
                        'actor_user_id' => null,
                        'actor_name_snapshot' => 'UAT Seeder',
                        'action' => 'uat_seed_approved',
                        'from_review_status' => 'submitted',
                        'to_review_status' => 'approved',
                        'reason' => 'UAT demo listing seeded as published.',
                        'listing_snapshot' => json_encode([
                            'id' => $propertyId,
                            'title' => $row['title'],
                            'status' => 'published',
                            'review_status' => 'approved',
                        ], JSON_UNESCAPED_UNICODE),
                        'metadata' => json_encode(['uat_seed' => true]),
                        'created_at' => $now,
                    ]);
                }
            }

            if (DB::connection()->getDriverName() === 'pgsql') {
                DB::statement("UPDATE properties SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography WHERE title LIKE '[UAT]%' AND latitude IS NOT NULL AND longitude IS NOT NULL");
            }
        });

        if ($this->command) {
            $this->command->info('UAT demo properties seeded: '.count($rows));
        }
    }
}
