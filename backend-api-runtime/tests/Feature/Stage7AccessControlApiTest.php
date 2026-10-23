<?php
namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Models\UserPermissionOverride;
use App\Services\AccessControlService;
use App\Services\AuditLogService;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class Stage7AccessControlApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_assigns_registered_user_and_me_exposes_access(): void
    {
        [$user,$headers]=$this->verifiedUser('registered@example.test','+967700000201');
        $this->assertTrue($user->fresh()->hasRole('registered_user'));
        $this->withHeaders($headers)->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.user.is_platform_owner',false)
            ->assertJsonPath('data.user.roles.0','registered_user');
    }

    public function test_registered_user_cannot_open_admin_access_endpoints(): void
    {
        [, $headers]=$this->verifiedUser('plain@example.test','+967700000202');
        $this->withHeaders($headers)->getJson('/api/admin/access/catalog')
            ->assertForbidden()->assertJsonPath('code','PERMISSION_DENIED');
    }

    public function test_permissions_manager_can_assign_broker_and_action_is_audited(): void
    {
        [$manager,$managerHeaders]=$this->verifiedUser('manager@example.test','+967700000203');
        $this->grantRole($manager,'permissions_manager');
        [$target]=$this->verifiedUser('broker-candidate@example.test','+967700000204');

        $this->withHeaders($managerHeaders)->putJson('/api/admin/access/users/'.$target->id.'/roles',[
            'role_keys'=>['registered_user','super_admin'],
        ])->assertUnprocessable();

        $this->withHeaders($managerHeaders)->putJson('/api/admin/access/users/'.$target->id.'/roles',[
            'role_keys'=>['registered_user','broker'],
        ])->assertOk()->assertJsonPath('data.user.roles.0','broker');

        $this->assertTrue($target->fresh()->hasRole('broker'));
        $this->assertDatabaseHas('audit_logs',[
            'actor_user_id'=>$manager->id,
            'target_user_id'=>$target->id,
            'action'=>'access.roles_changed',
        ]);
    }

    public function test_platform_owner_cannot_be_demoted_or_suspended_by_another_admin(): void
    {
        [$owner]=$this->verifiedUser('owner@example.test','+967700000205');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);

        [$manager,$headers]=$this->verifiedUser('manager2@example.test','+967700000206');
        $this->grantRole($manager,'permissions_manager');

        $this->withHeaders($headers)->putJson('/api/admin/access/users/'.$owner->id.'/roles',[
            'role_keys'=>['registered_user'],
        ])->assertUnprocessable();
        $this->withHeaders($headers)->patchJson('/api/admin/access/users/'.$owner->id.'/status',[
            'account_status'=>'suspended',
        ])->assertUnprocessable();

        $owner->refresh();
        $this->assertTrue($owner->is_platform_owner);
        $this->assertTrue($owner->hasRole('super_admin'));
        $this->assertSame(User::STATUS_ACTIVE,$owner->account_status);
    }

    public function test_direct_permission_deny_overrides_role_and_allow_can_grant_permission(): void
    {
        [$owner,$ownerHeaders]=$this->verifiedUser('owner2@example.test','+967700000207');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);

        [$target,$targetHeaders]=$this->verifiedUser('support@example.test','+967700000208');
        $this->grantRole($target,'support_manager');
        $this->withHeaders($targetHeaders)->getJson('/api/admin/access/audit-logs')->assertOk();

        $this->withHeaders($ownerHeaders)->putJson('/api/admin/access/users/'.$target->id.'/permission-overrides',[
            'overrides'=>[
                ['permission_key'=>'audit.view','effect'=>'deny','reason'=>'test deny'],
                ['permission_key'=>'users.manage_roles','effect'=>'allow','reason'=>'test allow'],
            ],
        ])->assertOk();

        $this->withHeaders($targetHeaders)->getJson('/api/admin/access/audit-logs')
            ->assertForbidden()->assertJsonPath('code','PERMISSION_DENIED');
        $this->assertTrue($target->fresh()->hasPermission('users.manage_roles'));
        $this->assertFalse($target->fresh()->hasPermission('audit.view'));
    }

    public function test_login_failure_and_listing_mutations_are_written_to_audit_log(): void
    {
        $this->postJson('/api/auth/login',['login'=>'missing@example.test','password'=>'wrong-password'])
            ->assertUnprocessable();
        $this->assertDatabaseHas('audit_logs',['action'=>'auth.login_failed']);

        [$user,$headers]=$this->verifiedUser('listing-audit@example.test','+967700000209');
        DB::table('account_verification_profiles')->insert([
            'user_id'=>$user->id,
            'type'=>'owner',
            'status'=>'approved',
            'details'=>json_encode([], JSON_THROW_ON_ERROR),
            'submitted_at'=>now(),
            'reviewed_at'=>now(),
            'created_at'=>now(),
            'updated_at'=>now(),
        ]);
        $created=$this->withHeaders($headers)->postJson('/api/properties',$this->listingPayload());
        $created->assertCreated();
        $id=(int)$created->json('data.id');
        $this->withHeaders($headers)->postJson('/api/properties/'.$id,['title'=>'Audit updated'])->assertOk();
        $this->withHeaders($headers)->deleteJson('/api/properties/'.$id)->assertOk();

        foreach(['listing.created','listing.updated','listing.deleted'] as $action){
            $this->assertDatabaseHas('audit_logs',['actor_user_id'=>$user->id,'action'=>$action,'subject_id'=>$id]);
        }
    }

    public function test_audit_metadata_sanitizer_removes_secret_bearing_keys_recursively(): void
    {
        $log=app(AuditLogService::class)->record(null,'test.sanitizer',null,[
            'password'=>'never-store-me',
            'plain_text_token'=>'never-store-me',
            'authorization_header'=>'never-store-me',
            'verification_code'=>'123456',
            'safe'=>'kept',
            'nested'=>['debug_code'=>'654321','reason'=>'kept too'],
        ]);
        $metadata=$log->fresh()->metadata;
        $this->assertSame('kept',$metadata['safe']);
        $this->assertSame('kept too',$metadata['nested']['reason']);
        $this->assertArrayNotHasKey('password',$metadata);
        $this->assertArrayNotHasKey('plain_text_token',$metadata);
        $this->assertArrayNotHasKey('authorization_header',$metadata);
        $this->assertArrayNotHasKey('verification_code',$metadata);
        $this->assertArrayNotHasKey('debug_code',$metadata['nested']);
    }

    public function test_audit_log_rows_are_immutable_even_through_query_builder(): void
    {
        $log=AuditLog::query()->create(['action'=>'test.immutable','created_at'=>now()]);
        try {
            DB::table('audit_logs')->where('id',$log->id)->update(['action'=>'tampered']);
            $this->fail('Audit update should have been blocked by database trigger.');
        } catch (QueryException) {
            $this->assertDatabaseHas('audit_logs',['id'=>$log->id,'action'=>'test.immutable']);
        }

        try {
            DB::table('audit_logs')->where('id',$log->id)->delete();
            $this->fail('Audit delete should have been blocked by database trigger.');
        } catch (QueryException) {
            $this->assertDatabaseHas('audit_logs',['id'=>$log->id,'action'=>'test.immutable']);
        }
    }


    public function test_database_allows_only_one_platform_owner_flag(): void
    {
        [$owner]=$this->verifiedUser('unique-owner@example.test','+967700000211');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);
        [$other]=$this->verifiedUser('other-owner@example.test','+967700000212');

        try {
            DB::table('users')->where('id',$other->id)->update(['is_platform_owner'=>true]);
            $this->fail('A second platform owner should have been blocked by the database constraint.');
        } catch (QueryException) {
            $this->assertSame(1,User::query()->where('is_platform_owner',true)->count());
            $this->assertTrue($owner->fresh()->is_platform_owner);
        }
    }

    public function test_platform_owner_account_cannot_be_deleted_by_model_or_query_builder(): void
    {
        [$owner]=$this->verifiedUser('protected-owner@example.test','+967700000210');
        app(AccessControlService::class)->bootstrapPlatformOwner($owner);

        try {
            $owner->delete();
            $this->fail('Platform owner deletion should have been blocked by the User model.');
        } catch (\LogicException) {
            $this->assertDatabaseHas('users',['id'=>$owner->id,'is_platform_owner'=>true]);
        }

        try {
            DB::table('users')->where('id',$owner->id)->delete();
            $this->fail('Platform owner deletion should have been blocked by database trigger.');
        } catch (QueryException) {
            $this->assertDatabaseHas('users',['id'=>$owner->id,'is_platform_owner'=>true]);
        }
    }

    public function test_system_roles_and_access_permissions_are_seeded(): void
    {
        $this->assertSame(9,Role::query()->count());
        foreach(['super_admin','platform_admin','permissions_manager','support_manager','support_agent','regions_manager','content_moderator','broker','registered_user'] as $key){
            $this->assertDatabaseHas('roles',['key'=>$key]);
        }
        foreach(['users.view','users.manage_status','users.manage_roles','users.manage_permissions','audit.view','regions.manage','brokers.manage','listings.moderate','support.handle_reports','conversations.review_private','dashboard.view','settings.view','settings.manage','support.reassign','support.escalate','support.reopen','support.view_team_metrics','support.view_worklog'] as $key){
            $this->assertTrue(Permission::query()->where('key',$key)->exists(),$key.' missing');
        }
    }

    private function verifiedUser(string $email,string $phone): array
    {
        $register=$this->postJson('/api/auth/register',[
            'name'=>'Stage Seven User','email'=>$email,'phone'=>$phone,
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
        ]);
        $register->assertCreated();
        $token=(string)$register->json('data.token');
        $headers=['Authorization'=>'Bearer '.$token,'Accept'=>'application/json'];
        $code=(string)$this->withHeaders($headers)->postJson('/api/auth/phone/request')->json('data.debug_code');
        $this->withHeaders($headers)->postJson('/api/auth/phone/verify',['code'=>$code])->assertOk();
        return [User::query()->where('email',$email)->firstOrFail(),$headers];
    }

    private function grantRole(User $user,string $roleKey): void
    {
        $role=Role::query()->where('key',$roleKey)->firstOrFail();
        $user->roles()->syncWithoutDetaching([$role->id=>['assigned_by_user_id'=>null,'created_at'=>now()]]);
    }

    private function listingPayload(): array
    {
        return [
            'title'=>'Stage 7 audit listing','description'=>'RBAC audit regression listing',
            'purpose'=>'sale','type'=>'house','price'=>50000000,'currency'=>'YER',
            'area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,'address'=>'Sanaa',
            'latitude'=>15.3694,'longitude'=>44.1910,
            'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ];
    }
}
