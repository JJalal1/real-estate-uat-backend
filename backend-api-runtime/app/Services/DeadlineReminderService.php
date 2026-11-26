<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\ServiceEntitlement;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class DeadlineReminderService
{
    public const TYPES = ['payment_due_reminder', 'entitlement_expiry_reminder', 'listing_expiry_reminder'];

    public function stillDue(\App\Models\UserNotification $notice): bool
    {
        $date = $notice->data['due_at'] ?? null;
        if (! $date) return false;
        $date = \Illuminate\Support\Carbon::parse($date)->utc();
        if ($date->isPast()) return false;
        return match ($notice->type) {
            'payment_due_reminder' => PropertyPlatformReceivable::query()->whereKey($notice->entity_id)
                ->where('advertiser_user_id', $notice->user_id)->where('status', 'open')
                ->whereColumn('amount_paid', '<', 'amount_total')->where('due_at', $date)->exists(),
            'entitlement_expiry_reminder' => ServiceEntitlement::query()->where('service_order_id', $notice->entity_id)
                ->where('user_id', $notice->user_id)->where('status', 'active')->whereNull('revoked_at')
                ->where('ends_at', $date)->exists(),
            'listing_expiry_reminder' => Property::query()->whereKey($notice->entity_id)
                ->where('user_id', $notice->user_id)->where('status', 'published')
                ->where('published_at', $notice->data['published_at'] ?? null)->exists(),
        };
    }

    public function __construct(
        private readonly UserNotificationService $notices,
        private readonly BackgroundQueue $queues,
    ) {}

    public function receivables(): void
    {
        $now = now();
        $due = PropertyPlatformReceivable::query()->outstanding()->where('due_at', '<=', $now)
            ->where(fn ($q) => $q->whereNull('last_reminded_at')->orWhere('last_reminded_at', '<=', $now->copy()->subDay()));
        $ids = (clone $due)->orderBy('id')->limit(250)->pluck('id');
        foreach ($ids as $id) {
            DB::transaction(function () use ($due, $id, $now): void {
                $row = (clone $due)->whereKey($id)->lockForUpdate()->first();
                if (! $row) return;
                $amount = round($row->amount_total - $row->amount_paid, 2);
                $receiptPending = $row->status === 'under_review' || \App\Models\PropertyPayment::query()
                    ->where('deal_financial_term_id', $row->deal_financial_term_id)->where('mode', 'platform_receivable')
                    ->whereIn('status', ['proof_submitted', 'under_review'])->exists();
                $text = $receiptPending
                    ? 'إثبات سداد المستحق قيد المراجعة.'
                    : "عليك مستحق للمنصة قدره {$amount} {$row->currency}. يرجى السداد.";
                $this->notices->create($row->advertiser_user_id, 'platform_receivable_reminder',
                    'تذكير بمستحق المنصة', $text, 'property_platform_receivable', $row->id,
                    ['receivable_id' => $row->id]);
                $row->forceFill(['last_reminded_at' => $now])->save();
            }, 3);
        }
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
            $days = (int) config('background.'.$purpose.'_days');
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
                        array_filter(['due_at' => $deadline->toIso8601String(),
                            'published_at' => $type === 'listing_expiry_reminder' ? $row->published_at->toDateTimeString() : null]));
                });
            }
        });
    }
}
