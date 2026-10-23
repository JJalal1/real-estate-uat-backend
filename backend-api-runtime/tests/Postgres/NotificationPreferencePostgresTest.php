<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class NotificationPreferencePostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_notification_preferences_are_backend_only_and_deny_direct_data_api_access(): void
    {
        $row = DB::selectOne(
            "SELECT relrowsecurity FROM pg_class WHERE oid = ?::regclass",
            ['public.user_notification_preferences'],
        );
        $this->assertNotNull($row);
        $this->assertTrue((bool) $row->relrowsecurity);

        $this->assertSame(
            0,
            (int) DB::table('pg_policies')
                ->where('schemaname', 'public')
                ->where('tablename', 'user_notification_preferences')
                ->count(),
        );

        foreach (['anon', 'authenticated'] as $role) {
            foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                $allowed = DB::selectOne(
                    'SELECT has_table_privilege(?, ?, ?) AS allowed',
                    [$role, 'public.user_notification_preferences', $privilege],
                );
                $this->assertFalse((bool) $allowed->allowed, "$role can $privilege user_notification_preferences");
            }
        }
    }
}
