<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BrokerVerificationDocument extends Model
{
    public const KIND_ID_FRONT = 'id_front';
    public const KIND_ID_BACK = 'id_back';
    public const KIND_SELFIE = 'selfie';

    protected $fillable = [
        'user_id', 'kind', 'path', 'original_name', 'mime_type', 'size_bytes',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
