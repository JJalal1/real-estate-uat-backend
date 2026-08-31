<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Property extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id','property_asset_id','geo_cell_id','owner_key','title','description','purpose','type','tenure_type','price','currency',
        'area_m2','area_value','area_unit','bedrooms','bathrooms','has_parking','building_facade','address','latitude','longitude','status',
        'contact_phone','contact_whatsapp','ownership_document_type','document_owner_name','owner_relationship_type','owner_relationship_note','review_status','submitted_at','published_at','reviewed_at','last_review_reason',
    ];

    protected $casts = [
        'price'=>'float','latitude'=>'float','longitude'=>'float','area_m2'=>'integer','area_value'=>'float',
        'bedrooms'=>'integer','bathrooms'=>'integer','has_parking'=>'boolean','submitted_at'=>'datetime','published_at'=>'datetime','reviewed_at'=>'datetime',
    ];

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function propertyAsset(): BelongsTo { return $this->belongsTo(PropertyAsset::class, 'property_asset_id'); }
    public function geoCell(): BelongsTo { return $this->belongsTo(GeoCell::class, 'geo_cell_id'); }

    public function documents(): HasMany { return $this->hasMany(ListingDocument::class)->orderBy('id'); }
    public function reviews(): HasMany { return $this->hasMany(ListingReview::class, 'listing_id')->orderBy('id'); }
    public function comments(): HasMany { return $this->hasMany(ListingComment::class)->orderBy('id'); }
    public function brokerVerifications(): HasMany { return $this->hasMany(ListingBrokerVerification::class, 'listing_id')->orderBy('id'); }

    public function images(): HasMany
    {
        return $this->hasMany(PropertyImage::class)
            ->orderByDesc('is_primary')->orderBy('sort_order')->orderBy('id');
    }
}
