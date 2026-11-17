<?php

namespace App\Services;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/** Reference geography independent of listings and permission/coverage cells. */
class YemenGovernorateCatalog
{
    private static ?array $features = null;

    public function features(): array
    {
        return self::$features ??= json_decode(file_get_contents(resource_path('regions/yemen-adm1.geojson')), true, 512, JSON_THROW_ON_ERROR)['features'];
    }

    public function feature(string $code): ?array
    {
        foreach ($this->features() as $feature) {
            if ($feature['properties']['code'] === $code) {
                return $feature;
            }
        }

        return null;
    }

    public function codes(): array
    {
        return array_column(array_column($this->features(), 'properties'), 'code');
    }

    public function locate(float $latitude, float $longitude, ?float $accuracy): array
    {
        $matches = [];
        foreach ($this->features() as $feature) {
            if ($this->covers($feature['geometry'], $longitude, $latitude)) {
                $matches[] = $feature;
            }
        }
        if (count($matches) !== 1) {
            return ['code' => null, 'status' => $matches === [] ? 'outside_reference' : 'boundary', 'needs_confirmation' => true];
        }
        $feature = $matches[0];
        $distance = $this->boundaryDistance($feature['geometry'], $longitude, $latitude);
        $uncertain = $accuracy === null || $accuracy <= 0 || $distance <= $accuracy;

        return ['code' => $feature['properties']['code'], 'status' => $accuracy === null || $accuracy <= 0 ? 'accuracy_unknown' : ($uncertain ? 'boundary' : 'resolved'),
            'needs_confirmation' => $uncertain, 'boundary_distance_m' => round($distance, 1)];
    }

    public function apply(Builder $query, string $code): void
    {
        $feature = $this->feature($code);
        if (! $feature) {
            $query->whereRaw('1=0');

            return;
        }
        if (DB::getDriverName() === 'pgsql') {
            $query->whereRaw('ST_Covers(ST_SetSRID(ST_GeomFromGeoJSON(?),4326), ST_SetSRID(ST_MakePoint(properties.longitude,properties.latitude),4326))',
                [json_encode($feature['geometry'], JSON_THROW_ON_ERROR)]);
        } else {
            // Disposable SQLite uses the identical full geometry without a row cap.
            $ids = DB::table('properties')->select(['id', 'latitude', 'longitude'])->get()
                ->filter(fn ($p) => $p->latitude !== null && $p->longitude !== null && $this->covers($feature['geometry'], (float) $p->longitude, (float) $p->latitude))->pluck('id');
            $query->whereIn('properties.id', $ids);
        }
    }

    public function covers(array $geometry, float $x, float $y): bool
    {
        $polygons = $geometry['type'] === 'Polygon' ? [$geometry['coordinates']] : $geometry['coordinates'];
        foreach ($polygons as $polygon) {
            $outer = $this->ring($polygon[0], $x, $y);
            if ($outer === 0) {
                continue;
            }
            if ($outer === 2) {
                return true;
            }
            $hole = false;
            foreach (array_slice($polygon, 1) as $ring) {
                $inside = $this->ring($ring, $x, $y);
                if ($inside === 2) {
                    return true;
                }
                if ($inside === 1) {
                    $hole = true;
                    break;
                }
            }
            if (! $hole) {
                return true;
            }
        }

        return false;
    }

    /** 0 outside, 1 inside, 2 on the boundary. */
    private function ring(array $ring, float $x, float $y): int
    {
        $inside = false;
        for ($i = 0, $j = count($ring) - 1; $i < count($ring); $j = $i++) {
            [$ax, $ay] = $ring[$j];
            [$bx, $by] = $ring[$i];
            $cross = ($x - $ax) * ($by - $ay) - ($y - $ay) * ($bx - $ax);
            if (abs($cross) < 1e-12 && $x >= min($ax, $bx) && $x <= max($ax, $bx) && $y >= min($ay, $by) && $y <= max($ay, $by)) {
                return 2;
            }
            if (($ay > $y) !== ($by > $y) && $x < ($bx - $ax) * ($y - $ay) / ($by - $ay) + $ax) {
                $inside = ! $inside;
            }
        }

        return $inside ? 1 : 0;
    }

    private function boundaryDistance(array $geometry, float $x, float $y): float
    {
        $polygons = $geometry['type'] === 'Polygon' ? [$geometry['coordinates']] : $geometry['coordinates'];
        $nearest = INF;
        $scaleX = 111320 * cos(deg2rad($y));
        foreach ($polygons as $polygon) {
            foreach ($polygon as $ring) {
                for ($i = 1; $i < count($ring); $i++) {
                    $ax = ($ring[$i - 1][0] - $x) * $scaleX;
                    $ay = ($ring[$i - 1][1] - $y) * 111320;
                    $bx = ($ring[$i][0] - $x) * $scaleX;
                    $by = ($ring[$i][1] - $y) * 111320;
                    $dx = $bx - $ax;
                    $dy = $by - $ay;
                    $t = ($dx * $dx + $dy * $dy) > 0 ? max(0, min(1, -($ax * $dx + $ay * $dy) / ($dx * $dx + $dy * $dy))) : 0;
                    $nearest = min($nearest, hypot($ax + $t * $dx, $ay + $t * $dy));
                }
            }
        }

        return $nearest;
    }
}
