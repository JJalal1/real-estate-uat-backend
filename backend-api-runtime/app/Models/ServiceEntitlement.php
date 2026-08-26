<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ServiceEntitlement extends Model
{
    protected $fillable = [
        'service_order_id','user_id','service_code','service_name_snapshot','target_type','target_id','target_title_snapshot',
        'starts_at','ends_at','status','granted_at','revoked_at',
    ];

    protected function casts(): array
    {
        return [
            'service_order_id'=>'integer','user_id'=>'integer','target_id'=>'integer','starts_at'=>'datetime','ends_at'=>'datetime',
            'granted_at'=>'datetime','revoked_at'=>'datetime',
        ];
    }
}
