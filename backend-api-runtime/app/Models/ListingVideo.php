<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

final class ListingVideo extends Model
{
    protected $fillable = [
        'property_id', 'upload_id', 'status', 'original_path', 'playback_path',
        'poster_path', 'moderation_status', 'moderated_at', 'moderated_by_user_id', 'mime_type', 'size_bytes', 'playback_size_bytes', 'content_sha256', 'duration_ms',
        'width', 'height', 'attempts', 'failure_code', 'processed_at',
    ];

    protected $casts = [
        'size_bytes' => 'integer',
        'duration_ms' => 'integer',
        'width' => 'integer',
        'height' => 'integer',
        'attempts' => 'integer',
        'moderated_at' => 'datetime',
        'processed_at' => 'datetime',
    ];

    public function property(): BelongsTo
    {
        return $this->belongsTo(Property::class);
    }
}
