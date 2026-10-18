<?php

namespace App\Services;

use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class RentalConditionService
{
    public const KINDS = ['advance', 'guarantor', 'deposit', 'duration', 'special'];

    public function normalize(mixed $input): array
    {
        if (is_string($input)) {
            if (strlen($input) > 8000) $this->invalid();
            try { $input = json_decode($input, true, 8, JSON_THROW_ON_ERROR); }
            catch (\Throwable) { $this->invalid(); }
        }
        if (! is_array($input) || ! array_is_list($input)) $this->invalid();
        Validator::make(['conditions' => $input], [
            'conditions' => ['array', 'max:8'],
            'conditions.*' => ['required', 'array:kind,months,text'],
            'conditions.*.kind' => ['required', Rule::in(self::KINDS)],
            'conditions.*.months' => ['nullable', 'integer', 'between:1,24'],
            'conditions.*.text' => ['nullable', 'string', 'max:300'],
        ])->validate();
        $result = []; $seen = []; $special = 0;
        foreach ($input as $row) {
            $kind = $row['kind'];
            if ($kind !== 'special' && isset($seen[$kind])) $this->invalid();
            $seen[$kind] = true;
            $next = ['kind' => $kind];
            if (in_array($kind, ['advance', 'duration'], true)) {
                if (! isset($row['months'])) $this->invalid();
                $next['months'] = (int) $row['months'];
            } elseif ($kind === 'special') {
                $text = trim((string) ($row['text'] ?? ''));
                if ($text === '' || ++$special > 4) $this->invalid();
                $next['text'] = $text;
            }
            // Reject irrelevant values rather than silently accepting hidden terms.
            if (array_diff(array_keys($row), array_keys($next))) $this->invalid();
            $result[] = $next;
        }
        $byKind = collect($result)->keyBy('kind');
        if (isset($byKind['advance'], $byKind['duration']) && $byKind['advance']['months'] > $byKind['duration']['months']) $this->invalid();
        return $result;
    }

    public function sentences(array $conditions): array
    {
        return array_map(fn (array $c): string => match ($c['kind']) {
            'advance' => 'مقدم إيجار: '.$c['months'].' أشهر',
            'duration' => 'مدة العقد: '.$c['months'].' أشهر',
            'guarantor' => 'ضمانة تجارية مطلوبة',
            'deposit' => 'تأمين مطلوب',
            'special' => $c['text'],
        }, $conditions);
    }

    private function invalid(): never
    {
        throw ValidationException::withMessages(['rental_conditions' => ['راجع الشروط المحددة وقيمها؛ لا نضيف شروطًا غير مختارة.']]);
    }
}
