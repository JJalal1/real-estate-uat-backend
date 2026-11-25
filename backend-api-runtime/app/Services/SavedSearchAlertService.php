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
        $cutoff = now('Asia/Aden')->startOfDay()->utc();
        $due = SavedPropertySearch::query()->where('alert_frequency', 'daily')->where('is_active', true)
            ->where(fn ($q) => $q->whereNull('last_checked_at')->orWhere('last_checked_at', '<', $cutoff));
        $sent = 0;
        foreach ((clone $due)->orderBy('id')->limit(50)->pluck('id') as $id) {
            $sent += DB::transaction(function () use ($id, $due, $cutoff): int {
                $search = (clone $due)->whereKey($id)->lockForUpdate()->first();
                if (! $search) return 0;
                $from = $cutoff->copy()->subDay()->max($search->last_checked_at ?? $search->created_at);
                $query = $this->searches->queryFor($search->filters ?? [])
                    ->where('user_id', '<>', $search->user_id)
                    ->where('published_at', '>=', $from)->where('published_at', '<', $cutoff);
                $matches = (clone $query)->reorder()->orderByDesc('published_at')->orderByDesc('id')->limit(20)->get(['id']);
                $notice = null;
                if ($matches->isNotEmpty()) {
                    $count = $matches->count() < 20 ? $matches->count() : $query->count();
                    $notice = $this->notifications->create($search->user_id, 'saved_search_digest',
                        'ملخص بحثك المحفوظ', "عدد العقارات الجديدة المطابقة لبحثك «$search->name» هو $count.",
                        'property', $matches->first()->id, ['saved_search_id' => $id,
                            'property_ids' => $matches->modelKeys(), 'total_count' => $count]);
                }
                $search->forceFill(['last_checked_at' => $cutoff,
                    'last_match_property_id' => max((int) $search->last_match_property_id, (int) $matches->max('id')) ?: null])->save();
                return $notice ? 1 : 0;
            });
        }
        return $sent;
    }
}
