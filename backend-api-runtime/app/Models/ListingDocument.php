<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ListingDocument extends Model
{
    public $timestamps = false;
    protected $fillable = ['property_id','uploaded_by_user_id','kind','path','original_name','mime_type','size_bytes','created_at'];
    protected $casts = ['size_bytes'=>'integer','created_at'=>'datetime'];
    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function uploader(): BelongsTo { return $this->belongsTo(User::class, 'uploaded_by_user_id'); }
}
