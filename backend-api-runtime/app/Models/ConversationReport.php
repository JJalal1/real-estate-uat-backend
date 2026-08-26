<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ConversationReport extends Model
{
    protected $fillable = [
        'thread_id','support_case_id','reporter_user_id','reporter_name_snapshot','reason_code','details',
        'status','resolved_by_user_id','resolved_by_name_snapshot','resolution_note','resolved_at',
    ];
    protected function casts(): array { return ['resolved_at'=>'datetime']; }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class,'thread_id'); }
}
