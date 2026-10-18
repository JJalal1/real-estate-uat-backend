<?php

namespace App\Services;

/** Natural Arabic copy assembled only from reviewed, typed listing facts. */
class ListingDescriptionComposer
{
    public function compose(array $facts, bool $invitation = false): array
    {
        $type = $facts['type'] ?? null;
        $purpose = $facts['purpose'] ?? null;
        $facts=app(DynamicPropertySchema::class)->facts($facts);

        $used = [];
        $read = function (string $key) use ($facts, &$used) {
            $value = $facts[$key] ?? null;
            if ($value !== null && $value !== '') $used[] = $key;
            return $value;
        };
        $noun = ListingAiService::TYPES[$type] ?? null;
        $lead = $noun ?? '';
        if ($noun !== null) $used[] = 'type';
        if (in_array($purpose, ['sale', 'rent'], true)) {
            $used[] = 'purpose';
            $lead = ($lead ?: 'عقار').($purpose === 'rent' ? ' للإيجار' : ' للبيع');
            if ($invitation && $noun !== null) $lead = ($purpose === 'rent' ? 'فرصة لاستئجار ' : 'فرصة لشراء ').$noun;
        }
        // Structured location components take precedence over a redundant address.
        $places = [];
        foreach (['district' => 'منطقة ', 'governorate' => 'محافظة ', 'street' => 'شارع '] as $key => $prefix) {
            $value = trim((string) ($facts[$key] ?? ''));
            if ($value === '' || in_array($value, array_column($places, 0), true)) continue;
            $used[] = $key;
            $places[] = [$value, preg_match('/^(منطقة|محافظة|شارع|حي)\s/u', $value) ? $value : $prefix.$value];
        }
        $place = implode('، ', array_column($places, 1));
        if ($place === '') $place = trim((string) $read('address'));
        if ($place !== '') $lead = ($lead ?: 'عقار').' في '.$place;
        if ($lead === '') $lead = trim((string) $read('title'));

        $layout = [];
        $floor = trim((string) ($facts['floor_number'] ?? ''));
        if ($floor !== '') {
            $read('floor_number');
            $ordinals = ['0' => 'الأرضي', '1' => 'الأول', '2' => 'الثاني', '3' => 'الثالث', '4' => 'الرابع',
                '5' => 'الخامس', '6' => 'السادس', '7' => 'السابع', '8' => 'الثامن', '9' => 'التاسع', '10' => 'العاشر'];
            $floor=app(DynamicPropertySchema::class)->normalizeFloor($floor);
            $floor = $ordinals[$floor] ?? $floor;
            $layout[] = $type === 'apartment' ? 'تقع في الدور '.$floor : 'يقع في الدور '.$floor;
        }
        $rooms = [];
        if (($facts['bedrooms'] ?? 0) > 0) {
            $count = (int) $read('bedrooms');
            $rooms[] = match ($count) { 1 => 'غرفة نوم واحدة', 2 => 'غرفتي نوم', default => $count.' غرف نوم' };
        }
        if (($facts['bathrooms'] ?? 0) > 0) {
            $count = (int) $read('bathrooms');
            $rooms[] = match ($count) { 1 => 'حمامًا واحدًا', 2 => 'حمامين', default => $count.' حمامات' };
        }
        if ($rooms !== []) $layout[] = (in_array($type, ['house', 'office', 'shop'], true) ? 'يضم ' : 'تضم ').implode(' و', $rooms);
        if (($facts['area_value'] ?? 0) > 0) {
            $area = $read('area_value');
            $unit = ListingAiService::UNITS[$facts['area_unit'] ?? 'sqm'] ?? 'م²';
            if (isset($facts['area_unit'])) $used[] = 'area_unit';
            $layout[] = (in_array($type, ['house', 'office', 'shop'], true) ? 'تبلغ مساحته ' : 'تبلغ مساحتها ').$this->number($area).' '.$unit;
        }
        if (($facts['unit_occupies_entire_floor'] ?? false) === true) {
            $read('unit_occupies_entire_floor');
            $layout[] = 'تشغل الوحدة الدور كاملًا';
        }

        $amenities = [];
        if (isset($facts['has_parking'])) $amenities[] = $read('has_parking') ? 'يتوفر موقف للسيارة' : 'لا يوجد موقف للسيارة';
        if (isset($facts['has_elevator'])) $amenities[] = $read('has_elevator') ? 'يتوفر مصعد في المبنى' : 'لا يوجد مصعد في المبنى';
        if (isset(ListingAiService::FACADES[$facts['building_facade'] ?? ''])) {
            $read('building_facade');
            $amenities[] = ($type === 'land' ? 'واجهة الأرض ' : 'واجهة المبنى ').ListingAiService::FACADES[$facts['building_facade']];
        }
        $price = '';
        $moneyKey = $purpose === 'rent' ? 'monthly_rent' : 'price';
        if (($facts[$moneyKey] ?? 0) > 0) {
            $value = $read($moneyKey);
            // Missing currency is left unstated rather than assumed in ad copy.
            $currency = isset($facts['currency']) ? ' '.(['YER'=>'ريال', 'USD'=>'دولار أمريكي', 'SAR'=>'ريال سعودي'][$read('currency')] ?? $facts['currency']) : '';
            $price = ($purpose === 'rent' ? 'الإيجار الشهري ' : 'السعر ').$this->number($value).$currency;
        }
        $requirements = [];
        if (($facts['rental_conditions'] ?? []) !== []) {
            $read('rental_conditions');
            $requirements = app(RentalConditionService::class)->sentences($facts['rental_conditions']);
        }
        $fee = '';
        if (($facts['sai_amount_type'] ?? '') === 'percentage' && isset($facts['broker_sai_rate_percent'])) {
            $read('sai_amount_type');
            $fee = 'السعي بنسبة '.$this->number($read('broker_sai_rate_percent')).'%';
        } elseif (($facts['sai_amount_type'] ?? '') === 'fixed' && isset($facts['fixed_sai_amount'])) {
            $read('sai_amount_type');
            $fee = 'السعي '.$this->number($read('fixed_sai_amount')).(isset($facts['currency']) ? ' '.(['YER'=>'ريال', 'USD'=>'دولار أمريكي', 'SAR'=>'ريال سعودي'][$facts['currency']] ?? $facts['currency']) : '');
        }
        $parts = array_filter([$lead, implode(' و', $layout), implode(' و', $amenities), $price, implode('، ', $requirements), $fee]);
        $text = implode('. ', array_map(fn ($part) => rtrim(trim($part), '.، '), $parts));
        return ['description' => $text === '' ? '' : $text.'.', 'fact_keys' => array_values(array_unique($used)), 'requires_review' => true];
    }

    private function number(mixed $value): string
    {
        return rtrim(rtrim(number_format((float) $value, 2, '.', ''), '0'), '.');
    }
}
