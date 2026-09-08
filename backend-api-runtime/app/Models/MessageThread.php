<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class MessageThread extends Model
{
    protected $fillable = ['property_id','sai_term_id','started_by_user_id','conversation_key','last_message_at'];
    protected function casts(): array { return ['last_message_at'=>'datetime']; }
    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function saiTerm(): BelongsTo { return $this->belongsTo(PropertySaiTerm::class, 'sai_term_id'); }
    public function participants(): HasMany { return $this->hasMany(MessageThreadParticipant::class,'thread_id'); }
    public function messages(): HasMany { return $this->hasMany(PrivateMessage::class,'thread_id'); }
}
