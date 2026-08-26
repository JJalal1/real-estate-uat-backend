<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PrivateMessage extends Model
{
    public $timestamps = false;
    protected $fillable = ['thread_id','sender_user_id','sender_name_snapshot','body','created_at'];
    protected function casts(): array { return ['created_at'=>'datetime']; }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class,'thread_id'); }
}
