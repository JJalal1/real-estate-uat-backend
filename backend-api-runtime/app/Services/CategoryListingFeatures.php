<?php

namespace App\Services;

use App\Models\Property;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Optional advertised facts used by the type-specific Sections filters. */
class CategoryListingFeatures
{
    private const LAND_USES = ['residential', 'commercial', 'agricultural', 'mixed'];
    private const WATER_SOURCES = ['well', 'network', 'rain', 'other'];
    private const CROP_TYPES = ['fruit', 'vegetables', 'grains', 'mixed', 'other'];

    public static function listingRules(): array
    {
        return [
            'parking_spaces' => ['nullable', 'integer', 'between:0,100'],
            'has_separate_majlis' => ['nullable', 'boolean'],
            'has_majlis_bathroom' => ['nullable', 'boolean'],
            'land_use' => ['nullable', Rule::in(self::LAND_USES)],
            'street_width_m' => ['nullable', 'numeric', 'gt:0', 'max:1000', 'decimal:0,2'],
            'has_yard' => ['nullable', 'boolean'],
            'office_rooms' => ['nullable', 'integer', 'between:1,100'],
            'farm_water_source' => ['nullable', Rule::in(self::WATER_SOURCES)],
            'farm_crop_type' => ['nullable', Rule::in(self::CROP_TYPES)],
            'section_elevator' => ['nullable', 'boolean'],
        ];
    }

    public static function filterRules(): array
    {
        return [
            'min_parking_spaces' => ['nullable', 'integer', 'between:1,100'],
            'has_separate_majlis' => ['nullable', 'boolean'],
            'has_majlis_bathroom' => ['nullable', 'boolean'],
            'land_use' => ['nullable', Rule::in(self::LAND_USES)],
            'min_street_width' => ['nullable', 'numeric', 'gt:0', 'max:1000', 'decimal:0,2'],
            'has_yard' => ['nullable', 'boolean'],
            'min_office_rooms' => ['nullable', 'integer', 'between:1,100'],
            'farm_water_source' => ['nullable', Rule::in(self::WATER_SOURCES)],
            'farm_crop_type' => ['nullable', Rule::in(self::CROP_TYPES)],
            'has_section_elevator' => ['nullable', 'boolean'],
            'min_floors' => ['nullable', 'integer', 'between:1,50'],
            'min_total_units' => ['nullable', 'integer', 'between:1,5000'],
            'min_shop_openings' => ['nullable', 'integer', 'between:1,100'],
        ];
    }

    public static function facts(Property $property): array
    {
        return array_filter(
            $property->only(array_keys(self::listingRules())),
            static fn (mixed $value): bool => $value !== null,
        );
    }

    public function normalizeWrite(array $input, ?Property $current = null): array
    {
        $scope = ['type' => $input['type'] ?? $current?->type, 'purpose' => $input['purpose'] ?? $current?->purpose];
        $schema = app(DynamicPropertySchema::class);
        $features = array_intersect_key($input, self::listingRules());

        foreach (array_keys(self::listingRules()) as $field) {
            if ($schema->applies($field, $scope)) {
                continue;
            }
            unset($features[$field]);
            if ($current?->getAttribute($field) !== null) {
                $features[$field] = null;
            }
        }

        if (isset($features['parking_spaces'])) {
            $hasParking = (int) $features['parking_spaces'] > 0;
            if (isset($input['has_parking']) && (bool) $input['has_parking'] !== $hasParking) {
                throw ValidationException::withMessages(['parking_spaces' => ['عدد المواقف يجب أن يطابق اختيار توفر موقف سيارة.']]);
            }
            $features['has_parking'] = $hasParking;
        } elseif (isset($input['has_parking']) && ! (bool) $input['has_parking'] && $current?->parking_spaces !== null) {
            $features['parking_spaces'] = null;
        }

        $independentMajlis = array_key_exists('has_separate_majlis', $features)
            ? (bool) $features['has_separate_majlis']
            : (bool) $current?->has_separate_majlis;
        if (! $independentMajlis) {
            if ($features['has_majlis_bathroom'] ?? false) {
                throw ValidationException::withMessages(['has_majlis_bathroom' => ['حدد وجود مجلس مستقل أولًا.']]);
            }
            if (array_key_exists('has_majlis_bathroom', $features) || $current?->has_majlis_bathroom !== null) {
                $features['has_majlis_bathroom'] = null;
            }
        }

        // Ignore inapplicable input and clear old facts after the advertiser
        // changes the type. Explicit null clears; an omitted fact is preserved.
        return array_replace(array_diff_key($input, self::listingRules()), $features);
    }

    public function apply(Builder $query, array $filters): void
    {
        foreach (['has_separate_majlis', 'has_majlis_bathroom', 'land_use', 'has_yard', 'farm_water_source', 'farm_crop_type'] as $field) {
            if (isset($filters[$field])) {
                $query->where($field, $filters[$field]);
            }
        }
        if (isset($filters['has_majlis_bathroom'])) {
            $query->where('has_separate_majlis', true);
        }

        foreach (['min_street_width' => 'street_width_m', 'min_office_rooms' => 'office_rooms',
            'min_floors' => 'floors_count', 'min_shop_openings' => 'shop_openings'] as $filter => $field) {
            if (isset($filters[$filter])) {
                $query->where($field, '>=', $filters[$filter]);
            }
        }

        if (isset($filters['min_parking_spaces'])) {
            $minimum = (int) $filters['min_parking_spaces'];
            $query->where(function (Builder $parking) use ($minimum): void {
                $parking->where('parking_spaces', '>=', $minimum);
                if ($minimum === 1) {
                    $parking->orWhere(fn (Builder $legacy) => $legacy->whereNull('parking_spaces')->where('has_parking', true));
                }
            });
        }

        if (isset($filters['has_section_elevator'])) {
            $expected = (bool) $filters['has_section_elevator'];
            $query->where(fn (Builder $elevator) => $elevator->where('section_elevator', $expected)
                ->orWhere(fn (Builder $legacy) => $legacy->whereNull('section_elevator')->where('has_elevator', $expected)));
        }

        if (isset($filters['min_total_units'])) {
            $this->applyTotalUnits($query, (int) $filters['min_total_units']);
        }
    }

    private function applyTotalUnits(Builder $query, int $minimum): void
    {
        $units = 'properties.units_per_floor';
        if ($query->getConnection()->getDriverName() === 'pgsql') {
            $rows = "json_array_elements(CASE WHEN json_typeof({$units}) = 'array' THEN {$units} ELSE '[]'::json END) AS units(value)";
            $text = 'CAST(units.value AS TEXT)';
            $value = "CASE WHEN {$text} ~ '^(100|[1-9][0-9]?)$' THEN CAST({$text} AS INTEGER) END";
        } else {
            $rows = "json_each(CASE WHEN json_type({$units}) = 'array' THEN {$units} ELSE '[]' END) AS units";
            $value = "CASE WHEN units.type = 'integer' AND units.value BETWEEN 1 AND 100 THEN units.value END";
        }
        // Untyped legacy JSON can contain a scalar or malformed entries.
        // An incomplete set of unit counts cannot satisfy a minimum.
        $query->whereRaw(
            "(SELECT CASE WHEN COUNT(*) = COUNT({$value}) THEN SUM({$value}) END FROM {$rows}) >= CAST(? AS INTEGER)",
            [$minimum],
        );
    }
}
