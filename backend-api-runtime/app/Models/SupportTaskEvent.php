<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SupportTaskEvent extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'support_task_id','actor_user_id','actor_name_snapshot','event',
        'from_status','to_status','metadata','created_at',
    ];

    protected function casts(): array
    {
        return ['metadata'=>'array','created_at'=>'datetime'];
    }
}
