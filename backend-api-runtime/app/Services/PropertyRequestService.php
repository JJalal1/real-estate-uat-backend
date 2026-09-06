<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\Governorate;
use App\Models\Property;
use App\Models\PropertyRequest;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

class PropertyRequestService
{
    public function isEligibleResearcher(User $user): bool
    {
        return AccountVerificationProfile::query()
            ->where('user_id', $user->id)
            ->where('status', AccountVerificationProfile::STATUS_APPROVED)
            ->whereNotNull('reviewed_at')
            ->whereIn('type', [
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ])
            ->exists();
    }

    /** @return array{governorate_id:int,geo_cell_id:int,governorate:string,district:string} */
    public function resolveLocation(array $validated): array
    {
        $governorate = Governorate::query()
            ->where('is_active', true)
            ->where(function (Builder $query) use ($validated): void {
                if (isset($validated['governorate_id'])) {
                    $query->whereKey($validated['governorate_id']);
                } else {
                    $query->where('name_ar', $validated['governorate']);
                }
            })
            ->first();

        $cell = $governorate?->cells()
            ->where('is_active', true)
            ->where(function (Builder $query) use ($validated): void {
                if (isset($validated['geo_cell_id'])) {
                    $query->whereKey($validated['geo_cell_id']);
                } else {
                    $query->where('name_ar', $validated['district']);
                }
            })
            ->first();

        if (! $governorate || ! $cell) {
            throw ValidationException::withMessages([
                'district' => ['Choose an active district from the platform region data.'],
            ]);
        }

        return [
            'governorate_id' => $governorate->id,
            'geo_cell_id' => $cell->id,
            'governorate' => $governorate->name_ar,
            'district' => $cell->name_ar,
        ];
    }

    public function expireDue(): void
    {
        PropertyRequest::query()
            ->whereIn('status', ['active', 'matched'])
            ->where('expires_at', '<=', now())
            ->update(['status' => 'expired', 'expired_at' => now(), 'updated_at' => now()]);
    }

    /** @return Collection<int, Property> */
    public function eligibleProperties(User $researcher, PropertyRequest $request): Collection
    {
        return Property::query()
            ->where('user_id', $researcher->id)
            ->where('status', 'published')
            ->where('review_status', 'approved')
            ->where('purpose', $request->operation_type)
            ->where('type', $request->property_type)
            ->where('currency', $request->currency)
            ->where('geo_cell_id', $request->geo_cell_id)
            ->whereBetween('price', [$request->budget_min, $request->budget_max])
            ->when($request->requested_area_min !== null, fn (Builder $query) => $query->where('area_m2', '>=', $request->requested_area_min))
            ->when($request->requested_area_max !== null, fn (Builder $query) => $query->where('area_m2', '<=', $request->requested_area_max))
            ->when(
                $request->rooms !== null && in_array($request->property_type, ['apartment', 'house', 'villa'], true),
                fn (Builder $query) => $query->where('bedrooms', '>=', $request->rooms),
            )
            ->get();
    }

    /**
     * The researcher query is bounded to 300 current requests for UAT, but its
     * coarse matching happens in SQL before that cap instead of loading every
     * request and performing an O(requests × properties) PHP scan. The owned
     * property input is capped at 250 for the current UAT scale; pagination or
     * a normalized matching table is required before that limit is raised.
     *
     * @return Collection<int, PropertyRequest>
     */
    public function matchingRequests(User $researcher): Collection
    {
        $properties = Property::query()
            ->where('user_id', $researcher->id)
            ->where('status', 'published')
            ->where('review_status', 'approved')
            ->latest('id')
            ->limit(250)
            ->get();

        if ($properties->isEmpty()) {
            return collect();
        }

        return PropertyRequest::query()
            ->whereIn('status', ['active', 'matched'])
            ->where('expires_at', '>', now())
            ->where(function (Builder $requests) use ($properties): void {
                foreach ($properties as $property) {
                    $requests->orWhere(function (Builder $match) use ($property): void {
                        $match->where('operation_type', $property->purpose)
                            ->where('property_type', $property->type)
                            ->where('currency', $property->currency)
                            ->where('geo_cell_id', $property->geo_cell_id)
                            ->where('budget_min', '<=', $property->price)
                            ->where('budget_max', '>=', $property->price)
                            ->where(fn (Builder $area) => $area->whereNull('requested_area_min')->orWhere('requested_area_min', '<=', $property->area_m2))
                            ->where(fn (Builder $area) => $area->whereNull('requested_area_max')->orWhere('requested_area_max', '>=', $property->area_m2));

                        if (in_array($property->type, ['apartment', 'house', 'villa'], true)) {
                            $match->where(fn (Builder $rooms) => $rooms->whereNull('rooms')->orWhere('rooms', '<=', $property->bedrooms));
                        }
                    });
                }
            })
            ->withCount('suggestions')
            ->latest('id')
            ->limit(300)
            ->get();
    }
}
