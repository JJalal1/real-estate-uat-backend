<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('governorates', function (Blueprint $table): void {
            $table->id();
            $table->string('code', 40)->unique();
            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();
            $table->boolean('is_active')->default(true)->index();
            $table->timestamps();
        });

        Schema::create('geo_cells', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('governorate_id')->constrained('governorates')->restrictOnDelete();
            $table->string('code', 60)->unique();
            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();
            $table->json('boundary_json');
            $table->boolean('is_active')->default(true)->index();
            $table->timestamps();
            $table->index(['governorate_id', 'is_active']);
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE geo_cells ADD COLUMN boundary geometry(Polygon,4326)');
            DB::statement("UPDATE geo_cells SET boundary = ST_GeomFromGeoJSON(boundary_json::text)");
            DB::statement('ALTER TABLE geo_cells ALTER COLUMN boundary SET NOT NULL');
            DB::statement('CREATE INDEX geo_cells_boundary_gix ON geo_cells USING GIST (boundary)');
            DB::statement('ALTER TABLE geo_cells ADD CONSTRAINT geo_cells_boundary_valid CHECK (ST_IsValid(boundary) AND NOT ST_IsEmpty(boundary))');
        }

        Schema::create('broker_cell_assignments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('geo_cell_id')->constrained('geo_cells')->restrictOnDelete();
            $table->foreignId('broker_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('assigned_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestampTz('starts_at')->useCurrent();
            $table->timestampTz('ends_at')->nullable();
            $table->foreignId('ended_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reason', 500)->nullable();
            $table->string('end_reason', 500)->nullable();
            $table->index(['broker_user_id', 'ends_at']);
            $table->index(['geo_cell_id', 'starts_at']);
        });
        DB::statement('CREATE UNIQUE INDEX broker_cell_assignments_one_active_per_cell ON broker_cell_assignments (geo_cell_id) WHERE ends_at IS NULL');

        Schema::table('properties', function (Blueprint $table): void {
            $table->foreignId('geo_cell_id')->nullable()->after('user_id')->constrained('geo_cells')->nullOnDelete();
            $table->index('geo_cell_id');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION stage8_prevent_cell_overlap() RETURNS trigger AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM geo_cells c
        WHERE c.id <> COALESCE(NEW.id, 0)
          AND ST_Relate(c.boundary, NEW.boundary, 'T********')
    ) THEN
        RAISE EXCEPTION 'Geographic cells may touch borders but their interiors may not overlap.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stage8_prevent_cell_overlap
BEFORE INSERT OR UPDATE OF boundary ON geo_cells
FOR EACH ROW EXECUTE FUNCTION stage8_prevent_cell_overlap();
SQL);
        }
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::unprepared('DROP TRIGGER IF EXISTS trg_stage8_prevent_cell_overlap ON geo_cells; DROP FUNCTION IF EXISTS stage8_prevent_cell_overlap();');
        }
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('geo_cell_id');
        });
        Schema::dropIfExists('broker_cell_assignments');
        Schema::dropIfExists('geo_cells');
        Schema::dropIfExists('governorates');
    }
};
