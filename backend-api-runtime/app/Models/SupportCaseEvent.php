<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use LogicException;

class SupportCaseEvent extends Model
{
    public $timestamps = false;
    protected $fillable = ['support_case_id','actor_user_id','actor_name_snapshot','event','from_status','to_status','metadata','created_at'];
    protected function casts(): array { return ['metadata'=>'array','created_at'=>'datetime']; }
    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Support events are immutable.'));
        static::deleting(fn () => throw new LogicException('Support events are immutable.'));
    }
}
