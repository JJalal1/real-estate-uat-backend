<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SupportTeam extends Model
{
    protected $fillable = ['code','name_ar','governorate_id','manager_user_id','is_fallback','is_active'];
    protected function casts(): array { return ['is_fallback'=>'boolean','is_active'=>'boolean']; }
    public function governorate(): BelongsTo { return $this->belongsTo(Governorate::class); }
    public function manager(): BelongsTo { return $this->belongsTo(User::class, 'manager_user_id'); }
    public function members(): HasMany { return $this->hasMany(SupportTeamMember::class); }
}
