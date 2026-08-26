<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VerificationChallenge extends Model
{
    public const PURPOSE_PHONE = 'phone_verification';
    public const PURPOSE_PASSWORD_RESET = 'password_reset';

    protected $fillable = [
        'user_id','destination','purpose','code_hash','attempts','expires_at','consumed_at',
    ];
    protected $hidden = ['code_hash'];
    protected $casts = ['expires_at'=>'datetime','consumed_at'=>'datetime'];
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}
