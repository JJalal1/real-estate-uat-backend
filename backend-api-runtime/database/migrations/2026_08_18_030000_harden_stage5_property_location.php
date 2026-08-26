<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        $addOwnerKey = ! Schema::hasColumn('properties', 'owner_key');
        $addPhone = ! Schema::hasColumn('properties', 'contact_phone');
        $addWhatsapp = ! Schema::hasColumn('properties', 'contact_whatsapp');

        Schema::table('properties', function (Blueprint $table) use (
            $addOwnerKey,
            $addPhone,
            $addWhatsapp,
        ) {
            if ($addOwnerKey) {
                $table->string('owner_key', 96)->nullable()->index();
            }
            if ($addPhone) {
                $table->string('contact_phone', 32)->nullable();
            }
            if ($addWhatsapp) {
                $table->string('contact_whatsapp', 32)->nullable();
            }
        });

        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        DB::unprepared(<<<'SQL'
            CREATE OR REPLACE FUNCTION sync_properties_location()
            RETURNS trigger AS $$
            BEGIN
                NEW.location := ST_SetSRID(
                    ST_MakePoint(NEW.longitude, NEW.latitude),
                    4326
                )::geography;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS properties_location_sync_trigger ON properties;
            CREATE TRIGGER properties_location_sync_trigger
            BEFORE INSERT OR UPDATE OF latitude, longitude ON properties
            FOR EACH ROW EXECUTE FUNCTION sync_properties_location();

            UPDATE properties
            SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
            WHERE location IS NULL;

            CREATE INDEX IF NOT EXISTS properties_status_id_idx
            ON properties (status, id DESC);

            CREATE INDEX IF NOT EXISTS properties_owner_key_id_idx
            ON properties (owner_key, id DESC);
            SQL);
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        DB::unprepared(<<<'SQL'
            DROP TRIGGER IF EXISTS properties_location_sync_trigger ON properties;
            DROP FUNCTION IF EXISTS sync_properties_location();
            DROP INDEX IF EXISTS properties_status_id_idx;
            DROP INDEX IF EXISTS properties_owner_key_id_idx;
            SQL);
    }
};
