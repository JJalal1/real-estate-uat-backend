<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SavedPropertySearch;
use Illuminate\Database\Eloquent\Builder;

class SavedPropertySearchService
{
    public const ALERT_FREQUENCIES = ['instant', 'daily', 'off'];
    public const PURPOSES = ['sale', 'rent'];
    public const TYPES = ['apartment', 'floor', 'building', 'house', 'villa', 'land', 'shop', 'office', 'farm'];

    public function normalizeFilters(array $filters): array
    {
        $allowed = array_keys(app(PropertyDiscoveryFilterService::class)->rules());
        $normalized = [];
        foreach ($allowed as $key) {
            if (! array_key_exists($key, $filters) || $filters[$key] === null || $filters[$key] === '') {
                continue;
            }
            $normalized[$key] = match ($key) {
                'search', 'purpose', 'type', 'area_polygon', 'currency', 'governorate', 'floor_number', 'building_facade' => trim((string) $filters[$key]),
                'has_parking', 'has_elevator', 'unit_occupies_entire_floor', 'spotlight' => (bool) $filters[$key],
                'advertiser_id' => (int) $filters[$key],
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
        $query = app(PropertyDiscoveryFilterService::class)->publicQuery();
        $discovery = app(PropertyDiscoveryFilterService::class);
        $discovery->apply($query, $filters);
        $discovery->applyGeometry($query, $filters);

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
