<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ListingImageUploadIntent extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'user_id' => 'integer',
            'listing_editor_draft_id' => 'integer',
            'byte_length' => 'integer',
            'signed_until' => 'datetime',
            'purge_after' => 'datetime',
        ];
    }
}

