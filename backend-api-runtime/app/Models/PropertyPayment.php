<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyPayment extends Model
{
    protected $fillable = [
        'reference','deal_financial_term_id','property_id','payer_user_id','advertiser_user_id','payment_method_id',
        'mode','status','required_amount','currency','provider_reference','sender_name','sender_phone',
        'proof_path','proof_original_name','proof_mime_type','proof_size_bytes','reviewed_by_user_id',
        'reviewed_by_name_snapshot','review_note','submitted_at','reviewed_at','confirmed_at',
    ];

    protected function casts(): array
    {
        return [
            'required_amount'=>'float','proof_size_bytes'=>'integer','submitted_at'=>'datetime',
            'reviewed_at'=>'datetime','confirmed_at'=>'datetime',
        ];
    }

    public function payer(): BelongsTo { return $this->belongsTo(User::class, 'payer_user_id'); }
    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }
    public function method(): BelongsTo { return $this->belongsTo(PropertyPaymentMethod::class, 'payment_method_id'); }
    public function financialTerm(): BelongsTo { return $this->belongsTo(PropertyDealFinancialTerm::class, 'deal_financial_term_id'); }
    public function property(): BelongsTo { return $this->belongsTo(Property::class, 'property_id'); }
}
