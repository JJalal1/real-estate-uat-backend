<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('listing_comments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_id')->constrained('properties')->cascadeOnDelete();
            $table->unsignedBigInteger('author_user_id')->nullable()->index();
            $table->string('author_name_snapshot', 120);
            $table->text('body');
            $table->string('status', 24)->default('visible')->index();
            $table->unsignedBigInteger('moderated_by_user_id')->nullable()->index();
            $table->string('moderated_by_name_snapshot', 120)->nullable();
            $table->string('moderation_reason', 500)->nullable();
            $table->timestamp('edited_at')->nullable();
            $table->timestamp('moderated_at')->nullable();
            $table->timestamps();
            $table->index(['property_id', 'status', 'created_at'], 'listing_comments_public_idx');
        });

        Schema::create('advertiser_ratings', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('advertiser_user_id')->index();
            $table->string('advertiser_name_snapshot', 120);
            $table->unsignedBigInteger('rater_user_id')->index();
            $table->string('rater_name_snapshot', 120);
            $table->unsignedBigInteger('source_property_id')->nullable()->index();
            $table->unsignedTinyInteger('rating');
            $table->string('comment', 1000)->nullable();
            $table->string('status', 24)->default('visible')->index();
            $table->unsignedBigInteger('moderated_by_user_id')->nullable()->index();
            $table->string('moderated_by_name_snapshot', 120)->nullable();
            $table->string('moderation_reason', 500)->nullable();
            $table->timestamp('moderated_at')->nullable();
            $table->timestamps();
            $table->unique(['advertiser_user_id', 'rater_user_id'], 'advertiser_ratings_one_per_user');
            $table->index(['advertiser_user_id', 'status'], 'advertiser_ratings_public_idx');
        });

        Schema::create('support_cases', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 40)->unique();
            $table->string('kind', 24)->index();
            $table->unsignedBigInteger('requester_user_id')->nullable()->index();
            $table->string('requester_name_snapshot', 120)->nullable();
            $table->string('requester_email_snapshot', 190)->nullable();
            $table->string('subject', 160);
            $table->text('description');
            $table->string('target_type', 32)->nullable()->index();
            $table->unsignedBigInteger('target_id')->nullable()->index();
            $table->string('reason_code', 50)->nullable()->index();
            $table->string('status', 32)->default('open')->index();
            $table->string('priority', 20)->default('normal')->index();
            $table->unsignedBigInteger('assigned_to_user_id')->nullable()->index();
            $table->string('assigned_to_name_snapshot', 120)->nullable();
            $table->timestamp('sla_due_at')->index();
            $table->timestamp('first_response_at')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamp('escalated_at')->nullable()->index();
            $table->unsignedTinyInteger('escalation_level')->default(0);
            $table->timestamp('last_activity_at')->useCurrent()->index();
            $table->timestamps();
            $table->index(['kind', 'status', 'sla_due_at'], 'support_cases_queue_idx');
            $table->index(['requester_user_id', 'created_at'], 'support_cases_requester_idx');
            $table->index(['target_type', 'target_id', 'status'], 'support_cases_target_idx');
        });

        Schema::create('support_case_messages', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('support_case_id')->index();
            $table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot', 120)->nullable();
            $table->string('actor_role', 24);
            $table->boolean('is_internal')->default(false)->index();
            $table->text('body');
            $table->timestamp('created_at')->useCurrent()->index();
        });

        Schema::create('support_case_events', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('support_case_id')->index();
            $table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot', 120)->nullable();
            $table->string('event', 80)->index();
            $table->string('from_status', 32)->nullable();
            $table->string('to_status', 32)->nullable();
            $table->json('metadata')->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
        });

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE advertiser_ratings ADD CONSTRAINT advertiser_ratings_rating_check CHECK (rating BETWEEN 1 AND 5)');
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage10_support_history_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'stage10 support history is immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER support_case_messages_immutable_update BEFORE UPDATE ON support_case_messages FOR EACH ROW EXECUTE FUNCTION prevent_stage10_support_history_mutation();
CREATE TRIGGER support_case_messages_immutable_delete BEFORE DELETE ON support_case_messages FOR EACH ROW EXECUTE FUNCTION prevent_stage10_support_history_mutation();
CREATE TRIGGER support_case_events_immutable_update BEFORE UPDATE ON support_case_events FOR EACH ROW EXECUTE FUNCTION prevent_stage10_support_history_mutation();
CREATE TRIGGER support_case_events_immutable_delete BEFORE DELETE ON support_case_events FOR EACH ROW EXECUTE FUNCTION prevent_stage10_support_history_mutation();
SQL);
        } elseif ($driver === 'sqlite') {
            DB::unprepared("CREATE TRIGGER support_case_messages_immutable_update BEFORE UPDATE ON support_case_messages BEGIN SELECT RAISE(ABORT, 'stage10 support history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER support_case_messages_immutable_delete BEFORE DELETE ON support_case_messages BEGIN SELECT RAISE(ABORT, 'stage10 support history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER support_case_events_immutable_update BEFORE UPDATE ON support_case_events BEGIN SELECT RAISE(ABORT, 'stage10 support history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER support_case_events_immutable_delete BEFORE DELETE ON support_case_events BEGIN SELECT RAISE(ABORT, 'stage10 support history is immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            foreach ([
                'support_case_messages_immutable_update', 'support_case_messages_immutable_delete',
            ] as $trigger) {
                DB::unprepared("DROP TRIGGER IF EXISTS {$trigger} ON support_case_messages");
            }
            foreach ([
                'support_case_events_immutable_update', 'support_case_events_immutable_delete',
            ] as $trigger) {
                DB::unprepared("DROP TRIGGER IF EXISTS {$trigger} ON support_case_events");
            }
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage10_support_history_mutation()');
        } elseif ($driver === 'sqlite') {
            foreach ([
                'support_case_messages_immutable_update', 'support_case_messages_immutable_delete',
                'support_case_events_immutable_update', 'support_case_events_immutable_delete',
            ] as $trigger) {
                DB::unprepared("DROP TRIGGER IF EXISTS {$trigger}");
            }
        }
        Schema::dropIfExists('support_case_events');
        Schema::dropIfExists('support_case_messages');
        Schema::dropIfExists('support_cases');
        Schema::dropIfExists('advertiser_ratings');
        Schema::dropIfExists('listing_comments');
    }
};
