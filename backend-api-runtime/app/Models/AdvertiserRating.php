<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AdvertiserRating extends Model
{
    protected $fillable = [
        'advertiser_user_id','advertiser_name_snapshot','rater_user_id','rater_name_snapshot',
        'source_property_id','rating','comment','status','moderated_by_user_id',
        'moderated_by_name_snapshot','moderation_reason','moderated_at',
    ];

    protected function casts(): array
    {
        return ['rating'=>'integer','moderated_at'=>'datetime'];
    }
}
