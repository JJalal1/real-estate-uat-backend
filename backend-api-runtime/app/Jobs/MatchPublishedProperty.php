<?php

namespace App\Jobs;

use App\Services\SavedSearchAlertService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class MatchPublishedProperty implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $propertyId, public ?int $publishedAt = null) {}

    public function handle(SavedSearchAlertService $alerts): void
    {
        if ($this->publishedAt !== null && $this->publishedAt < now()->subDay()->timestamp) return;
        $alerts->notifyPublishedProperty($this->propertyId, $this->publishedAt);
    }
}
