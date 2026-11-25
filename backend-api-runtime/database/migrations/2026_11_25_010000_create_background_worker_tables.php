<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('background_workers', function (Blueprint $table) {
            $table->string('queue', 40)->primary();
            $table->timestampTz('heartbeat_at');
            $table->string('consumer', 64);
        });
        Schema::create('background_receipts', function (Blueprint $table) {
            $table->string('event_key', 64)->primary();
            $table->timestampTz('expires_at')->index();
        });
        if (DB::getDriverName() === 'pgsql') {
            foreach (['background_workers', 'background_receipts'] as $table) {
                DB::statement("ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE public.$table FROM PUBLIC");
                foreach (['anon', 'authenticated'] as $role) {
                    if (DB::table('pg_roles')->where('rolname', $role)->exists()) {
                        DB::statement("REVOKE ALL ON TABLE public.$table FROM $role");
                    }
                }
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('background_receipts');
        Schema::dropIfExists('background_workers');
    }
};
