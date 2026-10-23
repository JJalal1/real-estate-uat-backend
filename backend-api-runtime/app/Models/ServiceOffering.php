<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ServiceOffering extends Model
{
    protected $fillable = [
        'code','name_ar','name_en','description_ar','description_en','target_type','duration_days',
        'price_amount','currency','is_active','sort_order','created_by_user_id','created_by_name_snapshot',
    ];

    protected function casts(): array
    {
        return [
            'duration_days'=>'integer','price_amount'=>'decimal:2','is_active'=>'boolean','sort_order'=>'integer',
            'created_by_user_id'=>'integer',
        ];
    }
}
