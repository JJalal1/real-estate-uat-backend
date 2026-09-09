<?php

namespace App\Observers;

use App\Models\Property;
use App\Services\PropertyPriceChangeAlertService;
use App\Services\SavedSearchAlertService;
use Illuminate\Support\Facades\DB;

class PropertyExperienceObserver
{
    public function updated(Property $property): void
    {
        $propertyId = (int) $property->id;

        if ($property->wasChanged('status') && $property->status === 'published') {
            DB::afterCommit(static function () use ($propertyId): void {
                app(SavedSearchAlertService::class)->notifyPublishedProperty($propertyId);
            });
        }

        if ($property->wasChanged('price') && $property->status === 'published') {
            $oldPrice = (float) $property->getOriginal('price');
            $newPrice = (float) $property->price;
            DB::afterCommit(static function () use ($propertyId, $oldPrice, $newPrice): void {
                app(PropertyPriceChangeAlertService::class)->notify(
                    $propertyId,
                    $oldPrice,
                    $newPrice,
                );
            });
        }
    }
}
