<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use LogicException;

class AuditLog extends Model
{
    public $timestamps = false;
    protected $guarded = [];
    protected function casts(): array { return ['metadata'=>'array','created_at'=>'datetime']; }

    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Audit logs are immutable.'));
        static::deleting(fn () => throw new LogicException('Audit logs are immutable.'));
    }
}
