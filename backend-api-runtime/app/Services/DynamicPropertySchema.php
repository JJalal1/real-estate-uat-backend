<?php

namespace App\Services;

/** The JSON definition is shared by listing, AI, discovery and mobile rendering. */
class DynamicPropertySchema
{
    public function definition(): array
    {
        static $definition=null;
        return $definition ??= json_decode(file_get_contents(resource_path('property-schema.json')), true, flags: JSON_THROW_ON_ERROR);
    }

    public function applies(string $key, array $facts): bool
    {
        $field = $this->definition()['fields'][$key] ?? null;
        if ($field === null) foreach ($this->definition()['fields'] as $candidate) { if (in_array($key,$candidate['aliases'] ?? [],true)) { $field=$candidate; break; } }
        if ($field === null) return true;
        if ($field['retired'] ?? false) return false;
        $type = ($facts['type'] ?? null) === 'floor' ? 'apartment' : ($facts['type'] ?? null);
        $purpose = $facts['purpose'] ?? null;
        if ($type !== null && isset($field['types']) && ! in_array($type, $field['types'], true)) return false;
        if ($purpose !== null && isset($field['purposes']) && ! in_array($purpose, $field['purposes'], true)) return false;
        foreach ($field['exclude'] ?? [] as $case) if ($this->matches($case, $facts)) return false;
        return true;
    }

    private function matches(array $case, array $facts): bool
    {
        foreach ($case as $key => $value) {
            $actual = $facts[$key] ?? null;
            if ($key === 'type' && $actual === 'floor') $actual = 'apartment';
            if ($actual !== $value) return false;
        }
        return true;
    }

    public function required(array $facts): array
    {
        $keys = [];
        foreach ($this->definition()['fields'] as $key => $field) {
            if (! $this->applies($key, $facts)) continue;
            if (($field['required_since'] ?? 0) > (int)($facts['listing_input_version'] ?? $facts['editor_version'] ?? 9)) continue;
            if ($field['required'] ?? false) $keys[] = $key;
            else foreach ($field['required_cases'] ?? [] as $case) {
                if ($this->matches($case, $facts)) { $keys[] = $key; break; }
            }
        }
        return $keys;
    }

    public function facts(array $facts, bool $clearHidden = false): array
    {
        if (($facts['type'] ?? '') === 'shop' && isset($facts['area_value'])) {
            $factor = $this->definition()['area_units_to_sqm'][$facts['area_unit'] ?? 'sqm'] ?? 1;
            $facts['area_value'] = round((float) $facts['area_value'] * $factor, 2);
            if (array_key_exists('area_m2',$facts)) $facts['area_m2'] = (int) round($facts['area_value']);
            $facts['area_unit'] = 'sqm';
        }
        foreach ($this->definition()['fields'] as $key => $_) {
            if ($this->applies($key, $facts)) continue;
            foreach (array_merge([$key], $this->definition()['fields'][$key]['aliases'] ?? []) as $alias) {
                if ($clearHidden) $facts[$alias] = match($alias) { 'rental_conditions'=>[], 'unit_occupies_entire_floor'=>false, default=>null };
                else unset($facts[$alias]);
            }
        }
        return $facts;
    }

    public function filters(array $filters): array
    {
        foreach ($this->definition()['fields'] as $key => $field) {
            if ($this->applies($key, $filters)) continue;
            foreach ($field['filters'] ?? [] as $filter) unset($filters[$filter]);
        }
        return $filters;
    }

    public function normalizeFloor(string $value): string
    {
        $value = trim(strtr($value, ['أ'=>'ا', 'إ'=>'ا', '٠'=>'0', '١'=>'1', '٢'=>'2', '٣'=>'3', '٤'=>'4', '٥'=>'5', '٦'=>'6', '٧'=>'7', '٨'=>'8', '٩'=>'9']));
        $value = preg_replace('/^(?:الدور|الطابق)\s*/u', '', $value);
        return ['ارضي'=>'0','الارضي'=>'0','الاول'=>'1','الثاني'=>'2','الثالث'=>'3','الرابع'=>'4','الخامس'=>'5','السادس'=>'6','السابع'=>'7','الثامن'=>'8','التاسع'=>'9','العاشر'=>'10'][$value] ?? $value;
    }

    public function validateStructure(array $facts): array
    {
        if (isset($facts['units_per_floor']) && is_string($facts['units_per_floor'])) {
            $facts['units_per_floor'] = json_decode($facts['units_per_floor'], true);
            if (!is_array($facts['units_per_floor'])) throw \Illuminate\Validation\ValidationException::withMessages(['units_per_floor'=>['أدخل عدد الوحدات لكل دور.']]);
        }
        foreach (['floors_count'=>50,'shop_openings'=>100] as $key=>$max) {
            if (!isset($facts[$key]) || !$this->applies($key,$facts)) continue;
            if (filter_var($facts[$key], FILTER_VALIDATE_INT) === false || (int)$facts[$key] < 1 || (int)$facts[$key] > $max) {
                throw \Illuminate\Validation\ValidationException::withMessages([$key=>['أدخل عددًا صحيحًا ضمن النطاق المسموح.']]);
            }
            $facts[$key]=(int)$facts[$key];
        }
        if (isset($facts['units_per_floor']) && $this->applies('units_per_floor',$facts)) {
            $units=$facts['units_per_floor'];
            if (!is_array($units) || !array_is_list($units) || count($units)>50 || (isset($facts['floors_count']) && count($units)!==(int)$facts['floors_count'])) {
                throw \Illuminate\Validation\ValidationException::withMessages(['units_per_floor'=>['حدد عدد الوحدات في كل دور من أدوار العقار.']]);
            }
            foreach ($units as $unit) if (filter_var($unit,FILTER_VALIDATE_INT)===false || (int)$unit<1 || (int)$unit>100) {
                throw \Illuminate\Validation\ValidationException::withMessages(['units_per_floor'=>['عدد الوحدات في كل دور من 1 إلى 100.']]);
            }
            $facts['units_per_floor']=array_map('intval',$units);
        }
        return $facts;
    }

    /** Validate current editor writes without changing historical read models. */
    public function validateApartmentFloor(array $facts, string $key = 'floor_number'): array
    {
        if (($facts['type'] ?? '') !== 'apartment' || !isset($facts['floor_number']) || trim((string)$facts['floor_number']) === '') return $facts;
        $floor = $this->normalizeFloor((string)$facts['floor_number']);
        if (!in_array($floor, array_column($this->definition()['apartment_floors'], 'value'), true)) {
            throw \Illuminate\Validation\ValidationException::withMessages([$key => ['اختر دورًا من الأرضي إلى السابع.']]);
        }
        $facts['floor_number'] = $floor;
        return $facts;
    }
}
