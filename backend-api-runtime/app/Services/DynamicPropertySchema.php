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
            $facts['area_m2'] = (int) round($facts['area_value']);
            $facts['area_unit'] = 'sqm';
        }
        foreach ($this->definition()['fields'] as $key => $_) {
            if ($this->applies($key, $facts)) continue;
            foreach (array_merge([$key], $this->definition()['fields'][$key]['aliases'] ?? []) as $alias) {
                if ($clearHidden) $facts[$alias] = $alias === 'rental_conditions' ? [] : null;
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
}
