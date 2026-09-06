<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private const FOREIGN_KEY_INDEXES = [
        'account_verification_profiles_reviewed_by_idx' => ['account_verification_profiles', 'reviewed_by_user_id'],
        'broker_cell_assignments_assigned_by_idx' => ['broker_cell_assignments', 'assigned_by_user_id'],
        'broker_cell_assignments_ended_by_idx' => ['broker_cell_assignments', 'ended_by_user_id'],
        'listing_broker_verifications_geo_cell_idx' => ['listing_broker_verifications', 'geo_cell_id'],
        'listing_broker_verifications_requested_by_idx' => ['listing_broker_verifications', 'requested_by_user_id'],
        'listing_documents_property_idx' => ['listing_documents', 'property_id'],
        'listing_documents_uploaded_by_idx' => ['listing_documents', 'uploaded_by_user_id'],
        'properties_user_idx' => ['properties', 'user_id'],
        'property_assets_created_by_idx' => ['property_assets', 'created_by_user_id'],
        'property_images_property_idx' => ['property_images', 'property_id'],
        'publication_blocks_blocked_by_idx' => ['property_publication_blocks', 'blocked_by_user_id'],
        'publication_blocks_lifted_by_idx' => ['property_publication_blocks', 'lifted_by_user_id'],
        'role_permission_permission_idx' => ['role_permission', 'permission_id'],
        'permission_overrides_assigned_by_idx' => ['user_permission_overrides', 'assigned_by_user_id'],
        'permission_overrides_permission_idx' => ['user_permission_overrides', 'permission_id'],
        'user_role_assigned_by_idx' => ['user_role', 'assigned_by_user_id'],
        'user_role_role_idx' => ['user_role', 'role_id'],
        'users_broker_verified_by_idx' => ['users', 'broker_verified_by_user_id'],
    ];

    private const HARDENED_FUNCTIONS = [
        'sync_properties_location',
        'prevent_stage7_platform_owner_delete',
        'prevent_stage7_audit_log_mutation',
        'stage8_prevent_cell_overlap',
        'prevent_stage9_listing_review_mutation',
        'prevent_stage10_support_history_mutation',
        'prevent_stage11_private_access_history_mutation',
        'prevent_stage13_booking_history_mutation',
        'prevent_stage14_payment_history_mutation',
    ];

    public function up(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        foreach (self::HARDENED_FUNCTIONS as $function) {
            DB::statement("ALTER FUNCTION public.{$function}() SET search_path TO pg_catalog, public, extensions");
        }

        foreach (self::FOREIGN_KEY_INDEXES as $name => [$table, $column]) {
            DB::statement("CREATE INDEX IF NOT EXISTS {$name} ON public.{$table} ({$column})");
        }

        DB::unprepared(<<<'SQL'
DO $$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT schemaname, tablename
        FROM pg_catalog.pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
            target.schemaname,
            target.tablename
        );
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.enable_rls_for_new_public_tables()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    command record;
BEGIN
    FOR command IN
        SELECT * FROM pg_event_trigger_ddl_commands()
        WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
          AND object_type IN ('table', 'partitioned table')
    LOOP
        IF command.schema_name = 'public' THEN
            EXECUTE format('ALTER TABLE IF EXISTS %s ENABLE ROW LEVEL SECURITY', command.object_identity);
        END IF;
    END LOOP;
END
$$;

DROP EVENT TRIGGER IF EXISTS enable_rls_on_public_table_create;
CREATE EVENT TRIGGER enable_rls_on_public_table_create
ON ddl_command_end
WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
EXECUTE FUNCTION public.enable_rls_for_new_public_tables();
SQL);
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        DB::unprepared(<<<'SQL'
DROP EVENT TRIGGER IF EXISTS enable_rls_on_public_table_create;
DROP FUNCTION IF EXISTS public.enable_rls_for_new_public_tables();

DO $$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT schemaname, tablename
        FROM pg_catalog.pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I DISABLE ROW LEVEL SECURITY',
            target.schemaname,
            target.tablename
        );
    END LOOP;
END
$$;
SQL);

        foreach (array_keys(self::FOREIGN_KEY_INDEXES) as $name) {
            DB::statement("DROP INDEX IF EXISTS public.{$name}");
        }

        foreach (self::HARDENED_FUNCTIONS as $function) {
            DB::statement("ALTER FUNCTION public.{$function}() RESET search_path");
        }
    }
};
