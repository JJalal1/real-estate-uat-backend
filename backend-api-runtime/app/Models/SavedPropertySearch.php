<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SavedPropertySearch extends Model
{
    protected $fillable = [
        'user_id',
        'name',
        'filters',
        'fingerprint',
        'alert_frequency',
        'is_active',
        'last_match_property_id',
        'last_checked_at',
    ];

    protected $casts = [
        'filters' => 'array',
        'is_active' => 'boolean',
        'last_match_property_id' => 'integer',
        'last_checked_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
