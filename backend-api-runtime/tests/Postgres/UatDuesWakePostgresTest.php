<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UatDuesWakePostgresTest extends TestCase
{
    public function test_wake_only_for_due_work_and_retry_until_laravel_records_delivery(): void
    {
        $this->assertSame('pgsql', DB::getDriverName());
        $this->assertSame('testing', app()->environment());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
        $source = file_get_contents(dirname(__DIR__, 3).'/scripts/configure_frankfurt_dues_reminders.sql');
        $this->assertSame(1, preg_match('/\\$wake\\$(.*?)\\$wake\\$/s', $source, $matches));
        $sql = str_replace(['net.http_get(', 'public.property_platform_receivables'],
            ['pg_temp.record_wake(', 'pg_temp.dues'], $matches[1], $replacements);
        $this->assertSame(2, $replacements);

        DB::beginTransaction();
        try {
            DB::unprepared(<<<'SQL'
                CREATE TEMP TABLE dues (status text, amount_paid numeric, amount_total numeric,
                    due_at timestamptz, last_reminded_at timestamptz);
                CREATE TEMP TABLE observed_wakes (url text, timeout_ms integer);
                CREATE FUNCTION pg_temp.record_wake(url text, timeout_milliseconds integer) RETURNS bigint
                LANGUAGE sql VOLATILE AS $function$
                    INSERT INTO pg_temp.observed_wakes VALUES (url, timeout_milliseconds) RETURNING 1::bigint
                $function$;
                SQL);
            $this->assertCount(0, DB::select($sql));
            DB::unprepared(<<<'SQL'
                INSERT INTO pg_temp.dues VALUES
                    ('paid', 100, 100, now() - interval '1 day', NULL),
                    ('open', 100, 100, now() - interval '1 day', NULL),
                    ('open', 0, 100, now() + interval '1 second', NULL),
                    ('open', 0, 100, now(), now() - interval '23 hours 59 minutes 59 seconds');
                SQL);
            $this->assertCount(0, DB::select($sql));
            DB::unprepared(<<<'SQL'
                INSERT INTO pg_temp.dues VALUES
                    ('overdue', 2, 100, now(), NULL),
                    ('under_review', 0, 100, now(), now() - interval '24 hours'),
                    ('disputed', 1, 100, now(), NULL);
                SQL);
            $this->assertCount(1, DB::select($sql));
            $this->assertCount(1, DB::select($sql)); // First request failed, no delivery yet.
            DB::update('UPDATE pg_temp.dues SET last_reminded_at = CURRENT_TIMESTAMP');
            $this->assertCount(0, DB::select($sql));
            $wakes = DB::select('SELECT * FROM pg_temp.observed_wakes');
            $this->assertCount(2, $wakes);
            $this->assertSame('https://real-estate-uat-api-frankfurt.onrender.com/up', $wakes[0]->url);
            $this->assertSame(55000, (int) $wakes[0]->timeout_ms);
        } finally {
            DB::rollBack();
        }
    }
}
