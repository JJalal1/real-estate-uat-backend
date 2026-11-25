<?php

namespace App\Jobs;

use App\Http\Controllers\Api\GeneralManagerInsightsController;
use App\Services\BackgroundQueue;
use App\Services\BrokerAvailabilityService;
use App\Services\BrokerCustomerFollowupService;
use App\Services\DeadlineReminderService;
use App\Services\SavedSearchAlertService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class RunScheduledBackgroundTask implements ShouldQueue
{
    use Queueable;

    public function __construct(public string $feature, public int $createdAt) {}

    public function handle(BackgroundQueue $queues): void
    {
        if (! $queues->enabled($this->feature) || $this->createdAt < now()->subMinutes(10)->timestamp) return;
        match ($this->feature) {
            'broker_reminders' => app(BrokerCustomerFollowupService::class)->sweep(100),
            'availability' => app(BrokerAvailabilityService::class)->sweep(100),
            'daily_search' => app(SavedSearchAlertService::class)->sendDailyDigests(),
            'receivables' => app(DeadlineReminderService::class)->receivables(),
            'entitlements' => app(DeadlineReminderService::class)->entitlements(),
            'listing_expiry' => app(DeadlineReminderService::class)->listings(),
            'reports' => app(GeneralManagerInsightsController::class)->refreshSummary(),
        };
    }
}
