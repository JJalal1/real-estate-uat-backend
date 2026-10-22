<?php

namespace App\Jobs;

use App\Models\UserNotification;
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

    public function __construct(public readonly int $notificationId) {}

    public function backoff(): array
    {
        return [30,120,600];
    }

    public function handle(FcmPushSender $sender): void
    {
        if (! config('push.enabled',false)) return;
        $notification=UserNotification::query()->withoutGlobalScopes()->find($this->notificationId);
        if (! $notification) return;
        $sender->send($notification);
    }
}
