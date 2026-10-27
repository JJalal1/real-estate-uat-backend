<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserPushDevice extends Model
{
    protected $fillable = [
        'user_id',
        'platform',
        'token',
        'token_hash',
        'installation_hash',
        'app_build',
        'last_seen_at',
        'disabled_at',
    ];

    protected function casts(): array
    {
        return [
            'token' => 'encrypted',
            'app_build' => 'integer',
            'last_seen_at' => 'datetime',
            'disabled_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
