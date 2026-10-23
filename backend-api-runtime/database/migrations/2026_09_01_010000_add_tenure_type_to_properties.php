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
            $table->string('tenure_type', 16)->nullable()->after('type');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_tenure_type_check CHECK (tenure_type IS NULL OR tenure_type IN ('freehold','waqf'))");
        }
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_tenure_type_check');
        }
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropColumn('tenure_type');
        });
    }
};
