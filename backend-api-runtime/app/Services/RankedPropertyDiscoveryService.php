<?php

namespace App\Services;

use App\Models\GeoCell;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** One ordered stream: every exact page, followed by bounded explained alternatives. */
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
        $exact = $this->query($input, $place);
        if ($approximate) {
            $exact->whereRaw('1=0');
        }
        $exactTotal = (clone $exact)->count();
        $nearby = $this->alternatives($input, $place, $exact);
        $total = $exactTotal + count($nearby);
        $offset = ($page - 1) * $perPage;
        $rows = [];
        if ($offset < $exactTotal) {
            $this->filters->applySearchOrdering($exact, $input, $sort);
            match ($sort) {
                'price_asc' => $exact->orderBy('price')->orderByDesc('id'),
                'price_desc' => $exact->orderByDesc('price')->orderByDesc('id'),
                default => $exact->orderByDesc('id'),
            };
            foreach ($exact->offset($offset)->limit($perPage)->get() as $property) {
                $rows[] = ['property' => $property, 'match' => ['kind' => 'exact', 'reasons' => [], 'distance_m' => null]];
            }
        }
        if (count($rows) < $perPage) {
            $rows = array_merge($rows, array_slice($nearby, max(0, $offset - $exactTotal), $perPage - count($rows)));
        }

        return ['rows' => $rows, 'meta' => ['current_page' => $page, 'last_page' => max(1, (int) ceil($total / $perPage)),
            'per_page' => $perPage, 'total' => $total, 'exact_total' => $exactTotal, 'alternative_total' => count($nearby),
            'alternative_limit' => self::ALTERNATIVE_LIMIT, 'ranking' => 'fewest_changes,budget,distance,filter_gap,id']];
    }

    private function query(array $input, ?array $place, bool $geometry = true): Builder
    {
        $query = $this->filters->publicQuery()->with('primaryImage');
        if ($place !== null) {
            unset($input['search']);
            if ($place['kind'] === 'cell') {
                $query->where('geo_cell_id', $place['id']);
            } else {
                $input['governorate'] ??= $place['name'];
            }
        }
        $this->filters->apply($query, $input);
        if ($geometry) {
            $this->filters->applyGeometry($query, $input);
        }

        return $query;
    }

    private function alternatives(array $input, ?array $place, Builder $exact): array
    {
        $soft = array_intersect_key($input, self::NUMERIC);
        $reference = $this->reference($input, $place);
        $approximate = (bool) ($place['approximate'] ?? false);
        if ($soft === [] && $reference === null && ! $approximate) {
            return [];
        }
        $hard = array_diff_key($input, self::NUMERIC, array_flip(self::GEOMETRY));
        // A place may expand only with real recorded geometry. Unknown text
        // stays a hard requirement, so an empty district never becomes random stock.
        $candidatePlace = $reference === null ? $place : null;
        if ($reference !== null && $place !== null) {
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
        $distanceSql = '0';
        $distanceBindings = [];
        if ($reference !== null) {
            [$distanceSql, $distanceBindings] = $this->distanceSql($query, $reference);
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
        $query->select('properties.*')->selectRaw("{$distanceSql} AS discovery_distance_m", $distanceBindings)
            ->selectRaw("{$locationSql} AS discovery_location_difference", $locationBindings)
            ->whereRaw("{$differenceSql} BETWEEN 1 AND 2", $bindings)
            ->orderByRaw("{$differenceSql} ASC", $bindings);
        if ($overParts !== []) {
            $query->orderByRaw('CASE WHEN ('.implode(' OR ', $overParts).') THEN 1 ELSE 0 END ASC', $overBindings);
        }
        $query->orderBy('discovery_distance_m');
        if ($gapParts !== []) {
            $query->orderByRaw('('.implode(' + ', $gapParts).') ASC', $gapBindings);
        }
        $result = [];
        foreach ($query->orderBy('properties.id')->limit(self::ALTERNATIVE_LIMIT)->get() as $property) {
            $reasons = [];
            if ($approximate) {
                $reasons[] = ['field' => 'search', 'message' => 'كتابة قريبة من بحثك: '.$place['name']];
            }
            $distance = $reference === null ? null : round((float) $property->discovery_distance_m, 1);
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
                'distance_reference' => isset($input['area_polygon']) ? 'drawn_boundary' : ($reference === null ? 'text_only' : 'requested_area')]];
        }

        return $result;
    }

    private function number(float $value): string
    {
        return rtrim(rtrim(number_format($value, 2, '.', ''), '0'), '.');
    }

    private function reference(array $input, ?array $place): ?array
    {
        if (isset($input['area_polygon'])) {
            return ['type' => 'Polygon', 'coordinates' => [json_decode($input['area_polygon'], true, flags: JSON_THROW_ON_ERROR)]];
        }
        if (isset($input['south'], $input['west'], $input['north'], $input['east'])) {
            [$s, $w, $n, $e] = array_map(fn ($k) => (float) $input[$k], ['south', 'west', 'north', 'east']);
            if ($s >= $n || $w === $e) {
                return null;
            }
            $ring = fn ($west, $east) => [[$west, $s], [$east, $s], [$east, $n], [$west, $n], [$west, $s]];

            return $w <= $e ? ['type' => 'Polygon', 'coordinates' => [$ring($w, $e)]]
                : ['type' => 'MultiPolygon', 'coordinates' => [[$ring($w, 180)], [$ring(-180, $e)]]];
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
            if (($geometry['type'] ?? '') === 'Polygon') {
                $polygons[] = $geometry['coordinates'];
            } elseif (($geometry['type'] ?? '') === 'MultiPolygon') {
                array_push($polygons, ...$geometry['coordinates']);
            }
        }

        return $polygons === [] ? null : ['type' => 'MultiPolygon', 'coordinates' => $polygons];
    }

    private function distanceSql(Builder $query, array $reference): array
    {
        if (DB::getDriverName() !== 'pgsql') {
            DB::connection()->getPdo()->sqliteCreateFunction('phase04_distance',
                fn ($lat, $lon) => $lat === null || $lon === null ? null : DiscoverySearchGeometry::distance((float) $lat, (float) $lon, $reference), 2);
            $sql = 'phase04_distance(latitude, longitude)';
            $query->whereRaw($sql.' <= ?', [self::NEARBY_METRES]);

            return [$sql, []];
        }
        $query->whereNotNull('location');
        if (isset($reference['latitude'])) {
            $point = 'ST_SetSRID(ST_MakePoint(?, ?),4326)::geography';
            $coordinates = [$reference['longitude'], $reference['latitude']];
            $query->whereRaw("ST_DWithin(location, {$point}, ?)", [...$coordinates, $reference['radius_m'] + self::NEARBY_METRES]);

            return ["GREATEST(0, ST_Distance(location, {$point}) - ?)", [...$coordinates, $reference['radius_m']]];
        }
        $json = json_encode($reference, JSON_THROW_ON_ERROR);
        $shape = 'ST_SetSRID(ST_GeomFromGeoJSON(?),4326)::geography';
        $query->whereRaw("ST_DWithin(location, {$shape}, ?)", [$json, self::NEARBY_METRES]);

        return ["ST_Distance(location, {$shape})", [$json]];
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
