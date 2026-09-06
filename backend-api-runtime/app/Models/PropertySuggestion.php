<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertySuggestion extends Model
{
    protected $fillable = ['property_request_id','property_id','suggested_by_user_id','suggested_by_name_snapshot','note','viewed_at'];
    protected function casts(): array { return ['viewed_at'=>'datetime']; }
    public function propertyRequest(): BelongsTo { return $this->belongsTo(PropertyRequest::class); }
    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function suggestedBy(): BelongsTo { return $this->belongsTo(User::class, 'suggested_by_user_id'); }
}
