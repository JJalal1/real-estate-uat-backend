<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SavedPropertySearch;
use App\Models\UserNotification;
use Illuminate\Support\Facades\DB;

class SavedSearchAlertService
{
    public function __construct(
        private readonly SavedPropertySearchService $searches,
        private readonly UserNotificationService $notifications,
    ) {}

    public function notifyPublishedProperty(int $propertyId): int
    {
        $property = app(PropertyDiscoveryFilterService::class)->publicQuery()->whereKey($propertyId)->first();
        if (! $property) return 0;

        $notified = 0;
        SavedPropertySearch::query()
            ->where('is_active', true)
            ->where('alert_frequency', 'instant')
            ->where('user_id', '<>', $property->user_id)
            ->orderBy('id')
            ->chunkById(100, function ($rows) use ($property, &$notified): void {
                foreach ($rows as $savedSearch) {
                    $notified += DB::transaction(function () use ($savedSearch, $property): int {
                        $search = SavedPropertySearch::query()->whereKey($savedSearch->id)->lockForUpdate()->first();
                        if (!$search || !$search->is_active || $search->alert_frequency !== 'instant') return 0;
                        if (!$this->searches->queryFor($search->filters ?? [])->whereKey($property->id)->exists()) return 0;
                        if (UserNotification::query()->where('user_id', $search->user_id)->where('type', 'saved_search_match')
                            ->where('entity_type', 'property')->where('entity_id', $property->id)
                            ->where('data->saved_search_id', $search->id)->exists()) return 0;
                        $notification = $this->notifications->create(
                            (int) $search->user_id, 'saved_search_match', 'عقار جديد يطابق بحثك', $property->title,
                            'property', (int) $property->id,
                            ['saved_search_id' => (int) $search->id, 'saved_search_name' => $search->name],
                        );
                        $search->forceFill([
                            'last_match_property_id' => max((int)($search->last_match_property_id ?? 0), (int)$property->id),
                            'last_checked_at' => now(),
                        ])->save();
                        return $notification !== null ? 1 : 0;
                    });
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
