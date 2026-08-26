<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use LogicException;

class PrivateMessageAccessEvent extends Model
{
    public $timestamps = false;
    protected $fillable = ['conversation_report_id','thread_id','actor_user_id','actor_name_snapshot','action','created_at'];
    protected function casts(): array { return ['created_at'=>'datetime']; }
    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Private-message access history is immutable.'));
        static::deleting(fn () => throw new LogicException('Private-message access history is immutable.'));
    }
}
