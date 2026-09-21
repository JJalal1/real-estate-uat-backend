<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class PropertyAsset extends Model
{
    protected $fillable = [
        'created_by_user_id','identity_hash','identity_version','identity_kind','property_type','canonical_address','canonical_address_normalized',
        'canonical_latitude','canonical_longitude','area_m2','bedrooms','bathrooms','identity_notes','status',
        'building_reference','building_identity_key','unit_identity_key','unit_number','floor_number','land_boundary_geojson','land_boundary_hash',
    ];

    protected $casts = [
        'canonical_latitude'=>'float','canonical_longitude'=>'float','area_m2'=>'integer',
        'bedrooms'=>'integer','bathrooms'=>'integer','identity_version'=>'integer','land_boundary_geojson'=>'array',
    ];

    public function creator(): BelongsTo { return $this->belongsTo(User::class, 'created_by_user_id'); }
    public function listings(): HasMany { return $this->hasMany(Property::class, 'property_asset_id'); }
    public function publicationBlocks(): HasMany { return $this->hasMany(PropertyPublicationBlock::class, 'property_asset_id'); }
}
