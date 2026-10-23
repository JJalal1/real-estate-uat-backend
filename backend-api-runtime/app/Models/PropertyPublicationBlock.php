<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyPublicationBlock extends Model
{
    protected $fillable = [
        'property_asset_id','purpose','is_active','reason','blocked_by_user_id','source_listing_id','blocked_at',
        'lifted_by_user_id','lifted_reason','lifted_at',
    ];
    protected $casts = ['is_active'=>'boolean','blocked_at'=>'datetime','lifted_at'=>'datetime'];
    public function propertyAsset(): BelongsTo { return $this->belongsTo(PropertyAsset::class); }
    public function blockedBy(): BelongsTo { return $this->belongsTo(User::class, 'blocked_by_user_id'); }
    public function liftedBy(): BelongsTo { return $this->belongsTo(User::class, 'lifted_by_user_id'); }
}
