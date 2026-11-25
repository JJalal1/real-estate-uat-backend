<?php

namespace App\Jobs;

use App\Services\SavedSearchAlertService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class MatchPublishedProperty implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $propertyId) {}

    public function handle(SavedSearchAlertService $alerts): void
    {
        $alerts->notifyPublishedProperty($this->propertyId);
    }
}
