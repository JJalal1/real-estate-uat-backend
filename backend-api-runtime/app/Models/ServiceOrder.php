<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class ServiceOrder extends Model
{
    protected $fillable = [
        'reference','user_id','user_name_snapshot','service_offering_id','service_code_snapshot','service_name_snapshot',
        'target_type','target_id','target_title_snapshot','duration_days_snapshot','amount','currency','status',
        'payment_provider','payment_reference','paid_at','cancelled_at','refunded_at',
    ];

    protected function casts(): array
    {
        return [
            'user_id'=>'integer','service_offering_id'=>'integer','target_id'=>'integer','duration_days_snapshot'=>'integer',
            'amount'=>'decimal:2','paid_at'=>'datetime','cancelled_at'=>'datetime','refunded_at'=>'datetime',
        ];
    }

    public function entitlement(): HasOne
    {
        return $this->hasOne(ServiceEntitlement::class);
    }

    public function events(): HasMany
    {
        return $this->hasMany(PaymentEvent::class)->orderBy('id');
    }
}
