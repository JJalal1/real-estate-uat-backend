<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('property_assets', function (Blueprint $table): void {
            $table->string('identity_kind', 24)->default('standalone')->index();
            $table->string('building_reference', 160)->nullable();
            $table->string('building_identity_key', 64)->nullable()->index();
            $table->string('unit_identity_key', 96)->nullable();
            $table->string('unit_number', 64)->nullable();
            $table->string('floor_number', 32)->nullable();
            $table->string('canonical_address_normalized', 255)->nullable();
            $table->json('land_boundary_geojson')->nullable();
            $table->string('land_boundary_hash', 64)->nullable()->index();
        });

        Schema::table('properties', function (Blueprint $table): void {
            $table->string('building_reference', 160)->nullable();
            $table->string('unit_number', 64)->nullable();
            $table->string('floor_number', 32)->nullable();
            $table->json('land_boundary_geojson')->nullable();
            $table->string('duplicate_check_status', 32)->default('unchecked')->index();
            $table->unsignedSmallInteger('duplicate_check_score')->default(0);
            $table->json('duplicate_check_metadata')->nullable();
            $table->json('duplicate_self_verification')->nullable();
            $table->timestampTz('duplicate_checked_at')->nullable();
        });

        Schema::create('property_identity_checks', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_id')->constrained('properties')->cascadeOnDelete();
            $table->foreignId('candidate_property_id')->nullable()->constrained('properties')->nullOnDelete();
            $table->foreignId('candidate_property_asset_id')->nullable()->constrained('property_assets')->nullOnDelete();
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('result', 32)->index();
            $table->unsignedSmallInteger('score')->default(0);
            $table->json('signals');
            $table->json('metadata')->nullable();
            $table->timestampTz('created_at')->useCurrent();
            $table->index('property_id', 'property_identity_checks_property_idx');
            $table->index('candidate_property_id', 'property_identity_checks_candidate_property_idx');
            $table->index('candidate_property_asset_id', 'property_identity_checks_candidate_asset_idx');
            $table->index('actor_user_id', 'property_identity_checks_actor_idx');
            $table->index(['property_id', 'created_at'], 'property_identity_checks_property_time_idx');
        });

        Schema::create('property_representation_claims', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_asset_id')->constrained('property_assets')->restrictOnDelete();
            $table->foreignId('property_id')->nullable()->constrained('properties')->nullOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->string('purpose', 16);
            $table->string('status', 16)->default('active')->index();
            $table->timestampTz('started_at')->useCurrent();
            $table->timestampTz('ended_at')->nullable();
            $table->string('end_reason', 160)->nullable();
            $table->timestamps();
            $table->index('property_asset_id', 'property_representation_claims_asset_idx');
            $table->index('property_id', 'property_representation_claims_property_idx');
            $table->index('advertiser_user_id', 'property_representation_claims_advertiser_idx');
            $table->index(['advertiser_user_id', 'status'], 'property_representation_claims_advertiser_status_idx');
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE property_assets ADD COLUMN land_boundary geometry(Polygon,4326)');
            DB::statement('CREATE INDEX property_assets_land_boundary_gist ON property_assets USING GIST (land_boundary)');
            DB::statement("CREATE UNIQUE INDEX property_assets_unit_identity_unique ON property_assets (building_identity_key, unit_identity_key) WHERE building_identity_key IS NOT NULL AND unit_identity_key IS NOT NULL AND status = 'active'");
            DB::statement("CREATE UNIQUE INDEX property_representation_claims_active_asset_unique ON property_representation_claims (property_asset_id) WHERE status = 'active'");

            foreach (['property_identity_checks', 'property_representation_claims'] as $table) {
                DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE {$table} FROM PUBLIC");
            }
            DB::statement('REVOKE ALL ON SEQUENCE property_identity_checks_id_seq FROM PUBLIC');
            DB::statement('REVOKE ALL ON SEQUENCE property_representation_claims_id_seq FROM PUBLIC');
            DB::unprepared(<<<'SQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE property_identity_checks, property_representation_claims FROM anon;
    REVOKE ALL ON SEQUENCE property_identity_checks_id_seq, property_representation_claims_id_seq FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE property_identity_checks, property_representation_claims FROM authenticated;
    REVOKE ALL ON SEQUENCE property_identity_checks_id_seq, property_representation_claims_id_seq FROM authenticated;
  END IF;
END $$;
SQL);
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION property_identity_checks_immutable()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'property_identity_checks is immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER property_identity_checks_immutable_update
BEFORE UPDATE ON property_identity_checks
FOR EACH ROW EXECUTE FUNCTION property_identity_checks_immutable();
CREATE TRIGGER property_identity_checks_immutable_delete
BEFORE DELETE ON property_identity_checks
FOR EACH ROW EXECUTE FUNCTION property_identity_checks_immutable();
SQL);
        } elseif ($driver === 'sqlite') {
            DB::statement("CREATE UNIQUE INDEX property_assets_unit_identity_unique ON property_assets (building_identity_key, unit_identity_key) WHERE building_identity_key IS NOT NULL AND unit_identity_key IS NOT NULL AND status = 'active'");
            DB::statement("CREATE UNIQUE INDEX property_representation_claims_active_asset_unique ON property_representation_claims (property_asset_id) WHERE status = 'active'");
            DB::unprepared("CREATE TRIGGER property_identity_checks_immutable_update BEFORE UPDATE ON property_identity_checks BEGIN SELECT RAISE(ABORT, 'property_identity_checks is immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_identity_checks_immutable_delete BEFORE DELETE ON property_identity_checks BEGIN SELECT RAISE(ABORT, 'property_identity_checks is immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('DROP TRIGGER IF EXISTS property_identity_checks_immutable_update ON property_identity_checks');
            DB::statement('DROP TRIGGER IF EXISTS property_identity_checks_immutable_delete ON property_identity_checks');
            DB::statement('DROP FUNCTION IF EXISTS property_identity_checks_immutable()');
            DB::statement('DROP INDEX IF EXISTS property_assets_land_boundary_gist');
            DB::statement('DROP INDEX IF EXISTS property_assets_unit_identity_unique');
            DB::statement('DROP INDEX IF EXISTS property_representation_claims_active_asset_unique');
        } elseif ($driver === 'sqlite') {
            DB::statement('DROP TRIGGER IF EXISTS property_identity_checks_immutable_update');
            DB::statement('DROP TRIGGER IF EXISTS property_identity_checks_immutable_delete');
            DB::statement('DROP INDEX IF EXISTS property_assets_unit_identity_unique');
            DB::statement('DROP INDEX IF EXISTS property_representation_claims_active_asset_unique');
        }

        Schema::dropIfExists('property_representation_claims');
        Schema::dropIfExists('property_identity_checks');

        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE property_assets DROP COLUMN IF EXISTS land_boundary');
        }

        Schema::table('properties', function (Blueprint $table): void {
            $table->dropColumn([
                'building_reference', 'unit_number', 'floor_number', 'land_boundary_geojson',
                'duplicate_check_status', 'duplicate_check_score', 'duplicate_check_metadata',
                'duplicate_self_verification', 'duplicate_checked_at',
            ]);
        });

        Schema::table('property_assets', function (Blueprint $table): void {
            $table->dropColumn([
                'identity_kind', 'building_reference', 'building_identity_key', 'unit_identity_key',
                'unit_number', 'floor_number', 'canonical_address_normalized',
                'land_boundary_geojson', 'land_boundary_hash',
            ]);
        });
    }
};
