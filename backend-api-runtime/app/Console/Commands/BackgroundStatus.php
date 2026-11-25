<?php

namespace App\Console\Commands;

use App\Services\BackgroundQueue;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class BackgroundStatus extends Command
{
    protected $signature = 'background:status';
    protected $description = 'Report queue age, failures and enabled consumers without reading payloads';

    public function handle(BackgroundQueue $queues): int
    {
        $unhealthy = false;
        foreach (array_unique(BackgroundQueue::ROUTES) as $queue) {
            $enabled = collect(BackgroundQueue::ROUTES)->filter(
                fn ($lane, $feature) => $lane === $queue && $queues->enabled($feature)
            )->isNotEmpty();
            $alive = DB::table('background_workers')->where('queue', $queue)
                ->where('heartbeat_at', '>=', now()->subSeconds(BackgroundQueue::leaseSeconds($queue)))->exists();
            $jobs = DB::table(config('queue.connections.database.table'))->where('queue', $queue);
            $oldest = (clone $jobs)->min('created_at');
            $age = $oldest ? max(0, time() - $oldest) : 0;
            $failed = DB::table(config('queue.failed.table'))->where('queue', $queue)->where('connection', 'database')->count();
            $depth = $jobs->count();
            $this->line(json_encode(compact('queue', 'enabled', 'alive', 'depth', 'age', 'failed')));
            $unhealthy = $unhealthy || ($enabled && ! $alive) || $failed > 0 || $age > 120;
        }
        return $unhealthy ? self::FAILURE : self::SUCCESS;
    }
}
