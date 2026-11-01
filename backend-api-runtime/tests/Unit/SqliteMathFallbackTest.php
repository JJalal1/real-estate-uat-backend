<?php

namespace Tests\Unit;

use PDO;
use PHPUnit\Framework\TestCase;
use Tests\Support\SqliteMathFallback;

class SqliteMathFallbackTest extends TestCase
{
    public function test_missing_math_matches_the_needed_spherical_query_operations(): void
    {
        $pdo = $this->connection();
        SqliteMathFallback::registerMissing($pdo);

        $this->assertEqualsWithDelta(M_PI, (float) $pdo->query('SELECT RADIANS(180)')->fetchColumn(), 1e-12);
        $this->assertEqualsWithDelta(0.0, (float) $pdo->query('SELECT SIN(0)')->fetchColumn(), 1e-12);
        $this->assertEqualsWithDelta(1.0, (float) $pdo->query('SELECT COS(0)')->fetchColumn(), 1e-12);
        $this->assertEqualsWithDelta(3.0, (float) $pdo->query('SELECT SQRT(9)')->fetchColumn(), 1e-12);
        $this->assertEqualsWithDelta(8.0, (float) $pdo->query('SELECT POWER(2, 3)')->fetchColumn(), 1e-12);
        $this->assertEqualsWithDelta(M_PI / 2, (float) $pdo->query('SELECT ASIN(1)')->fetchColumn(), 1e-12);

        foreach (['RADIANS(NULL)', 'SIN(NULL)', 'COS(NULL)', 'SQRT(NULL)', 'ASIN(NULL)',
            'POWER(NULL, 2)', 'POWER(2, NULL)', 'SQRT(-1)', 'ASIN(1.00001)',
            'ASIN(-1.00001)', 'POWER(0, -1)'] as $expression) {
            $this->assertNull($pdo->query("SELECT {$expression}")->fetchColumn(), $expression);
        }
    }

    public function test_existing_math_function_is_not_replaced(): void
    {
        $pdo = $this->connection();
        $pdo->sqliteCreateFunction('SIN', static fn ($value): float => 42.0, 1);
        SqliteMathFallback::registerMissing($pdo);
        SqliteMathFallback::registerMissing($pdo);

        $this->assertEqualsWithDelta(42.0, (float) $pdo->query('SELECT SIN(0)')->fetchColumn(), 1e-12);
    }

    private function connection(): PDO
    {
        $pdo = new PDO('sqlite::memory:');
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    }
}
