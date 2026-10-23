<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot', 120)->nullable();
            $table->unsignedBigInteger('target_user_id')->nullable()->index();
            $table->string('action', 120)->index();
            $table->string('subject_type', 120)->nullable()->index();
            $table->unsignedBigInteger('subject_id')->nullable()->index();
            $table->string('request_method', 12)->nullable();
            $table->string('request_path', 500)->nullable();
            $table->string('ip_address', 64)->nullable();
            $table->string('request_id', 80)->nullable()->index();
            $table->json('metadata')->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage7_audit_log_mutation()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs are immutable';
END;
$$ LANGUAGE plpgsql
SQL);
            DB::unprepared('CREATE TRIGGER audit_logs_immutable_update BEFORE UPDATE ON audit_logs FOR EACH ROW EXECUTE FUNCTION prevent_stage7_audit_log_mutation()');
            DB::unprepared('CREATE TRIGGER audit_logs_immutable_delete BEFORE DELETE ON audit_logs FOR EACH ROW EXECUTE FUNCTION prevent_stage7_audit_log_mutation()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared("CREATE TRIGGER audit_logs_immutable_update BEFORE UPDATE ON audit_logs BEGIN SELECT RAISE(ABORT, 'audit_logs are immutable'); END;");
            DB::unprepared("CREATE TRIGGER audit_logs_immutable_delete BEFORE DELETE ON audit_logs BEGIN SELECT RAISE(ABORT, 'audit_logs are immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared('DROP TRIGGER IF EXISTS audit_logs_immutable_update ON audit_logs');
            DB::unprepared('DROP TRIGGER IF EXISTS audit_logs_immutable_delete ON audit_logs');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage7_audit_log_mutation()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('DROP TRIGGER IF EXISTS audit_logs_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS audit_logs_immutable_delete');
        }
        Schema::dropIfExists('audit_logs');
    }
};
