<?php

namespace App\Services;

use App\Models\GeoCell;
use App\Models\Property;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Ranked public discovery shared by list and map. */
class RankedPropertyDiscoveryService
{
    public const ALTERNATIVE_LIMIT = 12;

    public const NEARBY_METRES = 5000;

    private const NUMERIC = [
        'min_price' => ['price', '>=', 'budget'], 'max_price' => ['price', '<=', 'budget'],
        'min_monthly_rent' => ['monthly_rent', '>=', 'budget'], 'max_monthly_rent' => ['monthly_rent', '<=', 'budget'],
        'min_bedrooms' => ['bedrooms', '>=', 'bedrooms'], 'min_bathrooms' => ['bathrooms', '>=', 'bathrooms'],
        'min_area_m2' => ['area_m2', '>=', 'area'], 'max_area_m2' => ['area_m2', '<=', 'area'],
    ];

    private const GEOMETRY = ['area_polygon', 'latitude', 'longitude', 'radius_km', 'south', 'west', 'north', 'east'];

    public function __construct(private readonly PropertyDiscoveryFilterService $filters, private readonly DiscoveryPlaceResolver $places) {}

    public function page(array $input, int $page, int $perPage, string $sort, int $version): array
    {
        if (isset($input['min_monthly_rent']) || isset($input['max_monthly_rent'])) {
            if (isset($input['purpose']) && $input['purpose'] !== 'rent') {
                throw ValidationException::withMessages(['purpose' => ['فلتر الإيجار الشهري لا ينطبق على عقارات البيع.']]);
            }
            $input['purpose'] = 'rent';
        }
        $input = app(DynamicPropertySchema::class)->filters($input);
        $this->filters->validateGeometry($input);
        $this->assertPurposeConsistent($input);
        $place = $this->places->resolve((string) ($input['search'] ?? ''), $input['governorate'] ?? null);
        $approximate = (bool) ($place['approximate'] ?? false);
        $location = $this->requestedLocation($input, $place);
        $drawn = isset($input['area_polygon']);
        $point = isset($location['latitude']);
        // Camera bounds can constrain candidates but never supply a ranking origin.
        $area = ! $drawn && isset($input['south'], $input['west'], $input['north'], $input['east'])
            ? $this->viewportArea($input) : $location;
        $rankReference = $drawn || $point || ! $approximate ? $location : null;
        $exact = $this->query($input, $place);
        if ($approximate) {
            $exact->whereRaw('1=0');
        }
        $offset = ($page - 1) * $perPage;
        $bySpecifications = $version === 2;
        $alternatives = $this->alternatives($input, $place, $exact, $area, $rankReference, $bySpecifications, $sort);
        if ($bySpecifications) {
            [$properties, $total, $exactTotal] = $this->specificationPage($exact, $alternatives, $rankReference, $drawn, $offset, $perPage, $sort);
            $rows = $properties->map(fn (Property $property) => $property->discovery_nearby
                ? $this->alternativeRow($property, $input, $place, $area)
                : $this->exactRow($property))->all();
        } else {
            $exactTotal = (clone $exact)->count();
            $nearby = $alternatives?->get()->all() ?? [];
            $total = $exactTotal + count($nearby);
            $rows = $this->legacyPage($exact, $nearby, $input, $place, $area, $rankReference, $drawn, $exactTotal, $offset, $perPage, $sort);
        }

        return ['rows' => $rows, 'meta' => ['current_page' => $page, 'last_page' => max(1, (int) ceil($total / $perPage)),
            'per_page' => $perPage, 'total' => $total, 'exact_total' => $exactTotal, 'alternative_total' => $total - $exactTotal,
            'alternative_limit' => self::ALTERNATIVE_LIMIT,
            'ranking' => $bySpecifications ? 'specification_misses,distance_when_known,tiebreakers,id' : 'fewest_changes,distance_when_known,tiebreakers,id',
            'ranking_distance_reference' => $rankReference === null ? null : ($drawn ? 'drawn_area' : ($point ? 'point' : 'recorded_area'))]];
    }

