<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BrokerCellAssignment extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'geo_cell_id', 'broker_user_id', 'assigned_by_user_id', 'starts_at',
        'ends_at', 'ended_by_user_id', 'reason', 'end_reason',
    ];

    protected function casts(): array
    {
        return ['starts_at' => 'datetime', 'ends_at' => 'datetime'];
    }

    public function cell(): BelongsTo
    {
        return $this->belongsTo(GeoCell::class, 'geo_cell_id');
    }

    public function broker(): BelongsTo
    {
        return $this->belongsTo(User::class, 'broker_user_id');
    }

    public function assignedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_by_user_id');
    }
}
