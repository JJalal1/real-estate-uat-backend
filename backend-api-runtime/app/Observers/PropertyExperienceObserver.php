<?php

namespace App\Observers;

use App\Models\Property;
use App\Services\SavedSearchAlertService;
use Illuminate\Support\Facades\DB;

class PropertyExperienceObserver
{
    public function updated(Property $property): void
    {
        if (! $property->wasChanged('status') || $property->status !== 'published') {
            return;
        }

        $propertyId = (int) $property->id;
        DB::afterCommit(static function () use ($propertyId): void {
            app(SavedSearchAlertService::class)->notifyPublishedProperty($propertyId);
        });
    }
}
