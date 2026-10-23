<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AccountVerificationDocument extends Model
{
    public const IDENTITY_DOCUMENT = 'identity_document';
    public const IDENTITY_BACK = 'identity_back';
    public const SELFIE = 'selfie';
    public const PROFESSIONAL_LICENSE = 'professional_license';
    public const RESPONSIBLE_IDENTITY = 'responsible_identity';
    public const COMMERCIAL_REGISTER = 'commercial_register';
    public const OFFICE_LICENSE = 'office_license';
    public const OFFICE_FRONTAGE = 'office_frontage';
    public const OFFICE_LOGO = 'office_logo';

    protected $fillable = [
        'profile_id', 'kind', 'path', 'original_name', 'mime_type', 'size_bytes',
    ];

    protected function casts(): array
    {
        return ['size_bytes' => 'integer'];
    }

    public function profile(): BelongsTo
    {
        return $this->belongsTo(AccountVerificationProfile::class, 'profile_id');
    }
}
