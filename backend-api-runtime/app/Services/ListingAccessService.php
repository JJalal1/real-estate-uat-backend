<?php

namespace App\Services;

use App\Models\Property;
use App\Models\User;
use Illuminate\Http\Exceptions\HttpResponseException;

class ListingAccessService
{
    public function isProfessional(User $user): bool
    {
        return $user->hasApprovedVerificationProfile('broker') || $user->hasApprovedVerificationProfile('office');
    }

    public function personalLimitApplies(User $user): bool
    {
        // v0 is the existing historical local/test compatibility policy, never
        // granted by modern registration. Approved owners use the personal cap.
        return ! $this->isProfessional($user)
            && ((int) $user->identity_policy_version >= 1 || $user->isOwnerVerified());
    }

    public function metadata(User $user): array
    {
        $personal = $this->personalLimitApplies($user);
        $count = Property::query()->withoutGlobalScopes()->where('user_id', $user->id)
            ->where('status', '<>', 'archived')->count();
        $limitReached = $personal && $count >= 1;
        return ['mode' => $this->isProfessional($user) ? 'professional' : 'personal',
            'listing_limit' => $personal ? 1 : null, 'listing_count' => $count,
            'can_create' => $user->canCreateListings() && ! $limitReached,
            'upgrade_required' => $limitReached,
            'upgrade_path' => '/account-verification?upgrade=broker'];
    }

    public function assertCanCreate(User $user): void
    {
        if (! $this->personalLimitApplies($user)) return;
        if (Property::query()->withoutGlobalScopes()->where('user_id', $user->id)->where('status', '<>', 'archived')->exists()) {
            throw new HttpResponseException(response()->json([
                'message' => 'لديك عقار شخصي بالفعل. فعّل حساب دلال لإدارة عدة عقارات بعد اعتماد التوثيق.',
                'code' => 'personal_listing_limit', 'upgrade_required' => true,
                'upgrade_path' => '/account-verification?upgrade=broker',
            ], 409));
        }
    }
}
