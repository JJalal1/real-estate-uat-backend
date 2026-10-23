<?php

use App\Services\CloudAssetStorageService;
use App\Services\SupportCaseService;
use App\Services\SupportTaskService;
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


Artisan::command('support:process-contact-followups', function (SupportTaskService $tasks) {
    $result=$tasks->processContactFollowupDeadlines();
    $this->info("Contact follow-ups: {$result['overdue_notified']} overdue notification(s), {$result['escalated']} escalation(s).");
})->purpose('Notify overdue contact follow-ups and auto-escalate them after an additional 24 hours.');


Artisan::command('uat:video-storage-probe', function (CloudAssetStorageService $storage): int {
    if (! app()->environment('staging') || ! $storage->cloudEnabled()) {
        $this->error('Private media probe requires the Cloud UAT environment.');
        return 1;
    }
    try {
        $storage->probePrivateVideoStorage();
        $this->info('Private UAT video storage canary passed: streamed upload, exact range and full download.');
        return 0;
    } catch (\Throwable) {
        // Do not echo storage URLs, response bodies or provider credentials.
        $this->error('Private UAT video storage canary failed.');
        return 1;
    }
})->purpose('Probe private Supabase Storage video protocol using disposable synthetic bytes.');

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
Artisan::command('uat:ai-check', function (\App\Services\GeminiClient $client): int {
    if (! app()->environment('uat', 'staging')) { $this->error('AI connectivity probe is UAT-only.'); return 1; }
    if (! $client->available()) { $this->warn('Gemini server configuration is unavailable; manual workflows remain available.'); return 1; }
    try {
        $result = $client->object('Return the exact JSON probe value ok. No other output.', ['probe' => 'connection'],
            ['type' => 'object', 'properties' => ['probe' => ['type' => 'string', 'enum' => ['ok']]], 'required' => ['probe']]);
        if (($result['probe'] ?? null) !== 'ok') { $this->warn('Gemini connectivity probe did not match.'); return 1; }
        $this->info('Gemini UAT connection probe passed; key remains server-only.');
        return 0;
    } catch (\Throwable) { $this->warn('Gemini UAT connection probe unavailable ('.$client->probeFailure().'); manual workflows remain available.'); return 1; }
})->purpose('Check Gemini from UAT without logging keys, prompts, or provider error details.');
Schedule::command('support:process-contact-followups')->hourly();

\Illuminate\Support\Facades\Artisan::command('broker:refresh-availability', function (): void {
    app(\App\Services\BrokerAvailabilityService::class)->sweep(500);
    $this->info('Availability reminders and pauses refreshed.');
});
\Illuminate\Support\Facades\Schedule::command('broker:refresh-availability')->hourly()->withoutOverlapping();

\Illuminate\Support\Facades\Artisan::command('broker:process-followups', function (): void {
    $sent=app(\App\Services\BrokerCustomerFollowupService::class)->sweep(500);
    $this->info("Private customer reminders: {$sent}.");
});
\Illuminate\Support\Facades\Schedule::command('broker:process-followups')->everyMinute()->withoutOverlapping();
