<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('support_cases', function (Blueprint $table): void {
            $table->string('channel', 20)->nullable()->index();
            $table->uuid('intake_key')->nullable();
            $table->unique(['requester_user_id', 'intake_key'], 'support_intake_key');
        });
        Schema::table('support_case_messages', fn (Blueprint $table) => $table->string('action_path')->nullable());
        // Inline references prevent SQLite from rebuilding these existing tables.
        DB::statement('ALTER TABLE support_cases ADD COLUMN context_property_id BIGINT REFERENCES properties(id) ON DELETE SET NULL');
        DB::statement('ALTER TABLE users ADD COLUMN support_publication_hold_case_id BIGINT REFERENCES support_cases(id) ON DELETE SET NULL');
        Schema::create('support_case_files', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('support_case_message_id')->constrained()->cascadeOnDelete();
            $table->string('private_path');
            $table->string('name');
            $table->string('mime', 50);
        });
        Schema::create('support_staff_threads', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('support_team_id')->constrained()->cascadeOnDelete();
            $table->foreignId('manager_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('recipient_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('channel', 20);
            $table->timestamps();
            $table->unique(['support_team_id', 'manager_user_id', 'recipient_user_id', 'channel'], 'staff_thread_pair');
        });
        Schema::create('support_staff_messages', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('support_staff_thread_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sender_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('support_task_id')->nullable()->constrained()->nullOnDelete();
            $table->uuid('client_key');
            $table->text('body');
            $table->timestamp('created_at');
            $table->unique(['support_staff_thread_id', 'sender_user_id', 'client_key'], 'staff_message_key');
        });

        if (DB::getDriverName() !== 'pgsql') return;
        foreach (['support_case_files', 'support_staff_threads', 'support_staff_messages'] as $table) {
            DB::statement("ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY");
            DB::statement("REVOKE ALL ON TABLE public.$table FROM PUBLIC");
            DB::statement("REVOKE ALL ON SEQUENCE public.{$table}_id_seq FROM PUBLIC");
            foreach (['anon', 'authenticated'] as $role) {
                if (!DB::table('pg_roles')->where('rolname', $role)->exists()) continue;
                DB::statement("REVOKE ALL ON TABLE public.$table FROM $role");
                DB::statement("REVOKE ALL ON SEQUENCE public.{$table}_id_seq FROM $role");
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('support_staff_messages');
        Schema::dropIfExists('support_staff_threads');
        Schema::dropIfExists('support_case_files');
        Schema::table('support_case_messages', fn (Blueprint $table) => $table->dropColumn('action_path'));
        DB::statement('ALTER TABLE users DROP COLUMN support_publication_hold_case_id');
        DB::statement('ALTER TABLE support_cases DROP COLUMN context_property_id');
        Schema::table('support_cases', function (Blueprint $table): void {
            $table->dropUnique('support_intake_key');
            $table->dropIndex(['channel']);
            $table->dropColumn(['channel', 'intake_key']);
        });
    }
};
