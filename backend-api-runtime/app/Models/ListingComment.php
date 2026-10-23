<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ListingComment extends Model
{
    protected $fillable = [
        'property_id','author_user_id','author_name_snapshot','body','status',
        'moderated_by_user_id','moderated_by_name_snapshot','moderation_reason','edited_at','moderated_at',
    ];

    protected function casts(): array
    {
        return ['edited_at'=>'datetime','moderated_at'=>'datetime'];
    }

    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
}
