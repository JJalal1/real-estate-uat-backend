<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserNotification extends Model
{
    public $timestamps = false;
    protected $fillable = ['user_id','type','title','body','entity_type','entity_id','data','read_at','created_at'];
    protected function casts(): array { return ['data'=>'array','read_at'=>'datetime','created_at'=>'datetime']; }
}
