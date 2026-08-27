<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\SupportCase;
use App\Models\User;
use App\Services\AccessControlService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatAdminSupportWorkspaceApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_dashboard_safe_settings_and_audit_are_available_without_exposing_secrets(): void
    {
        [$owner,$headers]=$this->user('workspace-owner@example.test','+967733330001');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);

        $catalog=$this->withHeaders($headers)->getJson('/api/admin/access/catalog')->assertOk();
        $this->assertSame('المدير العام', collect($catalog->json('data.roles'))->firstWhere('key','super_admin')['name_ar']);
        $this->assertSame('مشرف المحتوى', collect($catalog->json('data.roles'))->firstWhere('key','content_moderator')['name_ar']);

        $this->withHeaders($headers)->getJson('/api/admin/dashboard')
            ->assertOk()->assertJsonStructure(['data'=>['users','listings','support'=>['open','tickets_open','reports_open','overdue'],'bookings','alerts']]);

        \Illuminate\Support\Facades\DB::table('platform_settings')->insert([
            'key'=>'internal.api_secret','value'=>'must-not-leak','value_type'=>'string','group_key'=>'internal','label_ar'=>'سري',
            'is_public'=>false,'created_at'=>now(),'updated_at'=>now(),
        ]);
        $settings=$this->withHeaders($headers)->getJson('/api/admin/settings')->assertOk();
        $keys=collect($settings->json('data'))->pluck('key')->all();
        $this->assertContains('platform.name',$keys);
        $this->assertContains('listings.review_warning_hours',$keys);
        $this->assertContains('notifications.dashboard_alerts_enabled',$keys);
        $this->assertNotContains('internal.api_secret',$keys);
        foreach($keys as $key){
            $this->assertStringNotContainsString('password',$key);
            $this->assertStringNotContainsString('secret',$key);
            $this->assertStringNotContainsString('api_key',$key);
        }

        $this->withHeaders($headers)->patchJson('/api/admin/settings',[
            'settings'=>[['key'=>'platform.name','value'=>'منصة العقارات اليمنية']],
        ])->assertOk();
        $this->assertDatabaseHas('audit_logs',['actor_user_id'=>$owner->id,'action'=>'platform.settings_updated']);
    }

    public function test_general_manager_can_turn_a_regular_user_into_a_broker_and_back_by_role_assignment(): void
    {
        [$owner,$headers]=$this->user('workspace-owner-role@example.test','+967733330021');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        [$target]=$this->user('workspace-role-target@example.test','+967733330022');

        $this->assertSame(User::ACCOUNT_TYPE_REGULAR,$target->account_type);

        $this->withHeaders($headers)->putJson('/api/admin/access/users/'.$target->id.'/roles',[
            'role_keys'=>['broker'],
        ])->assertOk();

        $target=$target->fresh();
        $this->assertTrue($target->hasRole('broker'));
        $this->assertTrue($target->hasRole('registered_user'));
        $this->assertSame(User::ACCOUNT_TYPE_BROKER,$target->account_type);
        $this->assertSame(User::BROKER_VERIFICATION_NOT_SUBMITTED,$target->broker_verification_status);

        $this->withHeaders($headers)->putJson('/api/admin/access/users/'.$target->id.'/roles',[
            'role_keys'=>[],
        ])->assertOk();

        $target=$target->fresh();
        $this->assertFalse($target->hasRole('broker'));
        $this->assertTrue($target->hasRole('registered_user'));
        $this->assertSame(User::ACCOUNT_TYPE_REGULAR,$target->account_type);
        $this->assertSame(User::BROKER_VERIFICATION_NOT_REQUIRED,$target->broker_verification_status);
        $this->assertDatabaseHas('audit_logs',[
            'actor_user_id'=>$owner->id,
            'action'=>'access.roles_changed',
            'subject_id'=>$target->id,
        ]);
    }

    public function test_support_agent_can_work_cases_but_cannot_grant_roles_reassign_or_open_system_settings(): void
    {
        [$agent,$agentHeaders]=$this->user('workspace-agent@example.test','+967733330002',['support_agent']);
        [$target]=$this->user('workspace-target@example.test','+967733330003');
        [, $requesterHeaders]=$this->user('workspace-requester@example.test','+967733330004');
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',[
            'subject'=>'مشكلة في الحساب','description'=>'أحتاج مساعدة من فريق الدعم في هذه الحالة.','category'=>'account',
        ])->assertCreated()->json('data.id');

        $this->withHeaders($agentHeaders)->getJson('/api/admin/support/summary')->assertOk();
        $this->withHeaders($agentHeaders)->getJson('/api/admin/support/worklog')->assertOk();
        $this->withHeaders($agentHeaders)->getJson('/api/admin/support/users/'.$target->id)->assertOk();
        $this->withHeaders($agentHeaders)->postJson('/api/admin/support/cases/'.$caseId.'/escalate',['reason'=>'تحتاج صلاحية مدير الدعم لاتخاذ القرار النهائي.'])
            ->assertOk()->assertJsonPath('data.escalation_level',1);
        $this->assertDatabaseHas('audit_logs',['actor_user_id'=>$agent->id,'action'=>'support.case_escalated','subject_id'=>$caseId]);
        $this->withHeaders($agentHeaders)->putJson('/api/admin/support/cases/'.$caseId.'/assign',['user_id'=>$agent->id])->assertForbidden();
        $this->withHeaders($agentHeaders)->putJson('/api/admin/access/users/'.$target->id.'/roles',['role_keys'=>['support_manager']])->assertForbidden();
        $this->withHeaders($agentHeaders)->getJson('/api/admin/settings')->assertForbidden();
    }

    public function test_support_manager_can_assign_reopen_and_view_team_metrics(): void
    {
        [$manager,$managerHeaders]=$this->user('workspace-manager@example.test','+967733330005',['support_manager']);
        [$agent]=$this->user('workspace-agent2@example.test','+967733330006',['support_agent']);
        [, $requesterHeaders]=$this->user('workspace-requester2@example.test','+967733330007');
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',[
            'subject'=>'تذكرة للإسناد','description'=>'اختبار إسناد التذكرة وإعادة فتحها من مدير الدعم.','category'=>'technical',
        ])->assertCreated()->json('data.id');

        $this->withHeaders($managerHeaders)->putJson('/api/admin/support/cases/'.$caseId.'/assign',['user_id'=>$agent->id])
            ->assertOk()->assertJsonPath('data.assigned_to_user_id',$agent->id);
        $this->withHeaders($managerHeaders)->patchJson('/api/admin/support/cases/'.$caseId.'/status',['status'=>'resolved'])->assertOk();
        $this->withHeaders($managerHeaders)->postJson('/api/admin/support/cases/'.$caseId.'/reopen',['reason'=>'الحالة تحتاج متابعة إضافية.'])
            ->assertOk()->assertJsonPath('data.status','in_progress');
        $summary=$this->withHeaders($managerHeaders)->getJson('/api/admin/support/summary')->assertOk();
        $this->assertIsArray($summary->json('data.team'));
        $this->withHeaders($managerHeaders)->getJson('/api/admin/support/agents')->assertOk();
        $this->assertDatabaseHas('audit_logs',['actor_user_id'=>$manager->id,'action'=>'support.case_reopened','subject_id'=>$caseId]);
    }

    public function test_platform_admin_has_operational_permissions_but_not_role_granting_by_default(): void
    {
        [$admin,$adminHeaders]=$this->user('platform-admin@example.test','+967733330008',['platform_admin']);
        [$target]=$this->user('platform-target@example.test','+967733330009');
        $this->assertTrue($admin->fresh()->hasPermission('dashboard.view'));
        $this->assertTrue($admin->fresh()->hasPermission('users.view'));
        $this->assertFalse($admin->fresh()->hasPermission('users.manage_roles'));
        $this->withHeaders($adminHeaders)->getJson('/api/admin/dashboard')->assertOk();
        $this->withHeaders($adminHeaders)->putJson('/api/admin/access/users/'.$target->id.'/roles',['role_keys'=>['support_agent']])->assertForbidden();
    }

    public function test_listing_review_and_region_contracts_do_not_restore_main_broker_workflow(): void
    {
        [, $managerHeaders]=$this->user('workspace-content@example.test','+967733330010',['support_manager']);
        [$owner]=$this->user('workspace-listing-owner@example.test','+967733330011');
        $listing=Property::query()->create([
            'user_id'=>$owner->id,'title'=>'إعلان للمراجعة','description'=>'إعلان لا يعتمد على دلال رئيسي أو منطقة حصرية.',
            'purpose'=>'sale','type'=>'house','price'=>50000000,'currency'=>'YER','area_m2'=>200,'address'=>'صنعاء',
            'latitude'=>15.3694,'longitude'=>44.1910,'status'=>'pending_review','review_status'=>'submitted','submitted_at'=>now(),
        ]);
        $detail=$this->withHeaders($managerHeaders)->getJson('/api/admin/listing-review/listings/'.$listing->id)->assertOk();
        $detail->assertJsonPath('data.broker_verification.required', false)
            ->assertJsonPath('data.broker_verification.approval_allowed', true)
            ->assertJsonPath('data.broker_verification.reason', 'broker_region_verification_retired');
        $this->withHeaders($managerHeaders)->postJson('/api/admin/listing-review/listings/'.$listing->id.'/broker-verification/request')->assertNotFound();
        $this->withHeaders($managerHeaders)->getJson('/api/admin/regions/brokers')->assertNotFound();
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create([
            'name'=>'مستخدم اختبار ثلاثي','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!'),
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);
        foreach($roles as $key){
            $role=Role::query()->where('key',$key)->firstOrFail();
            $user->roles()->syncWithoutDetaching([$role->id=>['assigned_by_user_id'=>null,'created_at'=>now()]]);
        }
        $plain='re_admin_'.substr(hash('sha512',$email),0,72);
        $user->apiTokens()->create(['name'=>'admin-support-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
