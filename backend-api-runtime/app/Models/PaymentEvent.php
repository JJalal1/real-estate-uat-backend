<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PaymentEvent extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'service_order_id','actor_user_id','actor_name_snapshot','event','provider','provider_reference',
        'amount','currency','metadata','created_at',
    ];

    protected function casts(): array
    {
        return ['service_order_id'=>'integer','actor_user_id'=>'integer','amount'=>'decimal:2','metadata'=>'array','created_at'=>'datetime'];
    }
}
