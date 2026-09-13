<?php

namespace App\Models;

use App\Services\PropertySaiService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Property extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id', 'property_asset_id', 'current_sai_term_id', 'geo_cell_id', 'owner_key', 'title', 'description', 'purpose', 'type', 'tenure_type', 'price', 'currency',
        'price_display_mode', 'monthly_rent', 'rental_term_months', 'advance_months', 'financial_hold_at', 'financial_hold_reason',
        'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'building_facade', 'address', 'latitude', 'longitude', 'status',
        'contact_phone', 'contact_whatsapp', 'ownership_document_type', 'document_owner_name', 'owner_relationship_type', 'owner_relationship_note', 'review_status', 'submitted_at', 'published_at', 'reviewed_at', 'last_review_reason',
    ];

    protected $casts = [
        'price' => 'float', 'monthly_rent'=>'float', 'rental_term_months'=>'integer', 'advance_months'=>'integer',
        'latitude' => 'float', 'longitude' => 'float', 'area_m2' => 'integer', 'area_value' => 'float',
        'bedrooms' => 'integer', 'bathrooms' => 'integer', 'has_parking' => 'boolean', 'submitted_at' => 'datetime', 'published_at' => 'datetime', 'reviewed_at' => 'datetime',
        'financial_hold_at'=>'datetime',
    ];

    protected static function booted(): void
    {
        static::addGlobalScope('financial_public_visibility', function (Builder $builder): void {
            if (app()->runningInConsole()) return;
            $request=request();
            if (!$request->isMethod('GET')) return;
            $path=$request->path();
            if (! in_array($path, ['api/properties','api/properties/nearby'], true)) return;
            $builder->whereNotExists(function ($query): void {
                $query->selectRaw('1')->from('property_platform_receivables as financial_due')
                    ->whereColumn('financial_due.advertiser_user_id','properties.user_id')
                    ->whereIn('financial_due.status',['open','under_review','overdue','disputed'])
                    ->whereColumn('financial_due.amount_paid','<','financial_due.amount_total')
                    ->where('financial_due.due_at','<=',now());
            });
        });

        static::saving(function (Property $property): void {
            if (! $property->exists) return;
            $stateChanged = $property->isDirty('status') || $property->isDirty('review_status');
            if (! $stateChanged) return;
            $requiresReadySai = in_array((string) $property->status, ['pending', 'published'], true)
                || in_array((string) $property->review_status, ['submitted', 'under_review', 'approved'], true);
            if (! $requiresReadySai) return;

            /** @var User $advertiser */
            $advertiser = $property->user()->firstOrFail();
            if (! $advertiser->verificationProfile()?->isApproved()) return;

            $policyProperty = Property::query()->findOrFail($property->getKey());
            $policyProperty->purpose = $property->purpose;
            app(PropertySaiService::class)->assertReadyForSubmission($policyProperty, $advertiser);
        });

        static::updating(function (Property $property): void {
            if ($property->getOriginal('review_status') === 'returned_for_correction'
                && $property->review_status === 'draft') {
                $property->review_status = 'returned_for_correction';
                $property->last_review_reason = $property->getOriginal('last_review_reason');
                $property->reviewed_at = $property->getOriginal('reviewed_at');
            }
        });
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function propertyAsset(): BelongsTo { return $this->belongsTo(PropertyAsset::class, 'property_asset_id'); }
    public function currentSaiTerm(): BelongsTo { return $this->belongsTo(PropertySaiTerm::class, 'current_sai_term_id'); }
    public function geoCell(): BelongsTo { return $this->belongsTo(GeoCell::class, 'geo_cell_id'); }
    public function documents(): HasMany { return $this->hasMany(ListingDocument::class)->orderBy('id'); }
    public function reviews(): HasMany { return $this->hasMany(ListingReview::class, 'listing_id')->orderBy('id'); }
    public function comments(): HasMany { return $this->hasMany(ListingComment::class)->orderBy('id'); }
    public function brokerVerifications(): HasMany { return $this->hasMany(ListingBrokerVerification::class, 'listing_id')->orderBy('id'); }
    public function images(): HasMany { return $this->hasMany(PropertyImage::class)->orderByDesc('is_primary')->orderBy('sort_order')->orderBy('id'); }
}
