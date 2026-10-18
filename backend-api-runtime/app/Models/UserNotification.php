<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserNotification extends Model
{
    public const RETIRED_VIEWING_TYPES = ['viewing_requested', 'booking_confirmed', 'booking_declined',
        'booking_cancelled', 'booking_rescheduled', 'booking_completed', 'booking_reschedule_accepted', 'viewing_reminder', 'booking_reminder'];
    public $timestamps = false;
    protected static function booted(): void
    {
        static::addGlobalScope('visible_notification_features', function (\Illuminate\Database\Eloquent\Builder $query): void {
            $query->whereNotIn('user_notifications.type', self::RETIRED_VIEWING_TYPES)
                ->where(fn ($q) => $q->whereNull('user_notifications.entity_type')->orWhere('user_notifications.entity_type', '<>', 'viewing_booking'));
        });
    }
    protected $fillable = ['user_id','type','title','body','entity_type','entity_id','data','read_at','created_at'];
    protected function casts(): array { return ['data'=>'array','read_at'=>'datetime','created_at'=>'datetime']; }
}
