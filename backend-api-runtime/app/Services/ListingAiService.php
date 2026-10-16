<?php

namespace App\Services;

use App\Models\Property;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ListingAiService
{
    public const LABELS = ['title' => 'العنوان', 'type' => 'نوع العقار', 'purpose' => 'الغرض', 'address' => 'الموقع',
        'price' => 'السعر', 'monthly_rent' => 'الإيجار الشهري', 'area_value' => 'المساحة',
        'bedrooms' => 'غرف النوم', 'bathrooms' => 'دورات المياه', 'floor_number' => 'الدور',
        'has_parking' => 'موقف', 'has_elevator' => 'مصعد', 'building_facade' => 'الواجهة',
        'unit_occupies_entire_floor' => 'نطاق الوحدة'];
    public const TYPES = ['apartment' => 'شقة', 'house' => 'منزل', 'villa' => 'فيلا', 'building' => 'عمارة',
        'land' => 'أرض', 'farm' => 'مزرعة', 'shop' => 'محل', 'office' => 'مكتب'];
    public const FACADES = ['north' => 'شمالية', 'south' => 'جنوبية', 'east' => 'شرقية', 'west' => 'غربية',
        'northeast' => 'شمالية شرقية', 'northwest' => 'شمالية غربية', 'southeast' => 'جنوبية شرقية',
        'southwest' => 'جنوبية غربية', 'multiple' => 'متعددة'];
    public const UNITS = ['sqm' => 'م²', 'libna_sanaani' => 'لبنة صنعاني', 'libna_dhamari' => 'لبنة ذماري',
        'qasaba_taizi_ashari' => 'قصبة تعزي عشاري', 'qasaba_taizi_hadawi' => 'قصبة تعزي هدوي', 'qasaba_ibbi' => 'قصبة إبي'];

    public function __construct(private readonly GeminiClient $gemini) {}

    public function rules(): array
    {
        $r = ['title' => ['nullable', 'string', 'max:160'], 'type' => ['nullable', Rule::in(array_keys(self::TYPES))],
            'purpose' => ['nullable', Rule::in(['sale', 'rent'])], 'currency' => ['nullable', Rule::in(['YER', 'USD', 'SAR'])],
            'area_unit' => ['nullable', Rule::in(array_keys(self::UNITS))], 'building_facade' => ['nullable', Rule::in(array_keys(self::FACADES))],
            'tenure_type' => ['nullable', Rule::in(['freehold', 'waqf'])],
            'floor_number' => ['nullable', 'string', 'max:32'], 'unit_number' => ['nullable', 'string', 'max:64']];
        foreach (['address', 'governorate', 'district', 'street'] as $key) $r[$key] = ['nullable', 'string', 'max:240'];
        foreach (['price', 'monthly_rent', 'area_value'] as $key) $r[$key] = ['nullable', 'numeric', 'gt:0', 'max:1000000000000'];
        foreach (['bedrooms', 'bathrooms'] as $key) $r[$key] = ['nullable', 'integer', 'between:1,50'];
        foreach (['has_parking', 'has_elevator', 'unit_occupies_entire_floor'] as $key) $r[$key] = ['nullable', 'boolean'];
        return $r;
    }

    public function facts(array $input): array
    {
        if (array_diff(array_keys($input), array_keys($this->rules())) !== []) {
            throw ValidationException::withMessages(['facts' => ['يقبل المساعد مواصفات الإعلان فقط.']]);
        }
        return Validator::make($input, $this->rules())->validate();
    }

    public function extract(string $message, array $current): array
    {
        $properties = [];
        foreach (array_keys($this->rules()) as $key) $properties[$key] = ['type' => ['string', 'number', 'boolean']];
        $schema = ['type' => 'object', 'additionalProperties' => false, 'properties' => [
            'fields' => ['type' => 'object', 'additionalProperties' => false, 'properties' => $properties]], 'required' => ['fields']];
        $result = $this->gemini->object(
            'Extract ONLY explicitly stated real-estate facts from the Arabic message into existing form fields. '
            .'Use current_facts only for resolving references. Do not repeat unmentioned values. Never invent specifications, identity, ownership, coordinates or approvals. '
            .'Do not add description or financial commission fields. A whole floor is apartment + unit_occupies_entire_floor true. '
            .'price is the sale price; a monthly rental amount belongs in monthly_rent. Local amounts in ريال mean YER unless another currency is explicit. '
            .'Do not infer a floor or apartment number for a whole building, house, villa, land or farm. '
            .'Prefer governorate, district and street components when explicitly named; never invent a missing address component. '
            .'String fields contain text, numeric fields actual JSON numbers, boolean fields actual JSON booleans. Unclear facts are omitted.',
            ['message' => $message, 'current_facts' => (object) $current], $schema,
        );
        try {
            Validator::make($result, ['fields' => ['present', 'array:'.implode(',', array_keys($this->rules()))]])->validate();
            if (array_diff(array_keys($result), ['fields']) !== []) $this->gemini->unavailable();
            $fields = $this->facts($result['fields']);
            $type = $fields['type'] ?? $current['type'] ?? null;
            if ($type && ! in_array($type, ['apartment', 'office', 'shop'], true)) unset($fields['floor_number'], $fields['unit_number']);
            if ($type && ! in_array($type, ['apartment', 'house', 'villa'], true)) unset($fields['bedrooms'], $fields['bathrooms']);
            if ($type !== 'apartment') unset($fields['unit_occupies_entire_floor']);
            if ($type && ! in_array($type, ['apartment', 'building', 'office'], true)) unset($fields['has_elevator']);
            if (($fields['unit_occupies_entire_floor'] ?? $current['unit_occupies_entire_floor'] ?? false) === true) unset($fields['unit_number']);
        } catch (ValidationException) {
            $this->gemini->unavailable();
        }
        return ['fields' => (object) $fields, 'requires_review' => true,
            'message' => 'راجع المواصفات المقترحة قبل استخدامها. لم نحفظ أو ننشر أي إعلان.'];
    }

    public function description(array $facts): array
    {
        $sentences = $this->sentences($facts);
        if ($sentences === []) throw ValidationException::withMessages(['facts' => ['أدخل مواصفات العقار أولًا.']]);
        // Gemini chooses a readable order; every rendered sentence is bound to
        // a verified input fact. Free generated claims never enter the result.
        $result = $this->gemini->object(
            'Arrange the supplied Arabic property facts into a professional, clear listing description. '
            .'Return fact_order with each useful fact key once, beginning with title/type/purpose/address as available. '
            .'Do not produce new text, specifications, assurances or investment promises. Select direct or invitation for the introductory tone.',
            ['verified_facts' => $sentences], ['type' => 'object', 'additionalProperties' => false, 'properties' => [
                'fact_order' => ['type' => 'array', 'minItems' => 1, 'maxItems' => count($sentences), 'items' => ['type' => 'string', 'enum' => array_keys($sentences)]],
                'tone' => ['type' => 'string', 'enum' => ['direct', 'invitation']],
            ], 'required' => ['fact_order', 'tone']],
        );
        try {
            Validator::make($result, ['fact_order' => ['required', 'array', 'min:1', 'max:'.count($sentences)],
                'fact_order.*' => [Rule::in(array_keys($sentences)), 'distinct'], 'tone' => ['required', Rule::in(['direct', 'invitation'])]])->validate();
            if (array_diff(array_keys($result), ['fact_order', 'tone']) !== []) $this->gemini->unavailable();
        } catch (ValidationException) { $this->gemini->unavailable(); }
        $order = array_values(array_unique(array_merge($result['fact_order'], array_keys($sentences))));
        $text = implode('، ', array_map(fn ($key) => $sentences[$key], $order)).'.';
        if ($result['tone'] === 'invitation') $text = 'تعرّف على هذا العقار: '.$text;
        return ['description' => $text, 'requires_review' => true, 'fact_keys' => $order];
    }

    public function question(Property $property, string $question): array
    {
        $facts = array_intersect_key($property->toArray(), array_flip(array_keys($this->rules())));
        $facts['area_value'] = $property->area_value ?? $property->area_m2;
        $facts['area_unit'] = $property->area_unit ?? 'sqm';
        if ($property->type === 'floor') { $facts['type'] = 'apartment'; $facts['unit_occupies_entire_floor'] = true; }
        $sentences = $this->sentences($facts);
        $description = trim((string) $property->description);
        $result = $this->gemini->object(
            'Select the supplied property fact keys that answer the Arabic question. Never answer from world knowledge. '
            .'If a needed fact is absent, return no keys. Optionally extract an EXACT, contiguous quote from listing_description (up to 400 characters) only when it directly answers the question. '
            .'Do not make guesses, calculate fees or payments, give legal advice or claim anything absent from the listing. '
            .'Return keys and quote only. The server will compose the answer from original data.',
            ['question' => $question, 'available_facts' => $sentences, 'listing_description' => mb_substr($description, 0, 5000)],
            ['type' => 'object', 'additionalProperties' => false, 'properties' => [
                'keys' => ['type' => 'array', 'maxItems' => 5, 'items' => ['type' => 'string', 'enum' => array_keys(self::LABELS)]],
                'quote' => ['type' => 'string', 'maxLength' => 400],
            ], 'required' => ['keys', 'quote']],
        );
        try {
            Validator::make($result, ['keys' => ['present', 'array', 'max:5'], 'keys.*' => [Rule::in(array_keys(self::LABELS)), 'distinct'],
                'quote' => ['present', 'string', 'max:400']])->validate();
            if (array_diff(array_keys($result), ['keys', 'quote']) !== []) $this->gemini->unavailable();
        } catch (ValidationException) { $this->gemini->unavailable(); }
        $answer = [];
        foreach ($result['keys'] as $key) if (isset($sentences[$key])) $answer[] = $sentences[$key];
        $quote = trim($result['quote']);
        if ($quote !== '' && mb_strpos($description, $quote) !== false) $answer[] = $quote;
        return ['answer' => $answer ? implode('، ', $answer) : 'هذه المعلومة غير مذكورة في الإعلان. يمكنك سؤال المعلن من المحادثة.',
            'source' => 'listing', 'property_id' => $property->id, 'not_mentioned' => $answer === []];
    }

    /** Copy is composed on the server from the facts the advertiser selected. */
    public function draftCopy(array $facts): array
    {
        $facts = $this->facts($facts);
        $type = $facts['type'] ?? null;
        $purpose = $facts['purpose'] ?? null;
        if ($type !== null && ! in_array($type, ['apartment', 'office', 'shop'], true)) {
            unset($facts['floor_number'], $facts['unit_number']);
        }
        if ($type !== null && ! in_array($type, ['apartment', 'house', 'villa'], true)) {
            unset($facts['bedrooms'], $facts['bathrooms']);
        }
        if ($type === 'apartment' && $purpose === 'rent') {
            unset($facts['area_value'], $facts['area_unit'], $facts['has_elevator']);
        }
        $title = trim((string) ($facts['title'] ?? ''));
        if ($title === '') {
            $title = self::TYPES[$type] ?? 'عقار';
            if (in_array($purpose, ['sale', 'rent'], true)) $title .= $purpose === 'rent' ? ' للإيجار' : ' للبيع';
            $place = trim((string) ($facts['district'] ?? $facts['governorate'] ?? $facts['address'] ?? ''));
            if ($place !== '') $title .= ' في '.$place;
            $title = mb_substr($title, 0, 160);
        }
        // Include the explicitly entered location components without inventing
        // coordinates, a building reference or a unit identity.
        if (empty($facts['address'])) {
            $location = array_filter(array_map(fn ($key) => trim((string) ($facts[$key] ?? '')), ['governorate', 'district', 'street']));
            if ($location !== []) $facts['address'] = implode('، ', array_unique($location));
        }
        unset($facts['title']);
        $sentences = $this->sentences($facts);
        return ['title' => $title, 'description' => implode('، ', array_values($sentences)).($sentences ? '.' : ''),
            'fact_keys' => array_keys($sentences), 'requires_review' => true];
    }

    private function sentences(array $facts): array
    {
        $result = [];
        foreach (['title', 'address'] as $key) if (is_string($facts[$key] ?? null) && trim($facts[$key]) !== '') $result[$key] = trim($facts[$key]);
        if (isset(self::TYPES[$facts['type'] ?? ''])) $result['type'] = self::TYPES[$facts['type']];
        if (isset($facts['purpose']) && in_array($facts['purpose'], ['sale', 'rent'], true)) $result['purpose'] = $facts['purpose'] === 'sale' ? 'معروض للبيع' : 'معروض للإيجار';
        $currency = $facts['currency'] ?? 'YER';
        foreach (['price', 'monthly_rent', 'area_value', 'bedrooms', 'bathrooms'] as $key) {
            if (! isset($facts[$key]) || ! is_numeric($facts[$key]) || $facts[$key] <= 0) continue;
            if ($key === 'price' && ($facts['purpose'] ?? '') === 'rent') continue;
            if ($key === 'monthly_rent' && ($facts['purpose'] ?? '') !== 'rent') continue;
            $suffix = match ($key) { 'price', 'monthly_rent' => ' '.$currency,
                'area_value' => ' '.(self::UNITS[$facts['area_unit'] ?? 'sqm'] ?? 'م²'), default => '' };
            $result[$key] = self::LABELS[$key].': '.rtrim(rtrim(number_format((float) $facts[$key], 2, '.', ''), '0'), '.').$suffix;
        }
        if (is_string($facts['floor_number'] ?? null) && trim($facts['floor_number']) !== '') $result['floor_number'] = 'الدور: '.$facts['floor_number'];
        foreach (['has_parking', 'has_elevator'] as $key) if (isset($facts[$key])) $result[$key] = ((bool) $facts[$key] ? 'يوجد ' : 'لا يوجد ').self::LABELS[$key];
        if (isset(self::FACADES[$facts['building_facade'] ?? ''])) $result['building_facade'] = 'واجهة '.self::FACADES[$facts['building_facade']];
        if (($facts['unit_occupies_entire_floor'] ?? false) === true) $result['unit_occupies_entire_floor'] = 'الوحدة تشغل الدور كاملًا';
        return $result;
    }
}
