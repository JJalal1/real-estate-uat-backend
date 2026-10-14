<?php

namespace Database\Seeders;

use App\Services\UatWave3CleanupService;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/** Append presentation facts once to untouched, explicitly scoped UAT fixtures. */
class UatWave3DesignSeeder extends Seeder
{
    public const MARKER = 'uat.marketplace.wave3.design.seeded';

    public function run(): void
    {
        app(UatWave3CleanupService::class)->guard();
        DB::transaction(function (): void {
            if (DB::connection()->getDriverName() === 'pgsql') DB::select('SELECT pg_advisory_xact_lock(73101404)');
            if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) return;
            $previous = json_decode((string) DB::table('platform_settings')->where('key', UatWave3MarketplaceSeeder::MARKER)->value('value'), true);
            if (! is_array($previous) || ! isset($previous['seeded_at'])) return;
            $seededAt = Carbon::parse($previous['seeded_at']);
            $spotlights = []; $facts = [];
            foreach (['owner' => '+12025550101', 'strong' => '+12025550104', 'office' => '+12025550110', 'new' => '+12025550103'] as $persona => $phone) {
                $userId = DB::table('users')->where('email', 'wave3-'.$persona.'@example.invalid')->where('phone', $phone)->value('id');
                if (! $userId || ! DB::table('account_verification_profiles')->where('user_id', $userId)->where('details->uat_fixture', true)->exists()) continue;
                $rows = DB::table('properties')->where('user_id', $userId)->where('status', 'published')
                    ->where('availability_status', 'available')->where('review_status', 'approved')
                    ->where('updated_at', '<=', $seededAt)->where('address', 'like', 'صنعاء، %')
                    ->whereExists(fn ($q) => $q->selectRaw('1')->from('listing_reviews')->whereColumn('listing_id', 'properties.id')->where('action', 'uat_wave3_fixture'))
                    ->orderBy('id')->limit(8)->get(['id', 'type', 'has_elevator', 'spotlight_until']);
                foreach ($rows as $row) {
                    if ($row->has_elevator === null && in_array($row->type, ['apartment', 'building', 'office'], true)) {
                        DB::table('properties')->where('id', $row->id)->update(['has_elevator' => $persona !== 'new']);
                        $facts[] = $row->id;
                    }
                }
                if ($persona !== 'new') {
                    $row = $rows->first(fn ($row) => $row->spotlight_until === null);
                    if ($row) { DB::table('properties')->where('id', $row->id)->update(['spotlight_until' => now()->addDays(30)]); $spotlights[] = $row->id; }
                }
            }
            DB::table('platform_settings')->insert(['key' => self::MARKER, 'value' => json_encode([
                'seeded_at' => now()->toIso8601String(), 'spotlight_property_ids' => $spotlights, 'elevator_property_ids' => $facts,
                'scope' => 'fictional UAT presentation only; no plans, prices, reviews, financial or account changes',
            ], JSON_UNESCAPED_UNICODE), 'label_ar' => 'تجهيز عرض الموجة الثالثة التجريبي',
                'type' => 'json', 'group' => 'uat', 'is_public' => false, 'created_at' => now(), 'updated_at' => now()]);
        });
    }
}
