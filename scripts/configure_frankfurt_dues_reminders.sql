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

DO $install$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_extension WHERE extname = 'pg_net') THEN
        CREATE EXTENSION pg_net WITH SCHEMA extensions;
        REVOKE USAGE ON SCHEMA net FROM PUBLIC, anon, authenticated;
    END IF;
END;
$install$;

-- A scheduled GET only wakes the web process. Its boot loop owns notification creation,
-- push preferences, balance rechecks, the receivable lock and the 24-hour checkpoint.
-- A failed wake is retried next minute while the receivable is still eligible.
SELECT cron.schedule(
    'aqer-frankfurt-due-reminders',
    '* * * * *',
    $wake$
    SELECT net.http_get(
        url := 'https://real-estate-uat-api-frankfurt.onrender.com/up',
        timeout_milliseconds := 55000
    )
    WHERE EXISTS (
        SELECT FROM public.property_platform_receivables
        WHERE status IN ('open', 'under_review', 'overdue', 'disputed')
          AND amount_paid < amount_total
          AND due_at <= CURRENT_TIMESTAMP
          AND (last_reminded_at IS NULL OR last_reminded_at <= CURRENT_TIMESTAMP - INTERVAL '24 hours')
    );
    $wake$
);

COMMIT;
