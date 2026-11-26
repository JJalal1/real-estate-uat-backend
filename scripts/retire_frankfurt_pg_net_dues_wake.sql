-- One-time cleanup for pg_net 0.20.4 installed solely for the first UAT dues scheduler.
-- Apply after configure_frankfurt_dues_reminders.sql and its independent smoke check.
BEGIN;

DO $cleanup$
BEGIN
    IF current_database() <> 'postgres'
        OR (SELECT system_identifier FROM pg_catalog.pg_control_system()) <> 7678071634733212629 THEN
        RAISE EXCEPTION 'Only the Frankfurt UAT cluster can use this cleanup';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_net') THEN
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_net' AND extversion = '0.20.4')
        OR NOT EXISTS (SELECT FROM pg_extension WHERE extname = 'http' AND extnamespace = 'aqer_dues_wake'::regnamespace)
        OR NOT EXISTS (SELECT FROM cron.job WHERE jobname = 'aqer-frankfurt-due-reminders'
                      AND active AND command LIKE '%aqer_dues_wake.http_get(%')
        OR EXISTS (SELECT FROM cron.job WHERE command ~* '(^|[^[:alnum:]_])net[.]')
        OR EXISTS (SELECT FROM pg_trigger t JOIN pg_proc f ON f.oid = t.tgfoid
                   JOIN pg_namespace n ON n.oid = f.pronamespace
                   WHERE NOT t.tgisinternal AND n.nspname = 'supabase_functions' AND f.proname = 'http_request')
        OR EXISTS (SELECT FROM net.http_request_queue)
        OR EXISTS (SELECT FROM net._http_response)
    THEN
        RAISE EXCEPTION 'UAT network cleanup preconditions are not satisfied';
    END IF;

    -- RESTRICT stops on any additional PostgreSQL dependency.
    DROP EXTENSION pg_net RESTRICT;
END;
$cleanup$;

COMMIT;
