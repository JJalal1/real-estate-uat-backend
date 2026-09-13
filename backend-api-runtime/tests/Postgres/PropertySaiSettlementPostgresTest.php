<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class PropertySaiSettlementPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_sai_settlement_ledger_is_deny_all_and_has_no_direct_data_api_policy(): void
    {
        $row = DB::selectOne(
            "SELECT relrowsecurity FROM pg_class WHERE oid = ?::regclass",
            ['public.property_sai_settlements'],
        );
        $this->assertNotNull($row);
        $this->assertTrue((bool) $row->relrowsecurity);
        $this->assertSame(
            0,
            (int) DB::table('pg_policies')
                ->where('schemaname', 'public')
                ->where('tablename', 'property_sai_settlements')
                ->count(),
        );

        foreach (['anon', 'authenticated'] as $role) {
            foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                $allowed = DB::selectOne(
                    'SELECT has_table_privilege(?, ?, ?) AS allowed',
                    [$role, 'public.property_sai_settlements', $privilege],
                );
                $this->assertFalse((bool) $allowed->allowed, "$role can $privilege property_sai_settlements");
            }
        }
    }

    public function test_sai_settlement_integrity_and_immutability_guards_exist(): void
    {
        $indexes = DB::table('pg_indexes')
            ->where('schemaname', 'public')
            ->where('tablename', 'property_sai_settlements')
            ->pluck('indexname')
            ->all();

        $this->assertContains('property_sai_settlements_property_agreement_id_unique', $indexes);
        $this->assertContains('property_sai_settlements_property_agreement_revision_id_unique', $indexes);
        $this->assertContains('property_sai_settlements_property_time_idx', $indexes);
        $this->assertContains('property_sai_settlements_term_time_idx', $indexes);

        foreach (['property_sai_settlements_immutable_update', 'property_sai_settlements_immutable_delete'] as $trigger) {
            $exists = DB::selectOne(
                "SELECT 1 AS present FROM pg_trigger WHERE tgname = ? AND NOT tgisinternal",
                [$trigger],
            );
            $this->assertNotNull($exists, "$trigger is missing");
        }
    }
}
