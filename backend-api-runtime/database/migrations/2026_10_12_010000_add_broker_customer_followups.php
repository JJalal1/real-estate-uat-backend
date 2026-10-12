<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('broker_customer_followups', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('message_thread_id')->constrained('message_threads')->cascadeOnDelete();
            $table->text('private_note')->nullable();
            $table->timestampTz('remind_at')->nullable();
            $table->timestampTz('reminded_at')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'message_thread_id'], 'broker_followups_owner_thread_unique');
            $table->index('message_thread_id');
            $table->index(['reminded_at', 'remind_at', 'id'], 'broker_followups_due_idx');
        });
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.broker_customer_followups ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.broker_customer_followups FROM PUBLIC');
            foreach (['anon', 'authenticated'] as $role) {
                if (DB::selectOne('SELECT 1 FROM pg_roles WHERE rolname = ?', [$role])) {
                    DB::statement('REVOKE ALL ON TABLE public.broker_customer_followups FROM '.$role);
                }
            }
        }
    }

    public function down(): void
    {
        throw new LogicException('Customer follow-up history must not be removed by a rollout rollback.');
    }
};
