<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\GeoCell;
use App\Models\Governorate;
use App\Models\Property;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\RegionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class RegionsController extends Controller
{
    public function __construct(
        private readonly RegionService $regions,
        private readonly AuditLogService $audit,
    ) {}

    public function publicCells(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'governorate_id' => ['nullable', 'integer', 'exists:governorates,id'],
            'south' => ['nullable', 'numeric', 'between:-90,90'],
            'west' => ['nullable', 'numeric', 'between:-180,180'],
            'north' => ['nullable', 'numeric', 'between:-90,90'],
            'east' => ['nullable', 'numeric', 'between:-180,180'],
        ]);

        $query = GeoCell::query()
            ->with(['governorate'])
            ->where('is_active', true)
            ->whereHas('governorate', fn ($q) => $q->where('is_active', true));

        if (isset($validated['governorate_id'])) {
            $query->where('governorate_id', $validated['governorate_id']);
        }
        if (isset($validated['south'], $validated['west'], $validated['north'], $validated['east'])) {
            if ((float) $validated['south'] >= (float) $validated['north']) {
                throw ValidationException::withMessages(['bounds' => ['south must be less than north.']]);
            }
            $query->whereRaw(
                'ST_Intersects(boundary, ST_MakeEnvelope(?, ?, ?, ?, 4326))',
                [(float) $validated['west'], (float) $validated['south'], (float) $validated['east'], (float) $validated['north']],
            );
        }

        $cells = $query->orderBy('governorate_id')->orderBy('id')->get();
        return response()->json(['data' => $cells->map(fn (GeoCell $cell) => $this->cellData($cell, false))->values()]);
    }

    public function resolvePoint(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $latitude = (float) $validated['latitude'];
        $longitude = (float) $validated['longitude'];
        $cell = $this->regions->resolveCell($latitude, $longitude);
        if ($cell) {
            $cell->loadMissing('governorate');
        }

        return response()->json([
            'data' => [
                'latitude' => $latitude,
                'longitude' => $longitude,
                'governorate' => $cell?->governorate ? [
                    'id' => $cell->governorate->id,
                    'code' => $cell->governorate->code,
                    'name_ar' => $cell->governorate->name_ar,
                    'name_en' => $cell->governorate->name_en,
                ] : null,
                'cell' => $cell ? [
                    'id' => $cell->id,
                    'code' => $cell->code,
                    'name_ar' => $cell->name_ar,
                    'name_en' => $cell->name_en,
                ] : null,
            ],
        ]);
    }

    public function reverseAddress(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $latitude = (float) $validated['latitude'];
        $longitude = (float) $validated['longitude'];
        $cell = $this->regions->resolveCell($latitude, $longitude);
        if ($cell) {
            $cell->loadMissing('governorate');
        }

        $nominatim = $this->lookupNominatim($latitude, $longitude);
        $nominatimAddress = is_array($nominatim['address'] ?? null) ? $nominatim['address'] : [];
        $displayName = $this->cleanAddressText($nominatim['display_name'] ?? null);

        $internalGovernorate = $cell?->governorate?->name_ar ?: $cell?->governorate?->name_en;
        $internalDistrict = $cell?->name_ar ?: $cell?->name_en;
        $governorate = $this->cleanAddressText($internalGovernorate)
            ?? $this->firstAddressText($nominatimAddress, ['state', 'province', 'state_district', 'county']);
        $district = $this->firstAddressText($nominatimAddress, [
            'neighbourhood', 'suburb', 'quarter', 'city_district', 'district',
            'village', 'town', 'city',
        ]) ?? $this->cleanAddressText($internalDistrict);
        $street = $this->firstAddressText($nominatimAddress, [
            'road', 'pedestrian', 'residential', 'footway', 'path',
        ]);

        $photon = [];
        if ($governorate === null || $district === null || $street === null) {
            $photon = $this->lookupPhoton($latitude, $longitude);
            $governorate ??= $this->firstPhotonText($photon, ['state', 'county']);
            $district ??= $this->firstPhotonText($photon, [
                'district', 'locality', 'city', 'county',
            ]);
            $street ??= $this->firstPhotonStreet($photon);
        }

        if ($street === null && $displayName !== null) {
            $first = trim(explode(',', $displayName)[0] ?? '');
            $street = $first !== '' && $first !== $district && $first !== $governorate ? $first : null;
        }

        $providers = [];
        if (($nominatim['ok'] ?? false) === true) {
            $providers[] = 'nominatim';
        }
        if (($photon['ok'] ?? false) === true) {
            $providers[] = 'photon';
        }
        if ($cell !== null) {
            $providers[] = 'internal';
        }
        $providerStatus = $providers === [] ? 'unavailable' : implode('+', array_values(array_unique($providers)));

        return response()->json([
            'data' => [
                'latitude' => $latitude,
                'longitude' => $longitude,
                'governorate' => $governorate,
                'district' => $district,
                'street' => $street,
                'formatted_address' => $displayName,
                'provider_status' => $providerStatus,
                'provider_attempts' => [
                    'nominatim' => $nominatim['status'] ?? 'not_attempted',
                    'photon' => $photon['status'] ?? 'not_needed',
                ],
                'cell_id' => $cell?->id,
                'governorate_id' => $cell?->governorate?->id,
            ],
        ]);
    }

    public function governorates(): JsonResponse
    {
        return response()->json([
            'data' => Governorate::query()->withCount('cells')->orderBy('name_ar')->get()->map(fn (Governorate $g) => [
                'id' => $g->id,
                'code' => $g->code,
                'name_ar' => $g->name_ar,
                'name_en' => $g->name_en,
                'is_active' => $g->is_active,
                'cells_count' => $g->cells_count,
            ])->values(),
        ]);
    }

    public function storeGovernorate(Request $request): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40', 'regex:/^[A-Za-z0-9_-]+$/', 'unique:governorates,code'],
            'name_ar' => ['required', 'string', 'max:120'],
            'name_en' => ['nullable', 'string', 'max:120'],
        ]);
        $data['code'] = strtoupper($data['code']);
        $governorate = Governorate::query()->create($data + ['is_active' => true]);
        $this->audit->record($actor, 'regions.governorate_created', $governorate, ['code' => $governorate->code], $request, $actor->id);
        return response()->json(['data' => $governorate], 201);
    }

    public function updateGovernorate(Request $request, Governorate $governorate): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $data = $request->validate([
            'code' => ['sometimes', 'string', 'max:40', 'regex:/^[A-Za-z0-9_-]+$/', Rule::unique('governorates', 'code')->ignore($governorate->id)],
            'name_ar' => ['sometimes', 'string', 'max:120'],
            'name_en' => ['nullable', 'string', 'max:120'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        if (isset($data['code'])) {
            $data['code'] = strtoupper($data['code']);
        }
        $governorate->fill($data)->save();
        $this->audit->record($actor, 'regions.governorate_updated', $governorate, ['fields' => array_keys($data)], $request, $actor->id);
        return response()->json(['data' => $governorate->fresh()]);
    }

    public function cells(Request $request): JsonResponse
    {
        $data = $request->validate([
            'governorate_id' => ['nullable', 'integer', 'exists:governorates,id'],
            'search' => ['nullable', 'string', 'max:120'],
        ]);
        $query = GeoCell::query()->with(['governorate'])->withCount([
            'properties',
            'properties as published_properties_count' => fn ($q) => $q->where('status', 'published'),
        ]);
        if (isset($data['governorate_id'])) {
            $query->where('governorate_id', $data['governorate_id']);
        }
        $search=trim((string)($data['search'] ?? ''));
        if($search!=='') $query->where(fn($q)=>$q->where('name_ar','like','%'.$search.'%')->orWhere('name_en','like','%'.$search.'%')->orWhere('code','like','%'.$search.'%'));
        return response()->json(['data' => $query->orderBy('governorate_id')->orderBy('id')->get()->map(fn (GeoCell $cell) => $this->cellData($cell, true))->values()]);
    }

    public function cellProperties(Request $request, GeoCell $cell): JsonResponse
    {
        $data=$request->validate([
            'search'=>['nullable','string','max:120'],
            'status'=>['nullable',Rule::in(['draft','pending_review','published','rejected','archived'])],
        ]);
        $query=$cell->properties()->with('user:id,name')->latest('id');
        $search=trim((string)($data['search']??''));
        if($search!=='') $query->where(fn($q)=>$q->where('title','like','%'.$search.'%')->orWhere('address','like','%'.$search.'%'));
        if(!empty($data['status'])) $query->where('status',(string)$data['status']);
        $rows=$query->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(Property $property)=>[
            'id'=>$property->id,'title'=>$property->title,'status'=>$property->status,'review_status'=>$property->review_status,
            'purpose'=>$property->purpose,'type'=>$property->type,'price'=>$property->price,'currency'=>$property->currency,
            'address'=>$property->address,'latitude'=>$property->latitude,'longitude'=>$property->longitude,
            'owner'=>['id'=>$property->user_id,'name'=>$property->user?->name],
        ])->values()]);
    }

    public function storeCell(Request $request): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $data = $request->validate($this->cellRules(false));
        $geoJson = $this->regions->polygonGeoJson($data['points']);

        try {
            $cell = DB::transaction(function () use ($data, $geoJson, $actor, $request): GeoCell {
            if (DB::connection()->getDriverName() === 'pgsql') {
                $now = now();
                $json = json_encode($geoJson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
                $row = DB::selectOne(
                    'INSERT INTO geo_cells (governorate_id, code, name_ar, name_en, boundary_json, is_active, boundary, created_at, updated_at) VALUES (?, ?, ?, ?, ?::jsonb, TRUE, ST_GeomFromGeoJSON(?), ?, ?) RETURNING id',
                    [$data['governorate_id'], strtoupper($data['code']), $data['name_ar'], $data['name_en'] ?? null, $json, $json, $now, $now],
                );
                $cell = GeoCell::query()->findOrFail((int) $row->id);
            } else {
                $cell = GeoCell::query()->create([
                    'governorate_id' => $data['governorate_id'],
                    'code' => strtoupper($data['code']),
                    'name_ar' => $data['name_ar'],
                    'name_en' => $data['name_en'] ?? null,
                    'boundary_json' => $geoJson,
                    'is_active' => true,
                ]);
            }
            $this->regions->refreshPropertyCellAssignments();
            $this->audit->record($actor, 'regions.cell_created', $cell, ['code' => $cell->code, 'governorate_id' => $cell->governorate_id], $request, $actor->id);
            return $cell;
            });
        } catch (QueryException $error) {
            $this->rethrowSpatialValidation($error);
        }

        $cell->load(['governorate'])->loadCount(['properties']);
        return response()->json(['data' => $this->cellData($cell, true)], 201);
    }

    public function updateCell(Request $request, GeoCell $cell): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $data = $request->validate($this->cellRules(true, $cell));
        $geoJson = isset($data['points']) ? $this->regions->polygonGeoJson($data['points']) : null;

        try {
            DB::transaction(function () use ($data, $geoJson, $cell, $actor, $request): void {
            $fields = [];
            foreach (['governorate_id', 'code', 'name_ar', 'name_en', 'is_active'] as $field) {
                if (array_key_exists($field, $data)) {
                    $fields[$field] = $field === 'code' ? strtoupper((string) $data[$field]) : $data[$field];
                }
            }
            if ($fields) {
                $cell->fill($fields)->save();
            }
            if ($geoJson !== null) {
                $cell->forceFill(['boundary_json' => $geoJson])->save();
                if (DB::connection()->getDriverName() === 'pgsql') {
                    $json = json_encode($geoJson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
                    DB::update('UPDATE geo_cells SET boundary=ST_GeomFromGeoJSON(?), updated_at=? WHERE id=?', [$json, now(), $cell->id]);
                }
            }
            $this->regions->refreshPropertyCellAssignments();
            $this->audit->record($actor, 'regions.cell_updated', $cell, ['fields' => array_keys($data)], $request, $actor->id);
            });
        } catch (QueryException $error) {
            $this->rethrowSpatialValidation($error);
        }

        $cell->refresh()->load(['governorate'])->loadCount(['properties']);
        return response()->json(['data' => $this->cellData($cell, true)]);
    }

    private function lookupNominatim(float $latitude, float $longitude): array
    {
        try {
            $response = Http::acceptJson()
                ->withHeaders([
                    'Accept-Language' => 'ar',
                    'User-Agent' => 'RealEstate-UAT/1.5 map-location-picker',
                ])
                ->connectTimeout(4)
                ->timeout(8)
                ->get('https://nominatim.openstreetmap.org/reverse', [
                    'format' => 'jsonv2',
                    'lat' => $latitude,
                    'lon' => $longitude,
                    'zoom' => 18,
                    'addressdetails' => 1,
                    'namedetails' => 1,
                    'accept-language' => 'ar',
                ]);
            if (! $response->successful()) {
                return ['ok' => false, 'status' => 'http_'.$response->status()];
            }
            return [
                'ok' => true,
                'status' => 'ok',
                'address' => is_array($response->json('address')) ? $response->json('address') : [],
                'display_name' => $this->cleanAddressText($response->json('display_name')),
            ];
        } catch (\Throwable $error) {
            return ['ok' => false, 'status' => 'exception:'.class_basename($error)];
        }
    }

    private function lookupPhoton(float $latitude, float $longitude): array
    {
        try {
            $response = Http::acceptJson()
                ->withHeaders([
                    'User-Agent' => 'RealEstate-UAT/1.8 map-location-picker',
                ])
                ->connectTimeout(4)
                ->timeout(8)
                ->get('https://photon.komoot.io/reverse', [
                    'lat' => $latitude,
                    'lon' => $longitude,
                    'limit' => 5,
                    'radius' => 10,
                ]);
            if (! $response->successful()) {
                return ['ok' => false, 'status' => 'http_'.$response->status(), 'features' => []];
            }
            $features = $response->json('features');
            return [
                'ok' => true,
                'status' => 'ok',
                'features' => is_array($features) ? $features : [],
            ];
        } catch (\Throwable $error) {
            return ['ok' => false, 'status' => 'exception:'.class_basename($error), 'features' => []];
        }
    }

    private function firstPhotonText(array $photon, array $keys): ?string
    {
        $features = is_array($photon['features'] ?? null) ? $photon['features'] : [];
        foreach ($features as $feature) {
            $properties = is_array($feature['properties'] ?? null) ? $feature['properties'] : [];
            $value = $this->firstAddressText($properties, $keys);
            if ($value !== null) {
                return $value;
            }
        }
        return null;
    }

    private function firstPhotonStreet(array $photon): ?string
    {
        $features = is_array($photon['features'] ?? null) ? $photon['features'] : [];
        foreach ($features as $feature) {
            $properties = is_array($feature['properties'] ?? null) ? $feature['properties'] : [];
            $street = $this->cleanAddressText($properties['street'] ?? null);
            if ($street !== null) {
                return $street;
            }
            if (($properties['osm_key'] ?? null) === 'highway') {
                $name = $this->cleanAddressText($properties['name'] ?? null);
                if ($name !== null) {
                    return $name;
                }
            }
        }
        return null;
    }

    private function firstAddressText(array $address, array $keys): ?string
    {
        foreach ($keys as $key) {
            $value = $this->cleanAddressText($address[$key] ?? null);
            if ($value !== null) {
                return $value;
            }
        }
        return null;
    }

    private function cleanAddressText(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }
        $value = trim($value);
        return $value === '' ? null : $value;
    }

    private function rethrowSpatialValidation(QueryException $error): never
    {
        $message = strtolower($error->getMessage());
        if (str_contains($message, 'geographic cells may touch borders') || str_contains($message, 'geo_cells_boundary_valid')) {
            throw ValidationException::withMessages([
                'points' => ['Cell boundary is invalid or overlaps the interior of another cell. Shared borders are allowed.'],
            ]);
        }
        throw $error;
    }

    private function cellRules(bool $partial, ?GeoCell $cell = null): array
    {
        $required = $partial ? ['sometimes'] : ['required'];
        return [
            'governorate_id' => array_merge($required, ['integer', 'exists:governorates,id']),
            'code' => array_merge($required, ['string', 'max:60', 'regex:/^[A-Za-z0-9_-]+$/', Rule::unique('geo_cells', 'code')->ignore($cell?->id)]),
            'name_ar' => array_merge($required, ['string', 'max:120']),
            'name_en' => ['nullable', 'string', 'max:120'],
            'is_active' => ['sometimes', 'boolean'],
            'points' => array_merge($required, ['array', 'min:3', 'max:100']),
            'points.*.latitude' => ['required_with:points', 'numeric', 'between:-90,90'],
            'points.*.longitude' => ['required_with:points', 'numeric', 'between:-180,180'],
        ];
    }

    private function cellData(GeoCell $cell, bool $admin): array
    {
        return [
            'id' => $cell->id,
            'governorate' => $cell->governorate ? [
                'id' => $cell->governorate->id,
                'code' => $cell->governorate->code,
                'name_ar' => $cell->governorate->name_ar,
            ] : null,
            'code' => $cell->code,
            'name_ar' => $cell->name_ar,
            'name_en' => $cell->name_en,
            'is_active' => $cell->is_active,
            'boundary' => $cell->boundary_json,
            'is_reserved' => false,
            'properties_count' => (int)($cell->properties_count ?? 0),
            'published_properties_count' => (int)($cell->published_properties_count ?? 0),
        ];
    }
}

