<?php

namespace Tests\Postgres;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class ListingImageUploadIntentPostgresTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('testing', app()->environment());
        $this->assertSame('pgsql', DB::connection()->getDriverName());
        $this->assertSame('real_estate_audit', DB::connection()->getDatabaseName());
    }

    public function test_upload_intents_and_their_sequence_deny_direct_data_api_access(): void
    {
        $row = DB::selectOne(
            "SELECT relrowsecurity FROM pg_class WHERE oid = ?::regclass",
            ['public.listing_image_upload_intents'],
        );
        $this->assertNotNull($row);
        $this->assertTrue((bool) $row->relrowsecurity);

        $this->assertSame(
            0,
            (int) DB::table('pg_policies')
                ->where('schemaname', 'public')
                ->where('tablename', 'listing_image_upload_intents')
                ->count(),
        );

        foreach (['anon', 'authenticated'] as $role) {
            foreach (['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] as $privilege) {
                $allowed = DB::selectOne(
                    'SELECT has_table_privilege(?, ?, ?) AS allowed',
                    [$role, 'public.listing_image_upload_intents', $privilege],
                );
                $this->assertFalse((bool) $allowed->allowed, "$role can $privilege listing_image_upload_intents");
            }
        }
        foreach (['anon','authenticated'] as $role) foreach (['USAGE','SELECT','UPDATE'] as $privilege) {
            $this->assertFalse((bool)DB::selectOne('SELECT has_sequence_privilege(?, ?, ?) AS allowed',[$role,'public.listing_image_upload_intents_id_seq',$privilege])->allowed);
        }

    }
}

