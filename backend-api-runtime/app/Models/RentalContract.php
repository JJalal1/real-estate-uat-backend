<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RentalContract extends Model
{
    protected $fillable = [
        'reference','property_agreement_id','property_id','message_thread_id','tenant_user_id','advertiser_user_id',
        'property_title_snapshot','property_address_snapshot','tenant_name_snapshot','advertiser_name_snapshot','status',
        'created_by_user_id','activated_at','cancelled_at','terminated_at','closure_reason',
    ];

    protected function casts(): array
    {
        return [
            'property_agreement_id'=>'integer','property_id'=>'integer','message_thread_id'=>'integer',
            'tenant_user_id'=>'integer','advertiser_user_id'=>'integer','created_by_user_id'=>'integer',
            'activated_at'=>'datetime','cancelled_at'=>'datetime','terminated_at'=>'datetime',
        ];
    }

    public function agreement(): BelongsTo { return $this->belongsTo(PropertyAgreement::class, 'property_agreement_id'); }
    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class, 'message_thread_id'); }
}
