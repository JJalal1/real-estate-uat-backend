<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AccountVerificationProfile extends Model
{
    public const TYPE_OWNER = 'owner';
    public const TYPE_BROKER = 'broker';
    public const TYPE_OFFICE = 'office';

    public const STATUS_NOT_SUBMITTED = 'not_submitted';
    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_NEEDS_MORE_INFO = 'needs_more_info';

    protected $fillable = [
        'user_id', 'type', 'status', 'details', 'submitted_at', 'reviewed_at',
        'reviewed_by_user_id', 'review_note',
    ];

    protected function casts(): array
    {
        return [
            'details' => 'array',
            'submitted_at' => 'datetime',
            'reviewed_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function reviewer(): BelongsTo { return $this->belongsTo(User::class, 'reviewed_by_user_id'); }
    public function documents(): HasMany { return $this->hasMany(AccountVerificationDocument::class, 'profile_id')->orderBy('id'); }

    public function isApproved(): bool
    {
        return $this->status === self::STATUS_APPROVED && $this->reviewed_at !== null;
    }
}
