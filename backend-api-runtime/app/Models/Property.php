<?php

namespace App\Models;

use App\Services\PropertySaiService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Property extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id', 'property_asset_id', 'current_sai_term_id', 'geo_cell_id', 'owner_key', 'title', 'description', 'purpose', 'type', 'tenure_type', 'price', 'currency',
        'listing_input_version', 'rental_conditions', 'price_display_mode', 'monthly_rent', 'rental_term_months', 'advance_months', 'financial_hold_at', 'financial_hold_reason',
        'floors_count', 'units_per_floor', 'shop_openings', 'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'has_elevator', 'building_facade', 'address', 'latitude', 'longitude', 'status',
        'parking_spaces', 'has_separate_majlis', 'has_majlis_bathroom', 'land_use', 'street_width_m', 'has_yard',
        'office_rooms', 'farm_water_source', 'farm_crop_type', 'section_elevator',
        'building_reference', 'unit_number', 'floor_number', 'unit_occupies_entire_floor', 'land_boundary_geojson',
        'duplicate_check_status', 'duplicate_check_score', 'duplicate_check_metadata', 'duplicate_self_verification', 'duplicate_checked_at',
        'contact_phone', 'contact_whatsapp', 'ownership_document_type', 'document_owner_name', 'owner_relationship_type', 'owner_relationship_note', 'review_status', 'submitted_at', 'published_at', 'reviewed_at', 'last_review_reason',
    ];

    protected $casts = [
        'floors_count'=>'integer', 'units_per_floor'=>'array', 'shop_openings'=>'integer',
        'parking_spaces' => 'integer', 'has_separate_majlis' => 'boolean', 'has_majlis_bathroom' => 'boolean',
        'street_width_m' => 'float', 'has_yard' => 'boolean', 'office_rooms' => 'integer', 'section_elevator' => 'boolean',
        'listing_input_version' => 'integer', 'rental_conditions' => 'array',
        'has_elevator' => 'boolean', 'spotlight_until' => 'datetime',
        'price' => 'float', 'monthly_rent'=>'float', 'rental_term_months'=>'integer', 'advance_months'=>'integer',
        'latitude' => 'float', 'longitude' => 'float', 'area_m2' => 'integer', 'area_value' => 'float',
        'bedrooms' => 'integer', 'bathrooms' => 'integer', 'unit_occupies_entire_floor' => 'boolean', 'has_parking' => 'boolean', 'submitted_at' => 'datetime', 'published_at' => 'datetime', 'reviewed_at' => 'datetime',
        'availability_confirmed_at'=>'datetime','availability_due_at'=>'datetime','availability_notified_at'=>'datetime','availability_status'=>'string','financial_hold_at'=>'datetime','land_boundary_geojson'=>'array','duplicate_check_score'=>'integer','duplicate_check_metadata'=>'array','duplicate_self_verification'=>'array','duplicate_checked_at'=>'datetime',
    ];

    protected static function booted(): void
    {
        static::addGlobalScope('unexpired_drafts', fn (Builder $query) => $query->where(fn ($q) =>
            $q->whereNull($query->qualifyColumn('draft_expires_at'))->orWhere($query->qualifyColumn('draft_expires_at'), '>', now())));
        static::creating(function (Property $property): void {
            if ($property->status === 'draft' && ($property->review_status ?? 'draft') === 'draft'
                && !$property->first_listed_at && !$property->published_at && !$property->submitted_at && !$property->reviewed_at) {
                $property->draft_expires_at = now()->addDays(7);
            }
        });
        static::saving(function (Property $property): void {
            if ($property->status !== 'draft' || ($property->review_status ?? 'draft') !== 'draft' || $property->first_listed_at) {
                $property->draft_expires_at = null;
            }
            if (! $property->exists) return;
            $stateChanged = $property->isDirty('status') || $property->isDirty('review_status');
            if (! $stateChanged) return;
            $requiresReadySai = in_array((string) $property->status, ['pending', 'published'], true)
                || in_array((string) $property->review_status, ['submitted', 'under_review', 'approved'], true);
            if (! $requiresReadySai) return;

            /** @var User $advertiser */
            $advertiser = $property->user()->firstOrFail();
            // Loaded models can predate an independent pricing or term update.
            $policyProperty = static::query()->findOrFail($property->getKey());
            foreach (['purpose', 'price', 'monthly_rent', 'advance_months', 'currency', 'listing_input_version', 'current_sai_term_id'] as $field) {
                if ($property->isDirty($field)) $policyProperty->$field = $property->$field;
            }
            if (! $policyProperty->current_sai_term_id && (int) $advertiser->identity_policy_version === 0
                && $advertiser->broker_enrolled_at === null && ! $advertiser->hasApprovedVerificationProfile()
                && ! PropertySaiTerm::query()->where('property_id', $property->id)->exists()) return;

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

    public function scopePubliclyAvailable(Builder $query): Builder
    {
        return $query->where('status', 'published')->where('availability_status', 'available')
            ->whereHas('user', fn (Builder $owner) => $owner->whereNull('support_publication_hold_case_id'));
    }

    public function scopePubliclyVisible(Builder $query): Builder
    {
        return $query->publiclyAvailable();
    }

    public function isPubliclyAvailable(): bool
    {
        if ($this->status !== 'published' || ($this->availability_status ?? 'available') !== 'available') return false;
        $owner = $this->relationLoaded('user') ? $this->getRelation('user') : null;
        if ($owner && array_key_exists('support_publication_hold_case_id', $owner->getAttributes())) {
            return $owner->support_publication_hold_case_id === null;
        }

        return $this->user()->whereNull('support_publication_hold_case_id')->exists();
    }

    public function isPubliclyVisible(): bool
    {
        return $this->isPubliclyAvailable() && static::query()
            ->whereKey($this->getKey())
            ->publiclyVisible()
            ->exists();
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
    public function primaryImage(): HasOne { return $this->hasOne(PropertyImage::class)->where('is_primary', true)->orderBy('sort_order')->orderBy('id'); }
}
