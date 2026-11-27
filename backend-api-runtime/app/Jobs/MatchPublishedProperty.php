<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class MatchPublishedProperty implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $propertyId, public ?int $publishedAt = null) {}

    public function handle(): void
    {
        // Jobs queued before the saved-search screen was retired can still be deserialized.
    }
}