    private function legacyPage(Builder $exact, array $nearby, array $input, ?array $place, ?array $area, ?array $reference,
        bool $drawn, int $exactTotal, int $offset, int $perPage, string $sort): array
    {
        $rows = [];
        if ($offset < $exactTotal) {
            $exact->select('properties.*');
            $this->selectDistance($exact, $reference, 'discovery_rank_distance_m', $drawn);
            if ($reference !== null && ! $drawn) {
                $exact->orderByRaw('discovery_rank_distance_m ASC NULLS LAST');
            }
            $this->filters->applySearchOrdering($exact, $input, $sort);
            match ($sort) {
                'price_asc' => $exact->orderBy('price')->orderByDesc('id'),
                'price_desc' => $exact->orderByDesc('price')->orderByDesc('id'),
                default => $exact->orderByDesc('id'),
            };
            foreach ($exact->offset($offset)->limit($perPage)->get() as $property) {
                $rows[] = $this->exactRow($property);
            }
        }
        foreach (array_slice($nearby, max(0, $offset - $exactTotal), $perPage - count($rows)) as $property) {
            $rows[] = $this->alternativeRow($property, $input, $place, $area);
        }

        return $rows;
    }

    private function specificationPage(Builder $exact, ?Builder $alternatives, ?array $reference, bool $drawn,
        int $offset, int $perPage, string $sort): array
    {
        $exact->select('properties.id as property_id', 'properties.price')
            ->selectRaw('0 AS discovery_nearby, 0 AS discovery_criteria_misses, 0 AS discovery_location_difference,
                CAST(NULL AS DOUBLE PRECISION) AS discovery_area_distance_m');
        $this->selectDistance($exact, $reference, 'discovery_rank_distance_m', $drawn);
        $eligible = $exact->toBase();
        if ($alternatives !== null) {
            // The alternative limit is applied to its own ranked candidates.
            // The combined stream is ranked again before any page is cut.
            $eligible->unionAll(DB::query()->fromSub($alternatives->toBase(), 'kept_alternatives'));
        }
        $ranks = DB::query()->fromSub($eligible, 'eligible');
        $page = (clone $ranks)->select('eligible.*')
            ->selectRaw('COUNT(*) OVER () AS discovery_total,
                COUNT(CASE WHEN discovery_nearby = 0 THEN 1 END) OVER () AS discovery_exact_total');
        $this->orderBySpecifications($page, $sort);
        $properties = Property::query()->with('images')
            ->joinSub($page->offset($offset)->limit($perPage), 'ranked', 'ranked.property_id', '=', 'properties.id')
            ->select('properties.*', 'ranked.discovery_nearby', 'ranked.discovery_criteria_misses',
                'ranked.discovery_location_difference', 'ranked.discovery_area_distance_m', 'ranked.discovery_rank_distance_m',
                'ranked.discovery_total', 'ranked.discovery_exact_total');
        $this->orderBySpecifications($properties, $sort, 'ranked.');
        $rows = $properties->get();
        // An empty/out-of-range page still returns totals for the same stream.
        $counts = $rows->first() ?? $ranks->selectRaw('COUNT(*) AS discovery_total,
            COUNT(CASE WHEN discovery_nearby = 0 THEN 1 END) AS discovery_exact_total')->first();

        return [$rows, (int) $counts->discovery_total, (int) $counts->discovery_exact_total];
    }

    private function orderBySpecifications(Builder|QueryBuilder $query, string $sort, string $prefix = ''): void
    {
        $query->orderBy($prefix.'discovery_criteria_misses')
            ->orderByRaw($prefix.'discovery_rank_distance_m ASC NULLS LAST');
        if (in_array($sort, ['price_asc', 'price_desc'], true)) {
            $query->orderBy($prefix.'price', $sort === 'price_asc' ? 'asc' : 'desc');
        }
        $query->orderByDesc($prefix.'property_id');
    }

    private function exactRow(Property $property): array
    {
        return ['property' => $property, 'match' => ['kind' => 'exact', 'reasons' => [], 'distance_m' => null,
            'criteria_misses' => 0, 'rank_distance_m' => $this->metres($property->discovery_rank_distance_m)]];
    }

    private function query(array $input, ?array $place, bool $geometry = true): Builder
    {
        $query = $this->filters->publicQuery()->with('primaryImage');
        if ($place !== null) {
            unset($input['search']);
            if ($place['kind'] === 'cell') {
                $query->where('geo_cell_id', $place['id']);
            } else {
                $this->applyRecordedGovernorate($query, $place);
                unset($input['governorate']);
            }
        }
        $this->filters->apply($query, $input);
        if ($geometry) {
            $this->filters->applyGeometry($query, $input);
        }

        return $query;
    }

    private function applyRecordedGovernorate(Builder $query, array $place): void
    {
        $query->where(function (Builder $region) use ($place): void {
            $this->filters->apply($region, ['governorate' => $place['name']]);
            $region->orWhere(function (Builder $legacy) use ($place): void {
                $legacy->whereNull('geo_cell_id')->where(function (Builder $address) use ($place): void {
                    $column = $this->filters->normalizedArabicSql('address');
                    $expression = DB::getDriverName() === 'pgsql' ? "STRPOS({$column}, ?) > 0" : "INSTR({$column}, ?) > 0";
                    foreach (array_filter($place['names']) as $name) {
                        $address->orWhereRaw($expression, [mb_strtolower($this->filters->normalizeArabicSearch($name))]);
                    }
                });
            });
        });
    }

    private function alternatives(array $input, ?array $place, Builder $exact, ?array $area, ?array $rankReference,
        bool $bySpecifications, string $sort): ?Builder
    {
        $soft = array_intersect_key($input, self::NUMERIC);
        $approximate = (bool) ($place['approximate'] ?? false);
        if ($soft === [] && $area === null && ! $approximate) {
            return null;
        }
        $hard = array_diff_key($input, self::NUMERIC, array_flip(self::GEOMETRY));
        // A place may expand only with real recorded geometry. Unknown text
        // stays a hard requirement, so an empty district never becomes random stock.
        $candidatePlace = $area === null ? $place : null;
        if ($area !== null && $place !== null) {
            unset($hard['search']);
        }
        $query = $this->query($hard, $candidatePlace, false)
            ->whereNotIn('properties.id', (clone $exact)->select('properties.id'));
        $groups = [];
        $gapParts = [];
        $gapBindings = [];
        $overParts = [];
        $overBindings = [];
        foreach ($soft as $key => $value) {
            [$column, $operator, $group] = self::NUMERIC[$key];
            $value = (float) $value;
            $expanded = in_array($group, ['bedrooms', 'bathrooms'], true) ? max(0, $value - 1)
                : ($operator === '>=' ? $value * .8 : $value * 1.2);
            $query->whereNotNull($column)->where($column, $operator, $expanded);
            $opposite = $operator === '>=' ? '<' : '>';
            $groups[$group]['sql'][] = "{$column} {$opposite} ?";
            $groups[$group]['bindings'][] = $value;
            $gapParts[] = "CASE WHEN {$column} {$opposite} ? THEN ABS({$column} - ?) / ? ELSE 0 END";
            array_push($gapBindings, $value, $value, max(1, $value));
            if ($group === 'budget' && $operator === '<=') {
                $overParts[] = "{$column} > ?";
                $overBindings[] = $value;
            }
        }
        // Original location predicate, including a drawn boundary, remains the
        // classification authority even when the alternative lies just outside.
        $location = $this->query(array_diff_key($input, self::NUMERIC), $place)->select('properties.id');
        $locationSql = 'CASE WHEN properties.id IN ('.$location->toSql().') THEN 0 ELSE 1 END';
        $locationBindings = $location->getBindings();
        $parts = [];
        $specificationBindings = [];
        foreach ($groups as $group) {
            $parts[] = 'CASE WHEN ('.implode(' OR ', $group['sql']).') THEN 1 ELSE 0 END';
            array_push($specificationBindings, ...$group['bindings']);
        }
        $specificationSql = $parts === [] ? '0' : '('.implode(' + ', $parts).')';
        // Geography and approximate place text retain their eligibility cost.
        // Only missed property specifications contribute to the new rank.
        $differenceSql = "({$locationSql} + {$specificationSql}".($approximate ? ' + 1' : '').')';
        $differenceBindings = [...$locationBindings, ...$specificationBindings];
        if ($bySpecifications) {
            $query->select('properties.id as property_id', 'properties.price')->selectRaw('1 AS discovery_nearby')
                ->selectRaw("{$specificationSql} AS discovery_criteria_misses", $specificationBindings);
        } else {
            $query->select('properties.*')->selectRaw("{$differenceSql} AS discovery_criteria_misses", $differenceBindings);
        }
        $query->selectRaw("{$locationSql} AS discovery_location_difference", $locationBindings)
            ->whereRaw("{$differenceSql} BETWEEN 1 AND 2", $differenceBindings);
        $this->selectDistance($query, $area, 'discovery_area_distance_m');
        if ($area !== null) {
            [$areaDistance, $areaBindings] = $this->distanceSql($area);
            $this->constrainNearby($query, $area, $areaDistance, $areaBindings);
        }
        $this->selectDistance($query, $rankReference, 'discovery_rank_distance_m');
        if ($bySpecifications) {
            $this->orderBySpecifications($query, $sort);

            return $query->limit(self::ALTERNATIVE_LIMIT);
        }

        $query->orderBy('discovery_criteria_misses');
        if ($rankReference !== null) {
            $query->orderByRaw('discovery_rank_distance_m ASC NULLS LAST');
        }
        if ($overParts !== []) {
            $query->orderByRaw('CASE WHEN ('.implode(' OR ', $overParts).') THEN 1 ELSE 0 END ASC', $overBindings);
        }
        if ($gapParts !== []) {
            $query->orderByRaw('('.implode(' + ', $gapParts).') ASC', $gapBindings);
        }
        return $query->orderBy('properties.id')->limit(self::ALTERNATIVE_LIMIT);
    }

    private function alternativeRow(Property $property, array $input, ?array $place, ?array $area): array
    {
        $reasons = [];
        if ($place['approximate'] ?? false) {
            $reasons[] = ['field' => 'search', 'message' => 'كتابة قريبة من بحثك: '.$place['name']];
        }
        $fromArea = $property->discovery_area_distance_m;
        $distance = $fromArea === null ? null : round(max(0, (float) $fromArea - ($area['radius_m'] ?? 0)), 1);
        if ((int) $property->discovery_location_difference !== 0) {
            $reasons[] = ['field' => 'location', 'message' => isset($input['area_polygon']) ? 'خارج المنطقة المرسومة' : 'قريب من النطاق المطلوب',
                'distance_m' => $distance];
        }
        foreach (array_intersect_key($input, self::NUMERIC) as $key => $value) {
            [$column, $operator, $group] = self::NUMERIC[$key];
            $actual = (float) $property->{$column};
            if ($operator === '>=' ? $actual >= $value : $actual <= $value) {
                continue;
            }
            $difference = abs($actual - (float) $value);
            $label = match ($group) {
                'budget' => $operator === '<=' ? 'أعلى من سقف السعر بـ' : 'أقل من الحد الأدنى للسعر بـ',
                'bedrooms' => 'غرف أقل من المطلوب بـ', 'bathrooms' => 'حمامات أقل من المطلوب بـ', default => 'فرق المساحة م²: '
            };
            $reasons[] = ['field' => $key, 'message' => $label.$this->number($difference).($group === 'budget' ? ' '.$property->currency : ''),
                'expected' => (float) $value, 'actual' => $actual, 'difference' => $difference];
        }

        return ['property' => $property, 'match' => ['kind' => 'nearby', 'reasons' => $reasons, 'distance_m' => $distance,
            'distance_reference' => isset($input['area_polygon']) ? 'drawn_boundary' : ($area === null ? 'text_only' : 'requested_area'),
            'criteria_misses' => (int) $property->discovery_criteria_misses,
            'rank_distance_m' => $this->metres($property->discovery_rank_distance_m)]];
    }

    private function selectDistance(Builder $query, ?array $reference, string $alias, bool $zero = false): void
    {
        if ($reference === null || $zero) {
            $constant = $zero ? '0' : 'NULL';
            $query->selectRaw("CAST({$constant} AS DOUBLE PRECISION) AS {$alias}");

            return;
        }
        [$distance, $bindings] = $this->distanceSql($reference);
        $query->selectRaw("{$distance} AS {$alias}", $bindings);
    }

    private function number(float $value): string
    {
        return rtrim(rtrim(number_format($value, 2, '.', ''), '0'), '.');
    }

    private function metres(mixed $distance): ?float
    {
        return $distance === null ? null : round((float) $distance, 1);
    }

    private function requestedLocation(array $input, ?array $place): ?array
    {
        if (isset($input['area_polygon'])) {
            return ['type' => 'Polygon', 'coordinates' => [json_decode($input['area_polygon'], true, flags: JSON_THROW_ON_ERROR)]];
        }
        if (isset($input['latitude'], $input['longitude'], $input['radius_km'])) {
            return ['latitude' => (float) $input['latitude'], 'longitude' => (float) $input['longitude'], 'radius_m' => (float) $input['radius_km'] * 1000];
        }
        if ($place === null) {
            return null;
        }
        $cells = GeoCell::query()->where('is_active', true);
        $place['kind'] === 'cell' ? $cells->where('id', $place['id']) : $cells->where('governorate_id', $place['id']);
        $polygons = [];
        foreach ($cells->pluck('boundary_json') as $geometry) {
            if (empty($geometry['coordinates'])) {
                continue;
            }
            if (($geometry['type'] ?? '') === 'Polygon') {
                $polygons[] = $geometry['coordinates'];
            } elseif (($geometry['type'] ?? '') === 'MultiPolygon') {
                array_push($polygons, ...$geometry['coordinates']);
            }
        }

        return $polygons === [] ? null : ['type' => 'MultiPolygon', 'coordinates' => $polygons];
    }

    private function viewportArea(array $input): ?array
    {
        [$s, $w, $n, $e] = array_map(fn ($k) => (float) $input[$k], ['south', 'west', 'north', 'east']);
        if ($s >= $n || $w === $e) {
            return null;
        }
        $ring = fn ($west, $east) => [[$west, $s], [$east, $s], [$east, $n], [$west, $n], [$west, $s]];

        return $w <= $e ? ['type' => 'Polygon', 'coordinates' => [$ring($w, $e)]]
            : ['type' => 'MultiPolygon', 'coordinates' => [[$ring($w, 180)], [$ring(-180, $e)]]];
    }

    private function distanceSql(array $reference): array
    {
        if (DB::getDriverName() !== 'pgsql') {
            // Two independently bound references may appear in one query.
            DB::connection()->getPdo()->sqliteCreateFunction('discovery_distance', static function ($lat, $lon, string $json): ?float {
                if ($lat === null || $lon === null) {
                    return null;
                }
                $distance = DiscoverySearchGeometry::distance((float) $lat, (float) $lon, json_decode($json, true, flags: JSON_THROW_ON_ERROR));

                return is_finite($distance) ? $distance : null;
            }, 3);

            return ['discovery_distance(properties.latitude, properties.longitude, ?)', [json_encode($reference, JSON_THROW_ON_ERROR)]];
        }
        [$geography, $bindings] = $this->geographySql($reference);
        if (isset($reference['latitude'])) {
            return ["ST_Distance(properties.location, {$geography})", $bindings];
        }
        // Preserve inclusive geometry coverage even along a horizontal ring edge.
        return ["CASE WHEN ST_Covers(ST_MakeValid({$geography}::geometry), properties.location::geometry) THEN 0
            ELSE ST_Distance(properties.location, {$geography}) END", [...$bindings, ...$bindings]];
    }

    private function constrainNearby(Builder $query, array $area, string $distance, array $bindings): void
    {
        $limit = self::NEARBY_METRES + ($area['radius_m'] ?? 0);
        if (DB::getDriverName() === 'pgsql') {
            [$geography, $parameters] = $this->geographySql($area);
            $query->whereNotNull('location')->whereRaw("ST_DWithin(properties.location, {$geography}, ?)", [...$parameters, $limit]);
        } else {
            $query->whereRaw("{$distance} <= CAST(? AS REAL)", [...$bindings, $limit]);
        }
    }

    private function geographySql(array $reference): array
    {
        if (isset($reference['latitude'])) {
            return ['ST_SetSRID(ST_MakePoint(?, ?),4326)::geography', [$reference['longitude'], $reference['latitude']]];
        }

        return ['ST_SetSRID(ST_GeomFromGeoJSON(?),4326)::geography', [json_encode($reference, JSON_THROW_ON_ERROR)]];
    }

    private function assertPurposeConsistent(array $input): void
    {
        $text = $this->filters->normalizeArabicSearch((string) ($input['search'] ?? ''));
        if (($input['purpose'] ?? '') === 'rent' && preg_match('/(?:^|\s)للبيع(?:$|\s|[،,.])/u', $text)
            || ($input['purpose'] ?? '') === 'sale' && preg_match('/(?:^|\s)للايجار(?:$|\s|[،,.])/u', $text)) {
            throw ValidationException::withMessages(['search' => ['الغرض المكتوب يخالف فلتر البيع أو الإيجار. عدّل النص أو الفلتر.']]);
        }
    }
}
