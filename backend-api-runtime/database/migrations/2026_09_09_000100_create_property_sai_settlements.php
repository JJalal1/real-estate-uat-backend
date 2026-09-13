<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('property_agreements', function (Blueprint $table): void {
            $table->foreignId('sai_term_id')
                ->nullable()
                ->after('message_thread_id')
                ->constrained('property_sai_terms')
                ->restrictOnDelete();
            $table->index('sai_term_id', 'property_agreements_sai_term_idx');
        });

        Schema::create('property_sai_settlements', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_agreement_id')
                ->unique()
                ->constrained('property_agreements')
                ->restrictOnDelete();
            $table->foreignId('property_agreement_revision_id')
                ->unique()
                ->constrained('property_agreement_revisions')
                ->restrictOnDelete();
            $table->unsignedBigInteger('property_id')->index();
            $table->unsignedBigInteger('message_thread_id')->index();
            $table->foreignId('sai_term_id')
                ->constrained('property_sai_terms')
                ->restrictOnDelete();
            $table->string('transaction_type', 16);
            $table->string('payer', 16);
            $table->string('calculation_basis', 32);
            $table->decimal('basis_amount', 16, 2);
            $table->string('currency', 8);
            $table->decimal('sai_rate_percent', 5, 2);
            $table->decimal('total_sai_amount', 16, 2);
            $table->decimal('platform_share_percent', 5, 2);
            $table->decimal('platform_share_amount', 16, 2);
            $table->decimal('broker_share_percent', 5, 2);
            $table->decimal('broker_share_amount', 16, 2);
            $table->timestamp('settled_at')->useCurrent();
            $table->timestamps();

            $table->index(['property_id', 'settled_at'], 'property_sai_settlements_property_time_idx');
            $table->index(['sai_term_id', 'settled_at'], 'property_sai_settlements_term_time_idx');
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE property_sai_settlements ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE property_sai_settlements FROM PUBLIC');
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE property_sai_settlements FROM anon'; END IF; END $$;");
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE property_sai_settlements FROM authenticated'; END IF; END $$;");
            DB::unprepared(<<<'SQL'
ALTER TABLE property_sai_settlements
    ADD CONSTRAINT property_sai_settlements_transaction_type_check CHECK (transaction_type IN ('sale','rent')),
    ADD CONSTRAINT property_sai_settlements_basis_check CHECK (calculation_basis IN ('final_sale_value','first_month_rent')),
    ADD CONSTRAINT property_sai_settlements_payer_check CHECK (
        (transaction_type = 'sale' AND payer IN ('seller','buyer')) OR
        (transaction_type = 'rent' AND payer IN ('landlord','tenant'))
    ),
    ADD CONSTRAINT property_sai_settlements_amounts_check CHECK (
        basis_amount > 0 AND total_sai_amount >= 0 AND platform_share_amount >= 0 AND broker_share_amount >= 0
    ),
    ADD CONSTRAINT property_sai_settlements_rate_check CHECK (sai_rate_percent BETWEEN 0 AND 100),
    ADD CONSTRAINT property_sai_settlements_share_check CHECK (
        platform_share_percent BETWEEN 0 AND 100 AND
        broker_share_percent BETWEEN 0 AND 100 AND
        platform_share_percent + broker_share_percent = 100
    );

CREATE OR REPLACE FUNCTION prevent_property_sai_settlement_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'property sai settlements are immutable';
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog, public;

CREATE TRIGGER property_sai_settlements_immutable_update
BEFORE UPDATE ON property_sai_settlements
FOR EACH ROW EXECUTE FUNCTION prevent_property_sai_settlement_mutation();

CREATE TRIGGER property_sai_settlements_immutable_delete
BEFORE DELETE ON property_sai_settlements
FOR EACH ROW EXECUTE FUNCTION prevent_property_sai_settlement_mutation();
SQL);
        } elseif ($driver === 'sqlite') {
            DB::unprepared("CREATE TRIGGER property_sai_settlements_immutable_update BEFORE UPDATE ON property_sai_settlements BEGIN SELECT RAISE(ABORT, 'property sai settlements are immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_sai_settlements_immutable_delete BEFORE DELETE ON property_sai_settlements BEGIN SELECT RAISE(ABORT, 'property sai settlements are immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_settlements_immutable_update ON property_sai_settlements');
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_settlements_immutable_delete ON property_sai_settlements');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_property_sai_settlement_mutation()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_settlements_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS property_sai_settlements_immutable_delete');
        }

        Schema::dropIfExists('property_sai_settlements');
        Schema::table('property_agreements', function (Blueprint $table): void {
            $table->dropIndex('property_agreements_sai_term_idx');
            $table->dropConstrainedForeignId('sai_term_id');
        });
    }
};
