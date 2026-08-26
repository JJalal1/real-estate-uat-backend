<?php

namespace App\Services;

use App\Models\GeoCell;
use App\Models\Property;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class RegionService
{
    public function resolveCell(float $latitude, float $longitude): ?GeoCell
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            $id = DB::table('geo_cells')
                ->join('governorates', 'governorates.id', '=', 'geo_cells.governorate_id')
                ->where('geo_cells.is_active', true)
                ->where('governorates.is_active', true)
                ->whereRaw(
                    'ST_Covers(boundary, ST_SetSRID(ST_MakePoint(?, ?), 4326))',
                    [$longitude, $latitude],
                )
                // Shared borders are deterministic: the lowest cell id wins.
                ->orderBy('geo_cells.id')
                ->value('geo_cells.id');
            return $id ? GeoCell::query()->find((int) $id) : null;
        }

        foreach (GeoCell::query()->where('is_active', true)->whereHas('governorate', fn ($q) => $q->where('is_active', true))->orderBy('id')->get() as $cell) {
            if ($this->pointInPolygon($latitude, $longitude, $cell->boundary_json ?? [])) {
                return $cell;
            }
        }
        return null;
    }

    /**
     * Resolve the geographic cell for reporting/search only. Broker accounts
     * are no longer assigned exclusive publication areas.
     */
    public function assertListingAllowed(User $user, float $latitude, float $longitude): ?GeoCell
    {
        return $this->resolveCell($latitude, $longitude);
    }

    public function refreshPropertyCellAssignments(): void
    {
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement(<<<'SQL'
UPDATE properties AS p
SET geo_cell_id = (
    SELECT c.id
    FROM geo_cells AS c
    JOIN governorates g ON g.id = c.governorate_id
    WHERE c.is_active = TRUE AND g.is_active = TRUE
      AND ST_Covers(c.boundary, ST_SetSRID(ST_MakePoint(p.longitude, p.latitude), 4326))
    ORDER BY c.id ASC
    LIMIT 1
)
WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
SQL);
            return;
        }

        Property::query()->whereNotNull('latitude')->whereNotNull('longitude')->each(function (Property $property): void {
            $cell = $this->resolveCell((float) $property->latitude, (float) $property->longitude);
            $property->forceFill(['geo_cell_id' => $cell?->id])->save();
        });
    }

    public function polygonGeoJson(array $points): array
    {
        $coordinates = array_map(
            fn (array $point): array => [(float) $point['longitude'], (float) $point['latitude']],
            $points,
        );
        if ($coordinates[0] !== $coordinates[count($coordinates) - 1]) {
            $coordinates[] = $coordinates[0];
        }
        return ['type' => 'Polygon', 'coordinates' => [$coordinates]];
    }

    private function pointInPolygon(float $latitude, float $longitude, array $geoJson): bool
    {
        $ring = $geoJson['coordinates'][0] ?? [];
        if (count($ring) < 4) {
            return false;
        }
        $inside = false;
        $j = count($ring) - 1;
        for ($i = 0, $n = count($ring); $i < $n; $j = $i++) {
            [$xi, $yi] = [(float) $ring[$i][0], (float) $ring[$i][1]];
            [$xj, $yj] = [(float) $ring[$j][0], (float) $ring[$j][1]];
            $den = ($yj - $yi);
            $intersects = (($yi > $latitude) !== ($yj > $latitude))
                && ($longitude < ($xj - $xi) * ($latitude - $yi) / (($den == 0.0) ? 1.0e-12 : $den) + $xi);
            if ($intersects) {
                $inside = ! $inside;
            }
        }
        return $inside;
    }
}
