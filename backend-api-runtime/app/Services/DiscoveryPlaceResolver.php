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
        $cities = Governorate::query()->where('is_active', true)->orderBy('id')->get(['id', 'name_ar', 'name_en']);
        $cityNames = $cities->pluck('name_ar', 'id');
        foreach ($cities as $city) {
            $places[] = ['kind' => 'governorate', 'id' => $city->id, 'name' => $city->name_ar,
                'governorate' => $city->name_ar, 'names' => [$city->name_ar, $city->name_en]];
        }
        $cells = GeoCell::query()->where('is_active', true)
            ->whereHas('governorate', fn ($q) => $q->where('is_active', true))
            ->orderBy('id')->get(['id', 'name_ar', 'name_en', 'governorate_id']);
        foreach ($cells as $cell) {
            $places[] = ['kind' => 'cell', 'id' => $cell->id, 'name' => $cell->name_ar,
                'governorate' => $cityNames[$cell->governorate_id], 'names' => [$cell->name_ar, $cell->name_en]];
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
        // Protect a valid recorded name globally before trying a spelling repair.
        // A conflicting city filter must not turn that name into another city.
        if ($exact !== []) {
            return $this->uniqueInGovernorate($exact, $governorate, false);
        }
        // A common omitted final hamza (صنعا) remains a spelling alias. A
        // substitution (سنعا) is a nearby result, never a silent exact match.
        $plain = str_replace('ء', '', $key);
        $aliases = array_values(array_filter($places, fn ($p) => str_replace('ء', '', $this->key($p['name'])) === $plain));
        if ($aliases !== []) {
            return $this->uniqueInGovernorate($aliases, $governorate, false);
        }
        if (mb_strlen($plain) < 4) {
            return null;
        }
        $near = array_values(array_filter($places, fn ($p) => $this->oneEdit($plain, str_replace('ء', '', $this->key($p['name'])))));

        return $this->uniqueInGovernorate($near, $governorate, true);
    }

    private function uniqueInGovernorate(array $places, ?string $governorate, bool $approximate): ?array
    {
        if ($governorate !== null) {
            $names = array_map($this->key(...), $this->filters->governorateAliases($governorate));
            $places = array_values(array_filter($places, fn ($place) => in_array($this->key($place['governorate']), $names, true)));
        }

        return count($places) === 1 ? $places[0] + ['approximate' => $approximate] : null;
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
