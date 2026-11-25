<?php

namespace App\Console\Commands;

use App\Services\BackgroundQueue;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Queue;

class BackgroundWork extends Command
{
    protected $signature = 'background:work {queue} {--once : Process one job and exit}';
    protected $description = 'Consume one isolated database queue and advertise its availability';

    public function handle(BackgroundQueue $queues): int
    {
        $queue = $this->argument('queue');
        if (! in_array($queue, BackgroundQueue::ROUTES, true)) {
            $this->error('Unknown background queue.');
            return self::FAILURE;
        }
        $timeout = match ($queue) {
            'media', 'listing-ai', 'discovery', 'reports', 'timers' => 75,
            default => 30,
        };
        if ((int) config('queue.connections.database.retry_after') <= $timeout ||
            (config('queue.connections.database.connection') ?: config('database.default')) !== config('database.default')) {
            $this->error('Check the queue database and retry timeout.');
            return self::FAILURE;
        }
        if (in_array($queue, ['push', 'push-urgent'], true) && $this->call('push:readiness') !== self::SUCCESS) {
            return self::FAILURE;
        }
        if (in_array($queue, ['push', 'push-urgent'], true) && app()->environment('staging')
            && config('push.fcm.android_package') !== 'com.aqer.yemen.uat.offline') {
            $this->error('Configure the verified Alazzi Android package before starting this worker.');
            return self::FAILURE;
        }
        $consumer = (string) \Illuminate\Support\Str::uuid();
        $last = 0;
        Queue::looping(function () use ($queue, $queues, $consumer, &$last) {
            if (time() - $last >= 5) {
                $queues->heartbeat($queue, $consumer);
                $last = time();
            }
        });
        try {
            return $this->call('queue:work', [
                'connection' => 'database', '--queue' => $queue, '--sleep' => 2,
                '--tries' => 3, '--timeout' => $timeout, '--memory' => 192,
                '--max-time' => 3600, '--once' => $this->option('once'),
            ]);
        } finally {
            \Illuminate\Support\Facades\DB::table('background_workers')
                ->where('queue', $queue)->where('consumer', $consumer)->delete();
        }
    }
}
