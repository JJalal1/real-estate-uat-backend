<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SavedPropertySearch;

class SavedSearchAlertService
{
    public function __construct(
        private readonly SavedPropertySearchService $searches,
        private readonly UserNotificationService $notifications,
    ) {}

    public function notifyPublishedProperty(int $propertyId): int
    {
        $property = Property::query()->whereKey($propertyId)->where('status', 'published')->first();
        if (! $property) return 0;

        $notified = 0;
        SavedPropertySearch::query()
            ->where('is_active', true)
            ->where('alert_frequency', 'instant')
            ->where('user_id', '<>', $property->user_id)
            ->orderBy('id')
            ->chunkById(100, function ($rows) use ($property, &$notified): void {
                foreach ($rows as $savedSearch) {
                    $matches = $this->searches->queryFor($savedSearch->filters ?? [])
                        ->whereKey($property->id)
                        ->exists();
                    if (! $matches) continue;

                    $notification = $this->notifications->create(
                        (int) $savedSearch->user_id,
                        'saved_search_match',
                        'عقار جديد يطابق بحثك',
                        $property->title,
                        'property',
                        (int) $property->id,
                        [
                            'saved_search_id' => (int) $savedSearch->id,
                            'saved_search_name' => $savedSearch->name,
                        ],
                    );
                    $savedSearch->forceFill([
                        'last_match_property_id' => max(
                            (int) ($savedSearch->last_match_property_id ?? 0),
                            (int) $property->id,
                        ),
                        'last_checked_at' => now(),
                    ])->save();
                    if ($notification !== null) $notified++;
                }
            });

        return $notified;
    }

    public function sendDailyDigests(): int
    {
        $sent = 0;
        SavedPropertySearch::query()
            ->where('is_active', true)
            ->where('alert_frequency', 'daily')
            ->orderBy('id')
            ->chunkById(100, function ($rows) use (&$sent): void {
                foreach ($rows as $savedSearch) {
                    $matches = $this->searches->newMatches($savedSearch, 20);
                    $newestId = $savedSearch->last_match_property_id;
                    foreach ($matches as $property) {
                        $newestId = max((int) ($newestId ?? 0), (int) $property->id);
                    }

                    if ($matches !== []) {
                        $first = $matches[0];
                        $count = count($matches);
                        $notification = $this->notifications->create(
                            (int) $savedSearch->user_id,
                            'saved_search_digest',
                            'ملخص بحثك المحفوظ',
                            $count === 1
                                ? 'يوجد عقار جديد يطابق «'.$savedSearch->name.'».'
                                : 'يوجد '.$count.' عقارات جديدة تطابق «'.$savedSearch->name.'».',
                            'property',
                            (int) $first->id,
                            [
                                'saved_search_id' => (int) $savedSearch->id,
                                'property_ids' => array_map(fn (Property $p) => (int) $p->id, $matches),
                            ],
                        );
                        if ($notification !== null) $sent++;
                    }

                    $savedSearch->forceFill([
                        'last_match_property_id' => $newestId,
                        'last_checked_at' => now(),
                    ])->save();
                }
            });

        return $sent;
    }
}
