<?php

namespace App\Services;

use App\Models\GeoCell;
use App\Models\Governorate;
use Illuminate\Validation\ValidationException;

class MarketplaceContextService
{
    public function __construct(private readonly RegionService $regions) {}

    public function resolve(array $input): array
    {
        if (! empty($input['governorate'])) {
            $name = $input['governorate'];
            $aliases = $name === 'صنعاء' ? ['صنعاء', 'أمانة العاصمة'] : [$name];
            $g = Governorate::query()->where('is_active', true)->whereIn('name_ar', $aliases)->orderBy('id')->first();
            if (! $g) throw ValidationException::withMessages(['governorate' => ['اختر محافظة متاحة.']]);
            return ['governorate' => $g->name_ar, 'label' => $g->name_ar === 'أمانة العاصمة' ? 'صنعاء' : $g->name_ar, 'source' => 'manual'];
        }
        if (isset($input['latitude'], $input['longitude'])) {
            $cell = $this->regions->resolveCell((float) $input['latitude'], (float) $input['longitude']);
            if (! $cell) {
                // Sparse UAT polygons: use the nearest defined region only
                // within a reasonable distance, otherwise the Sana'a default.
                $nearest = null; $distance = 150.0;
                foreach ($this->locations() as $row) {
                    $d = $this->distance((float) $input['latitude'], (float) $input['longitude'], $row['latitude'], $row['longitude']);
                    if ($d < $distance) { $nearest = $row; $distance = $d; }
                }
                if ($nearest) return ['governorate' => $nearest['governorate'], 'label' => $nearest['label'], 'source' => 'device'];
            } else {
                $cell->loadMissing('governorate');
                if ($cell->governorate) return ['governorate' => $cell->governorate->name_ar,
                    'label' => $cell->governorate->name_ar === 'أمانة العاصمة' ? 'صنعاء' : $cell->governorate->name_ar, 'source' => 'device'];
            }
        }
        return ['governorate' => Governorate::query()->where('is_active', true)->whereIn('name_ar', ['أمانة العاصمة', 'صنعاء'])->orderBy('id')->value('name_ar') ?? 'صنعاء',
            'label' => 'صنعاء', 'source' => 'default'];
    }

    public function locations(): array
    {
        $rows = [];
        foreach (GeoCell::query()->with('governorate')->where('is_active', true)
            ->whereHas('governorate', fn ($q) => $q->where('is_active', true))->orderBy('id')->get() as $cell) {
            if (isset($rows[$cell->governorate_id])) continue;
            $ring = $cell->boundary_json['coordinates'][0] ?? [];
            if (count($ring) < 4) continue;
            $latitudes = array_column($ring, 1); $longitudes = array_column($ring, 0);
            $rows[$cell->governorate_id] = ['governorate' => $cell->governorate->name_ar,
                'label' => $cell->governorate->name_ar === 'أمانة العاصمة' ? 'صنعاء' : $cell->governorate->name_ar,
                'latitude' => (min($latitudes) + max($latitudes)) / 2, 'longitude' => (min($longitudes) + max($longitudes)) / 2];
        }
        return array_values($rows);
    }

    private function distance(float $lat, float $lon, float $otherLat, float $otherLon): float
    {
        $a = sin(deg2rad($otherLat - $lat) / 2) ** 2
            + cos(deg2rad($lat)) * cos(deg2rad($otherLat)) * sin(deg2rad($otherLon - $lon) / 2) ** 2;
        return 6371 * 2 * atan2(sqrt($a), sqrt(max(0, 1 - $a)));
    }
}
