<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class GeoCell extends Model
{
    protected $fillable = ['governorate_id', 'code', 'name_ar', 'name_en', 'boundary_json', 'is_active'];

    protected function casts(): array
    {
        return ['boundary_json' => 'array', 'is_active' => 'boolean'];
    }

    public function governorate(): BelongsTo
    {
        return $this->belongsTo(Governorate::class);
    }

    public function assignments(): HasMany
    {
        return $this->hasMany(BrokerCellAssignment::class, 'geo_cell_id')->latest('starts_at');
    }

    public function activeAssignment(): HasOne
    {
        return $this->hasOne(BrokerCellAssignment::class, 'geo_cell_id')->whereNull('ends_at');
    }

    public function properties(): HasMany
    {
        return $this->hasMany(Property::class, 'geo_cell_id');
    }
}
