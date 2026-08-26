<?php

use App\Services\CloudAssetStorageService;
use App\Services\SupportCaseService;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('support:escalate-overdue', function (SupportCaseService $support) {
    $count=$support->escalateOverdue();
    $this->info("Escalated {$count} overdue support case(s).");
})->purpose('Escalate Stage 10 support cases that exceeded the 48-hour SLA.');

Artisan::command('uat:cloud-check', function (CloudAssetStorageService $storage) {
    $errors = [];

    if (! app()->environment('staging')) {
        $errors[] = 'APP_ENV must be staging for the Cloud UAT service.';
    }

    $appUrl = rtrim((string) config('app.url'), '/');
    if (! str_starts_with($appUrl, 'https://') || str_contains($appUrl, 'localhost') || str_contains($appUrl, '127.0.0.1')) {
        $errors[] = 'APP_URL must be the public HTTPS Render URL.';
    }

    if (config('database.default') !== 'pgsql') {
        $errors[] = 'DB_CONNECTION must resolve to pgsql.';
    }

    if (trim((string) config('app.key')) === '') {
        $errors[] = 'APP_KEY is missing.';
    }

    if (! (bool) config('services.supabase_storage.enabled', false)) {
        $errors[] = 'UAT_CLOUD_STORAGE_ENABLED must be true.';
    }
    if (trim((string) config('services.supabase_storage.url')) === '') {
        $errors[] = 'SUPABASE_URL is missing.';
    }
    if (trim((string) config('services.supabase_storage.server_key')) === '') {
        $errors[] = 'SUPABASE_STORAGE_SERVER_KEY is missing.';
    }
    if (trim((string) config('services.supabase_storage.bucket')) === '') {
        $errors[] = 'SUPABASE_STORAGE_BUCKET is missing.';
    }

    $otp = (array) config('services.whatsapp.uat_test_otp', []);
    if ((bool) ($otp['enabled'] ?? false)) {
        if (! preg_match('/^\d{6}$/', (string) ($otp['code'] ?? ''))) {
            $errors[] = 'UAT_TEST_OTP_CODE must contain exactly 6 digits while UAT test OTP is enabled.';
        }
        if (count((array) ($otp['phone_numbers'] ?? [])) === 0) {
            $errors[] = 'UAT_TEST_PHONE_NUMBERS is empty while UAT test OTP is enabled.';
        }
    }

    if ($errors === []) {
        try {
            DB::select('select 1');
            $extension = DB::selectOne(
                "select n.nspname as schema_name from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'postgis' limit 1"
            );
            $schema = trim((string) ($extension->schema_name ?? ''));

            if ($schema === '') {
                $errors[] = 'PostGIS is not enabled in the UAT database.';
            } else {
                $searchPath = array_values(array_filter(array_map(
                    static fn (string $value): string => trim($value, " \t\n\r\0\x0B\""),
                    explode(',', (string) config('database.connections.pgsql.search_path', 'public'))
                )));
                if (! in_array($schema, $searchPath, true)) {
                    $errors[] = 'DB_SEARCH_PATH does not include the PostGIS schema.';
                }
            }
        } catch (\Throwable) {
            $errors[] = 'PostgreSQL connection or PostGIS verification failed.';
        }
    }

    if ($errors === []) {
        try {
            $storage->probe();
        } catch (\Throwable) {
            $errors[] = 'Supabase Storage connectivity check failed.';
        }
    }

    if ($errors !== []) {
        foreach ($errors as $error) {
            $this->error($error);
        }
        return 1;
    }

    $this->info('Cloud UAT environment check passed: HTTPS, PostgreSQL/PostGIS, Supabase Storage, and UAT guards are ready.');
    return 0;
})->purpose('Verify Cloud UAT environment without printing secrets.');

Schedule::command('support:escalate-overdue')->hourly();
