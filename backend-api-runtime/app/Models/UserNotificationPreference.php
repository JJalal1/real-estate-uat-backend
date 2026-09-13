<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserNotificationPreference extends Model
{
    protected $primaryKey = 'user_id';
    public $incrementing = false;

    protected $fillable = [
        'user_id',
        'messages',
        'viewings',
        'agreements',
        'listing_activity',
        'discovery_alerts',
        'services',
    ];

    protected $casts = [
        'user_id' => 'integer',
        'messages' => 'boolean',
        'viewings' => 'boolean',
        'agreements' => 'boolean',
        'listing_activity' => 'boolean',
        'discovery_alerts' => 'boolean',
        'services' => 'boolean',
    ];
}
