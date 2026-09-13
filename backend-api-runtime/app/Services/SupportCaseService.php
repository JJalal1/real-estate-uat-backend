<?php
namespace App\Services;

use App\Models\SupportCase;
use App\Models\SupportCaseEvent;
use App\Models\SupportCaseMessage;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class SupportCaseService
{
    public const ACTIVE_STATUSES = ['open','in_progress','waiting_requester'];
    public const CLOSED_STATUSES = ['resolved','dismissed'];

    public function __construct(private readonly AuditLogService $audit, private readonly UserNotificationService $notifications, private readonly PlatformSettingsService $settings, private readonly SupportTaskService $tasks) {}

    public function create(
        User $requester,
        string $kind,
        string $subject,
        string $description,
        ?string $targetType,
        ?int $targetId,
        ?string $reasonCode,
        string $priority,
        Request $request,
    ): SupportCase {
        return DB::transaction(function () use ($requester,$kind,$subject,$description,$targetType,$targetId,$reasonCode,$priority,$request): SupportCase {
            $case=SupportCase::query()->create([
                'reference'=>$this->reference(),
                'kind'=>$kind,
                'requester_user_id'=>$requester->id,
                'requester_name_snapshot'=>$requester->name,
                'requester_email_snapshot'=>$requester->email,
                'subject'=>$subject,
                'description'=>$description,
                'target_type'=>$targetType,
                'target_id'=>$targetId,
                'reason_code'=>$reasonCode,
                'status'=>'open',
                'priority'=>$priority,
                'sla_due_at'=>now()->addHours((int)$this->settings->get('support.sla_hours',48)),
                'last_activity_at'=>now(),
            ]);
            $this->message($case,$requester,'requester',false,$description);
            $this->event($case,$requester,'created',null,'open',[
                'kind'=>$kind,'target_type'=>$targetType,'target_id'=>$targetId,'reason_code'=>$reasonCode,
            ]);
            $this->audit->record($requester,'support.case_created',$case,[
                'reference'=>$case->reference,'kind'=>$kind,'target_type'=>$targetType,'target_id'=>$targetId,
            ],$request,$requester->id);
            return $this->projected($case->fresh());
        });
    }

    public function requesterReply(User $requester, SupportCase $case, string $body, Request $request): SupportCase
    {
        if ((int)$case->requester_user_id !== (int)$requester->id) abort(404);
        if (in_array($case->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Closed support cases cannot receive new replies.');

        return DB::transaction(function () use ($requester,$case,$body,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $from=$locked->status;
            $this->message($locked,$requester,'requester',false,$body);
            $changes=['last_activity_at'=>now()];
            if ($locked->status === 'waiting_requester') {
                $changes['status']='in_progress';
                $changes['sla_due_at']=now()->addHours((int)$this->settings->get('support.sla_hours',48));
                $changes['escalated_at']=null;
                $changes['escalation_level']=0;
            }
            $locked->forceFill($changes)->save();
            $this->event($locked,$requester,'requester_replied',$from,$locked->status,['sla_due_at'=>$locked->sla_due_at?->toIso8601String()]);
            $this->audit->record($requester,'support.requester_replied',$locked,['reference'=>$locked->reference],$request,$requester->id);
            return $this->projected($locked->fresh());
        });
    }

    public function start(User $actor, SupportCase $case, Request $request): SupportCase
    {
        $this->assertOpen($case);
        return DB::transaction(function () use ($actor,$case,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $this->assertOpen($locked);
            $from=$locked->status;
            $locked->forceFill([
                'status'=>'in_progress',
                'assigned_to_user_id'=>$locked->assigned_to_user_id ?: $actor->id,
                'assigned_to_name_snapshot'=>$locked->assigned_to_user_id ? $locked->assigned_to_name_snapshot : $actor->name,
                'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'started',$from,'in_progress');
            $this->audit->record($actor,'support.case_started',$locked,['reference'=>$locked->reference],$request,$locked->requester_user_id);
            return $this->projected($locked->fresh());
        });
    }

    public function staffReply(User $actor, SupportCase $case, string $body, Request $request): SupportCase
    {
        $this->assertOpen($case);
        return DB::transaction(function () use ($actor,$case,$body,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $this->assertOpen($locked);
            $from=$locked->status;
            $this->message($locked,$actor,'staff',false,$body);
            $changes=[
                'status'=>$locked->status==='open'?'in_progress':$locked->status,
                'first_response_at'=>$locked->first_response_at ?: now(),
                'assigned_to_user_id'=>$locked->assigned_to_user_id ?: $actor->id,
                'assigned_to_name_snapshot'=>$locked->assigned_to_user_id ? $locked->assigned_to_name_snapshot : $actor->name,
                'last_activity_at'=>now(),
            ];
            $locked->forceFill($changes)->save();
            $this->event($locked,$actor,'staff_replied',$from,$locked->status);
            $this->audit->record($actor,'support.case_replied',$locked,['reference'=>$locked->reference],$request,$locked->requester_user_id);
            if($locked->requester_user_id){$this->notifications->create((int)$locked->requester_user_id,'support_reply','رد جديد من الدعم','لديك رد جديد في مركز الدعم.','support_case',$locked->id,['reference'=>$locked->reference]);}
            return $this->projected($locked->fresh());
        });
    }

    public function internalNote(User $actor, SupportCase $case, string $body, Request $request): SupportCase
    {
        return DB::transaction(function () use ($actor,$case,$body,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $this->message($locked,$actor,'staff',true,$body);
            $locked->forceFill(['last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'internal_note_added',$locked->status,$locked->status);
            $this->audit->record($actor,'support.internal_note_added',$locked,['reference'=>$locked->reference],$request,$locked->requester_user_id);
            return $this->projected($locked->fresh());
        });
    }

    public function setStatus(User $actor, SupportCase $case, string $status, Request $request): SupportCase
    {
        if (!in_array($status,['open','in_progress','waiting_requester','resolved','dismissed'],true)) abort(422,'Unsupported support status.');
        if (in_array($case->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Closed support cases cannot be reopened in Stage 10.');

        return DB::transaction(function () use ($actor,$case,$status,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            if (in_array($locked->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Closed support cases cannot be reopened in Stage 10.');
            $from=$locked->status;
            $changes=['status'=>$status,'last_activity_at'=>now()];
            if (in_array($status,self::CLOSED_STATUSES,true)) $changes['resolved_at']=now();
            if ($status === 'waiting_requester') $changes['resolved_at']=null;
            if ($status === 'in_progress' && $from === 'waiting_requester') {
                $changes['sla_due_at']=now()->addHours((int)$this->settings->get('support.sla_hours',48));
                $changes['escalated_at']=null;
                $changes['escalation_level']=0;
            }
            $locked->forceFill($changes)->save();
            $this->event($locked,$actor,'status_changed',$from,$status);
            $this->audit->record($actor,'support.status_changed',$locked,['from'=>$from,'to'=>$status,'reference'=>$locked->reference],$request,$locked->requester_user_id);
            if($locked->requester_user_id){$this->notifications->create((int)$locked->requester_user_id,'support_status','تم تحديث حالة الدعم','تم تحديث حالة طلب الدعم الخاص بك.','support_case',$locked->id,['status'=>$status,'reference'=>$locked->reference]);}
            return $this->projected($locked->fresh());
        });
    }


    public function reopen(User $actor, SupportCase $case, string $reason, Request $request): SupportCase
    {
        if (! in_array($case->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Only closed support cases can be reopened.');
        return DB::transaction(function()use($actor,$case,$reason,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            if (! in_array($locked->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Support case is no longer closed.');
            $from=$locked->status;
            $locked->forceFill([
                'status'=>'in_progress','resolved_at'=>null,'sla_due_at'=>now()->addHours((int)$this->settings->get('support.sla_hours',48)),
                'escalated_at'=>null,'escalation_level'=>0,'last_activity_at'=>now(),
            ])->save();
            $this->message($locked,$actor,'staff',true,'إعادة فتح الحالة: '.$reason);
            $this->event($locked,$actor,'reopened',$from,'in_progress',['reason'=>$reason]);
            $this->audit->record($actor,'support.case_reopened',$locked,['from'=>$from,'reason'=>$reason,'reference'=>$locked->reference],$request,$locked->requester_user_id);
            return $this->projected($locked->fresh());
        });
    }

    public function assign(User $actor, SupportCase $case, User $assignee, Request $request): SupportCase
    {
        if (!$assignee->hasPermission('support.handle_reports') && !$assignee->hasPermission('support.manage')) abort(422,'Assignee does not have support handling permission.');
        return DB::transaction(function () use ($actor,$case,$assignee,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $before=$locked->assigned_to_user_id;
            $locked->forceFill([
                'assigned_to_user_id'=>$assignee->id,
                'assigned_to_name_snapshot'=>$assignee->name,
                'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'assigned',$locked->status,$locked->status,['from_user_id'=>$before,'to_user_id'=>$assignee->id]);
            $this->audit->record($actor,'support.case_assigned',$locked,['from_user_id'=>$before,'to_user_id'=>$assignee->id,'reference'=>$locked->reference],$request,$locked->requester_user_id);
            return $this->projected($locked->fresh());
        });
    }

    public function escalate(User $actor, SupportCase $case, string $reason, Request $request): SupportCase
    {
        $this->assertOpen($case);
        return DB::transaction(function () use ($actor,$case,$reason,$request): SupportCase {
            $locked=SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            $this->assertOpen($locked);
            $from=$locked->status;
            $locked->forceFill([
                'escalated_at'=>$locked->escalated_at ?: now(),
                'escalation_level'=>max(1,(int)$locked->escalation_level+1),
                'priority'=>$locked->priority==='normal'?'high':$locked->priority,
                'last_activity_at'=>now(),
            ])->save();
            $this->message($locked,$actor,'staff',true,'تصعيد الحالة: '.$reason);
            $this->event($locked,$actor,'manual_escalated',$from,$locked->status,['reason'=>$reason,'level'=>$locked->escalation_level]);
            $this->audit->record($actor,'support.case_escalated',$locked,['reason'=>$reason,'level'=>$locked->escalation_level,'reference'=>$locked->reference],$request,$locked->requester_user_id);
            return $this->projected($locked->fresh());
        });
    }

    public function escalateOverdue(?Request $request=null): int
    {
        $ids=SupportCase::query()
            ->whereIn('status',['open','in_progress'])
            ->whereNull('escalated_at')
            ->where('sla_due_at','<=',now())
            ->orderBy('id')->pluck('id');
        $count=0;
        foreach($ids as $id){
            DB::transaction(function () use ($id,$request,&$count): void {
                $case=SupportCase::query()->lockForUpdate()->find($id);
                if(!$case || !in_array($case->status,['open','in_progress'],true) || $case->escalated_at || $case->sla_due_at?->isFuture()) return;
                $case->forceFill([
                    'escalated_at'=>now(),
                    'escalation_level'=>max(1,(int)$case->escalation_level+1),
                    'priority'=>$case->priority==='normal'?'high':$case->priority,
                    'last_activity_at'=>now(),
                ])->save();
                $this->tasks->projectSupportCase($case);
                $this->event($case,null,'sla_escalated',$case->status,$case->status,['sla_due_at'=>$case->sla_due_at?->toIso8601String(),'level'=>$case->escalation_level]);
                $this->audit->record(null,'support.sla_escalated',$case,['reference'=>$case->reference,'level'=>$case->escalation_level],$request,$case->requester_user_id);
                $count++;
            });
        }
        return $count;
    }

    private function projected(SupportCase $case): SupportCase
    {
        $this->tasks->projectSupportCase($case);
        return $case;
    }

    private function message(SupportCase $case, ?User $actor, string $role, bool $internal, string $body): SupportCaseMessage
    {
        return SupportCaseMessage::query()->create([
            'support_case_id'=>$case->id,
            'actor_user_id'=>$actor?->id,
            'actor_name_snapshot'=>$actor?->name,
            'actor_role'=>$role,
            'is_internal'=>$internal,
            'body'=>$body,
            'created_at'=>now(),
        ]);
    }

    private function event(SupportCase $case, ?User $actor, string $event, ?string $from, ?string $to, array $metadata=[]): SupportCaseEvent
    {
        return SupportCaseEvent::query()->create([
            'support_case_id'=>$case->id,
            'actor_user_id'=>$actor?->id,
            'actor_name_snapshot'=>$actor?->name,
            'event'=>$event,
            'from_status'=>$from,
            'to_status'=>$to,
            'metadata'=>$metadata ?: null,
            'created_at'=>now(),
        ]);
    }

    private function assertOpen(SupportCase $case): void
    {
        if (in_array($case->status,self::CLOSED_STATUSES,true)) throw new ConflictHttpException('Support case is closed.');
    }

    private function reference(): string
    {
        for($i=0;$i<8;$i++){
            $value='SUP-'.now()->format('ymd').'-'.Str::upper(Str::random(7));
            if(!SupportCase::query()->where('reference',$value)->exists()) return $value;
        }
        return 'SUP-'.Str::upper((string)Str::uuid());
    }
}
