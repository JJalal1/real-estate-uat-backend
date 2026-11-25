<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyFavorite;

class PropertyPriceChangeAlertService
{
    public function __construct(private readonly UserNotificationService $notifications) {}

    public function notify(int $propertyId, float $oldPrice, float $newPrice, ?string $eventId = null, ?string $currency = null, ?int $changedAt = null): int
    {
        if ($oldPrice === $newPrice) return 0;

        $property = Property::query()
            ->whereKey($propertyId)
            ->where('status', 'published')
            ->first();
        if (! $property) return 0;

        $direction = $newPrice < $oldPrice ? 'انخفض' : 'ارتفع';
        $notified = 0;

        PropertyFavorite::query()
            ->where('property_id', $property->id)
            ->where('user_id', '<>', $property->user_id)
            ->when($changedAt !== null, fn ($q) => $q->where('created_at', '<=', now()->setTimestamp($changedAt)))
            ->orderBy('id')
            ->chunkById(100, function ($rows) use (
                $property,
                $oldPrice,
                $newPrice,
                $direction,
                $eventId, $currency, &$notified,
            ): void {
                foreach ($rows as $favorite) {
                    $deliver = function () use ($eventId, $favorite, $oldPrice, $newPrice, $property, $direction, $currency): int {
                        if ($eventId !== null && ! app(BackgroundQueue::class)->claim(
                            "price:$eventId:$favorite->user_id", now()->addDays(2)
                        )) return 0;
                        $notification = $this->notifications->create(
                            (int) $favorite->user_id,
                            'favorite_price_changed',
                            'تغيّر سعر عقار محفوظ',
                            $direction.' سعر «'.$property->title.'».',
                            'property',
                            (int) $property->id,
                            [
                                'old_price' => $oldPrice,
                                'new_price' => $newPrice,
                                'currency' => $currency ?? $property->currency,
                                'direction' => $newPrice < $oldPrice ? 'down' : 'up',
                            ],
                        );
                        return $notification !== null ? 1 : 0;
                    };
                    $notified += $eventId === null ? $deliver() : \Illuminate\Support\Facades\DB::transaction($deliver);
                }
            });

        return $notified;
    }
}
