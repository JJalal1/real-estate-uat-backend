<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('property_agreements', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('property_id')->constrained()->cascadeOnDelete();
            $table->foreignId('message_thread_id')->constrained('message_threads')->cascadeOnDelete();
            $table->foreignId('viewing_booking_id')->nullable()->constrained('viewing_bookings')->nullOnDelete();
            $table->foreignId('requester_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('transaction_type', 16);
            $table->string('status', 24)->default('draft');
            $table->foreignId('created_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->timestamp('accepted_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->text('cancellation_reason')->nullable();
            $table->timestamps();
            $table->index('message_thread_id');
            $table->index('viewing_booking_id');
            $table->index('created_by_user_id');
            $table->index(['requester_user_id', 'status']);
            $table->index(['advertiser_user_id', 'status']);
            $table->index(['property_id', 'status']);
        });

        Schema::create('property_agreement_revisions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_agreement_id')->constrained('property_agreements')->cascadeOnDelete();
            $table->unsignedInteger('revision_number');
            $table->decimal('agreed_amount', 16, 2);
            $table->string('currency', 8);
            $table->string('rent_cadence', 24)->nullable();
            $table->decimal('security_deposit_amount', 16, 2)->nullable();
            $table->date('rental_start_date')->nullable();
            $table->date('rental_end_date')->nullable();
            $table->text('conditions')->nullable();
            $table->foreignId('created_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('created_by_name_snapshot');
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['property_agreement_id', 'revision_number'], 'property_agreement_revision_unique');
            $table->index('created_by_user_id');
        });

        Schema::create('property_agreement_acceptances', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_agreement_revision_id')->constrained('property_agreement_revisions')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('party_role', 24);
            $table->timestamp('accepted_at')->useCurrent();
            $table->unique(['property_agreement_revision_id', 'user_id'], 'property_agreement_acceptance_unique');
            $table->index('user_id');
        });

        Schema::create('rental_contracts', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('property_agreement_id')->unique()->constrained('property_agreements')->cascadeOnDelete();
            $table->foreignId('property_id')->constrained()->cascadeOnDelete();
            $table->foreignId('message_thread_id')->constrained('message_threads')->cascadeOnDelete();
            $table->foreignId('tenant_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('property_title_snapshot');
            $table->string('property_address_snapshot')->nullable();
            $table->string('tenant_name_snapshot');
            $table->string('advertiser_name_snapshot');
            $table->string('status', 24)->default('draft');
            $table->foreignId('created_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->timestamp('activated_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamp('terminated_at')->nullable();
            $table->text('closure_reason')->nullable();
            $table->timestamps();
            $table->index('property_id');
            $table->index('message_thread_id');
            $table->index('created_by_user_id');
            $table->index(['tenant_user_id', 'status']);
            $table->index(['advertiser_user_id', 'status']);
        });

        Schema::create('rental_contract_revisions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('rental_contract_id')->constrained('rental_contracts')->cascadeOnDelete();
            $table->unsignedInteger('revision_number');
            $table->decimal('rent_amount', 16, 2);
            $table->string('currency', 8);
            $table->string('rent_cadence', 24);
            $table->date('start_date');
            $table->date('end_date');
            $table->decimal('security_deposit_amount', 16, 2)->nullable();
            $table->unsignedTinyInteger('payment_due_day')->nullable();
            $table->text('additional_terms')->nullable();
            $table->foreignId('created_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('created_by_name_snapshot');
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['rental_contract_id', 'revision_number'], 'rental_contract_revision_unique');
            $table->index('created_by_user_id');
        });

        Schema::create('rental_contract_acceptances', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('rental_contract_revision_id')->constrained('rental_contract_revisions')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('party_role', 24);
            $table->timestamp('accepted_at')->useCurrent();
            $table->unique(['rental_contract_revision_id', 'user_id'], 'rental_contract_acceptance_unique');
            $table->index('user_id');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("CREATE UNIQUE INDEX property_agreements_active_thread_unique ON property_agreements (message_thread_id) WHERE status IN ('draft','accepted')");
            foreach (['property_agreements','property_agreement_revisions','property_agreement_acceptances','rental_contracts','rental_contract_revisions','rental_contract_acceptances'] as $table) {
                DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE {$table} FROM PUBLIC");
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM anon'; END IF; END $$;");
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM authenticated'; END IF; END $$;");
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('rental_contract_acceptances');
        Schema::dropIfExists('rental_contract_revisions');
        Schema::dropIfExists('rental_contracts');
        Schema::dropIfExists('property_agreement_acceptances');
        Schema::dropIfExists('property_agreement_revisions');
        Schema::dropIfExists('property_agreements');
    }
};
