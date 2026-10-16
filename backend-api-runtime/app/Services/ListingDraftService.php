<?php

namespace App\Services;

use Illuminate\Http\Exceptions\HttpResponseException;

/** Prepares proposals only. Property writes stay in the normal listing workflow. */
class ListingDraftService
{
    public function __construct(private readonly ListingAiService $listing) {}

    public function prepare(string $message, array $current): array
    {
        $source = 'ai';
        $notice = 'راجع التفاصيل والنص قبل تطبيقها على مسودتك.';
        try {
            $fields = (array) $this->listing->extract($message, $current)['fields'];
        } catch (HttpResponseException $error) {
            if (! in_array($error->getResponse()->getStatusCode(), [429, 503], true)) throw $error;
            $fields = $this->literalFields($message);
            $source = 'text';
            $notice = 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.';
        }
        // The mobile editor is YER-only. Never relabel a foreign amount.
        $foreign = isset($fields['currency']) && $fields['currency'] !== 'YER';
        if ($foreign) {
            unset($fields['price'], $fields['monthly_rent'], $fields['currency']);
            $notice .= ' المبلغ بعملة أخرى لم يُنقل إلى حقل الريال اليمني.';
        }
        // Titles/descriptions are composed from accepted facts, not free model
        // claims. Legacy whole-floor scope is not created by this assistant.
        unset($fields['title'], $fields['unit_occupies_entire_floor'], $fields['address']);
        $fields = array_filter($fields, fn ($value) => $value !== null && $value !== '');
        $facts = array_merge($current, $fields);
        $fields = $this->relevant($fields, $facts);
        $facts = $this->relevant(array_merge($current, $fields), $facts);
        return ['fields' => (object) $fields, 'copy' => $this->listing->draftCopy($facts),
            'source' => $source, 'message' => $notice, 'requires_review' => true];
    }

    public function copy(array $facts): array
    {
        $facts = $this->relevant($facts, $facts);
        return ['fields' => (object) [], 'copy' => $this->listing->draftCopy($facts),
            'source' => 'facts', 'requires_review' => true,
            'message' => 'العنوان والوصف من المعلومات التي حددتها فقط. راجعهما قبل الاستخدام.'];
    }

    private function relevant(array $fields, array $facts): array
    {
        $type = $facts['type'] ?? null;
        $purpose = $facts['purpose'] ?? null;
        if ($type && ! in_array($type, ['apartment', 'office', 'shop'], true)) unset($fields['floor_number'], $fields['unit_number']);
        if ($type && ! in_array($type, ['apartment', 'house', 'villa'], true)) unset($fields['bedrooms'], $fields['bathrooms']);
        if ($type && ! in_array($type, ['apartment', 'building', 'office'], true)) unset($fields['has_elevator']);
        if ($type === 'apartment' && $purpose === 'rent') unset($fields['area_value'], $fields['area_unit'], $fields['has_elevator']);
        if ($purpose === 'rent') unset($fields['price']);
        if ($purpose === 'sale') unset($fields['monthly_rent']);
        return $fields;
    }

