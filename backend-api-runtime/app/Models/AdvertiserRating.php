<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AdvertiserRating extends Model
{
    protected $fillable = [
        'broker_deal_outcome_id','advertiser_user_id','advertiser_name_snapshot','rater_user_id','rater_name_snapshot',
        'source_property_id','rating','comment','status','moderated_by_user_id',
        'moderated_by_name_snapshot','moderation_reason','moderated_at',
    ];

    public function scopeConfirmedCustomerRatings(\Illuminate\Database\Eloquent\Builder $query): \Illuminate\Database\Eloquent\Builder
    {
        return $query->whereExists(function ($result): void {
            $result->selectRaw('1')->from('broker_deal_outcomes as confirmed_result')
                ->whereColumn('confirmed_result.id', 'advertiser_ratings.broker_deal_outcome_id')
                ->whereColumn('confirmed_result.advertiser_user_id', 'advertiser_ratings.advertiser_user_id')
                ->whereColumn('confirmed_result.customer_user_id', 'advertiser_ratings.rater_user_id')
                ->where('confirmed_result.status', 'confirmed');
        });
    }

    protected function casts(): array
    {
        return ['rating'=>'integer','moderated_at'=>'datetime'];
    }
}
