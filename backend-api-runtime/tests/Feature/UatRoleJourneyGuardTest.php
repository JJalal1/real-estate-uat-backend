<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AuditLogService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class UatRoleJourneyGuardTest extends TestCase
{
    use RefreshDatabase;

    public function test_production_cannot_execute_even_with_a_live_run_identifier(): void
    {
        $this->app->detectEnvironment(fn () => 'production');
        Http::preventStrayRequests();
        $this->artisan('uat:role-journeys',['--run'=>'2026-10-24-109-v1','--base-url'=>'http://127.0.0.1:10000'])->assertExitCode(1);
        $this->assertDatabaseCount('users',0);
        $this->assertDatabaseCount('audit_logs',0);
    }

    public function test_staging_requires_exact_opt_in_and_exact_uat_storage_project(): void
    {
        $this->app->detectEnvironment(fn () => 'staging');
        Http::preventStrayRequests();
        $this->artisan('uat:role-journeys',['--run'=>'2026-10-24-109-v1','--base-url'=>'http://127.0.0.1:10000'])->assertExitCode(1);
        $this->assertDatabaseCount('users',0);
        $this->assertDatabaseCount('audit_logs',0);
    }

    public function test_arbitrary_run_or_non_loopback_origin_is_rejected_before_creating_actors(): void
    {
        Http::preventStrayRequests();
        foreach (['https://example.test','http://127.0.0.1:8099@other.test','http://127.0.0.1:8099/path','http://localhost:8099'] as $url) {
            $this->artisan('uat:role-journeys',['--run'=>'disposable-ci','--base-url'=>$url])->assertExitCode(1);
        }
        $this->artisan('uat:role-journeys',['--run'=>'not-authorized','--base-url'=>'http://127.0.0.1:8099'])->assertExitCode(1);
        $this->assertDatabaseCount('users',0);
        $this->assertDatabaseCount('audit_logs',0);
    }

    public function test_a_persisted_started_marker_prevents_replay_even_after_process_restart(): void
    {
        Http::fake();
        app(AuditLogService::class)->record(null,'uat.role_journeys.started',null,['release_run'=>'disposable-ci']);
        $this->artisan('uat:role-journeys',['--run'=>'disposable-ci','--base-url'=>'http://127.0.0.1:8099'])
            ->expectsOutputToContain('already-started-no-replay')->assertExitCode(0);
        $this->assertSame(0,User::count());
        $this->assertDatabaseCount('audit_logs',1);
        Http::assertNothingSent();
    }
}
