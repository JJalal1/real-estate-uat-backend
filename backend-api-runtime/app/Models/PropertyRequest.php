<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class PropertyRequest extends Model
{
    protected $fillable = ['requester_user_id','operation_type','property_type','governorate','district','area','budget_min','budget_max','currency','requested_area_min','requested_area_max','rooms','additional_specifications','active_duration_days','status','expires_at','matched_at','closed_at','expired_at'];
    protected function casts(): array { return ['budget_min'=>'float','budget_max'=>'float','requested_area_min'=>'integer','requested_area_max'=>'integer','rooms'=>'integer','expires_at'=>'datetime','matched_at'=>'datetime','closed_at'=>'datetime','expired_at'=>'datetime']; }
    public function requester(): BelongsTo { return $this->belongsTo(User::class, 'requester_user_id'); }
    public function suggestions(): HasMany { return $this->hasMany(PropertySuggestion::class); }
}
