<?php

namespace App\Services;

use App\Models\GeoCell;
use App\Models\Governorate;

/** Resolve only active, recorded places. Ambiguous names never get guessed. */
class DiscoveryPlaceResolver
{
    public function __construct(private readonly PropertyDiscoveryFilterService $filters) {}

    public function resolve(string $text, ?string $governorate = null): ?array
    {
        $key = $this->key($text);
        if ($key === '') {
            return null;
        }
        $places = [];
        foreach (Governorate::query()->where('is_active', true)->orderBy('id')->get(['id', 'name_ar', 'name_en']) as $city) {
            if ($governorate !== null && $this->key($city->name_ar) !== $this->key($governorate)) {
                continue;
            }
            $places[] = ['kind' => 'governorate', 'id' => $city->id, 'name' => $city->name_ar,
                'governorate' => $city->name_ar, 'names' => [$city->name_ar, $city->name_en]];
        }
        $cells = GeoCell::query()->where('is_active', true)
            ->whereHas('governorate', fn ($q) => $q->where('is_active', true))
            ->when($governorate !== null, fn ($q) => $q->whereHas('governorate', fn ($g) => $g->where('name_ar', $governorate)))
            ->orderBy('id')->get(['id', 'name_ar', 'name_en', 'governorate_id']);
        foreach ($cells as $cell) {
            $places[] = ['kind' => 'cell', 'id' => $cell->id, 'name' => $cell->name_ar,
                'names' => [$cell->name_ar, $cell->name_en]];
        }
        // Optional local aliases must name an existing unique active place.
        // This is data configuration, never an AI-generated gazetteer.
        $aliases = config('discovery_ranked.place_aliases', []);
        foreach ($places as &$place) {
            foreach ($aliases as $alias => $canonical) {
                if ($this->key($canonical) === $this->key($place['name'])) {
                    $place['names'][] = $alias;
                }
            }
        }
        unset($place);
        $exact = array_values(array_filter($places, fn ($p) => in_array($key, array_map($this->key(...), array_filter($p['names'])), true)));
        if (count($exact) === 1) {
            return $exact[0] + ['approximate' => false];
        }
        if ($exact !== []) {
            return null;
        }
        // A common omitted final hamza (صنعا) remains a spelling alias. A
        // substitution (سنعا) is a nearby result, never a silent exact match.
        $plain = str_replace('ء', '', $key);
        $aliases = array_values(array_filter($places, fn ($p) => str_replace('ء', '', $this->key($p['name'])) === $plain));
        if (count($aliases) === 1) {
            return $aliases[0] + ['approximate' => false];
        }
        if ($aliases !== [] || mb_strlen($plain) < 4) {
            return null;
        }
        $near = array_values(array_filter($places, fn ($p) => $this->oneEdit($plain, str_replace('ء', '', $this->key($p['name'])))));

        return count($near) === 1 ? $near[0] + ['approximate' => true] : null;
    }

    private function key(?string $value): string
    {
        $key = $this->filters->normalizeArabicSearch(mb_strtolower(trim($value ?? '')));

        return trim(preg_replace('/^(?:مدينه|محافظه|منطقه|حي)\s+/u', '', $key), " \t\n\r\0\x0B،,؛:");
    }

    private function oneEdit(string $a, string $b): bool
    {
        $a = mb_str_split($a);
        $b = mb_str_split($b);
        if (abs(count($a) - count($b)) > 1) {
            return false;
        }
        $row = range(0, count($b));
        foreach ($a as $i => $letter) {
            $next = [$i + 1];
            foreach ($b as $j => $other) {
                $next[] = min($next[$j] + 1, $row[$j + 1] + 1, $row[$j] + ($letter === $other ? 0 : 1));
            }
            $row = $next;
        }

        return end($row) === 1;
    }
}
