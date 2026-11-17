<?php

namespace Database\Seeders;

use App\Models\AccountVerificationProfile;
use App\Models\PropertyImage;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\PropertyDiscoveryFilterService;
use App\Services\YemenGovernorateCatalog;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/** Additive, one-shot fictional ads explicitly requested November 17. */
class UatPhase04RegionalSeeder extends UatCityDemoSeeder
{
    public const MARKER = 'uat.phase04.regional-fixtures.20261117.v1';

    public const RUN = '20261117-regional-v1';

    protected function fixtureReviewAction(): string
    {
        return 'uat_phase04_regional_fixture';
    }

    public function run(): void
    {
        if (! app()->environment('uat', 'staging', 'testing') || config('services.uat_phase04.regional_run') !== self::RUN) {
            throw new RuntimeException('Regional fixtures require the explicit UAT-only run ID.');
        }
        if (! app()->environment('testing') && (parse_url((string) config('services.supabase_storage.url'), PHP_URL_HOST) !== 'ipxsgxsqzthpgthwvdno.supabase.co'
            || parse_url((string) config('app.url'), PHP_URL_HOST) !== 'real-estate-uat-api-frankfurt.onrender.com')) {
            throw new RuntimeException('Regional fixtures are limited to the approved Frankfurt UAT.');
        }
        if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) {
            return;
        }
        $this->publicPaths = [];
        $this->privatePaths = [];
        try {
            DB::transaction(function (): void {
                if (DB::getDriverName() === 'pgsql') {
                    DB::select('SELECT pg_advisory_xact_lock(74111760)');
                }
                if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) {
                    return;
                }
                $actors = [];
                foreach (['wave3-strong@example.invalid', 'wave3-office@example.invalid'] as $email) {
                    $actor = User::query()->where('email', $email)->where('account_status', 'active')->first();
                    if (! $actor || ! AccountVerificationProfile::query()->where('user_id', $actor->id)->whereIn('type', ['broker', 'office'])
                        ->where('status', 'approved')->where('details->uat_fixture', true)->exists()) {
                        throw new RuntimeException('Approved fictional advertisers are required; accounts will not be changed.');
                    }
                    if (DB::table('property_platform_receivables')->where('advertiser_user_id', $actor->id)
                        ->whereIn('status', ['open', 'under_review', 'overdue', 'disputed'])->whereColumn('amount_paid', '<', 'amount_total')->where('due_at', '<=', now())->exists()) {
                        throw new RuntimeException('Existing advertiser finance must be preserved.');
                    }
                    $actors[] = $actor;
                }
                $catalog = app(YemenGovernorateCatalog::class);
                $cities = [['SANAA', 'صنعاء', 15.46, 44.36], ['DHAMAR', 'ذمار', 14.55, 44.4], ['IBB', 'إب', 13.9667, 44.1833]];
                $types = ['apartment' => 'شقة', 'house' => 'منزل', 'villa' => 'فيلا', 'building' => 'عمارة', 'land' => 'أرض', 'farm' => 'مزرعة', 'shop' => 'محل', 'office' => 'مكتب'];
                $ids = [];
                $byGovernorate = [];
                foreach ($cities as $cityIndex => [$code, $city, $lat, $lon]) {
                    if (! DB::table('governorates')->where('code', $code)->where('is_active', true)->exists()) {
                        throw new RuntimeException('A requested governorate is not active.');
                    }
                    for ($i = 0; $i < 20; $i++) {
                        $type = array_keys($types)[$i % 8];
                        $purpose = ($i + $cityIndex + intdiv($i, 8)) % 2 === 0 ? 'rent' : 'sale';
                        $baseLat = $lat + (intdiv($i, 5) - 1.5) * .006;
                        $baseLon = $lon + ($i % 5 - 2) * .006;
                        // Parent builder adds its own small offsets; validate the actual point first.
                        $actualLat = $baseLat + ($i % 8 - 3) * .0035;
                        $actualLon = $baseLon + ($i % 8 % 3 - 1) * .004;
                        if ($catalog->locate($actualLat, $actualLon, 5)['code'] !== $code) {
                            throw new RuntimeException('A fictional fixture point is outside its declared governorate.');
                        }
                        $property = $this->listing($actors[$i % count($actors)], $city, $cityIndex, $baseLat, $baseLon, $type, $types[$type], $purpose, $i % 8, ['title' => $types[$type].' '.($purpose === 'rent' ? 'للإيجار' : 'للبيع').' في '.$city.' — تجريبي '.str_pad((string) ($i + 1), 2, '0', STR_PAD_LEFT),
                            'address' => $city.'، منطقة تجريبية '.(intdiv($i, 5) + 1).'، شارع افتراضي '.($i % 5 + 1),
                            'description' => 'إعلان وهمي تجريبي في '.$city.' لا يمثل عرضًا حقيقيًا. الأسعار والمواصفات للاختبار ولا توجد معاملة مالية فعلية. الصور توضيحية وليست صور مبنى حقيقي، والعنوان والنقطة افتراضيان داخل المحافظة. معرّف الدفعة: '.self::RUN.'.']);
                        $photos = match ($type) {
                            'apartment' => ['building', 'villa'], 'house', 'villa' => ['apartment', 'building'],
                            'land', 'farm' => ['villa', 'building'], 'shop' => ['office', 'building'],
                            default => ['apartment', 'shop'],
                        };
                        foreach ($photos as $j => $photo) {
                            $path = app(CloudAssetStorageService::class)->storePublic(new UploadedFile(resource_path('uat-wave3/images/'.$photo.'.jpg'), $photo.'.jpg', 'image/jpeg', null, true), 'uat-phase04/listings/'.$property->id);
                            $this->publicPaths[] = $path;
                            PropertyImage::create(['property_id' => $property->id, 'path' => $path, 'sort_order' => $j + 1, 'is_primary' => false]);
                        }
                        $ids[] = $property->id;
                        $byGovernorate[$code][] = $property->id;
                    }
                }
                if (app(PropertyDiscoveryFilterService::class)->publicQuery()->whereIn('id', $ids)->count() !== 60
                    || DB::table('property_images')->whereIn('property_id', $ids)->count() !== 180) {
                    throw new RuntimeException('The 60 fixtures did not pass the normal public/media boundary.');
                }
                DB::table('platform_settings')->insert(['key' => self::MARKER, 'value' => json_encode([
                    'run' => self::RUN, 'seeded_at' => now()->toIso8601String(), 'property_ids' => $ids, 'by_governorate' => $byGovernorate,
                    'fictional' => true, 'additive_only' => true, 'images_per_listing' => 3,
                ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), 'value_type' => 'json', 'group_key' => 'uat',
                    'label_ar' => 'دفعة الرابعة: 60 إعلانًا وهميًا و180 صورة توضيحية', 'is_public' => false, 'created_at' => now(), 'updated_at' => now()]);
            });
        } catch (\Throwable $error) {
            foreach ($this->publicPaths as $path) {
                app(CloudAssetStorageService::class)->deletePublic($path);
            }
            foreach ($this->privatePaths as $path) {
                app(CloudAssetStorageService::class)->deletePrivate($path);
            }
            throw $error;
        }
        $this->command?->info('AQER_PHASE04_REGIONAL: added 60 fictional listings, 20 per governorate, with 3 images each.');
    }
}
