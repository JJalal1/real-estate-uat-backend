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
            $label = $cell->governorate->name_ar === 'أمانة العاصمة' ? 'صنعاء' : $cell->governorate->name_ar;
            if (isset($rows[$label])) continue;
            $ring = $cell->boundary_json['coordinates'][0] ?? [];
            if (count($ring) < 4) continue;
            $latitudes = array_column($ring, 1); $longitudes = array_column($ring, 0);
            $rows[$label] = ['governorate' => $cell->governorate->name_ar,
                'label' => $label,
                'latitude' => (min($latitudes) + max($latitudes)) / 2, 'longitude' => (min($longitudes) + max($longitudes)) / 2];
        }
        // Legacy listings can be public before coverage polygons are configured.
        // Derive approximate discovery centres from those public records only;
        // never invent coverage cells, which would change listing permissions.
        $missing = [];
        foreach (Governorate::query()->where('is_active', true)->orderBy('id')->get() as $governorate) {
            $label = $governorate->name_ar === 'أمانة العاصمة' ? 'صنعاء' : $governorate->name_ar;
            if (isset($rows[$label])) continue;
            $missing[$label] ??= ['governorate' => $governorate->name_ar, 'label' => $label,
                'latitude' => 0.0, 'longitude' => 0.0, 'count' => 0];
        }
        if ($missing !== []) {
            foreach (app(PropertyDiscoveryFilterService::class)->publicQuery()->whereNull('geo_cell_id')
                ->select(['id', 'address', 'latitude', 'longitude'])->orderBy('id')->cursor() as $property) {
                $lat = (float) $property->latitude; $lon = (float) $property->longitude;
                if (! is_finite($lat) || ! is_finite($lon) || abs($lat) > 90 || abs($lon) > 180) continue;
                foreach ($missing as $label => &$row) {
                    $names = $label === 'صنعاء' ? ['صنعاء', 'أمانة العاصمة'] : [$label];
                    foreach ($names as $name) {
                        if (preg_match('/(?<![\pL\pN])'.preg_quote($name, '/').'(?![\pL\pN])/u', (string) $property->address)) {
                            $row['latitude'] += $lat; $row['longitude'] += $lon; $row['count']++;
                            break;
                        }
                    }
                }
                unset($row);
            }
            foreach ($missing as $label => $row) {
                if ($row['count'] === 0) continue;
                $row['latitude'] /= $row['count']; $row['longitude'] /= $row['count'];
                unset($row['count']); $rows[$label] = $row;
            }
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
