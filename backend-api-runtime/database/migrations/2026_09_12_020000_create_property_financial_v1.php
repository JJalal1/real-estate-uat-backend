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
            $table->string('price_display_mode', 24)->nullable()->after('currency');
            $table->decimal('monthly_rent', 16, 2)->nullable()->after('price_display_mode');
            $table->unsignedSmallInteger('rental_term_months')->nullable()->after('monthly_rent');
            $table->unsignedSmallInteger('advance_months')->nullable()->after('rental_term_months');
            $table->timestampTz('financial_hold_at')->nullable()->after('published_at')->index();
            $table->string('financial_hold_reason', 255)->nullable()->after('financial_hold_at');
        });

        Schema::create('property_payment_methods', function (Blueprint $table): void {
            $table->id();
            $table->string('key', 32)->unique();
            $table->string('name_ar', 80);
            $table->string('asset_key', 120)->nullable();
            $table->string('beneficiary_name', 160);
            $table->string('destination_label', 80);
            $table->string('destination_value', 120);
            $table->char('currency', 3)->default('YER');
            $table->decimal('min_amount', 16, 2)->nullable();
            $table->decimal('max_amount', 16, 2)->nullable();
            $table->text('instructions_ar')->nullable();
            $table->boolean('requires_sender_phone')->default(false);
            $table->boolean('requires_provider_reference')->default(false);
            $table->boolean('is_enabled')->default(true)->index();
            $table->integer('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('property_deal_financial_terms', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_agreement_id')->unique()->constrained('property_agreements')->restrictOnDelete();
            $table->foreignId('property_agreement_revision_id')->constrained('property_agreement_revisions')->restrictOnDelete();
            $table->foreignId('property_sai_settlement_id')->nullable()->unique()->constrained('property_sai_settlements')->restrictOnDelete();
            $table->unsignedBigInteger('property_id')->index();
            $table->foreignId('buyer_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->string('transaction_type', 16)->index();
            $table->string('advertiser_type', 16)->index();
            $table->char('currency', 3);
            $table->decimal('base_amount', 16, 2);
            $table->decimal('monthly_basis_amount', 16, 2)->nullable();
            $table->unsignedSmallInteger('rental_term_months')->nullable();
            $table->unsignedSmallInteger('advance_months')->nullable();
            $table->string('sai_payer', 16);
            $table->decimal('sai_total_amount', 16, 2);
            $table->decimal('platform_share_amount', 16, 2);
            $table->decimal('advertiser_sai_share_amount', 16, 2);
            $table->string('price_display_mode', 24)->nullable();
            $table->json('snapshot')->nullable();
            $table->timestampTz('frozen_at')->useCurrent();
            $table->timestamps();
            $table->index(['advertiser_user_id', 'frozen_at'], 'property_deal_financial_terms_advertiser_idx');
            $table->index(['buyer_user_id', 'frozen_at'], 'property_deal_financial_terms_buyer_idx');
        });

        Schema::create('property_payments', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('deal_financial_term_id')->constrained('property_deal_financial_terms')->restrictOnDelete();
            $table->unsignedBigInteger('property_id')->index();
            $table->foreignId('payer_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('payment_method_id')->nullable()->constrained('property_payment_methods')->restrictOnDelete();
            $table->string('mode', 32)->index();
            $table->string('status', 32)->default('waiting_payment')->index();
            $table->decimal('required_amount', 16, 2);
            $table->char('currency', 3);
            $table->string('provider_reference', 120)->nullable();
            $table->string('sender_name', 160)->nullable();
            $table->string('sender_phone', 40)->nullable();
            $table->string('proof_path', 500)->nullable();
            $table->string('proof_original_name', 255)->nullable();
            $table->string('proof_mime_type', 100)->nullable();
            $table->unsignedBigInteger('proof_size_bytes')->nullable();
            $table->foreignId('reviewed_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reviewed_by_name_snapshot', 160)->nullable();
            $table->text('review_note')->nullable();
            $table->timestampTz('submitted_at')->nullable();
            $table->timestampTz('reviewed_at')->nullable();
            $table->timestampTz('confirmed_at')->nullable();
            $table->timestamps();
            $table->index(['payer_user_id', 'created_at'], 'property_payments_payer_time_idx');
            $table->index(['advertiser_user_id', 'created_at'], 'property_payments_advertiser_time_idx');
            $table->unique(['payment_method_id', 'provider_reference'], 'property_payments_method_reference_unique');
        });

        Schema::create('property_payment_allocations', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_payment_id')->constrained('property_payments')->restrictOnDelete();
            $table->string('allocation_type', 40);
            $table->foreignId('beneficiary_user_id')->nullable()->constrained('users')->restrictOnDelete();
            $table->decimal('amount', 16, 2);
            $table->char('currency', 3);
            $table->timestampTz('created_at')->useCurrent();
            $table->index(['property_payment_id', 'allocation_type'], 'property_payment_allocations_payment_type_idx');
        });

        Schema::create('property_manual_payment_confirmations', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('deal_financial_term_id')->constrained('property_deal_financial_terms')->restrictOnDelete();
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->string('party_role', 20);
            $table->string('decision', 20);
            $table->decimal('amount', 16, 2);
            $table->char('currency', 3);
            $table->text('note')->nullable();
            $table->timestampTz('confirmed_at')->useCurrent();
            $table->timestamps();
            $table->unique(['deal_financial_term_id', 'user_id'], 'property_manual_confirmation_party_unique');
        });

        Schema::create('property_platform_receivables', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('deal_financial_term_id')->unique()->constrained('property_deal_financial_terms')->restrictOnDelete();
            $table->unsignedBigInteger('property_id')->index();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->decimal('amount_total', 16, 2);
            $table->decimal('amount_paid', 16, 2)->default(0);
            $table->char('currency', 3);
            $table->string('status', 24)->default('open')->index();
            $table->timestampTz('confirmed_direct_at');
            $table->timestampTz('due_at')->index();
            $table->timestampTz('paid_at')->nullable();
            $table->timestamps();
            $table->index(['advertiser_user_id', 'status', 'due_at'], 'property_receivables_advertiser_status_due_idx');
        });

        Schema::create('property_payouts', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('deal_financial_term_id')->constrained('property_deal_financial_terms')->restrictOnDelete();
            $table->foreignId('property_payment_id')->nullable()->constrained('property_payments')->restrictOnDelete();
            $table->foreignId('advertiser_user_id')->constrained('users')->restrictOnDelete();
            $table->decimal('amount', 16, 2);
            $table->char('currency', 3);
            $table->string('status', 24)->default('pending')->index();
            $table->string('external_reference', 120)->nullable();
            $table->text('note')->nullable();
            $table->foreignId('recorded_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestampTz('paid_at')->nullable();
            $table->timestamps();
            $table->index(['advertiser_user_id', 'status', 'created_at'], 'property_payouts_advertiser_status_idx');
        });

        Schema::create('property_financial_ledger_entries', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 36)->unique();
            $table->string('entry_type', 48)->index();
            $table->string('source_type', 48)->index();
            $table->unsignedBigInteger('source_id')->index();
            $table->foreignId('created_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->text('memo')->nullable();
            $table->timestampTz('occurred_at')->useCurrent()->index();
            $table->timestampTz('created_at')->useCurrent();
        });

        Schema::create('property_financial_ledger_lines', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('ledger_entry_id')->constrained('property_financial_ledger_entries')->restrictOnDelete();
            $table->string('account_code', 80)->index();
            $table->foreignId('user_id')->nullable()->constrained('users')->restrictOnDelete();
            $table->string('direction', 8);
            $table->decimal('amount', 16, 2);
            $table->char('currency', 3);
            $table->json('metadata')->nullable();
            $table->timestampTz('created_at')->useCurrent();
            $table->index(['ledger_entry_id', 'direction'], 'property_ledger_lines_entry_direction_idx');
        });

        Schema::create('property_financial_holds', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->string('reason', 80)->index();
            $table->string('source_type', 48)->nullable();
            $table->unsignedBigInteger('source_id')->nullable();
            $table->timestampTz('started_at')->useCurrent()->index();
            $table->timestampTz('released_at')->nullable()->index();
            $table->foreignId('released_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('release_reason', 255)->nullable();
            $table->timestamps();
            $table->index(['user_id', 'released_at'], 'property_financial_holds_user_active_idx');
        });

        Schema::create('property_financial_disputes', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('deal_financial_term_id')->constrained('property_deal_financial_terms')->restrictOnDelete();
            $table->foreignId('opened_by_user_id')->constrained('users')->restrictOnDelete();
            $table->string('status', 24)->default('open')->index();
            $table->text('reason');
            $table->text('resolution')->nullable();
            $table->foreignId('resolved_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestampTz('resolved_at')->nullable();
            $table->timestamps();
        });

        Schema::create('property_refunds', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 32)->unique();
            $table->foreignId('property_payment_id')->constrained('property_payments')->restrictOnDelete();
            $table->foreignId('beneficiary_user_id')->constrained('users')->restrictOnDelete();
            $table->decimal('amount', 16, 2);
            $table->char('currency', 3);
            $table->string('status', 24)->default('pending')->index();
            $table->text('reason');
            $table->foreignId('recorded_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestampTz('refunded_at')->nullable();
            $table->timestamps();
        });

        Schema::create('property_sai_attestations', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('property_id')->unique();
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->unsignedBigInteger('sai_term_id')->index();
            $table->unsignedInteger('terms_version');
            $table->text('text_snapshot');
            $table->string('ip_address', 64)->nullable();
            $table->string('user_agent', 500)->nullable();
            $table->timestampTz('accepted_at');
            $table->timestamps();
            $table->index(['user_id', 'accepted_at'], 'property_sai_attestations_user_time_idx');
        });

        $now = now();
        foreach ([
            ['key'=>'payments.review','name_ar'=>'مراجعة إثباتات الدفع العقارية','name_en'=>'Review property payment proofs','scope'=>'finance'],
            ['key'=>'finance.view','name_ar'=>'عرض المالية العقارية','name_en'=>'View property finance','scope'=>'finance'],
            ['key'=>'finance.manage','name_ar'=>'إدارة المالية العقارية','name_en'=>'Manage property finance','scope'=>'finance'],
        ] as $permission) {
            DB::table('permissions')->updateOrInsert(
                ['key'=>$permission['key']],
                $permission + ['created_at'=>$now,'updated_at'=>$now],
            );
        }

        foreach ([
            ['key'=>'jeeb','name_ar'=>'جيب','asset_key'=>'assets/payments/jeeb.png','beneficiary_name'=>'حسام محمد احمد القديمي','destination_label'=>'رقم المحفظة','destination_value'=>'777914037','requires_sender_phone'=>true,'requires_provider_reference'=>false,'sort_order'=>10],
            ['key'=>'kuraimi','name_ar'=>'الكريمي','asset_key'=>'assets/payments/kuraimi.png','beneficiary_name'=>'حسام محمد احمد القديمي','destination_label'=>'رقم الحساب','destination_value'=>'3094504782','requires_sender_phone'=>false,'requires_provider_reference'=>false,'sort_order'=>20],
            ['key'=>'jawali','name_ar'=>'جوالي','asset_key'=>'assets/payments/jawali.png','beneficiary_name'=>'حسام محمد احمد القديمي','destination_label'=>'رقم المحفظة','destination_value'=>'777914037','requires_sender_phone'=>true,'requires_provider_reference'=>false,'sort_order'=>30],
            ['key'=>'transfer','name_ar'=>'حوالة','asset_key'=>null,'beneficiary_name'=>'حسام محمد احمد القديمي','destination_label'=>'رقم الهاتف','destination_value'=>'777914037','requires_sender_phone'=>false,'requires_provider_reference'=>false,'sort_order'=>40],
        ] as $method) {
            DB::table('property_payment_methods')->insert($method + [
                'currency'=>'YER','instructions_ar'=>'حوّل المبلغ المطلوب فقط، ثم ارفع صورة واضحة لإثبات العملية للتحقق.','is_enabled'=>true,'created_at'=>$now,'updated_at'=>$now,
            ]);
        }

        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::unprepared(<<<'SQL'
ALTER TABLE properties
    ADD CONSTRAINT properties_price_display_mode_check CHECK (price_display_mode IS NULL OR price_display_mode IN ('includes_sai','excludes_sai')),
    ADD CONSTRAINT properties_rental_financial_fields_check CHECK (
        (purpose <> 'rent' AND monthly_rent IS NULL AND rental_term_months IS NULL AND advance_months IS NULL)
        OR
        (purpose = 'rent' AND monthly_rent > 0 AND rental_term_months BETWEEN 1 AND 24 AND advance_months BETWEEN 1 AND rental_term_months)
    );

ALTER TABLE property_deal_financial_terms
    ADD CONSTRAINT property_deal_financial_transaction_check CHECK (transaction_type IN ('sale','rent')),
    ADD CONSTRAINT property_deal_financial_advertiser_check CHECK (advertiser_type IN ('owner','broker','office')),
    ADD CONSTRAINT property_deal_financial_amounts_check CHECK (base_amount > 0 AND sai_total_amount >= 0 AND platform_share_amount >= 0 AND advertiser_sai_share_amount >= 0),
    ADD CONSTRAINT property_deal_financial_display_check CHECK (price_display_mode IS NULL OR price_display_mode IN ('includes_sai','excludes_sai'));

ALTER TABLE property_payments
    ADD CONSTRAINT property_payments_mode_check CHECK (mode IN ('platform_full','platform_sai_only','platform_receivable')),
    ADD CONSTRAINT property_payments_status_check CHECK (status IN ('waiting_payment','proof_submitted','under_review','correction_required','confirmed','rejected','cancelled')),
    ADD CONSTRAINT property_payments_amount_check CHECK (required_amount > 0);

ALTER TABLE property_payment_allocations
    ADD CONSTRAINT property_payment_allocations_type_check CHECK (allocation_type IN ('platform_revenue','advertiser_principal','advertiser_sai_share','receivable_payment','refund')),
    ADD CONSTRAINT property_payment_allocations_amount_check CHECK (amount >= 0);

ALTER TABLE property_manual_payment_confirmations
    ADD CONSTRAINT property_manual_confirmation_role_check CHECK (party_role IN ('buyer','advertiser')),
    ADD CONSTRAINT property_manual_confirmation_decision_check CHECK (decision IN ('confirmed','disputed')),
    ADD CONSTRAINT property_manual_confirmation_amount_check CHECK (amount > 0);

ALTER TABLE property_platform_receivables
    ADD CONSTRAINT property_receivables_status_check CHECK (status IN ('open','under_review','paid','overdue','disputed')),
    ADD CONSTRAINT property_receivables_amount_check CHECK (amount_total > 0 AND amount_paid >= 0 AND amount_paid <= amount_total);

ALTER TABLE property_payouts
    ADD CONSTRAINT property_payouts_status_check CHECK (status IN ('pending','paid','cancelled')),
    ADD CONSTRAINT property_payouts_amount_check CHECK (amount > 0);

ALTER TABLE property_financial_ledger_lines
    ADD CONSTRAINT property_ledger_line_direction_check CHECK (direction IN ('debit','credit')),
    ADD CONSTRAINT property_ledger_line_amount_check CHECK (amount > 0);

ALTER TABLE property_financial_disputes
    ADD CONSTRAINT property_financial_disputes_status_check CHECK (status IN ('open','resolved','dismissed'));

ALTER TABLE property_refunds
    ADD CONSTRAINT property_refunds_status_check CHECK (status IN ('pending','paid','cancelled')),
    ADD CONSTRAINT property_refunds_amount_check CHECK (amount > 0);

CREATE OR REPLACE FUNCTION prevent_property_financial_ledger_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'property financial ledger is immutable';
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog, public;

CREATE TRIGGER property_financial_ledger_entries_immutable_update
BEFORE UPDATE ON property_financial_ledger_entries
FOR EACH ROW EXECUTE FUNCTION prevent_property_financial_ledger_mutation();
CREATE TRIGGER property_financial_ledger_entries_immutable_delete
BEFORE DELETE ON property_financial_ledger_entries
FOR EACH ROW EXECUTE FUNCTION prevent_property_financial_ledger_mutation();
CREATE TRIGGER property_financial_ledger_lines_immutable_update
BEFORE UPDATE ON property_financial_ledger_lines
FOR EACH ROW EXECUTE FUNCTION prevent_property_financial_ledger_mutation();
CREATE TRIGGER property_financial_ledger_lines_immutable_delete
BEFORE DELETE ON property_financial_ledger_lines
FOR EACH ROW EXECUTE FUNCTION prevent_property_financial_ledger_mutation();
SQL);

            foreach ([
                'property_payment_methods','property_deal_financial_terms','property_payments','property_payment_allocations',
                'property_manual_payment_confirmations','property_platform_receivables','property_payouts',
                'property_financial_ledger_entries','property_financial_ledger_lines','property_financial_holds',
                'property_financial_disputes','property_refunds','property_sai_attestations',
            ] as $table) {
                DB::statement('ALTER TABLE '.$table.' ENABLE ROW LEVEL SECURITY');
                DB::statement('REVOKE ALL ON TABLE '.$table.' FROM PUBLIC');
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM anon'; END IF; END $$;");
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM authenticated'; END IF; END $$;");
            }
        } elseif ($driver === 'sqlite') {
            DB::unprepared("CREATE TRIGGER property_financial_ledger_entries_immutable_update BEFORE UPDATE ON property_financial_ledger_entries BEGIN SELECT RAISE(ABORT, 'property financial ledger is immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_financial_ledger_entries_immutable_delete BEFORE DELETE ON property_financial_ledger_entries BEGIN SELECT RAISE(ABORT, 'property financial ledger is immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_financial_ledger_lines_immutable_update BEFORE UPDATE ON property_financial_ledger_lines BEGIN SELECT RAISE(ABORT, 'property financial ledger is immutable'); END;");
            DB::unprepared("CREATE TRIGGER property_financial_ledger_lines_immutable_delete BEFORE DELETE ON property_financial_ledger_lines BEGIN SELECT RAISE(ABORT, 'property financial ledger is immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            foreach (['entries','lines'] as $suffix) {
                DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_'.$suffix.'_immutable_update ON property_financial_ledger_'.$suffix);
                DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_'.$suffix.'_immutable_delete ON property_financial_ledger_'.$suffix);
            }
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_property_financial_ledger_mutation()');
        } elseif ($driver === 'sqlite') {
            DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_entries_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_entries_immutable_delete');
            DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_lines_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS property_financial_ledger_lines_immutable_delete');
        }

        $permissionIds = DB::table('permissions')->whereIn('key', ['payments.review','finance.view','finance.manage'])->pluck('id');
        if ($permissionIds->isNotEmpty()) DB::table('role_permission')->whereIn('permission_id', $permissionIds)->delete();
        DB::table('permissions')->whereIn('key', ['payments.review','finance.view','finance.manage'])->delete();

        Schema::dropIfExists('property_sai_attestations');
        Schema::dropIfExists('property_refunds');
        Schema::dropIfExists('property_financial_disputes');
        Schema::dropIfExists('property_financial_holds');
        Schema::dropIfExists('property_financial_ledger_lines');
        Schema::dropIfExists('property_financial_ledger_entries');
        Schema::dropIfExists('property_payouts');
        Schema::dropIfExists('property_platform_receivables');
        Schema::dropIfExists('property_manual_payment_confirmations');
        Schema::dropIfExists('property_payment_allocations');
        Schema::dropIfExists('property_payments');
        Schema::dropIfExists('property_deal_financial_terms');
        Schema::dropIfExists('property_payment_methods');

        Schema::table('properties', function (Blueprint $table): void {
            $table->dropColumn([
                'price_display_mode','monthly_rent','rental_term_months','advance_months','financial_hold_at','financial_hold_reason',
            ]);
        });
    }
};
