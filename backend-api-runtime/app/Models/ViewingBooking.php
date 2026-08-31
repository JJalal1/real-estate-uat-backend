<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ViewingBooking extends Model
{
    protected $fillable = [
        'reference','requester_user_id','requester_name_snapshot','host_user_id','host_name_snapshot','message_thread_id',
        'target_type','target_id','target_title_snapshot','target_address_snapshot','starts_at','ends_at',
        'timezone','status','requester_note','host_note','cancellation_reason','last_action_by_user_id',
        'last_action_by_name_snapshot','confirmed_at','declined_at','cancelled_at','completed_at',
    ];

    protected function casts(): array
    {
        return [
            'requester_user_id'=>'integer','host_user_id'=>'integer','message_thread_id'=>'integer','target_id'=>'integer',
            'last_action_by_user_id'=>'integer','starts_at'=>'datetime','ends_at'=>'datetime',
            'confirmed_at'=>'datetime','declined_at'=>'datetime','cancelled_at'=>'datetime','completed_at'=>'datetime',
        ];
    }

    public function events(): HasMany
    {
        return $this->hasMany(ViewingBookingEvent::class, 'viewing_booking_id')->orderBy('id');
    }
}
