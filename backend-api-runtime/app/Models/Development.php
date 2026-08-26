<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Development extends Model
{
    protected $fillable = [
        'developer_id','created_by_user_id','created_by_name_snapshot','name','slug','description',
        'status','completion_status','expected_completion_date','governorate_id','geo_cell_id',
        'address','latitude','longitude','cover_image_url','published_by_user_id',
        'published_by_name_snapshot','published_at',
    ];

    protected function casts(): array
    {
        return [
            'expected_completion_date'=>'date',
            'latitude'=>'float','longitude'=>'float','published_at'=>'datetime',
        ];
    }

    public function developer(): BelongsTo { return $this->belongsTo(Developer::class); }
    public function governorate(): BelongsTo { return $this->belongsTo(Governorate::class); }
    public function geoCell(): BelongsTo { return $this->belongsTo(GeoCell::class); }
    public function units(): HasMany { return $this->hasMany(DevelopmentUnit::class); }
}
