<?php

namespace App\Services;

use Carbon\CarbonInterface;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

class BackgroundQueue
{
    public const ROUTES = [
        'push_messages' => 'push-urgent', 'push_other' => 'push',
        'broker_reminders' => 'timers', 'availability' => 'timers',
        'instant_search' => 'discovery', 'favorite_price' => 'discovery', 'daily_search' => 'discovery',
        'images' => 'media', 'duplicates' => 'listing-ai', 'reports' => 'reports',
        'receivables' => 'timers', 'entitlements' => 'timers', 'listing_expiry' => 'timers',
    ];

    public function heartbeat(string $queue): void
    {
        DB::table('background_workers')->upsert(
            [['queue' => $queue, 'heartbeat_at' => now()]], ['queue'], ['heartbeat_at']
        );
    }

    public function enabled(string $feature): bool
    {
        return isset(self::ROUTES[$feature]) && config("background.features.$feature", false);
    }

    public function submit(string $feature, ShouldQueue $job, ?string $slot = null): bool
    {
        if (! $this->enabled($feature)) return false;
        $queue = self::ROUTES[$feature];
        // The receipt, capacity check and queue insert must use the same transaction.
        if ((config('queue.connections.database.connection') ?: DB::getDefaultConnection()) !== DB::getDefaultConnection()) {
            return false;
        }
        try {
            return DB::transaction(function () use ($feature, $job, $queue, $slot): bool {
                $worker = DB::table('background_workers')->where('queue', $queue)
                    ->where('heartbeat_at', '>=', now()->subSeconds(45))->lockForUpdate()->first();
                if (! $worker) return false;
                $count = DB::table(config('queue.connections.database.table', 'jobs'))->where('queue', $queue)->count();
                if ($count >= max(1, config('background.capacity'))) return false;
                if ($slot !== null && ! $this->claim("schedule:$feature:$slot", now()->addDays(2))) return true;
                $job->onConnection('database')->onQueue($queue)->beforeCommit();
                Bus::dispatch($job);
                return true;
            });
        } catch (Throwable $e) {
            Log::warning('background.admission_failed', ['queue' => $queue, 'exception' => $e::class]);
            return false;
        }
    }

    // Call inside the transaction containing the corresponding database effect.
    public function claim(string $key, CarbonInterface $expiresAt): bool
    {
        return DB::table('background_receipts')->insertOrIgnore([
            'event_key' => hash('sha256', $key), 'expires_at' => $expiresAt,
        ]) === 1;
    }
}
