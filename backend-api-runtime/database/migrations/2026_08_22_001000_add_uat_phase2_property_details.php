<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            if (! Schema::hasColumn('properties', 'area_value')) {
                $table->decimal('area_value', 12, 2)->nullable()->after('area_m2');
            }
            if (! Schema::hasColumn('properties', 'area_unit')) {
                $table->string('area_unit', 40)->nullable()->after('area_value');
            }
            if (! Schema::hasColumn('properties', 'has_parking')) {
                $table->boolean('has_parking')->nullable()->after('bathrooms');
            }
            if (! Schema::hasColumn('properties', 'building_facade')) {
                $table->string('building_facade', 30)->nullable()->after('has_parking');
            }
        });

        DB::table('properties')
            ->whereNotNull('area_m2')
            ->whereNull('area_value')
            ->update([
                'area_value' => DB::raw('area_m2'),
                'area_unit' => 'sqm',
            ]);

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_phase2_area_value_positive CHECK (area_value IS NULL OR area_value > 0)");
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_phase2_area_unit_valid CHECK (area_unit IS NULL OR area_unit IN ('sqm','libna_sanaani','libna_dhamari','qasaba_taizi_ashari','qasaba_taizi_hadawi','qasaba_ibbi'))");
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_phase2_building_facade_valid CHECK (building_facade IS NULL OR building_facade IN ('north','south','east','west','northeast','northwest','southeast','southwest','multiple'))");
        }
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_phase2_building_facade_valid');
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_phase2_area_unit_valid');
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_phase2_area_value_positive');
        }

        Schema::table('properties', function (Blueprint $table): void {
            $columns = [];
            foreach (['building_facade', 'has_parking', 'area_unit', 'area_value'] as $column) {
                if (Schema::hasColumn('properties', $column)) {
                    $columns[] = $column;
                }
            }
            if ($columns !== []) {
                $table->dropColumn($columns);
            }
        });
    }
};
