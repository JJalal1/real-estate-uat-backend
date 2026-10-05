<?php

namespace App\Support;

/**
 * Owner-approved current product scope.
 *
 * Finance/Sai code and historical schema are preserved, but the current
 * product is the free core. Re-enabling either capability requires a separate
 * owner-approved scope and must not happen through an environment toggle.
 */
final class CurrentProductPolicy
{
    public const FINANCE_ENABLED = false;
    public const SAI_ENABLED = false;

    public static function financeEnabled(): bool
    {
        return self::FINANCE_ENABLED;
    }

    public static function saiEnabled(): bool
    {
        return self::SAI_ENABLED;
    }
}
