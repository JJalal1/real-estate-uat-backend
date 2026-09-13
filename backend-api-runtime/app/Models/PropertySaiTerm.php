<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertySaiTerm extends Model
{
    protected $fillable = [
        'property_id',
        'version',
        'advertiser_type',
        'purpose',
        'source_mode',
        'requested_broker_rate_percent',
        'sai_rate_percent',
        'payer',
        'calculation_basis',
        'platform_share_percent',
        'broker_share_percent',
        'platform_terms_status',
        'platform_terms_accepted_at',
        'platform_terms_rejected_at',
        'created_by_user_id',
    ];

    protected function casts(): array
    {
        return [
            'version' => 'integer',
            'requested_broker_rate_percent' => 'float',
            'sai_rate_percent' => 'float',
            'platform_share_percent' => 'float',
            'broker_share_percent' => 'float',
            'platform_terms_accepted_at' => 'datetime',
            'platform_terms_rejected_at' => 'datetime',
        ];
    }

    public function currentProperty(): BelongsTo
    {
        return $this->belongsTo(Property::class, 'property_id');
    }
}
