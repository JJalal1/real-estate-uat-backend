<?php

namespace App\Jobs;

use App\Models\UserNotification;
use App\Models\UserPushDevice;
use App\Services\FcmPushSender;
use App\Services\PushDeliveryException;
use Illuminate\Support\Facades\Log;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class SendUserPushNotification implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries=3;
    public int $timeout=30;

    public function __construct(
        public readonly int $notificationId,
        public readonly int $deviceId,
    ) {}

    public function backoff(): array
    {
        return [30,120,600];
    }

    public function handle(FcmPushSender $sender): void
    {
        if (! config('push.enabled',false)) return;
        $notification=UserNotification::query()->withoutGlobalScopes()->find($this->notificationId);
        if (! $notification) return;
        $device=UserPushDevice::query()
            ->whereKey($this->deviceId)
            ->where('user_id',$notification->user_id)
            ->whereNull('disabled_at')
            ->first();
        if (! $device) return;
        try {
            $sender->send($notification,$device);
        } catch (PushDeliveryException $error) {
            if (! $error->retryable) { $this->fail($error); return; }
            if ($this->job !== null && $this->attempts() < $this->tries) {
                $delay=max($error->retryAfterSeconds,$this->backoff()[min($this->attempts()-1,2)]);
                Log::warning('push.retry_scheduled',['notification_id'=>$this->notificationId,'device_id'=>$this->deviceId,
                    'attempt'=>$this->attempts(),'delay_seconds'=>$delay]);
                $this->release($delay);
                return;
            }
            throw $error;
        }
    }

    public function failed(?\Throwable $error): void
    {
        Log::error('push.exhausted',['notification_id'=>$this->notificationId,'device_id'=>$this->deviceId,
            'http_status'=>$error instanceof PushDeliveryException ? $error->httpStatus : null]);
    }
}
