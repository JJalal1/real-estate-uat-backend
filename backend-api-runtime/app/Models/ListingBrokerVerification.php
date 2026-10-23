<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ListingBrokerVerification extends Model
{
    protected $fillable = [
        'listing_id','geo_cell_id','broker_user_id','requested_by_user_id','requested_by_name_snapshot',
        'broker_name_snapshot','status','request_note','response_note','requested_at','responded_at','cancelled_at','cancel_reason',
    ];

    protected $casts = [
        'requested_at'=>'datetime','responded_at'=>'datetime','cancelled_at'=>'datetime',
    ];

    public function listing(): BelongsTo { return $this->belongsTo(Property::class, 'listing_id'); }
    public function geoCell(): BelongsTo { return $this->belongsTo(GeoCell::class, 'geo_cell_id'); }
    public function broker(): BelongsTo { return $this->belongsTo(User::class, 'broker_user_id'); }
    public function requestedBy(): BelongsTo { return $this->belongsTo(User::class, 'requested_by_user_id'); }
}
