<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Governorate extends Model
{
    protected $fillable = ['code', 'name_ar', 'name_en', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function cells(): HasMany
    {
        return $this->hasMany(GeoCell::class);
    }
}
