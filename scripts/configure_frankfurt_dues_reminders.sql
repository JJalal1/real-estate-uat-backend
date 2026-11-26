-- Apply to the Frankfurt UAT Supabase project ipxsgxsqzthpgthwvdno after the 1847 API is healthy.
-- Verify with SELECT jobid, schedule, active FROM cron.job WHERE jobname = 'aqer-frankfurt-due-reminders';
-- Roll back this schedule with SELECT cron.unschedule('aqer-frankfurt-due-reminders');
BEGIN;

DO $guard$
BEGIN
    IF current_database() <> 'postgres'
        OR (SELECT system_identifier FROM pg_catalog.pg_control_system()) <> 7678071634733212629 THEN
        RAISE EXCEPTION 'The dues schedule belongs to the Frankfurt UAT cluster only';
    END IF;
    PERFORM last_reminded_at FROM public.property_platform_receivables LIMIT 0;
END;
$guard$;

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS aqer_dues_wake AUTHORIZATION postgres;

DO $private$
BEGIN
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'aqer_dues_wake') <> 'postgres' THEN
        RAISE EXCEPTION 'Unexpected owner of UAT scheduler schema';
    END IF;
END;
$private$;

REVOKE ALL ON SCHEMA aqer_dues_wake FROM PUBLIC, anon, authenticated;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA aqer_dues_wake;

DO $access$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_extension WHERE extname = 'http' AND extnamespace = 'aqer_dues_wake'::regnamespace
    ) OR has_schema_privilege('anon', 'aqer_dues_wake', 'USAGE')
      OR has_schema_privilege('authenticated', 'aqer_dues_wake', 'USAGE') THEN
        RAISE EXCEPTION 'The UAT HTTP extension must be isolated from client roles';
    END IF;
END;
$access$;

-- A scheduled GET only wakes the web process. Its boot loop owns notification creation,
-- push preferences, balance rechecks, the receivable lock and the 24-hour checkpoint.
-- A failed wake is retried next minute while the receivable is still eligible.
SELECT cron.schedule(
    'aqer-frankfurt-due-reminders',
    '* * * * *',
    $wake$
    BEGIN;
    SET LOCAL search_path TO pg_catalog, aqer_dues_wake, pg_temp;
    SET LOCAL http.curlopt_timeout_ms TO '55000';
    SELECT (aqer_dues_wake.http_get('https://real-estate-uat-api-frankfurt.onrender.com/up')).status
    WHERE EXISTS (
        SELECT FROM public.property_platform_receivables
        WHERE status IN ('open', 'under_review', 'overdue', 'disputed')
          AND amount_paid < amount_total
          AND due_at <= CURRENT_TIMESTAMP
          AND (last_reminded_at IS NULL OR last_reminded_at <= CURRENT_TIMESTAMP - INTERVAL '24 hours')
    );
    COMMIT;
    $wake$
);

COMMIT;
