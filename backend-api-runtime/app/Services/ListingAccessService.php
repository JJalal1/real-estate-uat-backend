<?php

namespace App\Services;

use App\Models\Property;
use App\Models\User;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;

class ListingAccessService
{
    public function isProfessional(User $user): bool
    {
        return $user->hasMarketplaceProfessionalProfile();
    }

    public function metadata(User $user): array
    {
        $personal = ! $this->isProfessional($user);
        $count = Property::withoutGlobalScopes()->where('user_id', $user->id)
            ->where(fn ($query) => $query->whereNotNull('first_listed_at')->orWhereNotNull('published_at')
                ->orWhereNotNull('submitted_at'))->count();

        return [
            'contact_phone_policy' => app(ListingContactService::class)->policy(),
            'mode' => $personal ? 'personal' : 'professional',
            'listing_limit' => $personal ? 1 : null,
            'listing_count' => $count,
            'can_create' => $user->canCreateListings(),
            'upgrade_required' => $personal && ($user->first_marketplace_listing_id !== null || $count > 0),
        ];
    }

    /** Called with the account locked in the same transaction as submission. */
    public function authorizePublication(User $user, Property $listing, Request $request): void
    {
        abort_unless($user->canCreateListings(), 403);
        if ($this->isProfessional($user)) return;

        // Resubmitting or editing a historical listing never consumes another listing.
        if ($listing->first_listed_at !== null || $listing->published_at !== null || $listing->submitted_at !== null) return;
        $firstId = $user->first_marketplace_listing_id ?? Property::withoutGlobalScopes()
            ->where('user_id', $user->id)->where(fn ($query) => $query->whereNotNull('first_listed_at')
                ->orWhereNotNull('published_at')->orWhereNotNull('submitted_at'))->min('id');
        if ($firstId === null || (int) $firstId === (int) $listing->id) {
            if ($user->first_marketplace_listing_id === null) {
                $user->forceFill(['first_marketplace_listing_id' => $listing->id])->save();
            }
            return;
        }
        if (! $request->boolean('upgrade_to_broker')) {
            throw new HttpResponseException(response()->json([
                'code' => 'broker_upgrade_required',
                'upgrade_required' => true,
                'message' => 'رقِّ حسابك إلى دلال لنشر إعلانك الثاني وإدارة عقاراتك ومتابعة عملائك.',
            ], 409));
        }

        $user->forceFill([
            'account_type' => User::ACCOUNT_TYPE_BROKER,
            'first_marketplace_listing_id' => $firstId,
            'broker_enrolled_at' => now(),
        ])->save();
        app(AuditLogService::class)->record($user, 'account.broker_enrolled', $user,
            ['listing_id' => $listing->id], $request, $user->id);
    }
}
