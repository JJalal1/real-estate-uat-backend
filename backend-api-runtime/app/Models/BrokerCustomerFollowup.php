<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BrokerCustomerFollowup extends Model
{
    protected $fillable = ['user_id', 'message_thread_id', 'private_note', 'remind_at', 'reminded_at'];

    protected function casts(): array
    {
        return ['remind_at'=>'datetime', 'reminded_at'=>'datetime'];
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class, 'message_thread_id'); }
}
