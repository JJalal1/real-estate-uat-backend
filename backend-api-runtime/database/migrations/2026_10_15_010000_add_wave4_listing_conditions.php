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
            $table->unsignedSmallInteger('listing_input_version')->default(1);
            $table->json('rental_conditions')->nullable();
        });
        // Append a new consent state; immutable term/history triggers stay enabled.
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE property_sai_terms DROP CONSTRAINT property_sai_terms_status_check');
            DB::statement("ALTER TABLE property_sai_terms ADD CONSTRAINT property_sai_terms_status_check CHECK (platform_terms_status IN ('not_required','accepted','rejected','pending'))");
        }
    }

    public function down(): void
    {
        if (DB::table('property_sai_terms')->where('platform_terms_status', 'pending')->exists()
            || DB::table('properties')->where('listing_input_version', 6)->exists()) {
            throw new RuntimeException('Wave4 records exist; rollback must preserve their terms and conditions.');
        }
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE property_sai_terms DROP CONSTRAINT property_sai_terms_status_check');
            DB::statement("ALTER TABLE property_sai_terms ADD CONSTRAINT property_sai_terms_status_check CHECK (platform_terms_status IN ('not_required','accepted','rejected'))");
        }
        Schema::table('properties', fn (Blueprint $table) => $table->dropColumn(['listing_input_version', 'rental_conditions']));
    }
};
