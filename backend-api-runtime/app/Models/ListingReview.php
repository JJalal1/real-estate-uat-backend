<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ListingReview extends Model
{
    public $timestamps = false;
    protected $fillable = [
        'listing_id','actor_user_id','actor_name_snapshot','action','from_review_status','to_review_status','reason',
        'listing_snapshot','metadata','created_at',
    ];
    protected $casts = ['listing_snapshot'=>'array','metadata'=>'array','created_at'=>'datetime'];
    public function actor(): BelongsTo { return $this->belongsTo(User::class, 'actor_user_id'); }
}
