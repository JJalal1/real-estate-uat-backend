<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PlatformSetting extends Model
{
    protected $fillable = ['key','value','value_type','group_key','label_ar','is_public','updated_by_user_id'];
    protected function casts(): array { return ['is_public'=>'boolean']; }
}
