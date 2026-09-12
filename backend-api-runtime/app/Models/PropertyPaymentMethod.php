<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PropertyPaymentMethod extends Model
{
    protected $fillable = [
        'key','name_ar','asset_key','beneficiary_name','destination_label','destination_value','currency',
        'min_amount','max_amount','instructions_ar','requires_sender_phone','requires_provider_reference','is_enabled','sort_order',
    ];

    protected function casts(): array
    {
        return [
            'min_amount'=>'float','max_amount'=>'float','requires_sender_phone'=>'boolean',
            'requires_provider_reference'=>'boolean','is_enabled'=>'boolean','sort_order'=>'integer',
        ];
    }
}
