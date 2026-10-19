<?php

namespace App\Services;

use App\Models\Governorate;

/** Completes only unambiguous, explicitly labelled facts; never guesses missing data. */
class ExplicitListingFacts
{
    public function __construct(private readonly ArabicListingNumber $numbers) {}

    public function extract(string $message): array
    {
        $text = ArabicListingNumber::normalize($message);
        $fields = [];
        $types = ['apartment'=>'شقه', 'house'=>'(?:منزل|بيت)', 'villa'=>'فيلا', 'building'=>'عماره',
            'land'=>'ارض', 'farm'=>'مزرعه', 'shop'=>'محل', 'office'=>'مكتب'];
        $found = [];
        foreach ($types as $key => $pattern) if ($this->positive($pattern, $text)) $found[] = $key;
        if (count($found) === 1) $fields['type'] = $found[0];
        $sale = $this->positive('(?:للبيع|بيع)', $text);
        $rent = $this->positive('(?:للايجار|ايجار|للتاجير|للاجار)', $text);
        if ($sale xor $rent) $fields['purpose'] = $rent ? 'rent' : 'sale';

        $places = [];
        foreach (Governorate::query()->where('is_active', true)->pluck('name_ar') as $place) {
            $normalized = preg_quote(ArabicListingNumber::normalize($place), '/');
            if ($this->positive('(?:في|محافظه|مدينه)\s+'.$normalized, $text)) $places[] = $place;
        }
        if (count($places) === 1) $fields['governorate'] = $places[0];

        $number = $this->numbers->pattern();
        foreach (['district'=>'(?:حي|الحي|منطقه)', 'street'=>'(?:شارع|الشارع)'] as $key => $label) {
            $stop = '(?=$|[\n،,؛.]|\s+(?:'.$number.'\s+(?:غرف|حمام)|يوجد|ويوجد|بدون|مطلوب|السعر|الايجار|بمساحه|المساحه|نسبه|ونسبه))';
            if (preg_match_all('/(?<!\pL)'.$label.'\s*[:=]?\s*([\pL\d][\pL\d ]{0,99}?)'.$stop.'/u', $text, $matches, PREG_SET_ORDER) === 1 && !$this->negated($text, $matches[0][0])) {
                $value = trim($matches[0][1]);
                if (!preg_match('/(?<!\pL)(?:او|ام)(?!\pL)/u', $value)) $fields[$key] = $this->originalPhrase($value, $message);
            }
        }
        foreach (['bedrooms'=>'(?:غرف(?:ه)?(?:\s*نوم)?)', 'bathrooms'=>'(?:حمامات|حمام|دورات?\s*مياه|دوره\s*مياه)'] as $key => $unit) {
            $value = $this->one('/(?<![-\pL\d.])(?:و\s*)?('.$number.')\s*'.$unit.'(?!\pL)/u', $text);
            if ($value !== null && $value >= 1 && $value <= 50 && floor($value) === $value) $fields[$key] = (int) $value;
        }
        // Dual nouns explicitly carry the count even without a separate number.
        foreach (['bedrooms'=>'غرفتين|غرفتان', 'bathrooms'=>'حمامين|حمامان'] as $key => $noun) {
            if (!isset($fields[$key]) && $this->positive('(?:'.$noun.')', $text)) $fields[$key] = 2;
        }
        if (preg_match_all('/(?<!\pL)(?:ال)?(?:دور|طابق)\s*(\d+|(?:ال)?(?:اول|ثاني|ثالث|رابع|خامس|سادس|سابع|ثامن|تاسع|عاشر|ارضي))(?!\pL|\d)/u', $text, $m) === 1
            && !$this->negated($text, $m[0][0]) && !$this->alternativeAfter($text, $m[0][0])) {
            $floor = $m[1][0];
            if (!ctype_digit($floor) && !str_starts_with($floor, 'ال')) $floor = 'ال'.$floor;
            $fields['floor_number'] = app(DynamicPropertySchema::class)->normalizeFloor($floor);
        }
        foreach (['has_parking'=>'موقف(?:\s*سيارات)?', 'has_elevator'=>'مصعد'] as $key => $word) {
            $no = preg_match('/(?:بدون|لا\s*يوجد|لا\s*يتوفر|ما\s*في)\s*'.$word.'/u', $text);
            $yes = $this->positive('(?:يوجد|يتوفر|مع)\s*'.$word, $text);
            if ($no && !$yes) $fields[$key] = false;
            elseif ($yes && !$no) $fields[$key] = true;
        }
        foreach (['price'=>'(?:سعر البيع|السعر)', 'monthly_rent'=>'(?:الايجار الشهري|الايجار|الاجار)'] as $key => $label) {
            if (preg_match_all('/(?<!\pL)'.$label.'\s*[:=]?\s*('.$number.')(?:\s*(ريال(?:\s*(?:يمني|سعودي))?|دولار|سعودي))?(?!\pL|\d)/u', $text, $m, PREG_SET_ORDER) !== 1) continue;
            $match = $m[0];
            if ($this->negated($text, $match[0]) || $this->alternativeAfter($text, $match[0])) continue;
            $value = $this->numbers->parse($match[1]);
            if ($value === null) continue;
            if ($key === 'monthly_rent' && empty($match[2]) && !preg_match('/الف|مليون|الشهري|[:=]/u', $match[0])) continue;
            $target = $key === 'price' && ($fields['purpose'] ?? '') === 'rent' ? 'monthly_rent' : $key;
            if (isset($fields[$target]) && $fields[$target] !== $value) { unset($fields[$target]); continue; }
            $fields[$target] = $value;
            $fields['currency'] = str_contains($text, 'دولار') ? 'USD' : (str_contains($text, 'سعودي') ? 'SAR' : 'YER');
        }
        // A single requested currency amount in an explicitly rental brief is
        // the quoted rent. Never use an unlabelled number, advance/deposit,
        // alternative amount or a brief whose sale/rent purpose is unclear.
        if (($fields['purpose'] ?? '') === 'rent' && !isset($fields['monthly_rent'])
            && preg_match_all('/(?<!\pL)(?:المطلوب|مطلوب)\s*[:=]?\s*('.$number.')\s*(ريال(?:\s*(?:يمني|سعودي))?|دولار|سعودي)(?!\pL)/u', $text, $m, PREG_SET_ORDER) === 1) {
            $match = $m[0];
            $tail = mb_substr($text, mb_strpos($text, $match[0]) + mb_strlen($match[0]));
            $prefix = mb_substr($text, 0, mb_strpos($text, $match[0]));
            if (!$this->negated($text, $match[0]) && !$this->alternativeAfter($text, $match[0])
                && !preg_match('/(?:مقدم|تامين|ضمان|سعي|عموله)\s*$/u', $prefix)
                && !preg_match('/^\s*(?:مقدم|تامين|ضمان|سعي|عموله|لـ?\s*'.$number.'\s*(?:اشهر|شهور|شهر))(?!\pL)/u', $tail)) {
                $amount = $this->numbers->parse($match[1]);
                if ($amount !== null) {
                    $fields['monthly_rent'] = $amount;
                    $fields['currency'] = str_contains($text, 'دولار') ? 'USD' : (str_contains($text, 'سعودي') ? 'SAR' : 'YER');
                }
            }
        }
        $area = $this->one('/المساحه\s*[:=]?\s*('.$number.')\s*(?:متر مربع|متر|م²|م2)(?!\pL|\d)/u', $text);
        if ($area !== null) { $fields['area_value'] = $area; $fields['area_unit'] = 'sqm'; }

        $conditions = [];
        foreach (['advance'=>'(?:ايجار\s*)?مقدم', 'duration'=>'(?:مده(?:\s*(?:العقد|الايجار))?)'] as $kind => $label) {
            $months = $this->one('/(?<!\pL)'.$label.'\s*[:=]?\s*('.$number.')\s*(?:اشهر|شهور|شهر)(?!\pL)/u', $text);
            if ($kind === 'advance') {
                $suffixMonths = $this->one('/(?<!\pL)(?:ايجار\s*)?('.$number.')\s*(?:اشهر|شهور|شهر)\s*مقدم(?!\pL)/u', $text);
                $months = $months !== null && $suffixMonths !== null && $months !== $suffixMonths ? null : ($months ?? $suffixMonths);
            }
            if ($months !== null && $months >= 1 && $months <= 24 && floor($months) === $months) $conditions[] = ['kind'=>$kind, 'months'=>(int)$months];
        }
        if ($this->positive('(?:ضمانه\s*تجاريه|ضامن\s*تجاري|كفيل)', $text)) $conditions[] = ['kind'=>'guarantor'];
        if ($conditions !== []) $fields['rental_conditions'] = $conditions;
        $rate = $this->one('/(?<!\pL)(?:و)?(?:نسبه\s*)?(?:السعي|العموله)\s*[:=]?\s*('.$number.')\s*(?:%|بالمئه)(?!\pL)/u', $text);
        if ($rate !== null && $rate <= 100) { $fields['sai_amount_type']='percentage'; $fields['broker_sai_rate_percent']=$rate; }
        $fee = $this->one('/(?<!\pL)(?:مبلغ\s*)?(?:السعي|العموله)\s*[:=]?\s*('.$number.')\s*ريال(?!\pL)/u', $text);
        if ($fee !== null && $rate === null) { $fields['sai_amount_type']='fixed'; $fields['fixed_sai_amount']=$fee; $fields['currency'] ??= 'YER'; }
        return $fields;
    }

