<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UxRefinementPostgresTest extends TestCase
{
    public function test_type_extension_keeps_postgres_constraint_rls_and_private_access(): void
    {
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
        $constraint = DB::selectOne("SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='properties'::regclass AND conname='properties_type_check'");
        $this->assertNotNull($constraint);
        foreach (['apartment', 'floor', 'building', 'farm'] as $type) $this->assertStringContainsString($type, $constraint->definition);
        foreach (['anon', 'authenticated'] as $role) {
            $this->assertFalse((bool) DB::selectOne('SELECT has_table_privilege(?, ?, ?) AS allowed', [$role, 'properties', 'SELECT'])->allowed);
        }
        $this->assertTrue((bool) DB::selectOne("SELECT relrowsecurity FROM pg_class WHERE oid='properties'::regclass")->relrowsecurity);
    }
}
