<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use LogicException;

class SupportCaseMessage extends Model
{
    public $timestamps = false;
    protected $fillable = ['support_case_id','actor_user_id','actor_name_snapshot','actor_role','is_internal','body','created_at'];
    protected function casts(): array { return ['is_internal'=>'boolean','created_at'=>'datetime']; }
    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Support messages are immutable.'));
        static::deleting(fn () => throw new LogicException('Support messages are immutable.'));
    }
}
