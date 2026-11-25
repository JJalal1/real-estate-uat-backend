<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\ServiceEntitlement;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class DeadlineReminderService
{
    public function __construct(
        private readonly UserNotificationService $notices,
        private readonly BackgroundQueue $queues,
    ) {}

    public function receivables(): void
    {
        $lead = (int) config('background.receivable_lead_minutes');
        if ($lead <= 0) return;
        $query = PropertyPlatformReceivable::query()->where('status', 'open')
            ->whereColumn('amount_paid', '<', 'amount_total')->where('due_at', '>', now())
            ->where('due_at', '<=', now()->addMinutes($lead));
        $this->notify($query, 'payment_due_reminder', 'property_platform_receivable', 'advertiser_user_id',
            'due_at', 'اقترب موعد سداد مستحق المنصة');
    }

    public function entitlements(): void
    {
        $lead = (int) config('background.entitlement_lead_minutes');
        if ($lead <= 0) return;
        $query = ServiceEntitlement::query()->where('status', 'active')->whereNull('revoked_at')
            ->where('ends_at', '>', now())->where('ends_at', '<=', now()->addMinutes($lead));
        $this->notify($query, 'entitlement_expiry_reminder', 'service_order', 'user_id',
            'ends_at', 'اقترب انتهاء مدة الخدمة', 'service_order_id');
    }

    public function listings(): void
    {
        $lead = (int) config('background.expiry_lead_minutes');
        if ($lead <= 0) return;
        foreach (['sale', 'rent'] as $purpose) {
            $days = (int) config("background.${purpose}_days");
            if ($days <= 0) continue;
            $query = Property::query()->where('status', 'published')->where('purpose', $purpose)
                ->where('published_at', '>', now()->subDays($days))
                ->where('published_at', '<=', now()->addMinutes($lead)->subDays($days));
            $this->notify($query, 'listing_expiry_reminder', 'property', 'user_id', 'published_at',
                'اقترب موعد انتهاء إعلانك', 'id', $days);
        }
    }

    private function notify(Builder $query, string $type, string $entity, string $actorColumn,
        string $dateColumn, string $title, string $entityKey = 'id', int $days = 0): void
    {
        (clone $query)->select('id')->chunkById(100, function ($batch) use (
            $query, $type, $entity, $actorColumn, $dateColumn, $title, $entityKey, $days
        ) {
            foreach ($batch as $item) {
                DB::transaction(function () use ($item, $query, $type, $entity, $actorColumn, $dateColumn, $title, $entityKey, $days) {
                    $row = (clone $query)->whereKey($item->id)->lockForUpdate()->first();
                    if (! $row) return;
                    $deadline = $row->$dateColumn->copy()->addDays($days);
                    if ($deadline->isPast() || ! $this->queues->claim(
                        "$type:$row->id:$deadline->timestamp", $deadline->copy()->addDays(2)
                    )) return;
                    $this->notices->create($row->$actorColumn, $type, $title, null, $entity, $row->$entityKey,
                        ['due_at' => $deadline->toIso8601String()]);
                });
            }
        });
    }
}
