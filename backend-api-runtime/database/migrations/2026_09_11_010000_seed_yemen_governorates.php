<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('governorates')) return;

        $now = now();
        $rows = [
            ['code' => 'AMANAT_AL_ASIMAH', 'name_ar' => 'أمانة العاصمة', 'name_en' => 'Amanat Al Asimah'],
            ['code' => 'SANAA', 'name_ar' => 'صنعاء', 'name_en' => 'Sanaa'],
            ['code' => 'ADEN', 'name_ar' => 'عدن', 'name_en' => 'Aden'],
            ['code' => 'TAIZ', 'name_ar' => 'تعز', 'name_en' => 'Taiz'],
            ['code' => 'HODEIDAH', 'name_ar' => 'الحديدة', 'name_en' => 'Al Hudaydah'],
            ['code' => 'IBB', 'name_ar' => 'إب', 'name_en' => 'Ibb'],
            ['code' => 'DHAMAR', 'name_ar' => 'ذمار', 'name_en' => 'Dhamar'],
            ['code' => 'HADRAMOUT', 'name_ar' => 'حضرموت', 'name_en' => 'Hadramout'],
            ['code' => 'HAJJAH', 'name_ar' => 'حجة', 'name_en' => 'Hajjah'],
            ['code' => 'SAADAH', 'name_ar' => 'صعدة', 'name_en' => 'Saada'],
            ['code' => 'AMRAN', 'name_ar' => 'عمران', 'name_en' => 'Amran'],
            ['code' => 'AL_JAWF', 'name_ar' => 'الجوف', 'name_en' => 'Al Jawf'],
            ['code' => 'MARIB', 'name_ar' => 'مأرب', 'name_en' => 'Marib'],
            ['code' => 'AL_MAHWIT', 'name_ar' => 'المحويت', 'name_en' => 'Al Mahwit'],
            ['code' => 'RAYMAH', 'name_ar' => 'ريمة', 'name_en' => 'Raymah'],
            ['code' => 'SHABWAH', 'name_ar' => 'شبوة', 'name_en' => 'Shabwah'],
            ['code' => 'LAHJ', 'name_ar' => 'لحج', 'name_en' => 'Lahj'],
            ['code' => 'ABYAN', 'name_ar' => 'أبين', 'name_en' => 'Abyan'],
            ['code' => 'AL_DALEA', 'name_ar' => 'الضالع', 'name_en' => 'Ad Dali'],
            ['code' => 'AL_BAYDA', 'name_ar' => 'البيضاء', 'name_en' => 'Al Bayda'],
            ['code' => 'AL_MAHRAH', 'name_ar' => 'المهرة', 'name_en' => 'Al Mahrah'],
            ['code' => 'SOCOTRA', 'name_ar' => 'أرخبيل سقطرى', 'name_en' => 'Socotra'],
        ];

        foreach ($rows as $row) {
            DB::table('governorates')->updateOrInsert(
                ['code' => $row['code']],
                $row + ['is_active' => true, 'created_at' => $now, 'updated_at' => $now],
            );
        }
    }

    public function down(): void
    {
        // Non-destructive: governorates may already be referenced by operational data.
    }
};
