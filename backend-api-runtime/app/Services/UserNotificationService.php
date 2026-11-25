<?php

namespace App\Services;

use App\Jobs\SendUserPushNotification;
use App\Models\UserNotification;
use App\Models\UserNotificationPreference;
use App\Models\UserPushDevice;

class UserNotificationService
{
    public function create(
        int $userId,
        string $type,
        string $title,
        ?string $body = null,
        ?string $entityType = null,
        ?int $entityId = null,
        array $data = [],
    ): ?UserNotification {
        if (in_array($type, UserNotification::RETIRED_VIEWING_TYPES, true) || $entityType === 'viewing_booking') return null;
        $category = $this->preferenceCategory($type);
        $canPush = $category === null || $this->enabled($userId, $category);
        // Keep this moderation decision in the inbox when optional listing alerts are muted.
        if (! $canPush && $type !== 'listing_duplicate_rejected') {
            return null;
        }

        $notification=UserNotification::query()->create([
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'data' => $data ?: null,
            'created_at' => now(),
        ]);

        if ($canPush && config('push.enabled',false)) {
            $feature = $type === 'message_received' ? 'push_messages' : 'push_other';
            $queues = app(BackgroundQueue::class);
            if ($queues->enabled($feature)) {
                $devices = UserPushDevice::query()->where('user_id', $userId)->whereNull('disabled_at')->pluck('id');
                foreach ($devices as $deviceId) {
                    $queues->submit($feature, new SendUserPushNotification($notification->id, (int) $deviceId, $feature));
                }
            }
        }

        return $notification;
    }

    private function enabled(int $userId, string $category): bool
    {
        $row = UserNotificationPreference::query()->whereKey($userId)->first();
        if (! $row) return true;
        return (bool) $row->{$category};
    }

    public function mayDeliver(UserNotification $notification): bool
    {
        if (in_array($notification->type, UserNotification::RETIRED_VIEWING_TYPES, true) || $notification->entity_type === 'viewing_booking') return false;
        if (! \App\Models\User::query()->whereKey($notification->user_id)->where('account_status', \App\Models\User::STATUS_ACTIVE)->exists()) return false;
        if ($notification->type === 'broker_customer_followup_due') {
            if ($notification->read_at !== null) return false;
            $time = $notification->data['remind_at'] ?? null;
            if ($time && ! \App\Models\BrokerCustomerFollowup::query()
                ->where('user_id', $notification->user_id)->where('message_thread_id', $notification->entity_id)
                ->where('remind_at', \Illuminate\Support\Carbon::parse($time)->utc())->exists()) return false;
        }
        if (in_array($notification->type, DeadlineReminderService::TYPES, true)
            && ! app(DeadlineReminderService::class)->stillDue($notification)) return false;
        $category=$this->preferenceCategory($notification->type);
        return $category === null || $this->enabled((int)$notification->user_id,$category);
    }

    private function preferenceCategory(string $type): ?string
    {
        if ($type === 'message_received') return 'messages';
        if (str_starts_with($type, 'booking_')) return 'viewings';
        if (str_starts_with($type, 'agreement_') || str_starts_with($type, 'rental_contract_')) {
            return 'agreements';
        }
        if ($type === 'saved_search_match' ||
            $type === 'saved_search_digest' ||
            $type === 'favorite_price_changed') {
            return 'discovery_alerts';
        }
        if (str_starts_with($type, 'listing_') ||
            str_starts_with($type, 'broker_listing_') ||
            str_starts_with($type, 'listing_review_')) {
            return 'listing_activity';
        }
        if (str_starts_with($type, 'service_') ||
            str_starts_with($type, 'payment_') ||
            str_starts_with($type, 'entitlement_')) {
            return 'services';
        }

        // Support, account verification, security and staff-assignment events
        // remain essential. They are intentionally not suppressible by the
        // product-notification preference screen.
        return null;
    }
}
