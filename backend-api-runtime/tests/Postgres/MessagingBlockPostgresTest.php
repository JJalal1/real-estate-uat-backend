<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class MessagingBlockPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_messaging_blocks_and_their_sequence_deny_direct_data_api_access(): void
    {
        $row = DB::selectOne(
            "SELECT relrowsecurity FROM pg_class WHERE oid = ?::regclass",
            ['public.user_messaging_blocks'],
        );
        $this->assertNotNull($row);
        $this->assertTrue((bool) $row->relrowsecurity);

        $this->assertSame(
            0,
            (int) DB::table('pg_policies')
                ->where('schemaname', 'public')
                ->where('tablename', 'user_messaging_blocks')
                ->count(),
        );

        foreach (['anon', 'authenticated'] as $role) {
            foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                $allowed = DB::selectOne(
                    'SELECT has_table_privilege(?, ?, ?) AS allowed',
                    [$role, 'public.user_messaging_blocks', $privilege],
                );
                $this->assertFalse((bool) $allowed->allowed, "$role can $privilege user_messaging_blocks");
            }
        }
        foreach (['anon','authenticated'] as $role) foreach (['USAGE','SELECT','UPDATE'] as $privilege) {
            $this->assertFalse((bool)DB::selectOne('SELECT has_sequence_privilege(?, ?, ?) AS allowed',[$role,'public.user_messaging_blocks_id_seq',$privilege])->allowed);
        }

    }
    public function test_pair_uniqueness_self_check_foreign_keys_and_migration_reversal_are_reviewable(): void
    {
        $rows=DB::select("SELECT contype,pg_get_constraintdef(oid) AS definition,confdeltype FROM pg_constraint WHERE conrelid='public.user_messaging_blocks'::regclass");
        $definitions=collect($rows)->pluck('definition')->implode(' ');
        $this->assertStringContainsString('UNIQUE (user_id, blocked_user_id)',$definitions);
        $this->assertStringContainsString('user_id <> blocked_user_id',$definitions);
        $this->assertSame(2,collect($rows)->where('contype','f')->where('confdeltype','r')->count());
        DB::beginTransaction();
        try {
            $migration=require database_path('migrations/2026_10_21_010000_create_user_messaging_blocks.php');
            $migration->down();
            $this->assertNull(DB::selectOne("SELECT to_regclass('public.user_messaging_blocks') AS target")->target);
            $migration->up();
            $this->assertTrue((bool)DB::selectOne("SELECT relrowsecurity FROM pg_class WHERE oid='public.user_messaging_blocks'::regclass")->relrowsecurity);
        } finally { DB::rollBack(); }
    }
}
