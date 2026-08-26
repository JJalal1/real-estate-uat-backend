<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Developer extends Model
{
    protected $fillable = [
        'name','slug','description','website','phone','email','logo_url','status',
        'created_by_user_id','created_by_name_snapshot',
    ];

    public function developments(): HasMany { return $this->hasMany(Development::class); }
}
