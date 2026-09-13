<?php

namespace App\Services;

use App\Models\UserNotification;
use App\Models\UserNotificationPreference;

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
        $category = $this->preferenceCategory($type);
        if ($category !== null && ! $this->enabled($userId, $category)) {
            return null;
        }

        return UserNotification::query()->create([
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'data' => $data ?: null,
            'created_at' => now(),
        ]);
    }

    private function enabled(int $userId, string $category): bool
    {
        $row = UserNotificationPreference::query()->whereKey($userId)->first();
        if (! $row) return true;
        return (bool) $row->{$category};
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
