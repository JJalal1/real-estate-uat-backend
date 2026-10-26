<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

final class ListingVideo extends Model
{
    public const MAX_PROCESS_ATTEMPTS = 3;

    public function derivativePathsForAttempt(int $attempt): array
    {
        $prefix='listing-video-display/'.$this->id.'/attempt-'.$attempt;
        return [$prefix.'/playback.mp4',$prefix.'/poster.jpg'];
    }

    /** Includes incomplete attempts, whose paths may not have reached the ready row. */
    public function trackedPaths(): array
    {
        $paths=array_merge($this->cleanup_paths ?? [],[$this->original_path,$this->playback_path,$this->poster_path,
            'listing-video-display/'.$this->id.'/playback.mp4',
            'listing-video-display/'.$this->id.'/poster.jpg']);
        for($attempt=1;$attempt<=min((int)$this->attempts,self::MAX_PROCESS_ATTEMPTS);$attempt++) {
            array_push($paths,...$this->derivativePathsForAttempt($attempt));
        }
        return array_values(array_unique(array_filter($paths)));
    }

    protected $fillable = [
        'property_id', 'upload_id', 'status', 'original_path', 'cleanup_paths', 'playback_path',
        'poster_path', 'moderation_status', 'moderated_at', 'moderated_by_user_id', 'mime_type', 'size_bytes', 'playback_size_bytes', 'content_sha256', 'duration_ms',
        'width', 'height', 'attempts', 'failure_code', 'processed_at',
    ];

    protected $casts = [
        'cleanup_paths' => 'array',
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

