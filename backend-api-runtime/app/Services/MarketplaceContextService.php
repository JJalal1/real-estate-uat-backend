<?php

namespace App\Services;

use App\Models\Governorate;
use Illuminate\Validation\ValidationException;

class MarketplaceContextService
{
    public function __construct(private readonly YemenGovernorateCatalog $catalog) {}

    public function resolve(array $input): array
    {
        if (isset($input['latitude'], $input['longitude'])) {
            $result = $this->catalog->locate((float) $input['latitude'], (float) $input['longitude'], isset($input['accuracy_m']) ? (float) $input['accuracy_m'] : null);
            $row = collect($this->locations())->firstWhere('governorate_code', $result['code']);
            return ['governorate' => $row['governorate'] ?? null, 'governorate_code' => $row['governorate_code'] ?? null,
                'label' => $row['label'] ?? 'اختر محافظتك', 'source' => 'device',
                'location_status' => $row ? $result['status'] : 'outside_reference', 'needs_confirmation' => ! $row || $result['needs_confirmation']];
        }
        if (! empty($input['governorate_code']) || ! empty($input['governorate'])) {
            $rows = collect($this->locations());
            $row = ! empty($input['governorate_code']) ? $rows->firstWhere('governorate_code', $input['governorate_code']) : $rows->firstWhere('governorate', $input['governorate']);
            if (! $row) throw ValidationException::withMessages(['governorate' => ['اختر محافظة متاحة.']]);
            return array_merge($row, ['source' => 'manual', 'needs_confirmation' => false]);
        }
        // Disclosed initial browsing context, never a fabricated GPS result.
        return ['governorate' => 'أمانة العاصمة', 'governorate_code' => 'AMANAT_AL_ASIMAH', 'label' => 'أمانة العاصمة', 'source' => 'default', 'needs_confirmation' => false];
    }

    public function locations(): array
    {
        $active = Governorate::query()->where('is_active', true)->pluck('name_ar', 'code');
        $rows = [];
        foreach ($this->catalog->features() as $feature) {
            $p = $feature['properties'];
            if (! isset($active[$p['code']])) continue;
            $rows[] = ['governorate' => $active[$p['code']], 'governorate_code' => $p['code'], 'label' => $active[$p['code']],
                'latitude' => $p['latitude'], 'longitude' => $p['longitude']];
        }
        return $rows;
    }
}
