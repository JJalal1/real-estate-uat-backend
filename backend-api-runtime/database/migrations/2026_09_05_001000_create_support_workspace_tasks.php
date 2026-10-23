<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('support_tasks', function (Blueprint $table): void {
            $table->id();
            $table->string('source_type', 40);
            $table->unsignedBigInteger('source_id');
            $table->string('source_reference', 80)->nullable();
            $table->string('subject', 180);
            $table->foreignId('requester_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('requester_name_snapshot', 160)->nullable();
            $table->string('status', 32)->default('new')->index();
            $table->string('priority', 16)->default('normal')->index();
            $table->string('severity', 16)->nullable()->index();
            $table->foreignId('assigned_to_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('assigned_to_name_snapshot', 160)->nullable();
            $table->timestamp('claimed_at')->nullable()->index();
            $table->timestamp('waiting_since')->nullable();
            $table->timestamp('sla_due_at')->nullable()->index();
            $table->timestamp('source_updated_at')->nullable();
            $table->timestamp('last_activity_at')->nullable()->index();
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->unique(['source_type','source_id'], 'support_tasks_source_unique');
            $table->index(['assigned_to_user_id','status'], 'support_tasks_assignee_status_idx');
            $table->index(['source_type','status','priority'], 'support_tasks_queue_idx');
        });

        Schema::create('support_task_events', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('support_task_id')->constrained('support_tasks')->cascadeOnDelete();
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('actor_name_snapshot', 160)->nullable();
            $table->string('event', 80)->index();
            $table->string('from_status', 32)->nullable();
            $table->string('to_status', 32)->nullable();
            $table->json('metadata')->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('support_task_events');
        Schema::dropIfExists('support_tasks');
    }
};
