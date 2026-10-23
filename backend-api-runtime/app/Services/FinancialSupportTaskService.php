<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyPayment;
use App\Models\SupportTask;
use App\Models\SupportTaskEvent;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class FinancialSupportTaskService
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
    ) {}

    public function projectPayment(PropertyPayment|int $payment): SupportTask
    {
        $payment=$payment instanceof PropertyPayment?$payment->fresh():PropertyPayment::query()->findOrFail($payment);
        $property=Property::query()->find($payment->property_id);
        $payer=User::query()->find($payment->payer_user_id);
        $existing=SupportTask::query()->where('source_type','payment_review')->where('source_id',$payment->id)->first();
        $status=match($payment->status){
            'proof_submitted'=>$existing?->status==='waiting_user'?'needs_followup':($existing?->assigned_to_user_id?'in_progress':'new'),
            'under_review'=>'in_progress',
            'correction_required'=>'waiting_user',
            'confirmed'=>'completed',
            'rejected','cancelled'=>'rejected',
            default=>'new',
        };
        $resolution=match($payment->status){
            'confirmed'=>'payment_confirmed','rejected'=>'payment_rejected','correction_required'=>'correction_requested','cancelled'=>'cancelled',default=>null,
        };
        $teamId=$existing?->support_team_id ?: DB::table('support_teams')->where('is_active',true)->orderByDesc('is_fallback')->value('id');
        $oldStatus=$existing?->status;
        $task=$existing?:new SupportTask();
        $task->forceFill([
            'source_type'=>'payment_review','source_id'=>$payment->id,'source_reference'=>$payment->reference,
            'subject'=>'تحقق دفع: '.($property?->title ?: $payment->reference),
            'requester_user_id'=>$payer?->id,'requester_name_snapshot'=>$payer?->name,
            'status'=>$status,'priority'=>'normal','severity'=>null,'support_team_id'=>$teamId,
            'sla_due_at'=>in_array($status,['completed','rejected','waiting_user'],true)?null:($existing?->sla_due_at?:now()->addHours(24)),
            'source_updated_at'=>$payment->updated_at,'last_activity_at'=>$payment->updated_at?:now(),
            'completed_at'=>in_array($status,['completed','rejected'],true)?($existing?->completed_at?:now()):null,
            'metadata'=>array_merge($existing?->metadata??[],[
                'payment_reference'=>$payment->reference,'payment_status'=>$payment->status,'resolution'=>$resolution,
                'amount'=>(float)$payment->required_amount,'currency'=>$payment->currency,'payment_method_id'=>$payment->payment_method_id,
                'property_id'=>$payment->property_id,'advertiser_user_id'=>$payment->advertiser_user_id,
            ]),
        ])->save();
        if(!$existing)$this->event($task,null,'created_from_payment',null,$status);
        elseif($oldStatus!==$status)$this->event($task,null,'payment_status_synced',$oldStatus,$status);
        return $task->fresh(['team','governorate']);
    }

    public function queryFor(User $actor,array $filters)
    {
        $isManager=$this->isManager($actor);$actingAsAgent=(bool)($filters['acting_as_agent']??false);
        if(!$isManager&&!$actor->hasRole('support_agent'))abort(403);
        if(!$isManager&&!$actor->hasPermission('payments.review'))return SupportTask::query()->whereRaw('1=0');
        if($isManager&&$actingAsAgent&&!$actor->hasPermission('payments.review')&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin'))return SupportTask::query()->whereRaw('1=0');

        $this->ensureSupportMembership($actor);
        $query=SupportTask::query()->with(['team:id,name_ar','governorate:id,name_ar'])->where('source_type','payment_review');
        if(!$actor->is_platform_owner&&!$actor->hasRole('super_admin')){
            $teamIds=DB::table('support_team_members')->where('user_id',$actor->id)->pluck('support_team_id');
            if($teamIds->isEmpty())return $query->whereRaw('1=0');
            $query->whereIn('support_team_id',$teamIds);
        }
        $scope=(string)($filters['scope']??'inbox');
        if(!$isManager||$actingAsAgent){
            if($scope==='mine')$query->where('assigned_to_user_id',$actor->id)->whereIn('status',SupportTaskService::ACTIVE_STATUSES);
            elseif($scope==='completed')$query->where('assigned_to_user_id',$actor->id)->whereIn('status',SupportTaskService::CLOSED_STATUSES);
            else $query->whereNull('assigned_to_user_id')->whereIn('status',SupportTaskService::INBOX_STATUSES);
        }elseif($scope==='mine')$query->where('assigned_to_user_id',$actor->id)->whereIn('status',SupportTaskService::ACTIVE_STATUSES);
        elseif($scope==='completed')$query->whereIn('status',SupportTaskService::CLOSED_STATUSES);
        elseif($scope==='inbox')$query->whereNull('assigned_to_user_id')->whereIn('status',SupportTaskService::INBOX_STATUSES);
        if(!empty($filters['status']))$query->where('status',$filters['status']);
        if(!empty($filters['priority']))$query->where('priority',$filters['priority']);
        if(!empty($filters['created_from']))$query->where('created_at','>=',$filters['created_from']);
        if(!empty($filters['created_to']))$query->where('created_at','<=',$filters['created_to']);
        if(!empty($filters['assignee_id'])&&$isManager&&!$actingAsAgent)$query->where('assigned_to_user_id',(int)$filters['assignee_id']);
        if(($filters['overdue']??false)===true)$query->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->whereIn('status',SupportTaskService::ACTIVE_STATUSES);
        return $query->orderByRaw("CASE priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END")->orderBy('sla_due_at')->orderBy('created_at');
    }

    public function claim(User $actor,SupportTask $task,Request $request,bool $actingAsAgent=false): SupportTask
    {
        $this->assertPaymentTask($task);$this->assertReviewer($actor,$actingAsAgent);$this->assertTeamScope($actor,$task);
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);$this->assertPaymentTask($locked);$this->assertTeamScope($actor,$locked);
            if(!$locked->isActive())throw new ConflictHttpException('هذه المهمة مغلقة.');
            if($locked->assigned_to_user_id&&(int)$locked->assigned_to_user_id!==(int)$actor->id)throw new ConflictHttpException('تم استلام هذه المهمة بواسطة موظف آخر.');
            $from=$locked->status;$locked->forceFill(['assigned_to_user_id'=>$actor->id,'assigned_to_name_snapshot'=>$actor->name,'claimed_at'=>$locked->claimed_at?:now(),'status'=>'in_progress','waiting_since'=>null,'last_activity_at'=>now()])->save();
            PropertyPayment::query()->whereKey($locked->source_id)->whereIn('status',['proof_submitted','under_review'])->update(['status'=>'under_review','updated_at'=>now()]);
            $this->event($locked,$actor,'claimed',$from,'in_progress');$this->audit->record($actor,'support_task.payment_claimed',$locked,[],$request,$locked->requester_user_id);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function assign(User $actor,SupportTask $task,User $assignee,Request $request): SupportTask
    {
        $this->assertPaymentTask($task);$this->assertManager($actor);$this->assertTeamScope($actor,$task);
        abort_unless($assignee->hasRole('support_agent')&&$assignee->hasPermission('payments.review'),422,'المهمة المالية تُسند لموظف دعم لديه صلاحية مراجعة المدفوعات.');
        $this->ensureSupportMembership($assignee);
        $member=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('user_id',$assignee->id)->where('is_available',true)->first();
        abort_unless($member,422,'الموظف غير متاح في فريق هذه المهمة.');
        return DB::transaction(function()use($actor,$task,$assignee,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);if(!$locked->isActive())throw new ConflictHttpException('المهمة مغلقة.');
            $from=$locked->status;$before=$locked->assigned_to_user_id;$locked->forceFill(['assigned_to_user_id'=>$assignee->id,'assigned_to_name_snapshot'=>$assignee->name,'claimed_at'=>$locked->claimed_at?:now(),'status'=>'in_progress','last_activity_at'=>now()])->save();
            PropertyPayment::query()->whereKey($locked->source_id)->whereIn('status',['proof_submitted','under_review'])->update(['status'=>'under_review','updated_at'=>now()]);
            $this->event($locked,$actor,'assigned',$from,'in_progress',['from_user_id'=>$before,'to_user_id'=>$assignee->id]);
            $this->audit->record($actor,'support_task.payment_assigned',$locked,['to_user_id'=>$assignee->id],$request,$locked->requester_user_id);
            $this->notifications->create($assignee->id,'support_task_assigned','قام مدير الدعم بإسناد مهمة لك','تمت إضافة «'.$locked->subject.'» إلى قائمة مهامك.','support_task',$locked->id,['task_id'=>$locked->id,'source_type'=>'payment_review','destination'=>'my_tasks']);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function release(User $actor,SupportTask $task,Request $request): SupportTask
    {
        $this->assertPaymentTask($task);$this->assertManager($actor);$this->assertTeamScope($actor,$task);
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);if(!$locked->isActive())throw new ConflictHttpException('المهمة مغلقة.');
            $from=$locked->status;$before=$locked->assigned_to_user_id;$locked->forceFill(['assigned_to_user_id'=>null,'assigned_to_name_snapshot'=>null,'claimed_at'=>null,'status'=>'new','last_activity_at'=>now()])->save();
            PropertyPayment::query()->whereKey($locked->source_id)->where('status','under_review')->update(['status'=>'proof_submitted','updated_at'=>now()]);
            $this->event($locked,$actor,'released_to_inbox',$from,'new',['from_user_id'=>$before]);$this->audit->record($actor,'support_task.payment_released',$locked,['from_user_id'=>$before],$request,$locked->requester_user_id);
            return $locked->fresh(['team','governorate']);
        });
    }

    private function assertReviewer(User $actor,bool $actingAsAgent): void
    {
        if($this->isManager($actor)){
            if(!$actingAsAgent&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin'))throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة مالية.');
            if(!$actor->hasPermission('payments.review')&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin'))abort(403);
            return;
        }
        abort_unless($actor->hasRole('support_agent')&&$actor->hasPermission('payments.review'),403);
    }

    private function ensureSupportMembership(User $actor): void
    {
        if(!Schema::hasTable('support_team_members')||!Schema::hasTable('support_teams'))return;
        $isManager=$actor->hasRole('support_manager');
        $isAgent=$actor->hasRole('support_agent');
        if(!$isManager&&!$isAgent)return;
        if(DB::table('support_team_members')->where('user_id',$actor->id)->exists())return;
        $fallbackId=DB::table('support_teams')->where('is_active',true)->where('is_fallback',true)->orderBy('id')->value('id');
        if(!$fallbackId)return;
        $role=$isManager?'manager':'agent';
        DB::table('support_team_members')->updateOrInsert(
            ['support_team_id'=>$fallbackId,'user_id'=>$actor->id],
            ['member_role'=>$role,'is_available'=>true,'capacity'=>10,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]
        );
        if($role==='manager'){
            DB::table('support_teams')->where('id',$fallbackId)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);
        }
    }

    private function assertManager(User $actor):void{abort_unless($this->isManager($actor),403);}
    private function isManager(User $actor):bool{return $actor->is_platform_owner||$actor->hasRole('super_admin')||$actor->hasRole('support_manager')||$actor->hasPermission('support.manage');}
    private function assertPaymentTask(SupportTask $task):void{abort_unless($task->source_type==='payment_review',422,'هذه ليست مهمة تحقق دفع.');}
    private function assertTeamScope(User $actor,SupportTask $task):void
    {
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;
        $this->ensureSupportMembership($actor);
        abort_unless(DB::table('support_team_members')->where('user_id',$actor->id)->where('support_team_id',$task->support_team_id)->exists(),403);
    }
    private function event(SupportTask $task,?User $actor,string $event,?string $from,?string $to,array $metadata=[]):void{SupportTaskEvent::query()->create(['support_task_id'=>$task->id,'actor_user_id'=>$actor?->id,'actor_name_snapshot'=>$actor?->name,'event'=>$event,'from_status'=>$from,'to_status'=>$to,'metadata'=>$metadata?:null,'created_at'=>now()]);}
}
