<?php

namespace App\Jobs;

use App\Models\Property;
use App\Services\ListingWorkflowService;
use App\Services\ListingDuplicateAssessment;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class AssessListingPhotos implements ShouldQueue
{
    use Queueable, InteractsWithQueue;

    public int $tries = 5;

    public function __construct(public int $propertyId, public int $submissionId) {}

    public function handle(ListingWorkflowService $workflow, ListingDuplicateAssessment $assessment): void
    {
        $property = Property::query()->find($this->propertyId);
        if (! $property || ! in_array($property->review_status, ['submitted', 'under_review'], true)
            || $assessment->submissionId($property) !== $this->submissionId) return;
        $delay = $assessment->retryDelay($property, $this->submissionId);
        if ($delay > 0) {
            $this->release($delay);
            return;
        }
        $workflow->assessSubmittedPhotos($property, $this->submissionId);
    }
}
