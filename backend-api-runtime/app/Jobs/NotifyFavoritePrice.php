<?php

namespace App\Jobs;

use App\Services\PropertyPriceChangeAlertService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;

class NotifyFavoritePrice implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public int $propertyId, public float $oldPrice, public float $newPrice,
        public string $eventId, public string $currency, public int $changedAt,
    ) {}

    public function handle(PropertyPriceChangeAlertService $alerts): void
    {
        if ($this->changedAt < now()->subDay()->timestamp) return;
        $alerts->notify($this->propertyId, $this->oldPrice, $this->newPrice, $this->eventId, $this->currency, $this->changedAt);
    }
}
