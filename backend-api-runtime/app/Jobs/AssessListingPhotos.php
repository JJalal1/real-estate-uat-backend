<?php

namespace App\Jobs;

use App\Models\Property;
use App\Services\ListingWorkflowService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class AssessListingPhotos implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $propertyId, public int $submissionId) {}

    public function handle(ListingWorkflowService $workflow): void
    {
        $property = Property::query()->find($this->propertyId);
        if ($property) $workflow->assessSubmittedPhotos($property, $this->submissionId);
    }
}
