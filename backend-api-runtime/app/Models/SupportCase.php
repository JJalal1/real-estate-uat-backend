<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use LogicException;

class SupportCase extends Model
{
    protected $fillable = [
        'reference','kind','requester_user_id','requester_name_snapshot','requester_email_snapshot',
        'subject','description','target_type','target_id','reason_code','status','priority',
        'assigned_to_user_id','assigned_to_name_snapshot','sla_due_at','first_response_at',
        'resolved_at','escalated_at','escalation_level','last_activity_at',
    ];

    protected function casts(): array
    {
        return [
            'sla_due_at'=>'datetime','first_response_at'=>'datetime','resolved_at'=>'datetime',
            'escalated_at'=>'datetime','last_activity_at'=>'datetime','escalation_level'=>'integer',
        ];
    }

    protected static function booted(): void
    {
        static::deleting(fn () => throw new LogicException('Support cases are retained as support history.'));
    }

    public function messages(): HasMany { return $this->hasMany(SupportCaseMessage::class)->orderBy('id'); }
    public function events(): HasMany { return $this->hasMany(SupportCaseEvent::class)->orderBy('id'); }
}
