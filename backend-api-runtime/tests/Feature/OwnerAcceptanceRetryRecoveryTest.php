<?php

namespace Tests\Feature;

use App\Console\Support\UatOwnerFixtureRecovery;
use App\Console\Support\UatOwnerRequestRetry;
use App\Models\User;
use App\Models\Role;
use App\Services\AuditLogService;
use App\Services\ApiTokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class OwnerAcceptanceRetryRecoveryTest extends TestCase
{
    use RefreshDatabase;

    public function test_otp_retry_obeys_provider_delay_and_still_requires_success(): void
    {
        Http::fakeSequence()->push([],429,['Retry-After'=>'2'])->push(['ok'=>true],200);
        $waits=[];$observed=[];
        $retry=new UatOwnerRequestRetry(function (int $seconds) use (&$waits): void { $waits[]=$seconds; });
        $response=$retry->send('/api/auth/whatsapp/start',fn()=>Http::get('https://synthetic.invalid/otp'),
            function ($seconds,$attempt) use (&$observed): void { $observed[]=[$seconds,$attempt]; },microtime(true));
        $this->assertSame(200,$response->status());$this->assertSame([3],$waits);$this->assertSame([[3,1]],$observed);
        Http::assertSentCount(2);
    }

    public function test_exhausted_throttle_is_not_converted_to_a_success(): void
    {
        Http::fakeSequence()->push([],429,['Retry-After'=>'0'])->push([],429,['Retry-After'=>'0'])->push([],429,['Retry-After'=>'0']);
        $waits=[];$retry=new UatOwnerRequestRetry(function ($seconds) use (&$waits): void { $waits[]=$seconds; });
        $response=$retry->send('/api/auth/whatsapp/verify',fn()=>Http::get('https://synthetic.invalid/otp'),fn()=>null,microtime(true));
        $this->assertSame(429,$response->status());$this->assertSame([1,1],$waits);Http::assertSentCount(3);
    }

    public function test_listing_writes_and_unbounded_or_missing_delays_are_never_retried(): void
    {
        foreach ([['/api/properties','1'],['/api/auth/whatsapp/start',''],['/api/auth/whatsapp/start','-1'],
            ['/api/auth/whatsapp/start','1000'],['/api/auth/whatsapp/start','99'],['/api/auth/whatsapp/start','date']] as [$path,$delay]) {
            $calls=0;$waits=0;
            $retry=new UatOwnerRequestRetry(function () use (&$waits): void { $waits++; });
            $response=$retry->send($path,function () use (&$calls,$delay) { $calls++;return new \Illuminate\Http\Client\Response(new \GuzzleHttp\Psr7\Response(429,['Retry-After'=>$delay])); },fn()=>null,microtime(true));
            $this->assertSame(429,$response->status());$this->assertSame(1,$calls);$this->assertSame(0,$waits);
        }
    }

    public function test_retry_cannot_exceed_the_original_probe_deadline(): void
    {
        Http::fakeSequence()->push([],429,['Retry-After'=>'2']);
        $retry=new UatOwnerRequestRetry(function (): void { $this->fail('Expired probe must not wait or send again.'); });
        $response=$retry->send('/api/auth/whatsapp/start',fn()=>Http::get('https://synthetic.invalid/otp'),fn()=>null,microtime(true)-479);
        $this->assertSame(429,$response->status());Http::assertSentCount(1);
    }

    public function test_no_fixed_actor_means_a_new_fixture_can_be_created_later(): void
    {
        $this->assertNull(app(UatOwnerFixtureRecovery::class)->find());$this->assertDatabaseCount('users',0);
    }

    public function test_foreign_phone_collision_is_never_reused_or_mutated(): void
    {
        $user=User::factory()->create(['phone'=>UatOwnerFixtureRecovery::PHONE,'email'=>'foreign@example.invalid']);
        $before=$user->fresh()->getAttributes();
        try { app(UatOwnerFixtureRecovery::class)->find();$this->fail('Unrelated fixture was accepted.'); }
        catch (RuntimeException $error) { $this->assertSame('fixture_collision',$error->getMessage()); }
        $this->assertSame($before,$user->fresh()->getAttributes());$this->assertDatabaseCount('users',1);
    }

    public function test_only_the_empty_audited_v1_actor_can_be_recovered_without_mutation(): void
    {
        $user=$this->fixture();$this->priorReceipt($user);
        $before=$user->fresh()->getAttributes();$found=app(UatOwnerFixtureRecovery::class)->find();
        $this->assertSame($user->id,$found->id);$this->assertSame($before,$user->fresh()->getAttributes());$this->assertDatabaseCount('users',1);
    }

    public function test_recovery_refuses_a_previously_used_account_or_a_completed_run(): void
    {
        $user=$this->fixture();$this->priorReceipt($user);
        app(ApiTokenService::class)->issue($user,Request::create('/synthetic','GET'));
        try { app(UatOwnerFixtureRecovery::class)->find();$this->fail('An active session must prevent fixture reuse.'); }
        catch (RuntimeException $error) { $this->assertSame('fixture_collision',$error->getMessage()); }
        $user->apiTokens()->delete();
        app(AuditLogService::class)->record(null,'uat.owner_acceptance.finished',null,
            ['release_run'=>UatOwnerFixtureRecovery::PREVIOUS,'result'=>['status'=>'passed','probe_sessions_revoked'=>true]]);
        $this->expectExceptionMessage('fixture_collision');app(UatOwnerFixtureRecovery::class)->find();
    }

    public function test_encrypted_capsule_parts_survive_real_audit_sanitization_and_database_roundtrip(): void
    {
        $cipher=random_bytes(4096);
        $parts=str_split(base64_encode($cipher),768);
        $row=app(AuditLogService::class)->record(null,'uat.owner_acceptance.finished',null,
            ['release_run'=>'synthetic-transport','result'=>['access_capsule_cms_base64_parts'=>$parts,'access_capsule_sha256'=>hash('sha256',$cipher)]]);
        $saved=$row->fresh()->metadata['result'];
        $this->assertGreaterThan(1,count($saved['access_capsule_cms_base64_parts']));
        $decoded=base64_decode(implode('',$saved['access_capsule_cms_base64_parts']),true);
        $this->assertSame($cipher,$decoded);$this->assertSame(hash('sha256',$decoded),$saved['access_capsule_sha256']);
    }

    private function fixture(): User
    {
        $user=User::factory()->create(['name'=>UatOwnerFixtureRecovery::NAME,'email'=>UatOwnerFixtureRecovery::EMAIL,
            'phone'=>UatOwnerFixtureRecovery::PHONE,'account_type'=>'regular','account_status'=>'active',
            'identity_policy_version'=>2,'phone_verified_at'=>now(),'profile_completed_at'=>now()]);
        $role=Role::where('key','registered_user')->firstOrFail();$user->roles()->attach($role->id,['created_at'=>now()]);return $user;
    }
    private function priorReceipt(User $user): void
    {
        app(AuditLogService::class)->record(null,'uat.owner_acceptance.fixture_created',$user,
            ['release_run'=>UatOwnerFixtureRecovery::PREVIOUS,'fixture'=>'erasure']);
        app(AuditLogService::class)->record(null,'uat.owner_acceptance.finished',null,
            ['release_run'=>UatOwnerFixtureRecovery::PREVIOUS,'result'=>['status'=>'incomplete','probe_sessions_revoked'=>true,
                'cases'=>[['case'=>'otp_start_reviewer','status'=>429,'passed'=>false]]]]);
    }
}
