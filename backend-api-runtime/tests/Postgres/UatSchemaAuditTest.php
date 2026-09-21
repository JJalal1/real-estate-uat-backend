<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;
use Tests\TestCase;

class UatSchemaAuditTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // This suite is run explicitly against a disposable CI database only.
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_complete_chain_and_public_spatial_api_are_ready(): void
    {
        $expected = array_map(fn ($path) => basename($path, '.php'), glob(database_path('migrations/*.php')));
        $actual = DB::table('migrations')->pluck('migration')->all();
        sort($expected);
        sort($actual);
        $this->assertSame($expected, $actual);
        $this->assertTrue(Schema::hasColumns('properties', ['tenure_type', 'review_assigned_to_user_id', 'location']));
        $this->assertTrue(Schema::hasColumn('viewing_bookings', 'message_thread_id'));
        $this->assertTrue(Schema::hasTable('support_tasks'));
        $this->assertTrue(Schema::hasTable('support_task_events'));
        $this->getJson('/api/health')->assertOk()->assertJsonPath('postgis', true);
        $this->getJson('/api/properties')->assertOk()->assertJsonPath('meta.total', 0);
        $this->getJson('/api/properties/nearby?latitude=15.35&longitude=44.2')->assertOk()->assertJsonPath('data', []);
    }

    public function test_application_tables_are_private_and_extension_tables_are_untouched(): void
    {
        $unprotected = DB::select(<<<'SQL'
SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
SQL);
        $this->assertSame([], $unprotected);
        $this->assertFalse((bool) DB::selectOne("SELECT relrowsecurity FROM pg_class WHERE oid = 'spatial_ref_sys'::regclass")->relrowsecurity);
        foreach (['anon', 'authenticated'] as $role) {
            foreach (['users', 'api_tokens', 'private_messages', 'account_verification_documents', 'support_tasks'] as $table) {
                foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                    $allowed = DB::selectOne('SELECT has_table_privilege(?, ?, ?) AS allowed', [$role, 'public.'.$table, $privilege]);
                    $this->assertFalse((bool) $allowed->allowed, "$role can $privilege $table");
                }
            }
        }
        $function = DB::selectOne("SELECT prosecdef, proconfig FROM pg_proc WHERE oid = 'public.enable_rls_for_new_public_tables()'::regprocedure");
        $this->assertFalse((bool) $function->prosecdef);
        $this->assertStringContainsString('search_path=pg_catalog', $function->proconfig);
    }

    public function test_new_tables_are_private_and_rls_blocks_even_an_explicit_select_grant(): void
    {
        DB::beginTransaction();
        try {
            DB::statement('CREATE TABLE public.audit_rls_probe (id integer PRIMARY KEY)');
            DB::statement('INSERT INTO public.audit_rls_probe VALUES (1)');
            $this->assertSame(1, (int) DB::table('audit_rls_probe')->count());
            $this->assertFalse((bool) DB::selectOne("SELECT has_table_privilege('anon', 'public.audit_rls_probe', 'TRUNCATE') AS allowed")->allowed);
            DB::statement('GRANT SELECT ON public.audit_rls_probe TO anon');
            DB::statement('SET LOCAL ROLE anon');
            $this->assertSame(0, (int) DB::table('audit_rls_probe')->count());
        } finally {
            DB::rollBack();
        }
    }

    public function test_foreign_keys_have_covering_indexes_and_trigger_paths_are_fixed(): void
    {
        $unindexed = DB::select(<<<'SQL'
SELECT c.conname FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE c.contype = 'f' AND n.nspname = 'public'
AND NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid
    AND i.indisvalid AND i.indpred IS NULL AND i.indexprs IS NULL
    AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1] @> c.conkey
)
SQL);
        $this->assertSame([], $unindexed);
        $mutable = DB::select(<<<'SQL'
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prorettype = 'trigger'::regtype
AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) setting WHERE setting LIKE 'search_path=%')
AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
SQL);
        $this->assertSame([], $mutable);
    }

    public function test_hardening_is_idempotent_and_rollback_cannot_reopen_data(): void
    {
        $migration = require database_path('migrations/2026_09_06_000000_harden_supabase_public_schema.php');
        $migration->up();
        try {
            $migration->down();
            $this->fail('Security rollback must stop before removing protections.');
        } catch (RuntimeException $exception) {
            $this->assertStringContainsString('cannot be rolled back automatically', $exception->getMessage());
        }
        $this->assertTrue((bool) DB::selectOne("SELECT relrowsecurity FROM pg_class WHERE oid = 'public.users'::regclass")->relrowsecurity);
    }
}
