<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const ORIGINAL = ['apartment', 'house', 'villa', 'land', 'shop', 'office', 'farm'];

    public function up(): void
    {
        $this->types([...self::ORIGINAL, 'floor', 'building']);
    }

    public function down(): void
    {
        if (DB::table('properties')->whereIn('type', ['floor', 'building'])->exists()) {
            throw new RuntimeException('Keep the type constraint while floor/building listings exist.');
        }
        $this->types(self::ORIGINAL);
    }

    private function types(array $types): void
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            // Laravel's original enum is a varchar CHECK on PostgreSQL. No
            // rows, grants, RLS, keys or indexes are replaced by this change.
            $values = implode(', ', array_map(fn ($type) => "'".$type."'", $types));
            DB::statement('ALTER TABLE properties DROP CONSTRAINT properties_type_check');
            DB::statement('ALTER TABLE properties ADD CONSTRAINT properties_type_check CHECK (type IN ('.$values.'))');
            return;
        }
        Schema::table('properties', function (Blueprint $table) use ($types): void {
            $table->enum('type', $types)->change();
        });
    }
};
