<?php

namespace App\Services;

use App\Models\Property;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** One public filtering contract for discovery, saved results and match alerts. */
class PropertyDiscoveryFilterService
{
    private const TYPES = ['apartment', 'floor', 'building', 'house', 'villa', 'land', 'shop', 'office', 'farm'];
    private const PURPOSES = ['sale', 'rent'];
    private const FACADES = ['north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest', 'multiple'];

    public function __construct(private readonly PropertyIdentityService $identity) {}

    public function publicQuery(): Builder
    {
        return Property::query()->publiclyAvailable()->whereNotExists(function ($query): void {
            $query->selectRaw('1')->from('property_platform_receivables as discovery_due')
                ->whereColumn('discovery_due.advertiser_user_id', 'properties.user_id')
                ->whereIn('discovery_due.status', ['open', 'under_review', 'overdue', 'disputed'])
                ->whereColumn('discovery_due.amount_paid', '<', 'discovery_due.amount_total')
                ->where('discovery_due.due_at', '<=', now());
        });
    }

    public function rules(): array
    {
        return [
            'area_polygon' => ['nullable', 'string', 'max:8192'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'radius_km' => ['nullable', 'numeric', 'between:0.1,100'],
            'south' => ['nullable', 'numeric', 'between:-90,90'],
            'west' => ['nullable', 'numeric', 'between:-180,180'],
            'north' => ['nullable', 'numeric', 'between:-90,90'],
            'east' => ['nullable', 'numeric', 'between:-180,180'],
            'advertiser_id' => ['nullable', 'integer', 'min:1'],
            'search' => ['nullable', 'string', 'max:120'],
            'currency' => ['nullable', 'string', 'size:3'],
            'max_monthly_rent' => ['nullable', 'numeric', 'min:0'],
            'min_monthly_rent' => ['nullable', 'numeric', 'min:0'],
            'governorate' => ['nullable', 'string', 'max:120'],
            'floor_number' => ['nullable', 'string', 'max:32'],
            'building_facade' => ['nullable', Rule::in(self::FACADES)],
            'has_parking' => ['nullable', 'boolean'], 'has_elevator' => ['nullable', 'boolean'],
            'unit_occupies_entire_floor' => ['nullable', 'boolean'],
            'spotlight' => ['nullable', 'boolean'],
            'purpose' => ['nullable', Rule::in(self::PURPOSES)],
            'type' => ['nullable', Rule::in(self::TYPES)],
            'min_price' => ['nullable', 'numeric', 'min:0'],
            'max_price' => ['nullable', 'numeric', 'gte:min_price'],
            'min_bedrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'min_bathrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'min_area_m2' => ['nullable', 'numeric', 'min:0'],
            'max_area_m2' => ['nullable', 'numeric', 'gte:min_area_m2'],
        ];
    }

    public function apply(Builder $query, array $validated): void
    {
        if (isset($validated['advertiser_id'])) $query->where('user_id', $validated['advertiser_id']);
        if (! empty($validated['governorate'])) {
            $name = $validated['governorate'];
            $aliases = in_array($name, ['صنعاء', 'أمانة العاصمة'], true) ? ['صنعاء', 'أمانة العاصمة'] : [$name];
            $query->where(function (Builder $regional) use ($aliases): void {
                $regional->whereHas('geoCell.governorate', fn ($g) => $g->where('is_active', true)->whereIn('name_ar', $aliases))
                    ->orWhere(function (Builder $legacy) use ($aliases): void {
                        $legacy->whereNull('geo_cell_id')->where(function (Builder $address) use ($aliases): void {
                            foreach ($aliases as $name) $address->orWhere('address', DB::connection()->getDriverName() === 'pgsql' ? 'ilike' : 'like', '%'.$name.'%');
                        });
                    });
            });
        }
        if (($validated['spotlight'] ?? false)) $query->where('spotlight_until', '>', now());
        foreach (['has_parking', 'has_elevator', 'building_facade'] as $field) if (isset($validated[$field])) $query->where($field, $validated[$field]);
        if (isset($validated['floor_number'])) {
            $floor = $this->identity->normalizeFloorForSearch($validated['floor_number']);
            $query->where(fn (Builder $q) => $q->where('floor_number', $validated['floor_number'])
                ->orWhereHas('propertyAsset', fn ($asset) => $asset->where('floor_number', $floor)));
        }
        if (array_key_exists('unit_occupies_entire_floor', $validated) && $validated['unit_occupies_entire_floor'] !== null) {
            if ((bool) $validated['unit_occupies_entire_floor']) $query->where(fn ($q) => $q->where('type', 'floor')->orWhere('unit_occupies_entire_floor', true));
            else $query->where('type', '<>', 'floor')->where('unit_occupies_entire_floor', false);
        }
        if (isset($validated['currency'])) $query->where('currency', strtoupper($validated['currency']));
        if (isset($validated['max_monthly_rent'])) {
            $query->where('purpose', 'rent')->where('monthly_rent', '<=', $validated['max_monthly_rent']);
        }
        if (isset($validated['min_monthly_rent'])) $query->where('purpose', 'rent')->where('monthly_rent', '>=', $validated['min_monthly_rent']);
        $search = trim((string) ($validated['search'] ?? ''));
        if ($search !== '') {
            $query->where(function (Builder $nested) use ($search) {
                $pattern = '%' . $search . '%';
                $operator = DB::connection()->getDriverName() === 'pgsql' ? 'ilike' : 'like';
                $nested
                    ->where('title', $operator, $pattern)
                    ->orWhere('description', $operator, $pattern)
                    ->orWhere('address', $operator, $pattern);
            });
        }

        if (($validated['type'] ?? null) === 'apartment') {
            $query->whereIn('type', ['apartment', 'floor']);
        } elseif (($validated['type'] ?? null) === 'floor') {
            $query->where(fn (Builder $scope) => $scope->where('type', 'floor')
                ->orWhere(fn (Builder $unit) => $unit->where('type', 'apartment')->where('unit_occupies_entire_floor', true)));
        } elseif (! empty($validated['type'])) {
            $query->where('type', $validated['type']);
        }
        foreach (['purpose'] as $field) {
            if (! empty($validated[$field])) {
                $query->where($field, $validated[$field]);
            }
        }

        $bounds = [
            'min_price' => ['price', '>='],
            'max_price' => ['price', '<='],
            'min_bedrooms' => ['bedrooms', '>='],
            'min_bathrooms' => ['bathrooms', '>='],
            'min_area_m2' => ['area_m2', '>='],
            'max_area_m2' => ['area_m2', '<='],
        ];

        foreach ($bounds as $input => [$column, $operator]) {
            if (isset($validated[$input])) {
                $query->where($column, $operator, $validated[$input]);
            }
        }
    }

    public function validateGeometry(array $validated): void
    {
        foreach (['min_price' => 'max_price', 'min_monthly_rent' => 'max_monthly_rent', 'min_area_m2' => 'max_area_m2'] as $min => $max) {
            if (isset($validated[$min], $validated[$max]) && $validated[$min] > $validated[$max]) {
                throw ValidationException::withMessages(['filters' => ['الحد الأدنى يجب ألا يتجاوز الحد الأعلى.']]);
            }
        }
        $circle = count(array_filter(['latitude', 'longitude', 'radius_km'], fn ($key) => isset($validated[$key])));
        if ($circle !== 0 && $circle !== 3) {
            throw ValidationException::withMessages(['filters' => ['حدد نقطة المركز ونطاق البحث معًا.']]);
        }
        if (isset($validated['area_polygon'])) $this->polygon($validated['area_polygon']);
        $keys = ['south', 'west', 'north', 'east'];
        $provided = collect($keys)->filter(fn (string $key) => isset($validated[$key]));

        if ($provided->isNotEmpty() && $provided->count() !== count($keys)) {
            throw ValidationException::withMessages([
                'bounds' => ['All four map bounds are required together.'],
            ]);
        }

        if ($provided->count() === count($keys)
            && (float) $validated['south'] > (float) $validated['north']) {
            throw ValidationException::withMessages([
                'bounds' => ['The south bound must not exceed the north bound.'],
            ]);
        }
    }

    public function applyBounds(Builder $query, array $validated): void
    {
        if (! isset($validated['south'], $validated['west'], $validated['north'], $validated['east'])) {
            return;
        }

        $south = (float) $validated['south'];
        $west = (float) $validated['west'];
        $north = (float) $validated['north'];
        $east = (float) $validated['east'];

        $query->whereBetween('latitude', [$south, $north]);

        if ($west <= $east) {
            $query->whereBetween('longitude', [$west, $east]);
            return;
        }

        // A wrapped longitude range crosses the antimeridian.
        $query->where(function (Builder $nested) use ($west, $east) {
            $nested->where('longitude', '>=', $west)
                ->orWhere('longitude', '<=', $east);
        });
    }

    public function applyGeometry(Builder $query, array $filters): void
    {
        $this->applyBounds($query, $filters);
        $this->applyPolygon($query, $filters);
        if (! isset($filters['latitude'], $filters['longitude'], $filters['radius_km'])) return;
        $lat = (float) $filters['latitude'];
        $lon = (float) $filters['longitude'];
        $radius = (float) $filters['radius_km'];
        if (DB::connection()->getDriverName() === 'pgsql') {
            $query->whereNotNull('location')->whereRaw(
                'ST_DWithin(location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
                [$lon, $lat, $radius * 1000],
            );
        } else {
            // SQLite test path uses the same spherical distance as nearby().
            $query->whereRaw(
                '(6371 * 2 * ASIN(MIN(1, SQRT(POWER(SIN(RADIANS(latitude - ?) / 2), 2) + COS(RADIANS(?)) * COS(RADIANS(latitude)) * POWER(SIN(RADIANS(longitude - ?) / 2), 2))))) <= ?',
                [$lat, $lat, $lon, $radius],
            );
        }
    }

    public function applyPolygonForNearby(Builder $query, array $filters): void
    {
        $this->applyBounds($query, $filters);
        $this->applyPolygon($query, $filters);
    }

    private function polygon(string $encoded): array
    {
        try { $ring = json_decode($encoded, true, 32, JSON_THROW_ON_ERROR); }
        catch (\JsonException) { $ring = null; }
        $valid = is_array($ring) && array_is_list($ring) && count($ring) >= 4 && count($ring) <= 81;
        if ($valid) foreach ($ring as $point) {
            if (!is_array($point) || !array_is_list($point) || count($point) !== 2 || !is_numeric($point[0]) || !is_numeric($point[1])
                || !is_finite((float)$point[0]) || !is_finite((float)$point[1]) || abs((float)$point[0]) > 180 || abs((float)$point[1]) > 90) { $valid = false; break; }
        }
        if ($valid) $valid = abs($ring[0][0] - $ring[count($ring)-1][0]) < 1.0e-9 && abs($ring[0][1] - $ring[count($ring)-1][1]) < 1.0e-9;
        if (!$valid) throw ValidationException::withMessages(['area_polygon' => ['حدود المنطقة المرسومة غير صالحة. أعد تحديدها على الخريطة.']]);
        return array_map(fn ($point) => [(float)$point[0], (float)$point[1]], $ring);
    }

    private function applyPolygon(Builder $query, array $filters): void
    {
        if (!isset($filters['area_polygon'])) return;
        $ring = $this->polygon($filters['area_polygon']);
        $query->whereBetween('latitude', [min(array_column($ring, 1)), max(array_column($ring, 1))])
            ->whereBetween('longitude', [min(array_column($ring, 0)), max(array_column($ring, 0))]);
        if (DB::connection()->getDriverName() === 'pgsql') {
            $json = json_encode(['type' => 'Polygon', 'coordinates' => [$ring]], JSON_THROW_ON_ERROR);
            $query->whereNotNull('location')->whereRaw('ST_Covers(ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)), location::geometry)', [$json]);
        } else {
            // SQLite is disposable-test only. Match the map's even/odd ring rule.
            DB::connection()->getPdo()->sqliteCreateFunction('discovery_inside_ring', function ($lat, $lon, $json): int {
                if ($lat === null || $lon === null) return 0;
                $points = json_decode($json, true); $inside = false;
                for ($i = 0, $j = count($points)-1; $i < count($points); $j = $i++) {
                    [$xi, $yi] = $points[$i]; [$xj, $yj] = $points[$j];
                    $cross = ($lon-$xi)*($yj-$yi)-($lat-$yi)*($xj-$xi);
                    if (abs($cross) < 1.0e-10 && $lon >= min($xi,$xj) && $lon <= max($xi,$xj) && $lat >= min($yi,$yj) && $lat <= max($yi,$yj)) return 1;
                    if (($yi > $lat) !== ($yj > $lat) && $lon < ($xj-$xi)*($lat-$yi)/($yj-$yi)+$xi) $inside = !$inside;
                }
                return $inside ? 1 : 0;
            }, 3);
            $query->whereRaw('discovery_inside_ring(latitude, longitude, ?) = 1', [json_encode($ring, JSON_THROW_ON_ERROR)]);
        }
    }
}
