<?php

namespace Tests\Feature;

use App\Console\Commands\UatOwnerAcceptancePreflight;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class OwnerAcceptanceGuardTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_preflight_never_runs_in_production_or_a_generic_test_environment(): void
    {
        foreach (['production','testing','local'] as $environment) {
            $this->app['env']=$environment;
            DB::enableQueryLog();DB::flushQueryLog();
            $this->artisan('uat:owner-acceptance-preflight',['--run'=>UatOwnerAcceptancePreflight::RUN,'--base-url'=>'http://127.0.0.1:10000'])
                ->expectsOutput('AQER_OWNER_PREFLIGHT {"status":"guard-refused","writes":false}')->assertFailed();
            $this->assertSame([],DB::getQueryLog());DB::disableQueryLog();
        }
    }

    public function test_owner_access_capsule_uses_the_exact_already_approved_public_recipient(): void
    {
        $path=resource_path('uat-owner-recipient.pem');
        $this->assertSame('12f6a686d39cef1b63f90011b979ebaef0a25f431d9f4eb1aa4d114a19c0f5e2',hash_file('sha256',$path));
        $cert=file_get_contents($path);
        $this->assertStringStartsWith('-----BEGIN CERTIFICATE-----',$cert);
        $this->assertStringNotContainsString('PRIVATE KEY',$cert);
    }
}
