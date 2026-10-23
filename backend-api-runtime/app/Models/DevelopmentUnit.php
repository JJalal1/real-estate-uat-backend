<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DevelopmentUnit extends Model
{
    protected $fillable = [
        'development_id','code','title','unit_type','floor_label','bedrooms','bathrooms',
        'area_m2','price','currency','status','available_from','description',
    ];

    protected function casts(): array
    {
        return ['bedrooms'=>'integer','bathrooms'=>'float','area_m2'=>'float','price'=>'float','available_from'=>'date'];
    }

    public function development(): BelongsTo { return $this->belongsTo(Development::class); }
}
