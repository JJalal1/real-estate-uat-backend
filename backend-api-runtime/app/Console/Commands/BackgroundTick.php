<?php

namespace App\Console\Commands;

use App\Jobs\RunScheduledBackgroundTask;
use App\Services\BackgroundQueue;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class BackgroundTick extends Command
{
    protected $signature = 'background:tick';
    protected $description = 'Admit due work for enabled features with a live consumer';

    public function handle(BackgroundQueue $queues): int
    {
        $now = now('Asia/Aden');
        foreach ([
            'broker_reminders' => 1, 'availability' => 60, 'reports' => 1, 'daily_search' => 1,
            'receivables' => 5, 'entitlements' => 5, 'listing_expiry' => 5,
        ] as $feature => $minutes) {
            if (! $queues->enabled($feature)) continue;
            $slot = (string) intdiv($now->timestamp, 60 * $minutes);
            $queues->submit($feature, new RunScheduledBackgroundTask($feature, $now->timestamp), $slot);
        }
        // Also maintain receipts for installations using only event-driven consumers.
        if (in_array(true, config('background.features'), true)) {
            $expired = DB::table('background_receipts')->where('expires_at', '<', now())
                ->orderBy('expires_at')->limit(500)->pluck('event_key');
            if ($expired->isNotEmpty()) DB::table('background_receipts')->whereIn('event_key', $expired)->delete();
        }
        return self::SUCCESS;
    }
}
