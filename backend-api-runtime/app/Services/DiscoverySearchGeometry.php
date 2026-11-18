<?php

namespace App\Services;

/** SQLite oracle for disposable tests; UAT distances use PostGIS geography. */
class DiscoverySearchGeometry
{
    public static function distance(float $lat, float $lon, array $reference): float
    {
        if (isset($reference['latitude'])) {
            return self::haversine($lat, $lon, $reference['latitude'], $reference['longitude']);
        }
        $polygons = ($reference['type'] ?? '') === 'Polygon' ? [$reference['coordinates']] : ($reference['coordinates'] ?? []);
        $minimum = INF;
        foreach ($polygons as $rings) {
            $inside = self::covers($lat, $lon, $rings[0]);
            foreach (array_slice($rings, 1) as $hole) {
                if (self::covers($lat, $lon, $hole)) {
                    $inside = false;
                }
            }
            if ($inside) {
                return 0;
            }
            foreach ($rings as $ring) {
                for ($i = 1; $i < count($ring); $i++) {
                    $a = $ring[$i - 1];
                    $b = $ring[$i];
                    $x1 = deg2rad(self::longitudeDelta($a[0] - $lon)) * 6371000 * cos(deg2rad($lat));
                    $y1 = deg2rad($a[1] - $lat) * 6371000;
                    $x2 = deg2rad(self::longitudeDelta($b[0] - $lon)) * 6371000 * cos(deg2rad($lat));
                    $y2 = deg2rad($b[1] - $lat) * 6371000;
                    $length = ($x2 - $x1) ** 2 + ($y2 - $y1) ** 2;
                    $t = $length > 0 ? max(0, min(1, (-$x1 * ($x2 - $x1) - $y1 * ($y2 - $y1)) / $length)) : 0;
                    $minimum = min($minimum, hypot($x1 + $t * ($x2 - $x1), $y1 + $t * ($y2 - $y1)));
                }
            }
        }

        return $minimum;
    }

    private static function longitudeDelta(float $value): float
    {
        return fmod($value + 540, 360) - 180;
    }

    private static function haversine(float $a, float $b, float $c, float $d): float
    {
        $h = sin(deg2rad($c - $a) / 2) ** 2 + cos(deg2rad($a)) * cos(deg2rad($c)) * sin(deg2rad($d - $b) / 2) ** 2;

        return 6371000 * 2 * asin(min(1, sqrt($h)));
    }

    private static function covers(float $lat, float $lon, array $ring): bool
    {
        $inside = false;
        for ($i = 0, $j = count($ring) - 1; $i < count($ring); $j = $i++) {
            [$x, $y] = $ring[$i];
            [$u, $v] = $ring[$j];
            $cross = ($lon - $x) * ($v - $y) - ($lat - $y) * ($u - $x);
            if (abs($cross) < 1e-10 && $lon >= min($x, $u) && $lon <= max($x, $u) && $lat >= min($y, $v) && $lat <= max($y, $v)) {
                return true;
            }
            if (($y > $lat) !== ($v > $lat) && $lon < ($u - $x) * ($lat - $y) / ($v - $y) + $x) {
                $inside = ! $inside;
            }
        }

        return $inside;
    }
}
