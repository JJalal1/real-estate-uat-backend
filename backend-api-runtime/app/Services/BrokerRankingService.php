<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class BrokerRankingService
{
    public function query(?string $governorate = null, bool $brokersOnly = true): Builder
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
        $listings = DB::table('properties')->where('status','published')->where('availability_status','available')
            ->whereNotExists(function ($q): void {
                $q->selectRaw('1')->from('property_platform_receivables as financial_due')
                    ->whereColumn('financial_due.advertiser_user_id','properties.user_id')
                    ->whereIn('financial_due.status',['open','under_review','overdue','disputed'])
                    ->whereColumn('financial_due.amount_paid','<','financial_due.amount_total')->where('financial_due.due_at','<=',now());
            })
            ->where(function ($query): void { $query->whereNull('availability_notified_at')->orWhere('availability_notified_at','>',now()->subDays(2)); })
            ->whereNull('financial_hold_at')->groupBy('user_id')->selectRaw('user_id, COUNT(*) AS active_listings')
            ->selectRaw('SUM(CASE WHEN availability_confirmed_at >= ? OR published_at >= ? THEN 1 ELSE 0 END) AS recent_activity', [now()->subDays(30),now()->subDays(30)]);
        $query = User::query()->where('users.account_status','active')->whereNotNull('users.phone_verified_at')
            ->whereHas('accountVerificationProfile',fn ($q) => $q->where('status','approved')->whereNotNull('reviewed_at')
                ->whereIn('type',$brokersOnly ? [AccountVerificationProfile::TYPE_BROKER,AccountVerificationProfile::TYPE_OFFICE] : [AccountVerificationProfile::TYPE_OWNER,AccountVerificationProfile::TYPE_BROKER,AccountVerificationProfile::TYPE_OFFICE]))
            ->leftJoinSub($ratings,'customer_rating',fn ($join) => $join->on('customer_rating.advertiser_user_id','=','users.id'))
            ->leftJoinSub($deals,'completed_result',fn ($join) => $join->on('completed_result.advertiser_user_id','=','users.id'))
            ->leftJoinSub($listings,'active_property',fn ($join) => $join->on('active_property.user_id','=','users.id'))
            ->with('accountVerificationProfile')
            ->select('users.*')
            ->selectRaw('COALESCE(customer_rating.rating_count,0) AS rating_count, COALESCE(customer_rating.rating_average,0) AS rating_average')
            ->selectRaw('COALESCE(completed_result.completed_deals,0) AS completed_deals, COALESCE(active_property.active_listings,0) AS active_listings');
        // Stars remain the actual customer average. Only the independent ordering score uses confidence, settlement and recency.
        $quality = '(COALESCE(customer_rating.rating_average,0) / 5.0) * (COALESCE(customer_rating.rating_count,0) * 1.0 / (COALESCE(customer_rating.rating_count,0) + 5.0))';
        $dealCredit = 'COALESCE(completed_result.recent_deal_credit,0)';
        $activity = 'COALESCE(active_property.recent_activity,0)';
        $score = "50.0 * $quality + 35.0 * (CASE WHEN $dealCredit >= 20 THEN 1.0 ELSE $dealCredit / 20.0 END) + 15.0 * (CASE WHEN $activity >= 20 THEN 1.0 ELSE $activity / 20.0 END)";
        $query->selectRaw("($score) AS ranking_score");
        if ($governorate !== null && $governorate !== '') {
            $local = DB::table('account_verification_profiles')->select('user_id')->where('status','approved')
                ->where('details->governorate',$governorate);
            $query->leftJoinSub($local,'local_professional',fn ($join) => $join->on('local_professional.user_id','=','users.id'))
                ->orderByRaw('CASE WHEN local_professional.user_id IS NULL THEN 1 ELSE 0 END');
        }
        return $query->orderByDesc('ranking_score')->orderByDesc('rating_count')->orderBy('users.id');
    }

    public function publicData(User $user): array
    {
        $profile = $user->accountVerificationProfile;
        $details = $profile?->details ?? [];
        return [
            'id'=>(int)$user->id,'name'=>$profile?->type === 'office' ? ($details['office_name'] ?? $user->name) : $user->name,
            'account_type'=>$profile?->type ?? 'broker','verified'=>$profile?->isApproved() ?? false,
            'governorate'=>$details['governorate'] ?? null,'work_areas'=>$details['work_areas'] ?? [],
            'specializations'=>$details['specialties'] ?? [],'bio'=>$user->public_professional_bio,
            'photo_url'=>$user->public_professional_photo_path ? url('/api/advertisers/'.$user->id.'/photo').'?v='.substr(hash('sha256',$user->public_professional_photo_path),0,16) : null,
            'rating_average'=>round((float)($user->rating_average ?? 0),2),'rating_count'=>(int)($user->rating_count ?? 0),
            'completed_deals'=>(int)($user->completed_deals ?? 0),'active_listings'=>(int)($user->active_listings ?? 0),
            'joined_at'=>$user->created_at?->toDateString(),
        ];
    }
}
