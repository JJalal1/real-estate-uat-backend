<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('property_sai_terms', function (Blueprint $table): void {
            $table->id();
            // Keep the listing id as an immutable historical snapshot. Do not
            // cascade/delete term versions when a listing is later removed.
            $table->unsignedBigInteger('property_id')->index();
            $table->unsignedInteger('version');
            $table->string('advertiser_type', 16);
            $table->string('purpose', 16);
            $table->string('source_mode', 24);
            $table->decimal('requested_broker_rate_percent', 5, 2)->nullable();
            $table->decimal('sai_rate_percent', 5, 2);
            $table->string('payer', 16);
            $table->string('calculation_basis', 32);
            $table->decimal('platform_share_percent', 5, 2);
            $table->decimal('broker_share_percent', 5, 2);
            $table->string('platform_terms_status', 16);
            $table->timestamp('platform_terms_accepted_at')->nullable();
            $table->timestamp('platform_terms_rejected_at')->nullable();
            $table->unsignedBigInteger('created_by_user_id')->nullable()->index();
            $table->timestamps();

            $table->unique(['property_id', 'version'], 'property_sai_terms_property_version_unique');
            $table->index(['property_id', 'created_at'], 'property_sai_terms_history_idx');
        });

        Schema::table('properties', function (Blueprint $table): void {
            $table->foreignId('current_sai_term_id')
                ->nullable()
                ->after('property_asset_id')
                ->constrained('property_sai_terms')
                ->restrictOnDelete();
            $table->index('current_sai_term_id', 'properties_current_sai_term_idx');
        });

        Schema::table('message_threads', function (Blueprint $table): void {
            $table->foreignId('sai_term_id')
                ->nullable()
                ->after('property_id')
                ->constrained('property_sai_terms')
                ->restrictOnDelete();
            $table->index('sai_term_id', 'message_threads_sai_term_idx');
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE property_sai_terms ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE property_sai_terms FROM PUBLIC');
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE property_sai_terms FROM anon'; END IF; END $$;");
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE property_sai_terms FROM authenticated'; END IF; END $$;");
            DB::unprepared(<<<'SQL'
ALTER TABLE property_sai_terms
    ADD CONSTRAINT property_sai_terms_advertiser_type_check CHECK (advertiser_type IN ('owner','broker','office')),
    ADD CONSTRAINT property_sai_terms_purpose_check CHECK (purpose IN ('sale','rent')),
    ADD CONSTRAINT property_sai_terms_source_mode_check CHECK (source_mode IN ('owner_fixed','broker_custom','platform_fallback')),
    ADD CONSTRAINT property_sai_terms_payer_check CHECK (
        (purpose = 'sale' AND payer IN ('seller','buyer')) OR
        (purpose = 'rent' AND payer IN ('landlord','tenant'))
    ),
    ADD CONSTRAINT property_sai_terms_rate_check CHECK (
        (purpose = 'sale' AND sai_rate_percent BETWEEN 0 AND 5) OR
        (purpose = 'rent' AND sai_rate_percent BETWEEN 0 AND 100)
    ),
    ADD CONSTRAINT property_sai_terms_share_check CHECK (
        platform_share_percent BETWEEN 0 AND 100 AND
        broker_share_percent BETWEEN 0 AND 100 AND
        platform_share_percent + broker_share_percent = 100
    ),
    ADD CONSTRAINT property_sai_terms_status_check CHECK (platform_terms_status IN ('not_required','accepted','rejected')),
    ADD CONSTRAINT property_sai_terms_basis_check CHECK (calculation_basis IN ('final_sale_value','first_month_rent'));

CREATE OR REPLACE FUNCTION prevent_property_sai_term_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'property sai term versions are immutable';
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog, public;

CREATE TRIGGER property_sai_terms_immutable_update
BEFORE UPDATE ON property_sai_terms
FOR EACH ROW EXECUTE FUNCTION prevent_property_sai_term_mutation();

CREATE TRIGGER property_sai_terms_immutable_delete
BEFORE DELETE ON property_sai_terms
FOR EACH ROW EXECUTE FUNCTION prevent_property_sai_term_mutation();
SQL);
        } elseif ($driver === 'sqlite') {
            DB::unprepared("CREATE TRIGGER property_sai_terms_immutable_update BEFORE UPDATE ON property_sai_terms BEGIN SELECT RAISE(ABORT, 'property sai term versions are immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_sai_terms_immutable_delete BEFORE DELETE ON property_sai_terms BEGIN SELECT RAISE(ABORT, 'property sai term versions are immutable'); END;");
        }
    }

    public function down(): void
    {
        Schema::table('message_threads', function (Blueprint $table): void {
            $table->dropIndex('message_threads_sai_term_idx');
            $table->dropConstrainedForeignId('sai_term_id');
        });
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropIndex('properties_current_sai_term_idx');
            $table->dropConstrainedForeignId('current_sai_term_id');
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_terms_immutable_update ON property_sai_terms');
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_terms_immutable_delete ON property_sai_terms');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_property_sai_term_mutation()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_terms_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_terms_immutable_delete');
        }

        Schema::dropIfExists('property_sai_terms');
    }
};
