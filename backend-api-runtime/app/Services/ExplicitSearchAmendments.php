<?php

namespace App\Services;

/** Reconcile a successful model patch with clear, explicitly stated search facts. */
class ExplicitSearchAmendments
{
    public function __construct(private readonly ArabicListingNumber $numbers) {}

    public function reconcile(string $message, array $patch): array
    {
        $text = ArabicListingNumber::normalize($message);
        // Adding rooms or a budget never authorizes an incidental type change.
        $typeWords = '(?:(?:ال)?(?:نوع|انواع|شقه|شقق|منزل|منازل|بيت|بيوت|فيلا|فلل|فيلات|عماره|عمارات|عمائر|ارض|اراضي|مزرعه|مزارع|محل|محلات|مكتب|مكاتب)|apartment|house|villa|building|land|farm|shop|office|types?)';
        if (!preg_match('/(?<!\pL)(?:و)?'.$typeWords.'(?:ا)?(?!\pL)|(?<!\pL)(?:ال)?(?:دور|طابق)\s+(?:كامل|كاملا|بالكامل)(?!\pL)/iu', $text)) {
            unset($patch['set']['type'], $patch['set']['types']);
            $patch['remove'] = array_values(array_diff($patch['remove'], ['type', 'types']));
        }
        // Ambiguous alternatives and questions remain model-led. This is not
        // a literal fallback and cannot turn a provider failure into success.
        if (preg_match('/[?؟]|(?<!\pL)(?:هل|ليش|لماذا|كيف|ربما|تقصد|او|ام)(?!\pL)/u', $text)) return $patch;

        $facts = [];
        foreach ([
            'min_bedrooms' => ['(?:غرف(?:ه)?(?:\s*نوم)?)', '(?:غرفتين|غرفتان)'],
            'min_bathrooms' => ['(?:حمامات|حمام|دورات?\s*مياه|دوره\s*مياه)', '(?:حمامين|حمامان)'],
        ] as $key => [$unit, $dual]) {
            $count = $this->count($text, $unit, $dual);
            if ($count !== null) $facts[$key] = $count;
        }
        $budget = $this->budget($text);
        if ($budget !== []) {
            // Ignore a model's inverted/new opposite bound; preserve any
            // unmentioned opposite bound already present in current_filters.
            unset($patch['set']['min_price'], $patch['set']['max_price'], $patch['set']['currency']);
            $patch['remove'] = array_values(array_diff($patch['remove'], ['min_price', 'max_price', 'currency']));
            $facts = array_merge($facts, $budget);
        }
        foreach ($facts as $key => $value) {
            $patch['remove'] = array_values(array_diff($patch['remove'], [$key]));
            $patch['set'][$key] = $value;
        }
        return $patch;
    }

    private function negated(string $prefix): bool
    {
        return preg_match('/(?:بدون|ليس(?:ت)?|غير|مو|مش|الغ|الغي|الغاء|ازل|ازاله|احذف|حذف|شيل|استبعد|لا(?:\s+اريد)?)\s+(?:\pL+\s+){0,2}$/u', $prefix) === 1;
    }

    private function count(string $text, string $unit, string $dual): ?int
    {
        $number = $this->numbers->pattern();
        $matches = [];
        $total = preg_match_all('/(?<![-\pL\d.])(?:و\s*)?('.$number.')\s*'.$unit.'(?!\pL)/u', $text, $matches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
        if ($total === 1) {
            $match = $matches[0];
            if ($this->negated(substr($text, 0, $match[0][1]))) return null;
            $tail = substr($text, $match[0][1] + strlen($match[0][0]));
            if (preg_match('/^\s*(?:الي|حتي|[-–])\s*'.$number.'\s*'.$unit.'/u', $tail)) return null;
            $value = $this->numbers->parse($match[1][0]);
            return $value !== null && $value >= 1 && $value <= 50 && floor($value) === $value ? (int) $value : null;
        }
        if ($total !== 0 || preg_match_all('/(?<!\pL)(?:و)?'.$dual.'(?!\pL)/u', $text, $matches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE) !== 1) return null;
        return $this->negated(substr($text, 0, $matches[0][0][1])) ? null : 2;
    }

    private function budget(string $text): array
    {
        $bounds = [
            'max_price' => '(?:ب?(?:ال)?حد\s+(?:ال)?اقصي|لا\s+(?:يزيد|تزيد)\s+عن|لا\s+يتجاوز|حتي|اقل\s+من)',
            'min_price' => '(?:ب?(?:ال)?حد\s+(?:ال)?ادني|لا\s+(?:يقل|تقل)\s+عن|(?:اكثر|اكبر)\s+من)',
        ];
        $gap = '(?:\s+(?:للسعر|للايجار|للميزانيه|السعر|الايجار|الشهري|شهريا|الميزانيه)){0,4}\s*[:=]?\s*';
        $currency = '(ريال(?:\s*(?:يمني|سعودي))?|دولار|سعودي)';
        $facts = []; $currencies = [];
        foreach ($bounds as $key => $bound) {
            $total = preg_match_all('/(?<!\pL)(?:و)?'.$bound.$gap.'('.$this->numbers->pattern().')\s*'.$currency.'(?!\pL)/u',
                $text, $matches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
            if ($total > 1) return [];
            if ($total !== 1) continue;
            $match = $matches[0]; $prefix = substr($text, 0, $match[0][1]);
            if ($this->negated($prefix) || preg_match('/(?:مقدم|تامين|سعي|عموله|ضمان)\s*(?:\pL+\s+){0,2}$/u', $prefix)) continue;
            $amount = $this->numbers->parse($match[1][0]);
            if ($amount === null) continue;
            $facts[$key] = $amount;
            $currencies[] = str_contains($match[2][0], 'دولار') ? 'USD' : (str_contains($match[2][0], 'سعودي') ? 'SAR' : 'YER');
        }
        if ($facts === [] || count(array_unique($currencies)) !== 1) return [];
        $facts['currency'] = $currencies[0];
        return $facts;
    }
}
