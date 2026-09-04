<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupportTask extends Model
{
    protected $fillable = [
        'source_type','source_id','source_reference','subject',
        'requester_user_id','requester_name_snapshot','status','priority',
        'severity','assigned_to_user_id','assigned_to_name_snapshot',
        'claimed_at','waiting_since','sla_due_at','source_updated_at',
        'last_activity_at','metadata',
    ];

    protected function casts(): array
    {
        return [
            'claimed_at'=>'datetime','waiting_since'=>'datetime',
            'sla_due_at'=>'datetime','source_updated_at'=>'datetime',
            'last_activity_at'=>'datetime','metadata'=>'array',
        ];
    }

    public function assignee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to_user_id');
    }

    public function requester(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requester_user_id');
    }

    public function isClosed(): bool
    {
        return in_array($this->status, ['completed','rejected'], true);
    }

    public function isActive(): bool
    {
        return ! $this->isClosed();
    }
}
