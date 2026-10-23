<?php

namespace Tests\Postgres;

use App\Models\Property;
use App\Services\PropertyMarketContextService;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class PropertyMarketContextPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_market_comparable_area_bounds_are_integer_safe_in_postgresql(): void
    {
        // The live failure was an integer area column compared against
        // a decimal bound (205 * .70 = 143.5). Test the actual PostgreSQL API.
        DB::beginTransaction();
        try {
            $target = new Property();
            $target->status = 'published';
            $target->id = -999;
            $target->purpose = 'sale';
            $target->type = 'building';
            $target->currency = 'YER';
            $target->area_m2 = 205;
            $target->price = 1000000;
            $target->location = null;
            $target->latitude = null;
            $target->longitude = null;

            $result = app(PropertyMarketContextService::class)->contextFor($target);
            $this->assertFalse($result['sufficient_data']);
            $this->assertArrayHasKey('sample_count', $result);
        } finally {
            DB::rollBack();
        }
    }
}
