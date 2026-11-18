<?php

namespace App\Services;

use App\Models\GeoCell;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** One ranked stream for list and map, with exact results at degree zero. */
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

    public function page(array $input, int $page, int $perPage, string $sort = 'latest'): array
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
        $exactTotal = (clone $exact)->count();
        $nearby = $this->alternatives($input, $place, $exact, $area, $rankReference);
        $total = $exactTotal + count($nearby);
        $offset = ($page - 1) * $perPage;
        $rows = [];
        if ($offset < $exactTotal) {
            if ($rankReference !== null && ! $drawn) {
                [$distance, $bindings] = $this->distanceSql($rankReference);
                $exact->select('properties.*')->selectRaw("{$distance} AS discovery_rank_distance_m", $bindings)
                    ->orderByRaw('discovery_rank_distance_m ASC NULLS LAST');
            }
            $this->filters->applySearchOrdering($exact, $input, $sort);
            match ($sort) {
                'price_asc' => $exact->orderBy('price')->orderByDesc('id'),
                'price_desc' => $exact->orderByDesc('price')->orderByDesc('id'),
                default => $exact->orderByDesc('id'),
            };
            foreach ($exact->offset($offset)->limit($perPage)->get() as $property) {
                $rows[] = ['property' => $property, 'match' => ['kind' => 'exact', 'reasons' => [], 'distance_m' => null,
                    'criteria_misses' => 0, 'rank_distance_m' => $drawn ? 0.0
                        : ($rankReference === null ? null : $this->metres($property->discovery_rank_distance_m))]];
            }
        }
        if (count($rows) < $perPage) {
            $rows = array_merge($rows, array_slice($nearby, max(0, $offset - $exactTotal), $perPage - count($rows)));
        }

        return ['rows' => $rows, 'meta' => ['current_page' => $page, 'last_page' => max(1, (int) ceil($total / $perPage)),
            'per_page' => $perPage, 'total' => $total, 'exact_total' => $exactTotal, 'alternative_total' => count($nearby),
            'alternative_limit' => self::ALTERNATIVE_LIMIT, 'ranking' => 'fewest_changes,distance_when_known,tiebreakers,id',
            'ranking_distance_reference' => $rankReference === null ? null : ($drawn ? 'drawn_area' : ($point ? 'point' : 'recorded_area'))]];
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

    private function alternatives(array $input, ?array $place, Builder $exact, ?array $area, ?array $rankReference): array
    {
        $soft = array_intersect_key($input, self::NUMERIC);
        $approximate = (bool) ($place['approximate'] ?? false);
        if ($soft === [] && $area === null && ! $approximate) {
            return [];
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
        $parts = [$locationSql];
        $bindings = $locationBindings;
        foreach ($groups as $group) {
            $parts[] = 'CASE WHEN ('.implode(' OR ', $group['sql']).') THEN 1 ELSE 0 END';
            array_push($bindings, ...$group['bindings']);
        }
        if ($approximate) {
            $parts[] = '1';
        }
        $differenceSql = '('.implode(' + ', $parts).')';
        $query->select('properties.*')->selectRaw("{$differenceSql} AS discovery_criteria_misses", $bindings)
            ->selectRaw("{$locationSql} AS discovery_location_difference", $locationBindings)
            ->whereRaw("{$differenceSql} BETWEEN 1 AND 2", $bindings)
            ->orderBy('discovery_criteria_misses');
        if ($area !== null) {
            [$areaDistance, $areaBindings] = $this->distanceSql($area);
            $this->constrainNearby($query, $area, $areaDistance, $areaBindings);
            $query->selectRaw("{$areaDistance} AS discovery_area_distance_m", $areaBindings);
        }
        $rankColumn = 'discovery_area_distance_m';
        if ($rankReference !== null) {
            if ($rankReference !== $area) {
                [$rankDistance, $rankBindings] = $this->distanceSql($rankReference);
                $rankColumn = 'discovery_rank_distance_m';
                $query->selectRaw("{$rankDistance} AS {$rankColumn}", $rankBindings);
            }
            $query->orderByRaw("{$rankColumn} ASC NULLS LAST");
        }
        if ($overParts !== []) {
            $query->orderByRaw('CASE WHEN ('.implode(' OR ', $overParts).') THEN 1 ELSE 0 END ASC', $overBindings);
        }
        if ($gapParts !== []) {
            $query->orderByRaw('('.implode(' + ', $gapParts).') ASC', $gapBindings);
        }
        $result = [];
        foreach ($query->orderBy('properties.id')->limit(self::ALTERNATIVE_LIMIT)->get() as $property) {
            $reasons = [];
            if ($approximate) {
                $reasons[] = ['field' => 'search', 'message' => 'كتابة قريبة من بحثك: '.$place['name']];
            }
            $fromArea = $area === null ? null : $property->discovery_area_distance_m;
            $distance = $fromArea === null ? null : round(max(0, (float) $fromArea - ($area['radius_m'] ?? 0)), 1);
            if ((int) $property->discovery_location_difference !== 0) {
                $reasons[] = ['field' => 'location', 'message' => isset($input['area_polygon']) ? 'خارج المنطقة المرسومة' : 'قريب من النطاق المطلوب',
                    'distance_m' => $distance];
            }
            foreach ($soft as $key => $value) {
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
            $result[] = ['property' => $property, 'match' => ['kind' => 'nearby', 'reasons' => $reasons, 'distance_m' => $distance,
                'distance_reference' => isset($input['area_polygon']) ? 'drawn_boundary' : ($area === null ? 'text_only' : 'requested_area'),
                'criteria_misses' => (int) $property->discovery_criteria_misses,
                'rank_distance_m' => $rankReference === null ? null : $this->metres($property->{$rankColumn})]];
        }

        return $result;
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
