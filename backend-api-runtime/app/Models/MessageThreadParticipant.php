<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MessageThreadParticipant extends Model
{
    protected $fillable = ['thread_id','user_id','user_name_snapshot','last_read_message_id','last_read_at'];
    protected function casts(): array { return ['last_read_at'=>'datetime']; }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class,'thread_id'); }
}
