<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatSupportCompletedInboxFlowApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_waiting_user_is_not_returned_as_unassigned_inbox_work(): void
    {
        [$agent,$headers]=$this->user('inbox-agent@example.test','+967744420001',['support_agent']);
        $task=SupportTask::query()->create([
            'source_type'=>'account_verification','source_id'=>999,'subject'=>'طلب تحقق مالك','status'=>'waiting_user','priority'=>'normal',
            'assigned_to_user_id'=>$agent->id,'assigned_to_name_snapshot'=>$agent->name,'last_activity_at'=>now(),
        ]);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=inbox')->assertOk()->assertJsonPath('meta.total',0);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=mine')->assertOk()->assertJsonPath('data.0.id',$task->id);
    }

    public function test_completed_scope_keeps_executor_and_listing_return_result(): void
    {
        [$agent,$headers]=$this->user('completed-agent@example.test','+967744420002',['support_agent']);
        $task=SupportTask::query()->create([
            'source_type'=>'listing_review','source_id'=>123,'subject'=>'تحقق نشر إعلان: شقة','status'=>'completed','priority'=>'normal',
            'assigned_to_user_id'=>$agent->id,'assigned_to_name_snapshot'=>$agent->name,'claimed_at'=>now()->subMinutes(5),'completed_at'=>now(),
            'last_activity_at'=>now(),'metadata'=>['review_status'=>'returned_for_correction','resolution'=>'returned_for_correction'],
        ]);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=completed')->assertOk()
            ->assertJsonPath('data.0.id',$task->id)->assertJsonPath('data.0.assigned_to_user_id',$agent->id)
            ->assertJsonPath('data.0.metadata.resolution','returned_for_correction');
    }

    public function test_manager_assignment_notification_mentions_my_tasks(): void
    {
        [$agent]=$this->user('assigned-agent@example.test','+967744420003',['support_agent']);
        [$manager,$managerHeaders]=$this->user('assigned-manager@example.test','+967744420004',['support_manager']);
        $fallback=\Illuminate\Support\Facades\DB::table('support_teams')->where('is_fallback',true)->value('id');
        \Illuminate\Support\Facades\DB::table('support_team_members')->updateOrInsert(['support_team_id'=>$fallback,'user_id'=>$agent->id],['member_role'=>'agent','is_available'=>true,'capacity'=>10,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        $task=SupportTask::query()->create(['source_type'=>'support_ticket','source_id'=>777,'subject'=>'تذكرة مسندة','status'=>'new','priority'=>'normal','support_team_id'=>$fallback,'last_activity_at'=>now()]);
        $this->withHeaders($managerHeaders)->putJson('/api/admin/workspace/tasks/'.$task->id.'/assign',['user_id'=>$agent->id])->assertOk()->assertJsonPath('data.assigned_to_user_id',$agent->id);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$agent->id,'type'=>'support_task_assigned','title'=>'قام مدير الدعم بإسناد مهمة لك']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Support Flow User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);$ids=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);
        $plain='sf_'.substr(hash('sha512',$email),0,80);$user->apiTokens()->create(['name'=>'support-flow-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
