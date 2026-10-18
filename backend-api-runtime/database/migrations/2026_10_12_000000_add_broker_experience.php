<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->string('availability_status', 32)->default('available')->index();
            $table->timestampTz('availability_confirmed_at')->nullable();
            $table->timestampTz('availability_due_at')->nullable()->index();
            $table->timestampTz('availability_notified_at')->nullable()->index();
            $table->unsignedBigInteger('view_count')->default(0);
        });
        Schema::table('users', function (Blueprint $table): void {
            $table->string('public_professional_bio', 900)->nullable();
            $table->string('public_professional_photo_path')->nullable();
        });
        Schema::table('message_threads', function (Blueprint $table): void {
            $table->string('lead_stage', 24)->default('new');
            $table->timestampTz('lead_updated_at')->nullable();
        });
        Schema::create('broker_deal_outcomes', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('property_id')->constrained()->restrictOnDelete();
            $table->foreignId('message_thread_id')->unique()->constrained('message_threads')->restrictOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('customer_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('sai_term_id')->nullable()->constrained('property_sai_terms')->restrictOnDelete();
            $table->string('status', 24)->default('pending_customer');
            $table->string('transaction_type', 16);
            $table->decimal('basis_amount', 16, 2);
            $table->char('currency', 3);
            $table->json('snapshot');
            $table->timestampTz('advertiser_confirmed_at');
            $table->timestampTz('customer_confirmed_at')->nullable();
            $table->timestampTz('confirmed_at')->nullable();
            $table->foreignId('support_case_id')->nullable()->constrained('support_cases')->restrictOnDelete();
            $table->foreignId('resolved_by_user_id')->nullable()->constrained('users')->restrictOnDelete();
            $table->text('resolution_note')->nullable();
            $table->timestamps();
            $table->index('property_id');
            $table->index('sai_term_id');
            $table->index('support_case_id');
            $table->index('resolved_by_user_id');
            $table->index(['advertiser_user_id', 'status', 'confirmed_at'], 'broker_outcomes_advertiser_state_idx');
            $table->index(['customer_user_id', 'status'], 'broker_outcomes_customer_state_idx');
        });
        Schema::create('property_listing_views', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_id')->constrained()->cascadeOnDelete();
            $table->string('viewer_hash', 64);
            $table->date('view_date');
            $table->timestampTz('created_at');
            $table->unique(['property_id', 'viewer_hash', 'view_date'], 'listing_views_daily_unique');
        });
        Schema::table('property_deal_financial_terms', function (Blueprint $table): void {
            $table->unsignedBigInteger('property_agreement_id')->nullable()->change();
            $table->unsignedBigInteger('property_agreement_revision_id')->nullable()->change();
            $table->foreignId('broker_deal_outcome_id')->nullable()->unique()->constrained('broker_deal_outcomes')->restrictOnDelete();
        });
        Schema::table('advertiser_ratings', function (Blueprint $table): void {
            $table->foreignId('broker_deal_outcome_id')->nullable()->constrained('broker_deal_outcomes')->restrictOnDelete();
            $table->index('broker_deal_outcome_id');
        });
        if (DB::connection()->getDriverName() === 'pgsql') {
            foreach (['broker_deal_outcomes', 'property_listing_views'] as $table) {
                DB::statement("ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE public.$table FROM PUBLIC");
                foreach (['anon', 'authenticated'] as $role) {
                    DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$role') THEN EXECUTE 'REVOKE ALL ON TABLE public.$table FROM $role'; END IF; END $$");
                }
            }
        }
    }

    public function down(): void
    {
        // Accepted financial and outcome history cannot be dropped in a routine rollback.
        throw new \LogicException('Broker history requires an explicit data-preserving rollback plan.');
    }
};
