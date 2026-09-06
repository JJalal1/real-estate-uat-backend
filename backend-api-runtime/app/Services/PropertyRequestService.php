<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\PropertyRequest;
use App\Models\Property;
use App\Models\User;
use Illuminate\Support\Collection;

class PropertyRequestService
{
    public function isEligibleResearcher(User $user): bool
    {
        return AccountVerificationProfile::query()->where('user_id', $user->id)
            ->where('status', AccountVerificationProfile::STATUS_APPROVED)
            ->whereNotNull('reviewed_at')
            ->whereIn('type', [AccountVerificationProfile::TYPE_BROKER, AccountVerificationProfile::TYPE_OFFICE])
            ->exists();
    }

    public function expireDue(): void
    {
        PropertyRequest::query()->whereIn('status', ['active','matched'])->where('expires_at', '<=', now())
            ->update(['status'=>'expired','expired_at'=>now(),'updated_at'=>now()]);
    }

    /** @return Collection<int, Property> */
    public function eligibleProperties(User $researcher, PropertyRequest $propertyRequest): Collection
    {
        return Property::query()
            ->where('user_id', $researcher->id)
            ->where('status', 'published')
            ->where('review_status', 'approved')
            ->get()
            ->filter(fn (Property $property) => $this->matches($propertyRequest, $property))
            ->values();
    }

    public function matches(PropertyRequest $request, Property $property): bool
    {
        if ($property->purpose !== $request->operation_type
            || $property->type !== $request->property_type
            || $property->price < $request->budget_min
            || $property->price > $request->budget_max) {
            return false;
        }
        if ($request->requested_area_min !== null && ($property->area_m2 === null || $property->area_m2 < $request->requested_area_min)) return false;
        if ($request->requested_area_max !== null && ($property->area_m2 === null || $property->area_m2 > $request->requested_area_max)) return false;
        if ($request->rooms !== null && in_array($request->property_type, ['apartment','house','villa'], true) && ($property->bedrooms ?? 0) < $request->rooms) return false;

        $address = mb_strtolower((string) $property->address);
        foreach ([$request->governorate, $request->district, $request->area] as $place) {
            if ($place && ! str_contains($address, mb_strtolower($place))) return false;
        }
        return true;
    }
}