    /** Conservative offline-provider fallback: ambiguous or unlabelled facts stay empty. */
    private function literalFields(string $message): array
    {
        $text = strtr($message, array_combine(
            preg_split('//u', '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', -1, PREG_SPLIT_NO_EMPTY),
            str_split('01234567890123456789'),
        ));
        $text = strtr($text, ['أ'=>'ا', 'إ'=>'ا', 'آ'=>'ا', 'ة'=>'ه', 'ى'=>'ي', '٫'=>'.', '٬'=>'']);
        $text = preg_replace('/(?<=\d),(?=\d{3}(?:\D|$))/u', '', $text);
        $fields = [];
        $types = ['apartment'=>'شقه', 'house'=>'(?:منزل|بيت)', 'villa'=>'فيلا', 'building'=>'عماره',
            'land'=>'ارض', 'farm'=>'مزرعه', 'shop'=>'محل', 'office'=>'مكتب'];
        $found = [];
        foreach ($types as $key => $pattern) {
            if ($this->positiveMention($pattern, $text)) $found[] = $key;
        }
        if (count($found) === 1) $fields['type'] = $found[0];
        $sale = $this->positiveMention('(?:للبيع|بيع)', $text);
        $rent = $this->positiveMention('(?:للايجار|ايجار|للتاجير|للاجار)', $text);
        if ($sale xor $rent) $fields['purpose'] = $rent ? 'rent' : 'sale';
        $foundPlaces = [];
        foreach (['صنعاء', 'عدن', 'تعز', 'الحديده', 'اب', 'ذمار', 'مارب', 'حضرموت'] as $place) {
            if (preg_match('/(?:في|محافظه)\s+'.preg_quote($place, '/').'(?!\pL)/u', $text)) $foundPlaces[] = $place;
        }
        if (count($foundPlaces ?? []) === 1) {
            $fields['governorate'] = strtr($foundPlaces[0], ['الحديده'=>'الحديدة', 'اب'=>'إب', 'مارب'=>'مأرب']);
        }
        foreach (['district'=>'الحي', 'street'=>'الشارع'] as $key => $label) {
            if (preg_match_all('/'.$label.'\s*[:=]\s*([^\n،,؛.]{2,100})/u', $message, $matches) === 1) $fields[$key] = trim($matches[1][0]);
        }
        $number = '(\d+(?:\.\d+)?)';
        foreach (['bedrooms'=>'غرف(?:ه)?\s*نوم', 'bathrooms'=>'(?:حمامات|حمام|دورات?\s*مياه|دوره\s*مياه)'] as $key => $unit) {
            $value = $this->singleNumber('/(?<![-\d.])'.$number.'\s*'.$unit.'/u', $text);
            if ($value !== null && $value >= 1 && $value <= 50 && floor($value) === $value) $fields[$key] = (int) $value;
        }
        if (preg_match_all('/(?:الدور|الطابق)\s*(\d+|الاول|الثاني|الثالث|الرابع|الخامس|السادس|السابع|الثامن|التاسع|العاشر|الارضي)(?!\pL|\d)/u', $text, $matches) === 1) {
            $fields['floor_number'] = ['الاول'=>'1', 'الثاني'=>'2', 'الثالث'=>'3', 'الرابع'=>'4', 'الخامس'=>'5',
                'السادس'=>'6', 'السابع'=>'7', 'الثامن'=>'8', 'التاسع'=>'9', 'العاشر'=>'10', 'الارضي'=>'أرضي'][$matches[1][0]] ?? $matches[1][0];
        }
        foreach (['has_parking'=>'موقف', 'has_elevator'=>'مصعد'] as $key => $word) {
            $no = preg_match('/(?:بدون|لا\s*يوجد)\s*'.$word.'/u', $text);
            $yes = $this->positiveMention('(?:يوجد|مع)\s*'.$word, $text);
            if ($no && ! $yes) $fields[$key] = false;
            elseif ($yes && ! $no) $fields[$key] = true;
        }
        foreach (['price'=>'(?:سعر البيع|السعر)', 'monthly_rent'=>'(?:الايجار الشهري|الايجار|الاجار)'] as $key => $label) {
            $pattern = '/'.$label.'\s*[:=]?\s*'.$number.'\s*(الف|مليون)?(?:\s*(ريال|دولار|سعودي|يمني))?/u';
            if (preg_match_all($pattern, $text, $matches, PREG_SET_ORDER) !== 1) continue;
            $match = $matches[0];
            // "للإيجار 3 غرف" does not identify a monthly amount.
            if ($key === 'monthly_rent' && empty($match[2]) && empty($match[3]) && ! str_contains($match[0], 'الشهري') && ! str_contains($match[0], ':') && ! str_contains($match[0], '=')) continue;
            $value = (float) $match[1] * match ($match[2] ?? '') { 'الف'=>1000, 'مليون'=>1000000, default=>1 };
            if ($value > 0 && $value <= 1000000000000) {
                $fields[$key] = $value;
                $fields['currency'] = str_contains($text, 'دولار') ? 'USD' : (str_contains($text, 'سعودي') ? 'SAR' : 'YER');
            }
        }
        $area = $this->singleNumber('/المساحه\s*[:=]?\s*'.$number.'\s*(?:متر مربع|متر|م²|م2)(?!\pL|\d)/u', $text);
        if ($area !== null && $area > 0 && $area <= 1000000000000) { $fields['area_value'] = $area; $fields['area_unit'] = 'sqm'; }
        return $this->listing->facts($fields);
    }

    private function singleNumber(string $pattern, string $text): ?float
    {
        if (preg_match_all($pattern, $text, $matches) !== 1) return null;
        return (float) $matches[1][0];
    }

    private function positiveMention(string $pattern, string $text): bool
    {
        preg_match_all('/(?<!\pL)'.$pattern.'(?!\pL)/u', $text, $matches, PREG_OFFSET_CAPTURE);
        foreach ($matches[0] as $match) {
            $prefix = substr($text, 0, $match[1]);
            if (! preg_match('/(?:ليس(?:ت)?|غير|بدون|مو|مش|لا)\s*$/u', $prefix)) return true;
        }
        return false;
    }
}
