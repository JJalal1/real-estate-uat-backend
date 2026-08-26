<?php
namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class Stage12DevelopmentsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_project_is_private_until_published_and_inactive_developer_hides_it(): void
    {
        [, $manager]=$this->user('s12-manager@example.test','+967740000001',['regions_manager']);
        [, $publisher]=$this->user('s12-publisher@example.test','+967740000002',['content_moderator']);
        $developerId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/developers',$this->developer('s12-dev-a'))->assertCreated()->json('data.id');
        $projectId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/projects',$this->project($developerId,'s12-project-a'))->assertCreated()->json('data.id');
        $this->getJson("/api/developments/$projectId")->assertNotFound();
        $this->withHeaders($publisher)->postJson("/api/admin/developments/projects/$projectId/publish")->assertUnprocessable();
        $this->withHeaders($manager)->postJson("/api/admin/developments/projects/$projectId/units",$this->unit('A-101'))->assertCreated();
        $this->withHeaders($publisher)->postJson("/api/admin/developments/projects/$projectId/publish")->assertOk()->assertJsonPath('data.status','published');
        $this->getJson("/api/developments/$projectId")->assertOk()->assertJsonPath('data.units.0.code','A-101');
        $this->withHeaders($manager)->patchJson("/api/admin/developments/developers/$developerId",$this->developer('s12-dev-a','inactive'))->assertOk();
        $this->getJson("/api/developments/$projectId")->assertNotFound();
    }

    public function test_manage_and_publish_permissions_are_separate_and_audited(): void
    {
        [, $manager]=$this->user('s12-manage@example.test','+967740000003',['regions_manager']);
        [, $publisher]=$this->user('s12-publish@example.test','+967740000004',['content_moderator']);
        $developerId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/developers',$this->developer('s12-dev-b'))->assertCreated()->json('data.id');
        $projectId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/projects',$this->project($developerId,'s12-project-b'))->assertCreated()->json('data.id');
        $this->withHeaders($manager)->postJson("/api/admin/developments/projects/$projectId/units",$this->unit('B-1'))->assertCreated();
        $this->withHeaders($manager)->postJson("/api/admin/developments/projects/$projectId/publish")->assertForbidden();
        $this->withHeaders($publisher)->getJson('/api/admin/developments/projects')->assertOk();
        $this->withHeaders($publisher)->postJson("/api/admin/developments/projects/$projectId/publish")->assertOk();
        $this->assertDatabaseHas('audit_logs',['action'=>'developments.project_published','subject_id'=>$projectId]);
        $this->assertTrue(User::query()->where('email','s12-manage@example.test')->firstOrFail()->hasPermission('developments.manage'));
        $this->assertFalse(User::query()->where('email','s12-manage@example.test')->firstOrFail()->hasPermission('developments.publish'));
        $this->assertTrue(User::query()->where('email','s12-publish@example.test')->firstOrFail()->hasPermission('developments.publish'));
    }

    public function test_unit_visibility_uniqueness_and_delete_safety(): void
    {
        [, $manager]=$this->user('s12-units@example.test','+967740000005',['regions_manager']);
        [, $publisher]=$this->user('s12-units-pub@example.test','+967740000006',['content_moderator']);
        $developerId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/developers',$this->developer('s12-dev-c'))->json('data.id');
        $projectId=(int)$this->withHeaders($manager)->postJson('/api/admin/developments/projects',$this->project($developerId,'s12-project-c'))->json('data.id');
        $unitId=(int)$this->withHeaders($manager)->postJson("/api/admin/developments/projects/$projectId/units",$this->unit('C-1'))->assertCreated()->json('data.id');
        $this->withHeaders($manager)->postJson("/api/admin/developments/projects/$projectId/units",$this->unit('C-1'))->assertUnprocessable();
        $this->withHeaders($publisher)->postJson("/api/admin/developments/projects/$projectId/publish")->assertOk();
        $hidden=$this->unit('C-1');$hidden['status']='hidden';
        $this->withHeaders($manager)->patchJson("/api/admin/developments/units/$unitId",$hidden)->assertOk();
        $this->getJson("/api/developments/$projectId")->assertOk()->assertJsonCount(0,'data.units');
        $reserved=$this->unit('C-1');$reserved['status']='reserved';
        $this->withHeaders($manager)->patchJson("/api/admin/developments/units/$unitId",$reserved)->assertOk();
        $this->withHeaders($manager)->deleteJson("/api/admin/developments/units/$unitId")->assertConflict();
    }

    public function test_stage12_schema_permissions_and_stage11_privacy_protection_exist(): void
    {
        foreach(['developers','developments','development_units','private_message_access_events'] as $table) $this->assertTrue(Schema::hasTable($table));
        $this->assertDatabaseHas('permissions',['key'=>'developments.manage']);
        $this->assertDatabaseHas('permissions',['key'=>'developments.publish']);
        $this->assertDatabaseHas('permissions',['key'=>'conversations.review_private']);
    }

    private function user(string $email,string $phone,array $roles): array
    {
        $user=User::query()->create(['name'=>'Stage 12 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        $sync=[];foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($sync);
        $plain='re12_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'stage12-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function developer(string $slug,string $status='active'): array
    {
        return ['name'=>'Stage 12 Developer '.$slug,'slug'=>$slug,'description'=>'Stage 12 developer test.','status'=>$status];
    }
    private function project(int $developerId,string $slug): array
    {
        return ['developer_id'=>$developerId,'name'=>'Stage 12 Project '.$slug,'slug'=>$slug,'description'=>'Stage 12 project test.','completion_status'=>'under_construction','address'=>'Stage 12 address'];
    }
    private function unit(string $code): array
    {
        return ['code'=>$code,'title'=>'Unit '.$code,'unit_type'=>'apartment','bedrooms'=>3,'bathrooms'=>2,'area_m2'=>145,'price'=>25000000,'currency'=>'YER','status'=>'available'];
    }
}
