<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ApiToken extends Model
{
    protected $fillable = [
        'user_id','name','token_hash','token_prefix','expires_at','last_used_at',
        'ip_address','user_agent',
    ];
    protected $hidden = ['token_hash'];
    protected $casts = ['expires_at'=>'datetime','last_used_at'=>'datetime'];
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}
