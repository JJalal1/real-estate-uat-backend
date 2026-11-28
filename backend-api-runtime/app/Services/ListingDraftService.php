<?php

namespace App\Services;

use Illuminate\Http\Exceptions\HttpResponseException;

/** Prepares proposals only. Property writes stay in the normal listing workflow. */
class ListingDraftService
{
    public function __construct(private readonly ListingAiService $listing) {}

    public function prepare(string $message, array $current, bool $supportsSaleCurrencies = false): array
    {
        $explicit = app(ExplicitListingFacts::class);
        $literal = $explicit->extract($message, $current['currency'] ?? 'YER');
        $source = 'ai';
        $notice = 'راجع التفاصيل والنص قبل تطبيقها على مسودتك.';
        try {
            $fields = (array) $this->listing->extract($message, $current, $literal)['fields'];
        } catch (HttpResponseException $error) {
            if (! in_array($error->getResponse()->getStatusCode(), [429, 503], true)) throw $error;
            $fields = $literal;
            $source = 'text';
            $notice = 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.';
        }
        // A successful but sparse model response must not discard clear facts
        // already supplied by the advertiser. Explicit labels take precedence.
        if (isset($literal['rental_conditions'], $fields['rental_conditions'])) {
            $kinds = array_column($literal['rental_conditions'], 'kind');
            $literal['rental_conditions'] = array_merge(array_values(array_filter($fields['rental_conditions'],
                fn ($row) => !in_array($row['kind'], $kinds, true))), $literal['rental_conditions']);
        }
        $proposed = array_replace($fields, $literal);
        $fields = $this->listing->facts($this->listing->reviewableSai($proposed, $current));
        if ((isset($proposed['fixed_sai_amount']) || isset($proposed['broker_sai_rate_percent']))
            && !isset($fields['sai_amount_type'])) {
            $notice .= ' راجع قيمة السعي وحدّه حسب سعر البيع أو إيجار الشهر الأول.';
        }
        // Older editors and the rent form accept only YER.
        $sale = ($fields['purpose'] ?? $current['purpose'] ?? null) === 'sale';
        $foreign = isset($fields['currency']) && $fields['currency'] !== 'YER';
        $mixed = $explicit->hasMixedCurrencies($message);
        if ($mixed || ($foreign && !($sale && $supportsSaleCurrencies))) {
            unset($fields['price'], $fields['monthly_rent'], $fields['currency'], $fields['fixed_sai_amount']);
            if (($fields['sai_amount_type'] ?? '') === 'fixed') unset($fields['sai_amount_type']);
            $notice .= $mixed ? ' أدخل السعر والسعي بعملة واحدة.' : ' المبلغ بعملة أخرى لم يُنقل إلى حقل الريال اليمني.';
        }
        // Titles/descriptions are composed from accepted facts, not free model
        // claims. Legacy whole-floor scope is not created by this assistant.
        unset($fields['title'], $fields['unit_occupies_entire_floor'], $fields['address']);
        $fields = array_filter($fields, fn ($value) => $value !== null && $value !== '');
        // Old numeric values must never acquire a newly proposed currency.
        if (isset($fields['currency']) && $fields['currency'] !== ($current['currency'] ?? 'YER')) {
            unset($current['price'], $current['monthly_rent'], $current['fixed_sai_amount']);
        }
        $facts = array_merge($current, $fields);
        $facts = app(DynamicPropertySchema::class)->validateApartmentFloor($facts, 'facts.floor_number');
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
        $clean=app(DynamicPropertySchema::class)->facts(array_merge($facts,$fields));
        $fields=array_intersect_key($clean,$fields);
        if (($facts['purpose'] ?? '') === 'rent') unset($fields['price']);
        return $fields;
    }
}
