<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SavedPropertySearch;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class SavedPropertySearchService
{
    public const ALERT_FREQUENCIES = ['instant', 'daily', 'off'];
    public const PURPOSES = ['sale', 'rent'];
    public const TYPES = ['apartment', 'house', 'villa', 'land', 'shop', 'office', 'farm'];

    public function normalizeFilters(array $filters): array
    {
        $allowed = [
            'search', 'purpose', 'type', 'min_price', 'max_price',
            'min_bedrooms', 'min_bathrooms', 'min_area_m2', 'max_area_m2',
            'latitude', 'longitude', 'radius_km', 'south', 'west', 'north', 'east',
        ];
        $normalized = [];
        foreach ($allowed as $key) {
            if (! array_key_exists($key, $filters) || $filters[$key] === null || $filters[$key] === '') {
                continue;
            }
            $normalized[$key] = match ($key) {
                'search', 'purpose', 'type' => trim((string) $filters[$key]),
                'min_bedrooms', 'min_bathrooms' => (int) $filters[$key],
                default => (float) $filters[$key],
            };
        }
        ksort($normalized);
        return $normalized;
    }

    public function fingerprint(array $filters): string
    {
        return hash('sha256', json_encode(
            $this->normalizeFilters($filters),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION,
        ));
    }

    public function queryFor(array $filters): Builder
    {
        $filters = $this->normalizeFilters($filters);
        $query = Property::query()->where('status', 'published');

        $search = trim((string) ($filters['search'] ?? ''));
        if ($search !== '') {
            $query->where(function (Builder $nested) use ($search): void {
                $operator = DB::connection()->getDriverName() === 'pgsql' ? 'ilike' : 'like';
                $pattern = '%'.$search.'%';
                $nested->where('title', $operator, $pattern)
                    ->orWhere('description', $operator, $pattern)
                    ->orWhere('address', $operator, $pattern);
            });
        }

        foreach (['purpose', 'type'] as $field) {
            if (! empty($filters[$field])) {
                $query->where($field, $filters[$field]);
            }
        }

        foreach ([
            'min_price' => ['price', '>='],
            'max_price' => ['price', '<='],
            'min_bedrooms' => ['bedrooms', '>='],
            'min_bathrooms' => ['bathrooms', '>='],
            'min_area_m2' => ['area_m2', '>='],
            'max_area_m2' => ['area_m2', '<='],
        ] as $input => [$column, $operator]) {
            if (isset($filters[$input])) {
                $query->where($column, $operator, $filters[$input]);
            }
        }

        if (isset($filters['south'], $filters['west'], $filters['north'], $filters['east'])) {
            $query->whereBetween('latitude', [(float) $filters['south'], (float) $filters['north']]);
            $west = (float) $filters['west'];
            $east = (float) $filters['east'];
            if ($west <= $east) {
                $query->whereBetween('longitude', [$west, $east]);
            } else {
                $query->where(function (Builder $nested) use ($west, $east): void {
                    $nested->where('longitude', '>=', $west)->orWhere('longitude', '<=', $east);
                });
            }
        }

        if (isset($filters['latitude'], $filters['longitude'], $filters['radius_km'])) {
            $latitude = (float) $filters['latitude'];
            $longitude = (float) $filters['longitude'];
            $radiusKm = (float) $filters['radius_km'];
            if (DB::connection()->getDriverName() === 'pgsql') {
                $pointSql = 'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography';
                $query->whereNotNull('location')->whereRaw(
                    "ST_DWithin(location, {$pointSql}, ?)",
                    [$longitude, $latitude, $radiusKm * 1000],
                );
            } else {
                // Test-only SQLite approximation. Bounding box first; exact
                // distance is not needed for production where PostGIS is used.
                $latDelta = $radiusKm / 111.0;
                $lngScale = max(cos(deg2rad($latitude)), 0.1);
                $lngDelta = $radiusKm / (111.0 * $lngScale);
                $query->whereBetween('latitude', [$latitude - $latDelta, $latitude + $latDelta])
                    ->whereBetween('longitude', [$longitude - $lngDelta, $longitude + $lngDelta]);
            }
        }

        return $query;
    }

    public function latestMatchId(array $filters): ?int
    {
        $id = $this->queryFor($filters)->max('id');
        return $id === null ? null : (int) $id;
    }

    public function matchingCount(array $filters): int
    {
        return $this->queryFor($filters)->count();
    }

    /** @return list<Property> */
    public function newMatches(SavedPropertySearch $search, int $limit = 10): array
    {
        $query = $this->queryFor($search->filters ?? [])->orderBy('id');
        if ($search->last_match_property_id !== null) {
            $query->where('id', '>', $search->last_match_property_id);
        }
        return $query->limit($limit)->get()->all();
    }
}
