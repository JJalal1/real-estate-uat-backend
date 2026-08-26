<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->boolean('is_platform_owner')->default(false)->index();
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared('CREATE UNIQUE INDEX users_single_platform_owner ON users (is_platform_owner) WHERE is_platform_owner = true');
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage7_platform_owner_delete()
RETURNS trigger AS $$
BEGIN
    IF OLD.is_platform_owner = true THEN
        RAISE EXCEPTION 'the platform owner account cannot be deleted';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql
SQL);
            DB::unprepared('CREATE TRIGGER users_protect_platform_owner_delete BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION prevent_stage7_platform_owner_delete()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('CREATE UNIQUE INDEX users_single_platform_owner ON users (is_platform_owner) WHERE is_platform_owner = 1');
            DB::unprepared("CREATE TRIGGER users_protect_platform_owner_delete BEFORE DELETE ON users WHEN OLD.is_platform_owner = 1 BEGIN SELECT RAISE(ABORT, 'the platform owner account cannot be deleted'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared('DROP TRIGGER IF EXISTS users_protect_platform_owner_delete ON users');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage7_platform_owner_delete()');
            DB::unprepared('DROP INDEX IF EXISTS users_single_platform_owner');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('DROP TRIGGER IF EXISTS users_protect_platform_owner_delete');
            DB::unprepared('DROP INDEX IF EXISTS users_single_platform_owner');
        }

        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn('is_platform_owner');
        });
    }
};
