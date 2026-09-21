<?php
namespace Tests\Feature;

use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UatSupportManagerAgentWorkflowApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_new_support_case_reaches_shared_inbox_without_read_time_sync(): void
    {
        [, $requesterHeaders]=$this->user('direct-requester@example.test','+967744410001');
        [, $agentHeaders]=$this->user('direct-agent@example.test','+967744410002',['support_agent']);
        $case=$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'طلب يصل مباشرة','description'=>'يجب إنشاء مهمة الدعم فور إنشاء الطلب دون انتظار فتح الوارد.','category'=>'technical'])->assertCreated();
        $caseId=(int)$case->json('data.id');
        $this->assertDatabaseHas('support_tasks',['source_type'=>'support_ticket','source_id'=>$caseId,'status'=>'new']);
        $this->withHeaders($agentHeaders)->getJson('/api/admin/workspace/tasks?scope=inbox&type=support_ticket')->assertOk()->assertJsonPath('meta.total',1)->assertJsonPath('data.0.source_id',$caseId);
    }

    public function test_agent_escalates_owned_task_and_manager_resolves_without_becoming_approval_gate(): void
    {
        [, $requesterHeaders]=$this->user('escalate-requester@example.test','+967744410011');
        [$agent,$agentHeaders]=$this->user('escalate-agent@example.test','+967744410012',['support_agent']);
        [, $managerHeaders]=$this->user('escalate-manager@example.test','+967744410013',['support_manager']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'حالة غير اعتيادية','description'=>'حالة تحتاج قرار إداري استثنائي فقط.','category'=>'technical'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_type','support_ticket')->where('source_id',$caseId)->firstOrFail();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertOk()->assertJsonPath('data.assigned_to_user_id',$agent->id);
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/escalate",['reason'=>'تعارض يحتاج قرار مدير الدعم.'])->assertOk()->assertJsonPath('data.status','escalated');
        $this->withHeaders($managerHeaders)->getJson('/api/admin/workspace/dashboard')->assertOk()->assertJsonPath('data.escalated',1);
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/resolve-escalation",['note'=>'تمت مراجعة الاستثناء، أكمل الإجراء المعتاد.'])->assertOk()->assertJsonPath('data.status','in_progress')->assertJsonPath('data.assigned_to_user_id',$agent->id);
    }

    public function test_support_manager_must_explicitly_act_as_agent_before_claiming_work(): void
    {
        [, $requesterHeaders]=$this->user('mode-requester@example.test','+967744410021');
        [$manager,$managerHeaders]=$this->user('mode-manager@example.test','+967744410022',['support_manager']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'ضغط وارد','description'=>'مدير الدعم يساعد الفريق فقط عبر الوضع الواضح.','category'=>'other'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_id',$caseId)->where('source_type','support_ticket')->firstOrFail();
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertStatus(409);
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim",['acting_as_agent'=>true])->assertOk()->assertJsonPath('data.assigned_to_user_id',$manager->id);
        $this->assertDatabaseHas('support_task_events',['support_task_id'=>$task->id,'event'=>'claimed','actor_user_id'=>$manager->id]);
    }

    public function test_manager_controls_team_availability_capacity_and_can_return_work_to_inbox(): void
    {
        [, $requesterHeaders]=$this->user('team-requester@example.test','+967744410031');
        [$agent,$agentHeaders]=$this->user('team-agent@example.test','+967744410032',['support_agent']);
        [, $managerHeaders]=$this->user('team-manager@example.test','+967744410033',['support_manager']);
        $teams=$this->withHeaders($managerHeaders)->getJson('/api/admin/workspace/teams')->assertOk();$teamId=(int)$teams->json('data.0.id');
        $this->withHeaders($managerHeaders)->putJson("/api/admin/workspace/team/members/{$agent->id}",['team_id'=>$teamId,'is_available'=>false,'capacity'=>3])->assertOk();
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'مهمة للفريق','description'=>'اختبار حالة توفر الموظف والحد التشغيلي.','category'=>'other'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_id',$caseId)->where('source_type','support_ticket')->firstOrFail();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertStatus(409);
        $this->withHeaders($managerHeaders)->putJson("/api/admin/workspace/team/members/{$agent->id}",['team_id'=>$teamId,'is_available'=>true,'capacity'=>3])->assertOk();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertOk();
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/team/members/{$agent->id}/redistribute")->assertOk()->assertJsonPath('data.released_tasks',1);
        $this->assertDatabaseHas('support_tasks',['id'=>$task->id,'assigned_to_user_id'=>null,'status'=>'new']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Support Workflow User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);$ids=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);
        if(in_array('support_agent',$roles,true)){
            $roleId=Role::query()->where('key','support_agent')->value('id');
            $permissionIds=DB::table('permissions')->whereIn('key',['support.handle_reports','listings.moderate'])->pluck('id');
            foreach($permissionIds as $permissionId){DB::table('role_permission')->insertOrIgnore(['role_id'=>$roleId,'permission_id'=>$permissionId]);}
        }
        $plain='sw_'.substr(hash('sha512',$email),0,80);$user->apiTokens()->create(['name'=>'support-workflow-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}