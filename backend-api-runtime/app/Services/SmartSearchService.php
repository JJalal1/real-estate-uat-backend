<?php

namespace App\Services;

use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class SmartSearchService
{
    public const TYPES = ['apartment', 'house', 'villa', 'building', 'land', 'farm', 'shop', 'office'];
    public const FIELDS = ['type', 'purpose', 'search', 'currency', 'min_price', 'max_price', 'min_area_m2', 'max_area_m2',
        'min_bedrooms', 'min_bathrooms', 'floor_number', 'has_parking', 'has_elevator', 'building_facade', 'unit_occupies_entire_floor'];

    public const CONTEXT_FIELDS = ['governorate', 'advertiser_id', 'spotlight', 'area_polygon', 'latitude', 'longitude', 'radius_km', 'south', 'west', 'north', 'east'];

    public function __construct(private readonly GeminiClient $gemini) {}

    public function validate(array $filters): array
    {
        if (array_diff(array_keys($filters), array_merge(self::FIELDS, self::CONTEXT_FIELDS)) !== []) {
            throw ValidationException::withMessages(['filters' => ['يوجد فلتر غير مدعوم.']]);
        }
        $rules = ['type' => ['nullable', Rule::in(self::TYPES)], 'purpose' => ['nullable', Rule::in(['sale', 'rent'])],
            'search' => ['nullable', 'string', 'max:120'], 'currency' => ['nullable', Rule::in(['YER', 'USD', 'SAR'])],
            'floor_number' => ['nullable', 'string', 'max:32'],
            'building_facade' => ['nullable', Rule::in(['north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest', 'multiple'])]];
        foreach (['min_price', 'max_price', 'min_area_m2', 'max_area_m2'] as $key) $rules[$key] = ['nullable', 'numeric', 'between:0,1000000000000'];
        foreach (['min_bedrooms', 'min_bathrooms'] as $key) $rules[$key] = ['nullable', 'integer', 'between:0,50'];
        foreach (['has_parking', 'has_elevator', 'unit_occupies_entire_floor'] as $key) $rules[$key] = ['nullable', 'boolean'];
        foreach (self::CONTEXT_FIELDS as $key) $rules[$key] = app(PropertyDiscoveryFilterService::class)->rules()[$key];
        $value = Validator::make($filters, $rules)->validate();
        app(PropertyDiscoveryFilterService::class)->validateGeometry($value);
        $value = array_filter($value, fn ($v) => $v !== null && $v !== '');
        foreach (['min_price' => 'max_price', 'min_area_m2' => 'max_area_m2'] as $min => $max) {
            if (isset($value[$min], $value[$max]) && $value[$min] > $value[$max]) {
                throw ValidationException::withMessages(['filters' => ['الحد الأدنى يجب ألا يتجاوز الحد الأعلى.']]);
            }
        }
        foreach (['has_parking', 'has_elevator', 'unit_occupies_entire_floor'] as $key) if (isset($value[$key])) $value[$key] = (bool) $value[$key];
        $value=app(DynamicPropertySchema::class)->filters($value);
        return $value;
    }

    public function update(string $message, array $current): array
    {
        $current = $this->validate($current);
        $schema = ['type' => 'object', 'additionalProperties' => false, 'properties' => [
            'set' => ['type' => 'object', 'additionalProperties' => false, 'properties' => $this->properties()],
            'remove' => ['type' => 'array', 'maxItems' => count(self::FIELDS), 'items' => ['type' => 'string', 'enum' => self::FIELDS]],
        ], 'required' => ['set', 'remove']];
        $patch = $this->gemini->object(
            'Interpret an Arabic Yemen real-estate search follow-up as a PATCH to current_filters. Return only set and remove. '
            .'Set ONLY explicitly requested changes and remove ONLY explicitly withdrawn criteria. Preserve every unmentioned filter. '
            .'Map coordinates, polygon, bounds, governorate, advertiser_id and spotlight in current_filters are read-only source constraints chosen by the user; never change or remove them. The user may remove their chips manually. '
            .'Resolve references against current_filters. Search is the location/address keyword. Do not insert property type or purpose into search. '
            .'Prices mean MONTHLY rent when the effective purpose is rent; they never mean advance payment or commission. '
            .'Numbers such as 50 ألف mean 50000. Rooms map to min_bedrooms. A whole floor is type apartment and unit_occupies_entire_floor true. '
            .'Never invent unavailable fields, listings, results or locations. If the request is unclear or outside property search, return empty set and remove. '
            .'A reset is handled by the app button, not by dropping all filters. Schema names are the only supported filters.',
            ['current_filters' => $current, 'follow_up' => $message, 'property_schema'=>app(DynamicPropertySchema::class)->definition()], $schema,
        );
        try {
            if (array_diff(array_keys($patch), ['set', 'remove']) !== []) $this->gemini->unavailable();
            Validator::make($patch, ['set' => ['present', 'array:'.implode(',', self::FIELDS)],
                'remove' => ['present', 'array', 'max:'.count(self::FIELDS)], 'remove.*' => [Rule::in(self::FIELDS)]])->validate();
            $next = $current;
            foreach ($patch['remove'] as $key) unset($next[$key]);
            foreach ($patch['set'] as $key => $value) {
                if ($value === null) unset($next[$key]); else $next[$key] = $value;
            }
            $next = $this->validate($next);
        } catch (ValidationException) {
            $this->gemini->unavailable();
        }
        return ['filters' => $next, 'suggestions' => $this->suggestions($next),
            'changed' => $current !== $next, 'message' => $current === $next ? 'لم نغيّر شروطك. يمكنك توضيح الطلب أو تعديل الشرائح.' : 'حدّثنا شروط البحث مع الاحتفاظ ببقية اختياراتك.'];
    }

    public function suggestions(array $filters): array
    {
        $type = $filters['type'] ?? null;
        $keys = match ($type) {
            'apartment' => ['min_bedrooms', 'floor_number', 'has_elevator', 'has_parking'],
            'house', 'villa' => ['min_bedrooms', 'min_area_m2', 'has_parking'],
            'land' => ['min_area_m2', 'building_facade', 'max_area_m2', 'search'],
            'farm' => ['min_area_m2', 'max_area_m2', 'search'],
            'shop', 'office' => ['min_area_m2', 'floor_number', 'building_facade'],
            default => ['type', 'purpose', 'search', 'max_price'],
        };
        $allowed=app(DynamicPropertySchema::class)->filters($filters+array_fill_keys($keys,true));
        return array_values(array_filter($keys,fn($key)=>!array_key_exists($key,$filters) && array_key_exists($key,$allowed)));
    }

    private function properties(): array
    {
        $result = ['type' => ['type' => 'string', 'enum' => self::TYPES],
            'purpose' => ['type' => 'string', 'enum' => ['sale', 'rent']],
            'search' => ['type' => 'string', 'maxLength' => 120],
            'currency' => ['type' => 'string', 'enum' => ['YER', 'USD', 'SAR']],
            'floor_number' => ['type' => 'string', 'maxLength' => 32],
            'building_facade' => ['type' => 'string', 'enum' => ['north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest', 'multiple']]];
        foreach (['min_price', 'max_price', 'min_area_m2', 'max_area_m2'] as $key) $result[$key] = ['type' => 'number', 'minimum' => 0, 'maximum' => 1000000000000];
        foreach (['min_bedrooms', 'min_bathrooms'] as $key) $result[$key] = ['type' => 'integer', 'minimum' => 0, 'maximum' => 50];
        foreach (['has_parking', 'has_elevator', 'unit_occupies_entire_floor'] as $key) $result[$key] = ['type' => 'boolean'];
        return $result;
    }
}
