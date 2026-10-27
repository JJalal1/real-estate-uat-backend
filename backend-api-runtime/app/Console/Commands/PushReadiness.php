<?php

namespace App\Console\Commands;

use App\Services\FcmPushSender;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Throwable;

class PushReadiness extends Command
{
    protected $signature='push:readiness';
    protected $description='Validate push worker prerequisites without sending or exposing credentials';

    public function handle(FcmPushSender $sender): int
    {
        $checks=[
            'push_enabled'=>(bool)config('push.enabled',false),
            'dedicated_database_queue'=>config('push.queue_connection')==='database' && config('push.queue')==='push',
            'visibility_exceeds_job_timeout'=>(int)config('queue.connections.database.retry_after',0)>=60,
            'signal_support'=>extension_loaded('pcntl'),
        ];
        try { $sender->validateConfiguration(); $checks['firebase_identity_and_secret']=true; }
        catch (Throwable) { $checks['firebase_identity_and_secret']=false; }
        try {
            DB::table('jobs')->where('queue','push')->limit(1)->count();
            DB::table('failed_jobs')->limit(1)->count();
            $checks['queue_database_reachable']=true;
        } catch (Throwable) { $checks['queue_database_reachable']=false; }
        $ready=!in_array(false,$checks,true);
        $this->line(json_encode(['ready'=>$ready,'checks'=>$checks,'sent_messages'=>0],JSON_THROW_ON_ERROR));
        return $ready ? self::SUCCESS : self::FAILURE;
    }
}
