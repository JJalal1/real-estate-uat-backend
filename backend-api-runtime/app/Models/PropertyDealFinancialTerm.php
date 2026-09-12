<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyDealFinancialTerm extends Model
{
    protected $fillable = [
        'property_agreement_id','property_agreement_revision_id','property_sai_settlement_id','property_id',
        'buyer_user_id','advertiser_user_id','transaction_type','advertiser_type','currency','base_amount',
        'monthly_basis_amount','rental_term_months','advance_months','sai_payer','sai_total_amount',
        'platform_share_amount','advertiser_sai_share_amount','price_display_mode','snapshot','frozen_at',
    ];

    protected function casts(): array
    {
        return [
            'base_amount'=>'float','monthly_basis_amount'=>'float','rental_term_months'=>'integer','advance_months'=>'integer',
            'sai_total_amount'=>'float','platform_share_amount'=>'float','advertiser_sai_share_amount'=>'float',
            'snapshot'=>'array','frozen_at'=>'datetime',
        ];
    }

    public function agreement(): BelongsTo { return $this->belongsTo(PropertyAgreement::class, 'property_agreement_id'); }
    public function buyer(): BelongsTo { return $this->belongsTo(User::class, 'buyer_user_id'); }
    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }
}
