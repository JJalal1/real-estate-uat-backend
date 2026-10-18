<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Aggregate cost guard only. No prompts, answers, user IDs or secrets.
        Schema::create('ai_daily_usage', function (Blueprint $table): void {
            $table->date('day')->primary();
            $table->unsignedInteger('request_count')->default(0);
        });
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE ai_daily_usage ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE ai_daily_usage FROM PUBLIC');
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE ai_daily_usage FROM anon'; END IF; IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE ai_daily_usage FROM authenticated'; END IF; END $$;");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_daily_usage');
    }
};
