<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ViewingBookingEvent extends Model
{
    public $timestamps = false;
    protected $fillable = [
        'viewing_booking_id','actor_user_id','actor_name_snapshot','event','from_status','to_status','metadata','created_at',
    ];
    protected function casts(): array { return ['actor_user_id'=>'integer','metadata'=>'array','created_at'=>'datetime']; }
}
