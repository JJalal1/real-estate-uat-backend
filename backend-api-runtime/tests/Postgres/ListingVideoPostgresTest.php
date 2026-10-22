<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class ListingVideoPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_video_originals_and_processing_state_have_database_isolation(): void
    {
        $table = DB::selectOne("SELECT relrowsecurity AS enabled
            FROM pg_class WHERE oid = 'public.listing_videos'::regclass");
        $this->assertTrue((bool) $table->enabled);

        foreach (['anon', 'authenticated'] as $role) {
            foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] as $operation) {
                $allowed = DB::selectOne('SELECT has_table_privilege(?, ?, ?) AS allowed', [
                    $role, 'public.listing_videos', $operation,
                ]);
                $this->assertFalse((bool) $allowed->allowed, "$role may $operation private video metadata");
            }
        }

        $constraints = DB::select("SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.listing_videos'::regclass");
        $names = array_map(fn ($row) => $row->conname, $constraints);
        $this->assertContains('listing_videos_status_check', $names);
        $this->assertContains('listing_videos_moderation_check', $names);
        $this->assertContains('listing_videos_property_upload_unique', $names);
        $this->assertContains('listing_videos_one_per_property_unique', $names);
    }
}
