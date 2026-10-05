<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.enable_rls_for_new_public_tables()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
    command record;
    api_role record;
BEGIN
    FOR command IN
        SELECT * FROM pg_event_trigger_ddl_commands()
        WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
          AND object_type IN ('table', 'partitioned table')
          AND NOT in_extension
    LOOP
        IF command.schema_name = 'public' THEN
            EXECUTE format('ALTER TABLE IF EXISTS %s ENABLE ROW LEVEL SECURITY', command.object_identity);
            EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC', command.object_identity);
            FOR api_role IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated')
            LOOP
                EXECUTE format('REVOKE ALL ON TABLE %s FROM %I', command.object_identity, api_role.rolname);
            END LOOP;
        END IF;
    END LOOP;
END
$$;

REVOKE ALL ON FUNCTION public.enable_rls_for_new_public_tables() FROM PUBLIC;
DO $$
DECLARE api_role record;
BEGIN
    FOR api_role IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated')
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION public.enable_rls_for_new_public_tables() FROM %I', api_role.rolname);
    END LOOP;
END
$$;

DROP EVENT TRIGGER IF EXISTS enable_rls_on_public_table_create;
CREATE EVENT TRIGGER enable_rls_on_public_table_create
ON ddl_command_end
WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
EXECUTE FUNCTION public.enable_rls_for_new_public_tables();
ALTER EVENT TRIGGER enable_rls_on_public_table_create ENABLE;
SQL);
    }

    public function down(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        throw new RuntimeException('Automatic RLS event-trigger repair is forward-only and cannot be rolled back automatically.');
    }
};
