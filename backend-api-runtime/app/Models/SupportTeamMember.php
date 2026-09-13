<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupportTeamMember extends Model
{
    protected $fillable = ['support_team_id','user_id','member_role','is_available','capacity','joined_at'];
    protected function casts(): array { return ['is_available'=>'boolean','capacity'=>'integer','joined_at'=>'datetime']; }
    public function team(): BelongsTo { return $this->belongsTo(SupportTeam::class, 'support_team_id'); }
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}
