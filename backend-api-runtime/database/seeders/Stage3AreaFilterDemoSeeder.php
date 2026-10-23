<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;

class Stage3AreaFilterDemoSeeder extends Seeder
{
    public function run(): void
    {
        DB::transaction(function (): void {
            $userId = DB::table('users')->orderBy('id')->value('id');

            if (!$userId) {
                throw new RuntimeException('No user exists. Seed/create a user before Stage3AreaFilterDemoSeeder.');
            }

            $areas = [
                ['name' => 'حدة', 'address' => 'شارع حدة، صنعاء', 'lat' => 15.3448, 'lng' => 44.1838],
                ['name' => 'شارع الستين', 'address' => 'شارع الستين، صنعاء', 'lat' => 15.3619, 'lng' => 44.1735],
                ['name' => 'سعوان', 'address' => 'سعوان، صنعاء', 'lat' => 15.3898, 'lng' => 44.2216],
                ['name' => 'بيت بوس', 'address' => 'بيت بوس، صنعاء', 'lat' => 15.3079, 'lng' => 44.1752],
                ['name' => 'شملان', 'address' => 'شملان، صنعاء', 'lat' => 15.4212, 'lng' => 44.1489],
                ['name' => 'مذبح', 'address' => 'مذبح، صنعاء', 'lat' => 15.3796, 'lng' => 44.1667],
                ['name' => 'الروضة', 'address' => 'الروضة، صنعاء', 'lat' => 15.4014, 'lng' => 44.2071],
                ['name' => 'دار سلم', 'address' => 'دار سلم، صنعاء', 'lat' => 15.2814, 'lng' => 44.1934],
                ['name' => 'حزيز', 'address' => 'حزيز، صنعاء', 'lat' => 15.2928, 'lng' => 44.2079],
                ['name' => 'عصر', 'address' => 'عصر، صنعاء', 'lat' => 15.3701, 'lng' => 44.1432],
                ['name' => 'بيت معياد', 'address' => 'بيت معياد، صنعاء', 'lat' => 15.3207, 'lng' => 44.1981],
                ['name' => 'صنعاء القديمة', 'address' => 'صنعاء القديمة، صنعاء', 'lat' => 15.3558, 'lng' => 44.2143],
                ['name' => 'شارع تعز', 'address' => 'شارع تعز، صنعاء', 'lat' => 15.3266, 'lng' => 44.2052],
                ['name' => 'شارع الزبيري', 'address' => 'شارع الزبيري، صنعاء', 'lat' => 15.3547, 'lng' => 44.1968],
                ['name' => 'شارع الجزائر', 'address' => 'شارع الجزائر، صنعاء', 'lat' => 15.3508, 'lng' => 44.1889],
                ['name' => 'شارع الخمسين', 'address' => 'شارع الخمسين، صنعاء', 'lat' => 15.3359, 'lng' => 44.1895],
                ['name' => 'فج عطان', 'address' => 'فج عطان، صنعاء', 'lat' => 15.3528, 'lng' => 44.1546],
                ['name' => 'أرتل', 'address' => 'أرتل، صنعاء', 'lat' => 15.3961, 'lng' => 44.2418],
            ];

            $imagePaths = [
                'demo-properties/property-exterior.png',
                'demo-properties/property-interior.png',
                'demo-properties/property-location.png',
            ];

            foreach ($areas as $index => $area) {
                $n = $index + 1;
                $offset = (($index % 5) - 2) * 0.00085;
                $lat = $area['lat'] + $offset;
                $lng = $area['lng'] - $offset;

                $rows = [
                    [
                        'title' => sprintf('شقة حديثة %s في %s - %02d', $index % 2 === 0 ? 'للإيجار' : 'للبيع', $area['name'], $n),
                        'description' => 'شقة تجريبية حديثة ضمن بيانات العرض، مناسبة لاختبار البحث والفلاتر حسب المنطقة والغرف والمساحة.',
                        'purpose' => $index % 2 === 0 ? 'rent' : 'sale',
                        'type' => 'apartment',
                        'price' => $index % 2 === 0 ? 140000 + ($n * 9000) : 32000000 + ($n * 1250000),
                        'area_m2' => 95 + (($index % 6) * 15),
                        'bedrooms' => 2 + ($index % 4),
                        'bathrooms' => 1 + ($index % 3),
                        'address' => $area['address'],
                        'latitude' => $lat,
                        'longitude' => $lng,
                    ],
                    [
                        'title' => sprintf('%s %s في %s - %02d', $index % 3 === 0 ? 'فيلا' : 'منزل', $index % 2 === 0 ? 'للبيع' : 'للإيجار', $area['name'], $n),
                        'description' => 'عقار عائلي تجريبي بمواصفات متنوعة لاختبار غرف النوم والحمامات والمساحة والسعر.',
                        'purpose' => $index % 2 === 0 ? 'sale' : 'rent',
                        'type' => $index % 3 === 0 ? 'villa' : 'house',
                        'price' => $index % 2 === 0 ? 85000000 + ($n * 4300000) : 280000 + ($n * 17000),
                        'area_m2' => 190 + (($index % 7) * 35),
                        'bedrooms' => 3 + ($index % 4),
                        'bathrooms' => 2 + ($index % 4),
                        'address' => $area['address'],
                        'latitude' => $lat + 0.0011,
                        'longitude' => $lng + 0.0013,
                    ],
                    [
                        'title' => sprintf('أرض سكنية للبيع في %s - %02d', $area['name'], $n),
                        'description' => 'قطعة أرض تجريبية مناسبة لاختبار البحث بالمنطقة وتصفية المساحة والسعر.',
                        'purpose' => 'sale',
                        'type' => 'land',
                        'price' => 42000000 + ($n * 3800000),
                        'area_m2' => 220 + (($index % 8) * 55),
                        'bedrooms' => null,
                        'bathrooms' => null,
                        'address' => $area['address'],
                        'latitude' => $lat - 0.0012,
                        'longitude' => $lng + 0.0010,
                    ],
                    [
                        'title' => sprintf('%s للإيجار في %s - %02d', $index % 2 === 0 ? 'مكتب' : 'محل', $area['name'], $n),
                        'description' => 'وحدة تجارية تجريبية لاختبار البحث باسم الشارع والمنطقة وفلاتر المساحة والسعر.',
                        'purpose' => 'rent',
                        'type' => $index % 2 === 0 ? 'office' : 'shop',
                        'price' => 180000 + ($n * 14000),
                        'area_m2' => 45 + (($index % 6) * 18),
                        'bedrooms' => null,
                        'bathrooms' => 1 + ($index % 2),
                        'address' => $area['address'],
                        'latitude' => $lat + 0.0014,
                        'longitude' => $lng - 0.0011,
                    ],
                ];

                foreach ($rows as $row) {
                    DB::table('properties')->updateOrInsert(
                        ['title' => $row['title']],
                        array_merge($row, [
                            'user_id' => $userId,
                            'currency' => 'YER',
                            'status' => 'published',
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]),
                    );

                    $propertyId = DB::table('properties')
                        ->where('title', $row['title'])
                        ->value('id');

                    DB::statement(
                        'UPDATE properties
                         SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
                         WHERE id = ?',
                        [$propertyId],
                    );

                    if (Schema::hasTable('property_images')) {
                        foreach ($imagePaths as $sortOrder => $path) {
                            DB::table('property_images')->updateOrInsert(
                                [
                                    'property_id' => $propertyId,
                                    'path' => $path,
                                ],
                                [
                                    'cdn_url' => $path,
                                    'sort_order' => $sortOrder,
                                    'is_primary' => $sortOrder === 0,
                                    'created_at' => now(),
                                    'updated_at' => now(),
                                ],
                            );
                        }
                    }
                }
            }
        });
    }
}
