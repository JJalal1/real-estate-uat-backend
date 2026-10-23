<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BrokerDealOutcome extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['basis_amount'=>'float', 'snapshot'=>'array', 'advertiser_confirmed_at'=>'datetime',
            'customer_confirmed_at'=>'datetime', 'confirmed_at'=>'datetime'];
    }

    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class, 'message_thread_id'); }
    public function customer(): BelongsTo { return $this->belongsTo(User::class, 'customer_user_id'); }
    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }
}
