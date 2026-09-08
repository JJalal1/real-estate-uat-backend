<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyAgreement extends Model
{
    protected $fillable = [
        'reference','property_id','message_thread_id','viewing_booking_id','requester_user_id','advertiser_user_id',
        'transaction_type','status','created_by_user_id','accepted_at','cancelled_at','cancellation_reason',
    ];

    protected function casts(): array
    {
        return [
            'property_id'=>'integer','message_thread_id'=>'integer','viewing_booking_id'=>'integer',
            'requester_user_id'=>'integer','advertiser_user_id'=>'integer','created_by_user_id'=>'integer',
            'accepted_at'=>'datetime','cancelled_at'=>'datetime',
        ];
    }

    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class, 'message_thread_id'); }
    public function viewing(): BelongsTo { return $this->belongsTo(ViewingBooking::class, 'viewing_booking_id'); }
}
