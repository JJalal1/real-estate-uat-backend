<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\PropertyRequest;
use App\Models\User;

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
            ->update(['status'=>'expired','updated_at'=>now()]);
    }
}
