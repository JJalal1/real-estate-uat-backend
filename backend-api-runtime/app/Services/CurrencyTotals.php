<?php

namespace App\Services;

use Illuminate\Database\Query\Builder;

final class CurrencyTotals
{
    /** The expression and currency column are internal SQL expressions, never request input. */
    public static function sum(Builder $query, string $expression, string $currency = 'currency'): array
    {
        return (clone $query)->selectRaw("$currency AS unit, SUM($expression) AS amount")
            ->groupBy($currency)->orderBy($currency)->get()
            ->mapWithKeys(fn ($row) => [$row->unit => round((float) $row->amount, 2)])
            ->all();
    }

    public static function summary(array $metrics): array
    {
        // Older mobile clients explicitly label every scalar in this response as YER.
        return array_map(fn (array $amounts) => $amounts['YER'] ?? 0.0, $metrics)
            + ['amounts_by_currency' => $metrics];
    }
}
