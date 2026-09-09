<?php

namespace App\Services;

use App\Models\Property;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class PropertyMarketContextService
{
    public const MIN_SAMPLE_SIZE = 5;
    public const RADIUS_KM = 10.0;

    public function contextFor(Property $property): array
    {
        if ($property->status !== 'published') {
            return $this->insufficient('property_not_published', 0);
        }

        $query = Property::query()
            ->where('status', 'published')
            ->where('id', '<>', $property->id)
            ->where('purpose', $property->purpose)
            ->where('type', $property->type)
            ->where('currency', $property->currency);

        if ($property->area_m2 !== null && (float) $property->area_m2 > 0) {
            $area = (float) $property->area_m2;
            $query->whereBetween('area_m2', [max(1, $area * 0.70), $area * 1.30]);
        }

        if (DB::connection()->getDriverName() === 'pgsql' && $property->location !== null) {
            $query->whereNotNull('location')->whereRaw(
                'ST_DWithin(location, (SELECT location FROM properties WHERE id = ?), ?)',
                [$property->id, self::RADIUS_KM * 1000],
            );
        } elseif ($property->latitude !== null && $property->longitude !== null) {
            $latitude = (float) $property->latitude;
            $longitude = (float) $property->longitude;
            $latDelta = self::RADIUS_KM / 111.0;
            $lngDelta = self::RADIUS_KM / (111.0 * max(cos(deg2rad($latitude)), 0.1));
            $query->whereBetween('latitude', [$latitude - $latDelta, $latitude + $latDelta])
                ->whereBetween('longitude', [$longitude - $lngDelta, $longitude + $lngDelta]);
        }

        $comparables = $query
            ->latest('published_at')
            ->limit(100)
            ->get(['id', 'price', 'area_m2', 'published_at']);

        $sampleCount = $comparables->count();
        if ($sampleCount < self::MIN_SAMPLE_SIZE) {
            return $this->insufficient('not_enough_comparables', $sampleCount);
        }

        $prices = $comparables->pluck('price')->map(fn ($value) => (float) $value)->sort()->values();
        $pricePerM2 = $comparables
            ->filter(fn (Property $item) => $item->area_m2 !== null && (float) $item->area_m2 > 0)
            ->map(fn (Property $item) => (float) $item->price / (float) $item->area_m2)
            ->sort()->values();

        $medianPrice = $this->median($prices);
        $medianPricePerM2 = $pricePerM2->count() >= self::MIN_SAMPLE_SIZE
            ? $this->median($pricePerM2)
            : null;
        $targetPricePerM2 = ($property->area_m2 !== null && (float) $property->area_m2 > 0)
            ? (float) $property->price / (float) $property->area_m2
            : null;

        $basisValue = $targetPricePerM2 !== null && $medianPricePerM2 !== null
            ? $medianPricePerM2
            : $medianPrice;
        $targetValue = $targetPricePerM2 !== null && $medianPricePerM2 !== null
            ? $targetPricePerM2
            : (float) $property->price;
        $deltaPercent = $basisValue > 0
            ? (($targetValue - $basisValue) / $basisValue) * 100
            : null;

        return [
            'sufficient_data' => true,
            'sample_count' => $sampleCount,
            'basis' => [
                'purpose' => $property->purpose,
                'property_type' => $property->type,
                'currency' => $property->currency,
                'radius_km' => self::RADIUS_KM,
                'area_band_percent' => $property->area_m2 === null ? null : 30,
                'source' => 'published_platform_listings',
            ],
            'market' => [
                'median_price' => round($medianPrice, 2),
                'median_price_per_m2' => $medianPricePerM2 === null ? null : round($medianPricePerM2, 2),
                'lower_quartile_price' => round($this->percentile($prices, 0.25), 2),
                'upper_quartile_price' => round($this->percentile($prices, 0.75), 2),
            ],
            'target' => [
                'price' => (float) $property->price,
                'price_per_m2' => $targetPricePerM2 === null ? null : round($targetPricePerM2, 2),
                'delta_from_median_percent' => $deltaPercent === null ? null : round($deltaPercent, 1),
                'position' => $this->position($deltaPercent),
            ],
            'disclaimer' => 'مؤشر استرشادي من عقارات منشورة ومعتمدة داخل المنصة، وليس تقييماً رسمياً أو ضماناً لسعر الصفقة.',
        ];
    }

    private function insufficient(string $reason, int $sampleCount): array
    {
        return [
            'sufficient_data' => false,
            'sample_count' => $sampleCount,
            'reason' => $reason,
            'message' => 'البيانات الحالية غير كافية لتقديم مؤشر سعري موثوق لهذا العقار.',
            'minimum_sample_size' => self::MIN_SAMPLE_SIZE,
        ];
    }

    private function median(Collection $values): float
    {
        return $this->percentile($values, 0.5);
    }

    private function percentile(Collection $values, float $p): float
    {
        $values = $values->values();
        $count = $values->count();
        if ($count === 0) return 0.0;
        if ($count === 1) return (float) $values[0];
        $index = ($count - 1) * $p;
        $lower = (int) floor($index);
        $upper = (int) ceil($index);
        if ($lower === $upper) return (float) $values[$lower];
        $weight = $index - $lower;
        return ((float) $values[$lower] * (1 - $weight)) + ((float) $values[$upper] * $weight);
    }

    private function position(?float $deltaPercent): string
    {
        if ($deltaPercent === null) return 'unknown';
        if ($deltaPercent <= -10) return 'below_comparable_median';
        if ($deltaPercent >= 10) return 'above_comparable_median';
        return 'near_comparable_median';
    }
}
