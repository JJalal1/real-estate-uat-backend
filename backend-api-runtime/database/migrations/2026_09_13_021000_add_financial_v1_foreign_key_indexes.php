<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('property_deal_financial_terms', function (Blueprint $table): void {
            $table->index('property_agreement_revision_id', 'pdf_terms_agreement_revision_idx');
        });

        Schema::table('property_payments', function (Blueprint $table): void {
            $table->index('deal_financial_term_id', 'property_payments_deal_term_idx');
            $table->index('reviewed_by_user_id', 'property_payments_reviewer_idx');
        });

        Schema::table('property_payment_allocations', function (Blueprint $table): void {
            $table->index('beneficiary_user_id', 'property_payment_alloc_beneficiary_idx');
        });

        Schema::table('property_manual_payment_confirmations', function (Blueprint $table): void {
            $table->index('user_id', 'property_manual_confirm_user_idx');
        });

        Schema::table('property_payouts', function (Blueprint $table): void {
            $table->index('deal_financial_term_id', 'property_payouts_deal_term_idx');
            $table->index('property_payment_id', 'property_payouts_payment_idx');
            $table->index('recorded_by_user_id', 'property_payouts_recorder_idx');
        });

        Schema::table('property_financial_ledger_entries', function (Blueprint $table): void {
            $table->index('created_by_user_id', 'property_fin_ledger_creator_idx');
        });

        Schema::table('property_financial_ledger_lines', function (Blueprint $table): void {
            $table->index('user_id', 'property_fin_ledger_lines_user_idx');
        });

        Schema::table('property_financial_holds', function (Blueprint $table): void {
            $table->index('released_by_user_id', 'property_fin_holds_releaser_idx');
        });

        Schema::table('property_financial_disputes', function (Blueprint $table): void {
            $table->index('deal_financial_term_id', 'property_fin_disputes_deal_idx');
            $table->index('opened_by_user_id', 'property_fin_disputes_opener_idx');
            $table->index('resolved_by_user_id', 'property_fin_disputes_resolver_idx');
        });

        Schema::table('property_refunds', function (Blueprint $table): void {
            $table->index('property_payment_id', 'property_refunds_payment_idx');
            $table->index('beneficiary_user_id', 'property_refunds_beneficiary_idx');
            $table->index('recorded_by_user_id', 'property_refunds_recorder_idx');
        });
    }

    public function down(): void
    {
        Schema::table('property_deal_financial_terms', function (Blueprint $table): void {
            $table->dropIndex('pdf_terms_agreement_revision_idx');
        });
        Schema::table('property_payments', function (Blueprint $table): void {
            $table->dropIndex('property_payments_deal_term_idx');
            $table->dropIndex('property_payments_reviewer_idx');
        });
        Schema::table('property_payment_allocations', function (Blueprint $table): void {
            $table->dropIndex('property_payment_alloc_beneficiary_idx');
        });
        Schema::table('property_manual_payment_confirmations', function (Blueprint $table): void {
            $table->dropIndex('property_manual_confirm_user_idx');
        });
        Schema::table('property_payouts', function (Blueprint $table): void {
            $table->dropIndex('property_payouts_deal_term_idx');
            $table->dropIndex('property_payouts_payment_idx');
            $table->dropIndex('property_payouts_recorder_idx');
        });
        Schema::table('property_financial_ledger_entries', function (Blueprint $table): void {
            $table->dropIndex('property_fin_ledger_creator_idx');
        });
        Schema::table('property_financial_ledger_lines', function (Blueprint $table): void {
            $table->dropIndex('property_fin_ledger_lines_user_idx');
        });
        Schema::table('property_financial_holds', function (Blueprint $table): void {
            $table->dropIndex('property_fin_holds_releaser_idx');
        });
        Schema::table('property_financial_disputes', function (Blueprint $table): void {
            $table->dropIndex('property_fin_disputes_deal_idx');
            $table->dropIndex('property_fin_disputes_opener_idx');
            $table->dropIndex('property_fin_disputes_resolver_idx');
        });
        Schema::table('property_refunds', function (Blueprint $table): void {
            $table->dropIndex('property_refunds_payment_idx');
            $table->dropIndex('property_refunds_beneficiary_idx');
            $table->dropIndex('property_refunds_recorder_idx');
        });
    }
};
