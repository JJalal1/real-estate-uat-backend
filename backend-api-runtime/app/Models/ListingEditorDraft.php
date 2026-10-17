<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ListingEditorDraft extends Model
{
    protected $guarded = ['id'];
    public function property() { return $this->belongsTo(Property::class); }
    protected function casts(): array
    {
        return ['payload'=>'array','images'=>'array','revision'=>'integer','property_id'=>'integer','user_id'=>'integer'];
    }
}
