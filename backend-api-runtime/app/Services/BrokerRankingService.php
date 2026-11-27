<?php

namespace App\Services;

use App\Models\Property;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class BrokerRankingService
{
    // Joined columns below contain only formerly approved public information.
    public const GOVERNORATE = "COALESCE(users.marketplace_governorate, CASE WHEN reviewed_profile.governorate = 'سقطرى' THEN 'أرخبيل سقطرى' ELSE reviewed_profile.governorate END)";
    public const IS_OFFICE = "COALESCE(users.marketplace_is_office, CASE WHEN reviewed_profile.type = 'office' THEN TRUE ELSE FALSE END)";
    public const OFFICE_NAME = "CASE WHEN users.marketplace_is_office IS NULL AND reviewed_profile.type = 'office' THEN reviewed_profile.office_name ELSE users.marketplace_office_name END";

    public function query(?string $governorate = null, bool $brokersOnly = true, bool $includePublicIndividuals = false): Builder
    {
        $ratings = DB::table('advertiser_ratings as rating')
            ->join('broker_deal_outcomes as result','result.id','=','rating.broker_deal_outcome_id')
            ->where('rating.status','visible')->where('result.status','confirmed')
            ->whereColumn('result.customer_user_id','rating.rater_user_id')
            ->whereColumn('result.advertiser_user_id','rating.advertiser_user_id')
            ->groupBy('rating.advertiser_user_id')
            ->selectRaw('rating.advertiser_user_id, COUNT(*) AS rating_count, AVG(rating.rating) AS rating_average');
        $deals = DB::table('broker_deal_outcomes as result')
            ->leftJoin('property_deal_financial_terms as term','term.broker_deal_outcome_id','=','result.id')
            ->leftJoin('property_platform_receivables as due','due.deal_financial_term_id','=','term.id')
            ->where('result.status','confirmed')->groupBy('result.advertiser_user_id')
            ->selectRaw('result.advertiser_user_id, COUNT(*) AS completed_deals')
            ->selectRaw('SUM(CASE WHEN result.confirmed_at >= ? THEN CASE WHEN due.id IS NULL OR due.status = ? THEN 1.0 ELSE 0.5 END ELSE 0 END) AS recent_deal_credit', [now()->subDays(90),'paid']);
        $listings = Property::query()->publiclyVisible()
            ->groupBy('user_id')->selectRaw('user_id, COUNT(*) AS active_listings')
            ->selectRaw('SUM(CASE WHEN (availability_notified_at IS NULL OR availability_notified_at > ?) '
                .'AND (availability_confirmed_at >= ? OR published_at >= ?) THEN 1 ELSE 0 END) AS recent_activity',
                [now()->subDays(2), now()->subDays(30), now()->subDays(30)]);
        $closed=DB::table('properties')->whereIn('availability_status',['sold','rented'])->groupBy('user_id')->selectRaw("user_id, SUM(CASE WHEN availability_status = 'sold' THEN 1 ELSE 0 END) AS sold_listings, SUM(CASE WHEN availability_status = 'rented' THEN 1 ELSE 0 END) AS rented_listings");
        $reviewedProfiles = DB::table('account_verification_profiles')
            ->where('status', 'approved')->whereNotNull('reviewed_at')
            ->select(['user_id', 'type', 'details->governorate as governorate', 'details->office_name as office_name']);
        $query = User::query()->where('users.account_status','active')->whereNotNull('users.phone_verified_at')
            ->leftJoinSub($reviewedProfiles, 'reviewed_profile', fn ($join) => $join->on('reviewed_profile.user_id', '=', 'users.id'))
            ->where(function ($eligible) use ($brokersOnly, $includePublicIndividuals): void {
                $eligible->whereNotNull('users.broker_enrolled_at')
                    ->orWhere(fn ($legacy) => $legacy->where('users.account_type', User::ACCOUNT_TYPE_BROKER)
                        ->where('users.broker_verification_status', User::BROKER_VERIFICATION_APPROVED)
                        ->whereNotNull('users.broker_verified_at')->whereDoesntHave('accountVerificationProfile'))
                    ->orWhereIn('reviewed_profile.type', $brokersOnly ? ['broker', 'office'] : ['owner', 'broker', 'office']);
                if ($includePublicIndividuals) $eligible->orWhereIn('users.id', app(PropertyDiscoveryFilterService::class)->publicQuery()->select('properties.user_id'));
            })
            ->leftJoinSub($closed,'closed_property',fn($join)=>$join->on('closed_property.user_id','=','users.id'))
            ->leftJoinSub($ratings,'customer_rating',fn ($join) => $join->on('customer_rating.advertiser_user_id','=','users.id'))
            ->leftJoinSub($deals,'completed_result',fn ($join) => $join->on('completed_result.advertiser_user_id','=','users.id'))
            ->leftJoinSub($listings,'active_property',fn ($join) => $join->on('active_property.user_id','=','users.id'))
            ->with('accountVerificationProfile')
            ->select('users.*')->selectRaw('COALESCE(closed_property.sold_listings,0) AS sold_listings, COALESCE(closed_property.rented_listings,0) AS rented_listings')
            ->selectRaw('COALESCE(customer_rating.rating_count,0) AS rating_count, COALESCE(customer_rating.rating_average,0) AS rating_average')
            ->selectRaw('COALESCE(completed_result.completed_deals,0) AS completed_deals, COALESCE(active_property.active_listings,0) AS active_listings');
        // Stars remain the actual customer average. Only the independent ordering score uses confidence, settlement and recency.
        $quality = '(COALESCE(customer_rating.rating_average,0) / 5.0) * (COALESCE(customer_rating.rating_count,0) * 1.0 / (COALESCE(customer_rating.rating_count,0) + 5.0))';
        $dealCredit = 'COALESCE(completed_result.recent_deal_credit,0)';
        $activity = 'COALESCE(active_property.recent_activity,0)';
        $score = "50.0 * $quality + 35.0 * (CASE WHEN $dealCredit >= 20 THEN 1.0 ELSE $dealCredit / 20.0 END) + 15.0 * (CASE WHEN $activity >= 20 THEN 1.0 ELSE $activity / 20.0 END)";
        $query->selectRaw("($score) AS ranking_score");
        if ($governorate !== null && $governorate !== '') {
            $query->orderByRaw('CASE WHEN '.self::GOVERNORATE.' = ? THEN 0 ELSE 1 END', [$governorate]);
        }
        return $query->orderByDesc('ranking_score')->orderByDesc('rating_count')->orderBy('users.id');
    }

    public function publicIdentity(User $user): array
    {
        $profile = $user->accountVerificationProfile;
        $approved = $profile?->isApproved() === true;
        $details = $approved ? ($profile->details ?? []) : [];
        $type = $approved && in_array($profile->type, ['broker', 'office'], true)
            ? $profile->type
            : 'individual';
        $officeName = null;
        if ($user->hasMarketplaceProfessionalProfile()) {
            $office = $user->marketplace_is_office === null ? $type === 'office' : (bool) $user->marketplace_is_office;
            $type = $office ? 'office' : 'broker';
            if ($office) {
                $officeName = $user->marketplace_is_office === null ? ($details['office_name'] ?? null) : $user->marketplace_office_name;
            }
        }
        $verified = $approved && $profile->type === $type;
        if ($verified && $type === 'office' && $user->marketplace_is_office !== null) {
            $verified = $officeName === ($details['office_name'] ?? null);
        }
        $region = $user->marketplace_governorate ?? ($details['governorate'] ?? null);
        return [
            'name' => $officeName ?: $user->name, 'account_type' => $type, 'office_name' => $officeName,
            'governorate' => $region === 'سقطرى' ? 'أرخبيل سقطرى' : $region, 'verified' => $verified,
        ];
    }

    public function publicData(User $user): array
    {
        $identity = $this->publicIdentity($user);
        return $identity + [
            'id' => (int) $user->id, 'bio' => $user->public_professional_bio,
            'photo_url'=>$user->public_professional_photo_path && ($user->hasMarketplaceProfessionalProfile() || $user->accountVerificationProfile?->isApproved()) ? url('/api/advertisers/'.$user->id.'/photo').'?v='.substr(hash('sha256',$user->public_professional_photo_path),0,16).'&format=jpeg-v1' : null,
            'rating_average'=>round((float)($user->rating_average ?? 0),2),'rating_count'=>(int)($user->rating_count ?? 0),
            'completed_deals'=>(int)($user->completed_deals ?? 0),'active_listings'=>(int)($user->active_listings ?? 0),
            'sold_listings'=>(int)($user->sold_listings ?? 0),'rented_listings'=>(int)($user->rented_listings ?? 0),
            'joined_at'=>$user->created_at?->toDateString(),
        ];
    }
}
