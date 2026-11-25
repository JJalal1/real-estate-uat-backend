<?php

namespace App\Observers;

use App\Jobs\MatchPublishedProperty;
use App\Jobs\NotifyFavoritePrice;
use App\Models\Property;
use App\Services\BackgroundQueue;
use App\Services\PropertyPriceChangeAlertService;
use App\Services\SavedSearchAlertService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class PropertyExperienceObserver
{
    public function updated(Property $property): void
    {
        $id = (int) $property->id;
        if ($property->status !== 'published') return;
        $queues = app(BackgroundQueue::class);
        if ($property->wasChanged('status') && ! $queues->submit('instant_search', new MatchPublishedProperty($id))) {
            DB::afterCommit(static fn () => app(SavedSearchAlertService::class)->notifyPublishedProperty($id));
        }
        if ($property->wasChanged('price')) {
            $old = (float) $property->getOriginal('price');
            $new = (float) $property->price;
            $job = new NotifyFavoritePrice($id, $old, $new, (string) Str::uuid(), (string) $property->currency, now()->timestamp);
            if (! $queues->submit('favorite_price', $job)) {
                DB::afterCommit(static fn () => app(PropertyPriceChangeAlertService::class)->notify($id, $old, $new));
            }
        }
    }
}
