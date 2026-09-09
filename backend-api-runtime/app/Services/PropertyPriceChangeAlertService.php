<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyFavorite;

class PropertyPriceChangeAlertService
{
    public function __construct(private readonly UserNotificationService $notifications) {}

    public function notify(int $propertyId, float $oldPrice, float $newPrice): int
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
            ->orderBy('id')
            ->chunkById(100, function ($rows) use (
                $property,
                $oldPrice,
                $newPrice,
                $direction,
                &$notified,
            ): void {
                foreach ($rows as $favorite) {
                    $this->notifications->create(
                        (int) $favorite->user_id,
                        'favorite_price_changed',
                        'تغيّر سعر عقار محفوظ',
                        $direction.' سعر «'.$property->title.'».',
                        'property',
                        (int) $property->id,
                        [
                            'old_price' => $oldPrice,
                            'new_price' => $newPrice,
                            'currency' => $property->currency,
                            'direction' => $newPrice < $oldPrice ? 'down' : 'up',
                        ],
                    );
                    $notified++;
                }
            });

        return $notified;
    }
}