    private function one(string $pattern, string $text): ?float
    {
        if (preg_match_all($pattern, $text, $matches, PREG_SET_ORDER) !== 1 || $this->negated($text, $matches[0][0]) || $this->alternativeAfter($text, $matches[0][0])) return null;
        return $this->numbers->parse($matches[0][1]);
    }

    private function originalPhrase(string $value, string $message): string
    {
        preg_match_all('/[\pL\pM\d]+/u', $message, $matches);
        $count = count(explode(' ', $value));
        for ($i = 0; $i + $count <= count($matches[0]); $i++) {
            $candidate = implode(' ', array_slice($matches[0], $i, $count));
            if (ArabicListingNumber::normalize($candidate) === $value) return $candidate;
        }
        return $value;
    }

    private function negated(string $text, string $match): bool
    {
        $offset = mb_strpos($text, $match);
        return preg_match('/(?:ليس(?:ت)?|غير|بدون|مو|مش|لا|او|ام)\s*$/u', mb_substr($text, 0, $offset));
    }

    private function alternativeAfter(string $text, string $match): bool
    {
        $tail = mb_substr($text, mb_strpos($text, $match) + mb_strlen($match));
        return preg_match('/^\s*(?:او|ام|الي|حتي|[-–])(?!\pL)/u', $tail);
    }

    private function positive(string $pattern, string $text): bool
    {
        preg_match_all('/(?<!\pL)(?:و)?(?:'.$pattern.')(?!\pL)/u', $text, $matches, PREG_OFFSET_CAPTURE);
        foreach ($matches[0] as $match) {
            $prefix = substr($text, 0, $match[1]);
            if (!preg_match('/(?:ليس(?:ت)?|غير|بدون|مو|مش|لا)\s*$/u', $prefix)) return true;
        }
        return false;
    }
}

