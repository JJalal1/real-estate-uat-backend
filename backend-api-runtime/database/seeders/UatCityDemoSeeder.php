<?php

namespace Database\Seeders;

use App\Models\AccountVerificationProfile;
use App\Models\Governorate;
use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\DynamicPropertySchema;
use App\Services\PropertyDiscoveryFilterService;
use App\Services\PropertyIdentityService;
use App\Services\PropertySaiService;
use Illuminate\Database\Seeder;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/** Additive fictional listings requested by the owner on 2026-10-18. */
class UatCityDemoSeeder extends Seeder
{
    public const MARKER = 'uat.marketplace.city-demo.20261018.v1';
    private array $publicPaths = [];
    private array $privatePaths = [];

    public function run(): void
    {
        if (! app()->environment('uat', 'staging', 'testing') || ! config('services.uat_city_demo.enabled')) {
            throw new RuntimeException('City demo seeding requires an explicit UAT-only opt-in.');
        }
        if (! app()->environment('testing') && parse_url((string) config('services.supabase_storage.url'), PHP_URL_HOST) !== 'ipxsgxsqzthpgthwvdno.supabase.co') {
            throw new RuntimeException('City demo seeding is limited to the approved Frankfurt UAT project.');
        }
        if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) return;
        $this->publicPaths = []; $this->privatePaths = [];
        try {
            DB::transaction(function (): void {
                if (DB::getDriverName() === 'pgsql') DB::select('SELECT pg_advisory_xact_lock(73101824)');
                if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) return;
                $actors = [];
                foreach (['wave3-strong@example.invalid', 'wave3-office@example.invalid'] as $email) {
                    $actor = User::query()->where('email', $email)->where('account_status', 'active')->first();
                    if (! $actor || ! AccountVerificationProfile::query()->where('user_id', $actor->id)
                        ->whereIn('type', ['broker', 'office'])->where('status', 'approved')->where('details->uat_fixture', true)->exists()) {
                        throw new RuntimeException('Approved fictional city-demo advertisers are missing; no accounts will be changed.');
                    }
                    if (DB::table('property_platform_receivables')->where('advertiser_user_id', $actor->id)
                        ->whereIn('status', ['open', 'under_review', 'overdue', 'disputed'])->whereColumn('amount_paid', '<', 'amount_total')->where('due_at', '<=', now())->exists()) {
                        throw new RuntimeException('A city-demo advertiser has an outstanding due; existing finance must be preserved.');
                    }
                    $actors[] = $actor;
                }
                $cities = [['صنعاء', 15.3694, 44.1910], ['ذمار', 14.5500, 44.4000], ['إب', 13.9667, 44.1833]];
                $types = ['apartment' => 'شقة', 'house' => 'منزل', 'villa' => 'فيلا', 'building' => 'عمارة',
                    'land' => 'أرض', 'farm' => 'مزرعة', 'shop' => 'محل', 'office' => 'مكتب'];
                $ids = [];
                foreach ($cities as $cityIndex => [$city, $lat, $lon]) {
                    if (! Governorate::query()->where('name_ar', $city)->where('is_active', true)->exists()) {
                        throw new RuntimeException('An approved city is not active; coverage will not be changed.');
                    }
                    foreach (array_keys($types) as $i => $type) {
                        $purpose = ($i + $cityIndex) % 2 === 0 ? 'rent' : 'sale';
                        $ids[] = $this->listing($actors[$i % count($actors)], $city, $cityIndex, $lat, $lon, $type, $types[$type], $purpose, $i)->id;
                    }
                }
                if (app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids)->count() !== 24) {
                    throw new RuntimeException('City demo listings did not pass the normal public discovery boundary.');
                }
                DB::table('platform_settings')->insert(['key' => self::MARKER, 'value' => json_encode([
                    'seeded_at' => now()->toIso8601String(), 'cities' => array_column($cities, 0), 'property_ids' => $ids,
                    'fictional' => true, 'additive_only' => true,
                ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), 'value_type' => 'json', 'group_key' => 'uat',
                    'label_ar' => 'إعلانات تجريبية لصنعاء وذمار وإب', 'is_public' => false, 'created_at' => now(), 'updated_at' => now()]);
            });
        } catch (\Throwable $error) {
            foreach ($this->publicPaths as $path) app(CloudAssetStorageService::class)->deletePublic($path);
            foreach ($this->privatePaths as $path) app(CloudAssetStorageService::class)->deletePrivate($path);
            throw $error;
        }
        $this->command?->info('Added 24 fictional city listings, eight per city; no existing records were reset.');
    }

    private function listing(User $actor, string $city, int $cityIndex, float $lat, float $lon, string $type, string $label, string $purpose, int $i): Property
    {
        $monthly = [110000, 220000, 390000, 950000, 65000, 100000, 120000, 90000][$i] + $cityIndex * 10000;
        $sale = [48000000, 85000000, 165000000, 270000000, 22000000, 39000000, 30000000, 36000000][$i] + $cityIndex * 500000;
        $residential = in_array($type, ['apartment', 'house', 'villa'], true);
        $data = ['listing_input_version' => 8, 'title' => $label.' '.($purpose === 'rent' ? 'للإيجار' : 'للبيع').' في '.$city.' — تجريبي',
            'description' => 'إعلان وهمي تجريبي في '.$city.' لا يمثل عرضًا حقيقيًا. الأسعار والموقع والمواصفات والصور أمثلة لاختبار التصفح والبحث والخريطة، ولا توجد معاملة مالية فعلية.',
            'type' => $type, 'purpose' => $purpose, 'tenure_type' => $purpose === 'sale' ? 'freehold' : null,
            'price' => $purpose === 'rent' ? $monthly * 3 : $sale, 'monthly_rent' => $purpose === 'rent' ? $monthly : null,
            'rental_term_months' => $purpose === 'rent' ? 12 : null, 'advance_months' => $purpose === 'rent' ? 3 : null,
            'currency' => 'YER', 'area_value' => $type === 'farm' ? 2400 : ($type === 'land' ? 400 : 100 + $i * 35), 'area_unit' => 'sqm',
            'bedrooms' => $residential ? 3 + $cityIndex % 2 : null, 'bathrooms' => $residential ? 2 : null,
            'floor_number' => in_array($type, ['apartment', 'office'], true) ? (string) ($cityIndex === 2 ? 7 : $cityIndex) : null,
            'unit_number' => in_array($type, ['apartment', 'office', 'shop'], true) ? 'تجريبي-'.($i + 1) : null,
            'has_parking' => in_array($type, ['house', 'villa', 'building'], true), 'building_facade' => in_array($type, ['land', 'farm'], true) ? null : 'south',
            'has_elevator' => $type === 'apartment' && $cityIndex === 2,
            'address' => $city.'، حي تجريبي '.($i + 1).'، موقع تقريبي للاختبار',
            'latitude' => $lat + ($i - 3) * 0.0035, 'longitude' => $lon + ($i % 3 - 1) * 0.004,
            'contact_phone' => $actor->phone, 'contact_whatsapp' => $actor->phone,
            'ownership_document_type' => 'purchase_deed', 'document_owner_name' => 'مالك وهمي للاختبار '.($cityIndex + 1).'-'.($i + 1),
            'owner_relationship_type' => 'agent'];
        $schema = app(DynamicPropertySchema::class);
        $data = $schema->facts($data, true);
        $data = $schema->validateApartmentFloor($data);
        $data['area_m2'] = isset($data['area_value']) ? (int) round($data['area_value']) : null;
        $identity = app(PropertyIdentityService::class);
        $identity->validateIdentityInput($data);
        $asset = $identity->resolveOrCreateAsset($actor, $data);
        $property = Property::create($data + ['user_id' => $actor->id, 'property_asset_id' => $asset->id, 'status' => 'draft', 'review_status' => 'draft']);
        $photo = ['house' => 'villa', 'farm' => 'land'][$type] ?? $type;
        $path = app(CloudAssetStorageService::class)->storePublic(new UploadedFile(resource_path('uat-wave3/images/'.$photo.'.jpg'), $photo.'.jpg', 'image/jpeg', null, true), 'uat-city-demo/listings/'.$property->id);
        $this->publicPaths[] = $path;
        PropertyImage::create(['property_id' => $property->id, 'path' => $path, 'sort_order' => 0, 'is_primary' => true]);
        $this->proof($actor, $property);
        app(PropertySaiService::class)->configure($actor, $property, $purpose === 'rent' ? 'tenant' : 'buyer', null, 'accept',
            Request::create('/uat/city-demo/fixtures', 'POST'), false, 'fixed', $purpose === 'rent' ? round($monthly * 0.5, 2) : round($sale * 0.02, 2));
        $property->refresh()->forceFill(['status' => 'published', 'review_status' => 'approved', 'submitted_at' => now(), 'reviewed_at' => now(), 'published_at' => now(),
            'availability_status' => 'available', 'availability_confirmed_at' => now(), 'availability_due_at' => now()->addDays($purpose === 'rent' ? 7 : 14)])->save();
        $identity->ensureRepresentation($property);
        DB::table('listing_reviews')->insert(['listing_id' => $property->id, 'action' => 'uat_city_demo_fixture', 'actor_name_snapshot' => 'UAT fictional fixture setup',
            'from_review_status' => 'draft', 'to_review_status' => 'approved', 'reason' => 'Owner-requested fictional UAT fixture; not a human or production review.',
            'listing_snapshot' => json_encode(['id' => $property->id, 'title' => $property->title]), 'metadata' => json_encode(['uat_city_demo' => true]), 'created_at' => now()]);
        if (DB::getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        return $property;
    }

    private function proof(User $actor, Property $property): void
    {
        $image = imagecreatetruecolor(720, 200);
        imagefilledrectangle($image, 0, 0, 719, 199, imagecolorallocate($image, 238, 242, 245));
        imagestring($image, 5, 25, 60, 'FICTIONAL UAT CITY DEMO - NOT A LEGAL DOCUMENT', imagecolorallocate($image, 35, 45, 60));
        $temp = tempnam(sys_get_temp_dir(), 'uat-city-demo-');
        try {
            imagepng($image, $temp);
            $path = app(CloudAssetStorageService::class)->storePrivate(new UploadedFile($temp, 'fictional-uat-proof.png', 'image/png', null, true), 'uat-city-demo/proofs/'.$property->id);
            $this->privatePaths[] = $path;
            $property->documents()->create(['uploaded_by_user_id' => $actor->id, 'kind' => 'ownership_or_authorization', 'path' => $path,
                'original_name' => 'FICTIONAL-UAT-NOT-A-LEGAL-DOCUMENT.png', 'mime_type' => 'image/png', 'size_bytes' => filesize($temp), 'created_at' => now()]);
        } finally { imagedestroy($image); if (is_file($temp)) unlink($temp); }
    }
}
