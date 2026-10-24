<?php

namespace App\Jobs;

use App\Models\UserNotification;
use App\Models\UserPushDevice;
use App\Services\FcmPushSender;
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
        $sender->send($notification,$device);
    }
}
