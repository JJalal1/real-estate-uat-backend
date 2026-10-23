<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('message_threads', function (Blueprint $table): void {
            $table->id();$table->unsignedBigInteger('property_id')->nullable()->index();$table->unsignedBigInteger('started_by_user_id')->nullable()->index();
            $table->string('conversation_key',190)->unique();$table->timestamp('last_message_at')->nullable()->index();$table->timestamps();
        });
        Schema::create('message_thread_participants', function (Blueprint $table): void {
            $table->id();$table->foreignId('thread_id')->constrained('message_threads')->cascadeOnDelete();$table->unsignedBigInteger('user_id')->index();
            $table->string('user_name_snapshot',120);$table->unsignedBigInteger('last_read_message_id')->nullable();$table->timestamp('last_read_at')->nullable();$table->timestamps();
            $table->unique(['thread_id','user_id'],'message_thread_participant_unique');$table->index(['user_id','thread_id'],'message_participant_user_idx');
        });
        Schema::create('private_messages', function (Blueprint $table): void {
            $table->id();$table->foreignId('thread_id')->constrained('message_threads')->cascadeOnDelete();$table->unsignedBigInteger('sender_user_id')->nullable()->index();
            $table->string('sender_name_snapshot',120)->nullable();$table->text('body');$table->timestamp('created_at')->useCurrent()->index();
            $table->index(['thread_id','id'],'private_messages_thread_idx');
        });
        Schema::create('conversation_reports', function (Blueprint $table): void {
            $table->id();$table->foreignId('thread_id')->constrained('message_threads')->cascadeOnDelete();$table->unsignedBigInteger('support_case_id')->nullable()->index();
            $table->unsignedBigInteger('reporter_user_id')->index();$table->string('reporter_name_snapshot',120);$table->string('reason_code',50)->index();$table->text('details');
            $table->string('status',24)->default('open')->index();$table->unsignedBigInteger('resolved_by_user_id')->nullable()->index();$table->string('resolved_by_name_snapshot',120)->nullable();
            $table->string('resolution_note',1000)->nullable();$table->timestamp('resolved_at')->nullable();$table->timestamps();
            $table->index(['thread_id','status'],'conversation_reports_thread_status_idx');
        });
        Schema::create('private_message_access_events', function (Blueprint $table): void {
            $table->id();$table->unsignedBigInteger('conversation_report_id')->index();$table->unsignedBigInteger('thread_id')->index();$table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot',120)->nullable();$table->string('action',80)->index();$table->timestamp('created_at')->useCurrent()->index();
        });
        Schema::create('user_notifications', function (Blueprint $table): void {
            $table->id();$table->unsignedBigInteger('user_id')->index();$table->string('type',80)->index();$table->string('title',180);$table->string('body',500)->nullable();
            $table->string('entity_type',80)->nullable()->index();$table->unsignedBigInteger('entity_id')->nullable()->index();$table->json('data')->nullable();$table->timestamp('read_at')->nullable()->index();$table->timestamp('created_at')->useCurrent()->index();
            $table->index(['user_id','read_at','id'],'user_notifications_unread_idx');
        });

        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::statement("CREATE UNIQUE INDEX conversation_reports_one_active ON conversation_reports(thread_id, reporter_user_id) WHERE status IN ('open','under_review')");
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage11_private_access_history_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'stage11 private-message access history is immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER private_message_access_events_immutable_update BEFORE UPDATE ON private_message_access_events FOR EACH ROW EXECUTE FUNCTION prevent_stage11_private_access_history_mutation();
CREATE TRIGGER private_message_access_events_immutable_delete BEFORE DELETE ON private_message_access_events FOR EACH ROW EXECUTE FUNCTION prevent_stage11_private_access_history_mutation();
SQL);
        }elseif($driver==='sqlite'){
            DB::unprepared("CREATE UNIQUE INDEX conversation_reports_one_active ON conversation_reports(thread_id, reporter_user_id) WHERE status IN ('open','under_review')");
            DB::unprepared("CREATE TRIGGER private_message_access_events_immutable_update BEFORE UPDATE ON private_message_access_events BEGIN SELECT RAISE(ABORT, 'stage11 private-message access history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER private_message_access_events_immutable_delete BEFORE DELETE ON private_message_access_events BEGIN SELECT RAISE(ABORT, 'stage11 private-message access history is immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::unprepared('DROP TRIGGER IF EXISTS private_message_access_events_immutable_update ON private_message_access_events');
            DB::unprepared('DROP TRIGGER IF EXISTS private_message_access_events_immutable_delete ON private_message_access_events');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage11_private_access_history_mutation()');
        }elseif($driver==='sqlite'){
            DB::unprepared('DROP TRIGGER IF EXISTS private_message_access_events_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS private_message_access_events_immutable_delete');
        }
        Schema::dropIfExists('user_notifications');Schema::dropIfExists('private_message_access_events');Schema::dropIfExists('conversation_reports');Schema::dropIfExists('private_messages');Schema::dropIfExists('message_thread_participants');Schema::dropIfExists('message_threads');
    }
};
