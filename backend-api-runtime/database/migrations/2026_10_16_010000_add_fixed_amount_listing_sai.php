<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('property_sai_terms', function (Blueprint $table): void {
            $table->string('sai_amount_type', 16)->default('percentage');
            $table->decimal('fixed_sai_amount', 16, 2)->nullable();
            $table->string('fixed_sai_currency', 3)->nullable();
        });

        // Defaults describe old rows without rewriting any immutable version.
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement(<<<'SQL'
ALTER TABLE property_sai_terms ADD CONSTRAINT property_sai_terms_amount_type_check CHECK (
    (sai_amount_type = 'percentage' AND fixed_sai_amount IS NULL AND fixed_sai_currency IS NULL)
    OR
    (sai_amount_type = 'fixed' AND fixed_sai_amount IS NOT NULL AND fixed_sai_amount > 0
        AND fixed_sai_currency IS NOT NULL AND length(fixed_sai_currency) = 3
        AND advertiser_type IN ('broker','office') AND source_mode = 'broker_custom'
        AND requested_broker_rate_percent IS NULL AND sai_rate_percent = 0)
)
SQL);
        }
    }

    public function down(): void
    {
        if (DB::table('property_sai_terms')->where('sai_amount_type', 'fixed')->exists()) {
            throw new RuntimeException('Fixed Sai history exists; use a forward-compatible fix instead of removing it.');
        }
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE property_sai_terms DROP CONSTRAINT property_sai_terms_amount_type_check');
        }
        Schema::table('property_sai_terms', function (Blueprint $table): void {
            $table->dropColumn(['sai_amount_type', 'fixed_sai_amount', 'fixed_sai_currency']);
        });
    }
};
