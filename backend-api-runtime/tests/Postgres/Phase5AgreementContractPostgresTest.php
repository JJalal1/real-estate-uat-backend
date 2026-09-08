<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Phase5AgreementContractPostgresTest extends TestCase
{
    private const TABLES = [
        'property_agreements',
        'property_agreement_revisions',
        'property_agreement_acceptances',
        'rental_contracts',
        'rental_contract_revisions',
        'rental_contract_acceptances',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_phase5_tables_are_deny_all_direct_access_with_rls_enabled(): void
    {
        foreach (self::TABLES as $table) {
            $row = DB::selectOne("SELECT relrowsecurity FROM pg_class WHERE oid = ?::regclass", ['public.'.$table]);
            $this->assertNotNull($row, $table.' is missing');
            $this->assertTrue((bool) $row->relrowsecurity, $table.' must have RLS enabled');

            $policyCount = (int) DB::table('pg_policies')->where('schemaname', 'public')->where('tablename', $table)->count();
            $this->assertSame(0, $policyCount, $table.' must remain deny-all for direct Data API access');

            foreach (['anon', 'authenticated'] as $role) {
                foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                    $allowed = DB::selectOne('SELECT has_table_privilege(?, ?, ?) AS allowed', [$role, 'public.'.$table, $privilege]);
                    $this->assertFalse((bool) $allowed->allowed, "$role can $privilege $table");
                }
            }
        }
    }

    public function test_phase5_integrity_indexes_exist_and_active_agreement_guard_is_partial_unique(): void
    {
        $index = DB::selectOne("SELECT indexdef FROM pg_indexes WHERE schemaname='public' AND tablename='property_agreements' AND indexname='property_agreements_active_thread_unique'");
        $this->assertNotNull($index);
        $definition = strtolower((string) $index->indexdef);
        $this->assertStringContainsString('unique index', $definition);
        $this->assertStringContainsString('(message_thread_id)', $definition);
        $this->assertStringContainsString('where', $definition);
        $this->assertStringContainsString('draft', $definition);
        $this->assertStringContainsString('accepted', $definition);

        $required = [
            'property_agreements_message_thread_id_index',
            'property_agreements_viewing_booking_id_index',
            'property_agreements_created_by_user_id_index',
            'property_agreement_revisions_created_by_user_id_index',
            'property_agreement_acceptances_user_id_index',
            'rental_contracts_property_id_index',
            'rental_contracts_message_thread_id_index',
            'rental_contracts_created_by_user_id_index',
            'rental_contract_revisions_created_by_user_id_index',
            'rental_contract_acceptances_user_id_index',
        ];
        $actual = DB::table('pg_indexes')->where('schemaname', 'public')->whereIn('indexname', $required)->pluck('indexname')->sort()->values()->all();
        sort($required);
        $this->assertSame($required, $actual);
    }
}
