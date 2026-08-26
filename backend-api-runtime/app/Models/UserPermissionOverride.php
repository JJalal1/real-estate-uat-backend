<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserPermissionOverride extends Model
{
    protected $fillable = ['user_id','permission_id','effect','assigned_by_user_id','reason'];
    public function permission(): BelongsTo { return $this->belongsTo(Permission::class); }
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}
