<?php

namespace Tests\Support;

use PDO;
use PDOException;
use RuntimeException;

/** Supply SQLite's optional math functions only on test builds that lack them. */
final class SqliteMathFallback
{
    public static function registerMissing(PDO $pdo): void
    {
        self::register($pdo, '');
    }

    /** Give the fallback callbacks absent names so tests cover them on every SQLite build. */
    public static function registerTestAliases(PDO $pdo): void
    {
        self::register($pdo, 'AQER_TEST_');
    }

    private static function register(PDO $pdo, string $prefix): void
    {
        if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'sqlite') {
            return;
        }

        $number = static fn ($value): ?float => $value !== null && is_numeric($value)
            ? (float) $value : null;
        $finite = static fn ($value): ?float => is_finite($value) ? $value : null;
        $unary = static fn ($value, $operation): ?float => ($x = $number($value)) === null
            ? null : $finite($operation($x));
        $functions = [
            'RADIANS' => [1, static fn ($x): ?float => $unary($x, deg2rad(...))],
            'SIN' => [1, static fn ($x): ?float => $unary($x, sin(...))],
            'COS' => [1, static fn ($x): ?float => $unary($x, cos(...))],
            'SQRT' => [1, static fn ($x): ?float => $unary($x, sqrt(...))],
            'ASIN' => [1, static fn ($x): ?float => $unary($x, asin(...))],
            'POWER' => [2, static function ($x, $y) use ($number, $finite): ?float {
                $base = $number($x);
                $exponent = $number($y);
                if ($base === null || $exponent === null || ($base == 0.0 && $exponent < 0.0)) {
                    return null;
                }
                return $finite(pow($base, $exponent));
            }],
        ];

        foreach ($functions as $name => [$arity, $callback]) {
            $sqlName = $prefix.$name;
            $args = $arity === 2 ? '2, 3' : '0';
            try {
                $pdo->query("SELECT {$sqlName}({$args})")->fetchColumn();
                continue;
            } catch (PDOException $error) {
                if (! str_contains($error->getMessage(), "no such function: {$sqlName}")) {
                    throw $error;
                }
            }

            if (! $pdo->sqliteCreateFunction($sqlName, $callback, $arity)) {
                throw new RuntimeException("Unable to register missing SQLite test function {$sqlName}.");
            }
        }
    }
}
