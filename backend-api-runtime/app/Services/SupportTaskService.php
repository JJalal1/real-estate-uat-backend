<?php
namespace App\Services;

use App\Models\ListingReview;
use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportCaseEvent;
use App\Models\SupportTask;
use App\Models\SupportTaskEvent;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class SupportTaskService
{
    public const ACTIVE_STATUSES = [
        'new','in_progress','waiting_user','waiting_internal','needs_followup','escalated',
    ];

    public function __construct(
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
    ) {}

    public function syncSources(): void
    {
        if (!Schema::hasTable('support_tasks')) return;
        $this->syncAccountVerifications();
        $this->syncListings();
        $this->syncSupportCases();
    }

    public function queryFor(User $actor, array $filters): Builder
    {
        if (! $this->isSupportAgent($actor) && ! $this->isManager($actor)) abort(403);
        $this->syncSources();
        $query=SupportTask::query();
        $scope=(string)($filters['scope']??'inbox');

        if ($this->isSupportAgent($actor)) {
            $this->applyAgentTypePermissions($query,$actor);
            if ($scope==='mine') {
                $query->where('assigned_to_user_id',$actor->id);
            } else {
                $query->whereNull('assigned_to_user_id')->whereIn('status',self::ACTIVE_STATUSES);
            }
        } elseif ($scope==='mine') {
            $query->where('assigned_to_user_id',$actor->id);
        } elseif ($scope==='inbox') {
            $query->whereNull('assigned_to_user_id')->whereIn('status',self::ACTIVE_STATUSES);
        }

        if (!empty($filters['type'])) $query->where('source_type',$filters['type']);
        if (!empty($filters['status'])) $query->where('status',$filters['status']);
        if (!empty($filters['priority'])) $query->where('priority',$filters['priority']);
        if (!empty($filters['severity'])) $query->where('severity',$filters['severity']);
        if (!empty($filters['created_from'])) {
            $query->where('created_at','>=',Carbon::parse($filters['created_from'])->startOfDay());
        }
        if (!empty($filters['created_to'])) {
            $query->where('created_at','<=',Carbon::parse($filters['created_to'])->endOfDay());
        }
        if (!empty($filters['assignee_id']) && !$this->isSupportAgent($actor)) {
            $query->where('assigned_to_user_id',(int)$filters['assignee_id']);
        }
        if (($filters['overdue']??false)===true) {
            $query->whereIn('status',self::ACTIVE_STATUSES)
                ->whereNotNull('sla_due_at')->where('sla_due_at','<=',now());
        }

        return $query
            ->orderByRaw("CASE priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END")
            ->orderByRaw('CASE WHEN sla_due_at IS NULL THEN 1 ELSE 0 END')
            ->orderBy('sla_due_at')->orderBy('created_at');
    }

    public function claim(User $actor, SupportTask $task, Request $request): SupportTask
    {
        $this->assertCanHandleType($actor,$task->source_type);
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            if (!$locked->isActive()) throw new ConflictHttpException('هذه المهمة مغلقة ولا يمكن استلامها.');
            if ($locked->assigned_to_user_id && (int)$locked->assigned_to_user_id!==(int)$actor->id) {
                throw new ConflictHttpException('تم استلام هذه المهمة بواسطة موظف آخر.');
            }
            $this->claimSource($actor,$locked);
            $from=$locked->status;
            $locked->forceFill([
                'assigned_to_user_id'=>$actor->id,
                'assigned_to_name_snapshot'=>$actor->name,
                'claimed_at'=>$locked->claimed_at?:now(),
                'status'=>'in_progress',
                'waiting_since'=>null,
                'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'claimed',$from,'in_progress');
            $this->audit->record($actor,'support_task.claimed',$locked,[
                'source_type'=>$locked->source_type,'source_id'=>$locked->source_id,
            ],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function assign(User $actor, SupportTask $task, User $assignee, Request $request): SupportTask
    {
        $this->assertManager($actor);
        if (!$assignee->hasRole('support_agent') && !$assignee->hasRole('support_manager')) {
            throw ValidationException::withMessages(['user_id'=>['يمكن إسناد مهام الدعم إلى موظف دعم أو مدير دعم فقط.']]);
        }
        return DB::transaction(function()use($actor,$task,$assignee,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            $before=$locked->assigned_to_user_id;
            $this->assignSource($locked,$assignee);
            $from=$locked->status;
            $next=in_array($locked->status,['new','needs_followup'],true)?'in_progress':$locked->status;
            $locked->forceFill([
                'assigned_to_user_id'=>$assignee->id,
                'assigned_to_name_snapshot'=>$assignee->name,
                'claimed_at'=>$locked->claimed_at?:now(),
                'status'=>$next,
                'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'assigned',$from,$next,[
                'from_user_id'=>$before,'to_user_id'=>$assignee->id,
            ]);
            $this->audit->record($actor,'support_task.assigned',$locked,[
                'from_user_id'=>$before,'to_user_id'=>$assignee->id,
            ],$request,$locked->requester_user_id);
            $this->notifications->create(
                $assignee->id,'support_task_assigned','تم إسناد مهمة دعم إليك',
                $locked->subject,'support_task',$locked->id,
                ['task_id'=>$locked->id,'source_type'=>$locked->source_type]
            );
            return $locked->fresh();
        });
    }

    public function classify(User $actor, SupportTask $task, string $priority, ?string $severity, Request $request): SupportTask
    {
        $this->assertManager($actor);
        return DB::transaction(function()use($actor,$task,$priority,$severity,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $metadata=$locked->metadata??[];
            $metadata['manual_classification']=true;
            $locked->forceFill([
                'priority'=>$priority,'severity'=>$severity,
                'metadata'=>$metadata,'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'classification_changed',$locked->status,$locked->status,[
                'priority'=>$priority,'severity'=>$severity,
            ]);
            $this->audit->record($actor,'support_task.classification_changed',$locked,[
                'priority'=>$priority,'severity'=>$severity,
            ],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function setOperationalStatus(User $actor, SupportTask $task, string $status, Request $request): SupportTask
    {
        $this->assertTaskOwnership($actor,$task);
        if (!in_array($task->source_type,['support_ticket','report'],true)) {
            throw ValidationException::withMessages(['task'=>['الحالة التشغيلية متاحة للتذاكر والبلاغات فقط.']]);
        }
        if (!in_array($status,['in_progress','waiting_internal'],true)) {
            throw ValidationException::withMessages(['status'=>['حالة تشغيلية غير مدعومة.']]);
        }
        return DB::transaction(function()use($actor,$task,$status,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskOwnership($actor,$locked);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            if (!$locked->assigned_to_user_id) throw new ConflictHttpException('يجب استلام أو إسناد المهمة أولاً.');
            $from=$locked->status;
            $locked->forceFill([
                'status'=>$status,
                'waiting_since'=>$status==='waiting_internal'?now():null,
                'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'operational_status_changed',$from,$status);
            $this->audit->record($actor,'support_task.operational_status_changed',$locked,[
                'from'=>$from,'to'=>$status,
            ],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function escalate(User $actor, SupportTask $task, Request $request): SupportTask
    {
        $this->assertManager($actor);
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            $from=$locked->status;
            $locked->forceFill(['status'=>'escalated','priority'=>'urgent','last_activity_at'=>now()])->save();
            if (in_array($locked->source_type,['support_ticket','report'],true)) {
                $case=SupportCase::query()->lockForUpdate()->find($locked->source_id);
                if ($case) $case->forceFill([
                    'escalated_at'=>now(),
                    'escalation_level'=>max(1,(int)$case->escalation_level+1),
                    'priority'=>'urgent','last_activity_at'=>now(),
                ])->save();
            }
            $this->event($locked,$actor,'escalated',$from,'escalated');
            $this->audit->record($actor,'support_task.escalated',$locked,[],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function reopen(User $actor, SupportTask $task, Request $request): SupportTask
    {
        $this->assertManager($actor);
        if (!in_array($task->source_type,['support_ticket','report'],true)) {
            throw ValidationException::withMessages(['task'=>['إعادة الفتح متاحة حالياً للتذاكر والبلاغات فقط.']]);
        }
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $case=SupportCase::query()->lockForUpdate()->findOrFail($locked->source_id);
            $from=$locked->status;
            $case->forceFill([
                'status'=>'in_progress','resolved_at'=>null,
                'last_activity_at'=>now(),'sla_due_at'=>now()->addHours(48),
            ])->save();
            $locked->forceFill([
                'status'=>'in_progress','sla_due_at'=>$case->sla_due_at,'last_activity_at'=>now(),
            ])->save();
            SupportCaseEvent::query()->create([
                'support_case_id'=>$case->id,'actor_user_id'=>$actor->id,
                'actor_name_snapshot'=>$actor->name,'event'=>'reopened_by_support_manager',
                'from_status'=>$from,'to_status'=>'in_progress','metadata'=>null,'created_at'=>now(),
            ]);
            $this->event($locked,$actor,'reopened',$from,'in_progress');
            $this->audit->record($actor,'support_task.reopened',$locked,[],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function requestVerificationDocuments(User $actor, SupportTask $task, string $note, Request $request): SupportTask
    {
        $this->assertTaskOwnership($actor,$task);
        if ($task->source_type!=='account_verification') {
            throw ValidationException::withMessages(['task'=>['هذه العملية خاصة بطلبات تحقق الحسابات.']]);
        }
        return DB::transaction(function()use($actor,$task,$note,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskOwnership($actor,$locked);
            if (Schema::hasTable('account_verification_profiles')) {
                DB::table('account_verification_profiles')->where('user_id',$locked->source_id)
                    ->whereIn('status',['pending','needs_more_info'])
                    ->update(['status'=>'needs_more_info','updated_at'=>now()]);
            }
            $metadata=$locked->metadata??[];
            $metadata['requested_documents_note']=$note;
            $metadata['requested_documents_at']=now()->toIso8601String();
            $from=$locked->status;
            $locked->forceFill([
                'status'=>'waiting_user','waiting_since'=>now(),'sla_due_at'=>null,
                'metadata'=>$metadata,'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'documents_requested',$from,'waiting_user',['note'=>$note]);
            $this->audit->record($actor,'account_verification.documents_requested',$locked,['note'=>$note],$request,$locked->requester_user_id);
            if ($locked->requester_user_id) {
                $this->notifications->create(
                    (int)$locked->requester_user_id,
                    'account_verification_documents_requested','مطلوب مستند إضافي',$note,
                    'account_verification',$locked->source_id,['task_id'=>$locked->id]
                );
            }
            return $locked->fresh();
        });
    }

    public function rejectVerification(User $actor, SupportTask $task, string $reason, Request $request): SupportTask
    {
        $this->assertTaskOwnership($actor,$task);
        if ($task->source_type!=='account_verification') {
            throw ValidationException::withMessages(['task'=>['هذه العملية خاصة بطلبات تحقق الحسابات.']]);
        }
        return DB::transaction(function()use($actor,$task,$reason,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskOwnership($actor,$locked);
            if (Schema::hasTable('account_verification_profiles')) {
                DB::table('account_verification_profiles')->where('user_id',$locked->source_id)
                    ->update(['status'=>'rejected','updated_at'=>now()]);
            }
            $metadata=$locked->metadata??[];
            $metadata['rejection_reason']=$reason;
            $from=$locked->status;
            $locked->forceFill(['status'=>'rejected','metadata'=>$metadata,'last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'verification_rejected',$from,'rejected',['reason'=>$reason]);
            $this->audit->record($actor,'account_verification.rejected',$locked,['reason'=>$reason],$request,$locked->requester_user_id);
            if ($locked->requester_user_id) {
                $this->notifications->create(
                    (int)$locked->requester_user_id,'account_verification_rejected',
                    'تم رفض طلب التحقق',$reason,'account_verification',$locked->source_id,
                    ['task_id'=>$locked->id]
                );
            }
            return $locked->fresh();
        });
    }

    public function assertTaskOwnership(User $actor, SupportTask $task): void
    {
        if ($this->isManager($actor)) return;
        if ((int)($task->assigned_to_user_id??0)!==(int)$actor->id) {
            throw new ConflictHttpException('يجب استلام المهمة أولاً قبل تنفيذ هذا الإجراء.');
        }
    }

    public function teamMetrics(): array
    {
        $this->syncSources();
        return User::query()->whereHas('roles',fn($q)=>$q->whereIn('roles.key',['support_agent','support_manager']))
            ->orderBy('name')->get()->map(function(User $user):array{
                $tasks=SupportTask::query()->where('assigned_to_user_id',$user->id);
                $open=(clone $tasks)->whereIn('status',self::ACTIVE_STATUSES)->count();
                $closed=(clone $tasks)->whereIn('status',['completed','rejected'])->count();
                $overdue=(clone $tasks)->whereIn('status',self::ACTIVE_STATUSES)
                    ->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count();
                $urgent=(clone $tasks)->whereIn('status',self::ACTIVE_STATUSES)->where('priority','urgent')->count();
                $claimed=(clone $tasks)->whereNotNull('claimed_at')->latest('id')->limit(100)->get(['claimed_at','created_at']);
                $avg=$claimed->isEmpty()?null:(int)round($claimed->avg(fn(SupportTask $t)=>$t->created_at->diffInMinutes($t->claimed_at)));
                $responseAvg=$this->averageSupportResponseMinutes($user->id);
                return [
                    'id'=>$user->id,'name'=>$user->name,
                    'role'=>$user->hasRole('support_manager')?'support_manager':'support_agent',
                    'open_tasks'=>$open,'closed_tasks'=>$closed,
                    'overdue_tasks'=>$overdue,'urgent_tasks'=>$urgent,'average_claim_minutes'=>$avg,
                    'average_response_minutes'=>$responseAvg,
                    'tickets'=>(clone $tasks)->where('source_type','support_ticket')->count(),
                    'verifications'=>(clone $tasks)->where('source_type','account_verification')->count(),
                    'listing_reviews'=>(clone $tasks)->where('source_type','listing_review')->count(),
                    'reports'=>(clone $tasks)->where('source_type','report')->count(),
                    'last_activity_at'=>(clone $tasks)->max('last_activity_at'),
                ];
            })->values()->all();
    }

    public function dashboard(User $actor): array
    {
        $this->syncSources();
        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) return $this->platformDashboard();
        if ($this->isManager($actor)) return $this->managerDashboard();
        $this->assertAgent($actor);
        return $this->agentDashboard($actor);
    }

    public function taskData(SupportTask $task, User $actor): array
    {
        $remaining=$task->sla_due_at?now()->diffInMinutes($task->sla_due_at,false):null;
        return [
            'id'=>$task->id,'source_type'=>$task->source_type,'source_id'=>$task->source_id,
            'source_reference'=>$task->source_reference,'subject'=>$task->subject,
            'requester_user_id'=>$task->requester_user_id,'requester_name'=>$task->requester_name_snapshot,
            'status'=>$task->status,'priority'=>$task->priority,'severity'=>$task->severity,
            'assigned_to_user_id'=>$task->assigned_to_user_id,'assigned_to_name'=>$task->assigned_to_name_snapshot,
            'created_at'=>$task->created_at?->toIso8601String(),'claimed_at'=>$task->claimed_at?->toIso8601String(),
            'last_activity_at'=>$task->last_activity_at?->toIso8601String(),'sla_due_at'=>$task->sla_due_at?->toIso8601String(),
            'remaining_minutes'=>$remaining,'is_overdue'=>$remaining!==null&&$remaining<0,
            'is_mine'=>(int)($task->assigned_to_user_id??0)===(int)$actor->id,
            'can_claim'=>$task->isActive()&&!$task->assigned_to_user_id,'metadata'=>$task->metadata??[],
        ];
    }

    private function agentDashboard(User $actor): array
    {
        $base=SupportTask::query();$this->applyAgentTypePermissions($base,$actor);
        return [
            'mode'=>'agent',
            'inbox_new'=>(clone $base)->whereNull('assigned_to_user_id')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'my_tasks'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'account_verifications'=>(clone $base)->where('source_type','account_verification')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'listing_reviews'=>(clone $base)->where('source_type','listing_review')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'tickets'=>(clone $base)->where('source_type','support_ticket')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'reports'=>(clone $base)->where('source_type','report')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'waiting_user'=>(clone $base)->where('assigned_to_user_id',$actor->id)->where('status','waiting_user')->count(),
            'overdue'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)
                ->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'attention'=>$this->attentionQuery($base,$actor->id)->limit(8)->get()
                ->map(fn(SupportTask $t)=>$this->taskData($t,$actor))->values(),
        ];
    }

    private function managerDashboard(): array
    {
        $active=SupportTask::query()->whereIn('status',self::ACTIVE_STATUSES);
        $claimed=SupportTask::query()->whereNotNull('claimed_at')->latest('id')->limit(300)->get(['claimed_at','created_at']);
        $avg=$claimed->isEmpty()?null:(int)round($claimed->avg(fn(SupportTask $t)=>$t->created_at->diffInMinutes($t->claimed_at)));
        return [
            'mode'=>'manager',
            'unassigned'=>(clone $active)->whereNull('assigned_to_user_id')->count(),
            'in_progress'=>(clone $active)->whereNotNull('assigned_to_user_id')->whereIn('status',['in_progress','needs_followup'])->count(),
            'overdue'=>(clone $active)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'waiting_user'=>(clone $active)->where('status','waiting_user')->count(),
            'escalated'=>(clone $active)->where('status','escalated')->count(),
            'critical_reports'=>(clone $active)->where('source_type','report')->where('severity','critical')->count(),
            'active_agents'=>User::query()->whereHas('roles',fn($q)=>$q->where('roles.key','support_agent'))
                ->where('account_status',User::STATUS_ACTIVE)->count(),
            'average_claim_minutes'=>$avg,
            'average_response_minutes'=>$this->averageSupportResponseMinutes(),
        ];
    }

    private function platformDashboard(): array
    {
        $active=SupportTask::query()->whereIn('status',self::ACTIVE_STATUSES);
        $claimed=SupportTask::query()->whereNotNull('claimed_at')->latest('id')->limit(300)->get(['claimed_at','created_at']);
        $avg=$claimed->isEmpty()?null:(int)round($claimed->avg(fn(SupportTask $t)=>$t->created_at->diffInMinutes($t->claimed_at)));
        $today=now()->startOfDay();
        return [
            'mode'=>'platform','users'=>User::query()->count(),
            'pending_listing_reviews'=>Property::query()->whereIn('review_status',['submitted','under_review'])->count(),
            'pending_verifications'=>Schema::hasTable('account_verification_profiles')
                ?DB::table('account_verification_profiles')->whereIn('status',['pending','needs_more_info'])->count():0,
            'open_support_tasks'=>(clone $active)->count(),
            'critical_reports'=>(clone $active)->where('source_type','report')->where('severity','critical')->count(),
            'overdue'=>(clone $active)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'escalated'=>(clone $active)->where('status','escalated')->count(),
            'support_agents'=>User::query()->whereHas('roles',fn($q)=>$q->where('roles.key','support_agent'))
                ->where('account_status',User::STATUS_ACTIVE)->count(),
            'support_managers'=>User::query()->whereHas('roles',fn($q)=>$q->where('roles.key','support_manager'))
                ->where('account_status',User::STATUS_ACTIVE)->count(),
            'average_claim_minutes'=>$avg,
            'average_response_minutes'=>$this->averageSupportResponseMinutes(),
            'bookings'=>Schema::hasTable('viewing_bookings')?DB::table('viewing_bookings')->count():0,
            'regions'=>Schema::hasTable('governorates')?DB::table('governorates')->count():0,
            'service_orders'=>Schema::hasTable('service_orders')?DB::table('service_orders')->count():0,
            'today'=>[
                'new_users'=>User::query()->where('created_at','>=',$today)->count(),
                'listing_reviews'=>Property::query()->whereNotNull('submitted_at')->where('submitted_at','>=',$today)->count(),
                'verification_requests'=>Schema::hasTable('account_verification_profiles')
                    ?DB::table('account_verification_profiles')->where('created_at','>=',$today)->count():0,
                'new_support_tasks'=>SupportTask::query()->where('created_at','>=',$today)->count(),
                'critical_reports'=>SupportTask::query()->where('source_type','report')->where('severity','critical')
                    ->where('created_at','>=',$today)->count(),
            ],
        ];
    }

    private function syncAccountVerifications(): void
    {
        if (!Schema::hasTable('account_verification_profiles')) return;
        $rows=DB::table('account_verification_profiles')->orderByDesc('id')->limit(500)->get();
        if($rows->isEmpty())return;
        $userIds=$rows->pluck('user_id')->filter()->map(fn($id)=>(int)$id)->unique()->values();
        $users=User::query()->whereIn('id',$userIds)->get()->keyBy('id');
        $existingTasks=SupportTask::query()->where('source_type','account_verification')
            ->whereIn('source_id',$userIds)->get()->keyBy(fn(SupportTask $t)=>(int)$t->source_id);
        foreach($rows as $row){
            $user=$users->get((int)$row->user_id);if(!$user)continue;
            $existing=$existingTasks->get((int)$row->user_id);
            $sourceStatus=(string)($row->status??'pending');
            $updated=isset($row->updated_at)?Carbon::parse($row->updated_at):null;
            $followup=$existing?->status==='waiting_user' && $existing?->waiting_since && $updated && $updated->greaterThan($existing->waiting_since);
            $status=match(true){
                $sourceStatus==='approved'=>'completed',
                $sourceStatus==='rejected'=>'rejected',
                $followup=>'needs_followup',
                $sourceStatus==='needs_more_info'=>'waiting_user',
                default=>$existing?->assigned_to_user_id?'in_progress':'new',
            };
            $type=(string)($row->type??'account');
            $created=isset($row->created_at)?Carbon::parse($row->created_at):now();
            $sla=in_array($status,['waiting_user','completed','rejected'],true)
                ?null
                :($followup?now()->addHours(24):($existing?->sla_due_at?:$created->copy()->addHours(24)));
            $task=$this->upsertTask(
                'account_verification',(int)$row->user_id,'KYC-'.$row->user_id,
                'طلب تحقق '.match($type){'owner'=>'مالك','broker'=>'دلال','office'=>'مكتب عقارات',default=>'حساب'},
                $user,$status,'normal',null,$existing?->assigned_to_user_id,$existing?->assigned_to_name_snapshot,
                $sla,$updated,['verification_type'=>$type],false
            );
            $existingTasks->put((int)$row->user_id,$task);
        }
    }

    private function syncListings(): void
    {
        $properties=Property::query()->with('user')->whereNotNull('review_status')->latest('id')->limit(500)->get();
        if($properties->isEmpty())return;
        $ids=$properties->pluck('id')->map(fn($id)=>(int)$id)->values();
        $existingTasks=SupportTask::query()->where('source_type','listing_review')
            ->whereIn('source_id',$ids)->get()->keyBy(fn(SupportTask $t)=>(int)$t->source_id);
        $assigneeIds=$properties->pluck('review_assigned_to_user_id')->filter()->map(fn($id)=>(int)$id)->unique()->values();
        $assigneeNames=User::query()->whereIn('id',$assigneeIds)->pluck('name','id');
        foreach($properties as $property){
            $existing=$existingTasks->get((int)$property->id);
            $status=match($property->review_status){
                'approved'=>'completed','rejected_blocked'=>'rejected','returned_for_correction'=>'waiting_user',
                'under_review'=>'in_progress',
                'submitted'=>$existing?->status==='waiting_user'?'new':($property->review_assigned_to_user_id?'in_progress':'new'),
                default=>'completed',
            };
            $release=$property->review_status==='submitted'&&$existing?->status==='waiting_user';
            $submitted=$property->submitted_at?:$property->updated_at?:now();
            $assigneeId=$release?null:$property->review_assigned_to_user_id;
            $task=$this->upsertTask(
                'listing_review',$property->id,'LIST-'.$property->id,'تحقيق إعلان: '.$property->title,
                $property->user,$status,'normal',null,$assigneeId,
                $assigneeId?($assigneeNames[(int)$assigneeId]??null):null,
                in_array($status,['waiting_user','completed','rejected'],true)?null:$submitted->copy()->addHours(24),
                $property->updated_at,[
                    'review_status'=>$property->review_status,'price'=>$property->price,
                    'purpose'=>$property->purpose,'property_type'=>$property->type,
                ],$release||in_array($status,['waiting_user','completed','rejected'],true)
            );
            $existingTasks->put((int)$property->id,$task);
        }
    }

    private function syncSupportCases(): void
    {
        $cases=SupportCase::query()->latest('id')->limit(500)->get();
        if($cases->isEmpty())return;
        $caseIds=$cases->pluck('id')->map(fn($id)=>(int)$id)->values();
        $tasks=SupportTask::query()->whereIn('source_type',['support_ticket','report'])
            ->whereIn('source_id',$caseIds)->get();
        $existingByKey=$tasks->keyBy(fn(SupportTask $t)=>$t->source_type.':'.$t->source_id);
        $requesterIds=$cases->pluck('requester_user_id')->filter()->map(fn($id)=>(int)$id)->unique()->values();
        $requesters=User::query()->whereIn('id',$requesterIds)->get()->keyBy('id');
        foreach($cases as $case){
            $type=$case->kind==='report'?'report':'support_ticket';
            $existing=$existingByKey->get($type.':'.$case->id);
            $status=match($case->status){
                'resolved'=>'completed','dismissed'=>'rejected','waiting_requester'=>'waiting_user',
                'in_progress'=>$existing?->status==='waiting_user'?'needs_followup':
                    ($existing?->status==='waiting_internal'?'waiting_internal':'in_progress'),
                default=>$case->assigned_to_user_id?'in_progress':'new',
            };
            if($case->escalated_at&&!in_array($status,['completed','rejected','waiting_user'],true))$status='escalated';
            $priority=match($case->priority){'urgent','high'=>'urgent','low'=>'low',default=>'normal'};
            $severity=$case->kind==='report'?match($case->reason_code){
                'fraud','scam','impersonation','suspicious_documents','dangerous_content'=>'critical',
                'abuse','privacy'=>'high','spam','duplicate'=>'low',default=>'medium'
            }:null;
            if($severity==='critical')$priority='urgent';
            $task=$this->upsertTask(
                $type,$case->id,$case->reference,$case->subject,
                $case->requester_user_id?$requesters->get((int)$case->requester_user_id):null,
                $status,$priority,$severity,$case->assigned_to_user_id,$case->assigned_to_name_snapshot,
                $case->sla_due_at,$case->updated_at,[
                    'kind'=>$case->kind,'reason_code'=>$case->reason_code,
                    'target_type'=>$case->target_type,'target_id'=>$case->target_id,
                ],false
            );
            $existingByKey->put($type.':'.$case->id,$task);
            if($type==='report'&&$severity==='critical')$this->notifyCriticalReportManagers($task);
        }
    }

    private function upsertTask(
        string $sourceType,int $sourceId,?string $sourceReference,string $subject,?User $requester,
        string $status,string $priority,?string $severity,?int $assigneeId,?string $assigneeName,
        mixed $slaDueAt,mixed $sourceUpdatedAt,array $metadata,bool $releaseAssignment
    ): SupportTask {
        $task=SupportTask::query()->firstOrNew(['source_type'=>$sourceType,'source_id'=>$sourceId]);
        $isNew=!$task->exists;$oldStatus=$task->status;
        $current=$task->metadata??[];$manual=($current['manual_classification']??false)===true;
        $task->source_reference=$sourceReference;$task->subject=$subject;
        $task->requester_user_id=$requester?->id;$task->requester_name_snapshot=$requester?->name;
        $task->status=$status;
        if(!$manual){$task->priority=$priority;$task->severity=$severity;}
        if($releaseAssignment){
            $task->assigned_to_user_id=null;$task->assigned_to_name_snapshot=null;$task->claimed_at=null;
        }elseif($assigneeId){
            $task->assigned_to_user_id=$assigneeId;$task->assigned_to_name_snapshot=$assigneeName;
            $task->claimed_at=$task->claimed_at?:now();
        }
        if($status==='waiting_user'&&$oldStatus!=='waiting_user')$task->waiting_since=now();
        elseif($status!=='waiting_user')$task->waiting_since=null;
        $task->sla_due_at=$slaDueAt;$task->source_updated_at=$sourceUpdatedAt;
        $task->last_activity_at=$sourceUpdatedAt?:now();$task->metadata=array_merge($current,$metadata);$task->save();
        if($isNew)$this->event($task,null,'created_from_source',null,$status);
        elseif($oldStatus&&$oldStatus!==$status)$this->event($task,null,'source_status_synced',$oldStatus,$status);
        return $task;
    }

    private function claimSource(User $actor, SupportTask $task): void
    {
        if($task->source_type==='listing_review'){
            $property=Property::query()->lockForUpdate()->findOrFail($task->source_id);
            $assigned=(int)($property->review_assigned_to_user_id??0);
            if($assigned>0&&$assigned!==(int)$actor->id)throw new ConflictHttpException('تم استلام الإعلان بواسطة موظف آخر.');
            if(!in_array($property->review_status,['submitted','under_review'],true))throw new ConflictHttpException('الإعلان لم يعد في قائمة التحقيق.');
            $from=$property->review_status;
            $property->forceFill([
                'review_status'=>'under_review','status'=>'pending',
                'review_assigned_to_user_id'=>$actor->id,'review_assigned_at'=>$property->review_assigned_at?:now(),
            ])->save();
            if($from!=='under_review'){
                ListingReview::query()->create([
                    'listing_id'=>$property->id,'actor_user_id'=>$actor->id,'actor_name_snapshot'=>$actor->name,
                    'action'=>'review_started','from_review_status'=>$from,'to_review_status'=>'under_review',
                    'reason'=>null,'listing_snapshot'=>[
                        'id'=>$property->id,'title'=>$property->title,
                        'status'=>$property->status,'review_status'=>'under_review',
                    ],'metadata'=>['support_task_id'=>$task->id],'created_at'=>now(),
                ]);
            }
            return;
        }
        if(in_array($task->source_type,['support_ticket','report'],true)){
            $case=SupportCase::query()->lockForUpdate()->findOrFail($task->source_id);
            $assigned=(int)($case->assigned_to_user_id??0);
            if($assigned>0&&$assigned!==(int)$actor->id)throw new ConflictHttpException('تم استلام الحالة بواسطة موظف آخر.');
            $from=$case->status;
            $case->forceFill([
                'status'=>$case->status==='open'?'in_progress':$case->status,
                'assigned_to_user_id'=>$actor->id,'assigned_to_name_snapshot'=>$actor->name,
                'last_activity_at'=>now(),
            ])->save();
            SupportCaseEvent::query()->create([
                'support_case_id'=>$case->id,'actor_user_id'=>$actor->id,'actor_name_snapshot'=>$actor->name,
                'event'=>'claimed','from_status'=>$from,'to_status'=>$case->status,
                'metadata'=>['support_task_id'=>$task->id],'created_at'=>now(),
            ]);
        }
    }

    private function assignSource(SupportTask $task, User $assignee): void
    {
        if($task->source_type==='listing_review'){
            Property::query()->whereKey($task->source_id)->update([
                'review_status'=>'under_review','status'=>'pending',
                'review_assigned_to_user_id'=>$assignee->id,'review_assigned_at'=>now(),'updated_at'=>now(),
            ]);return;
        }
        if(in_array($task->source_type,['support_ticket','report'],true)){
            SupportCase::query()->whereKey($task->source_id)->update([
                'status'=>'in_progress','assigned_to_user_id'=>$assignee->id,
                'assigned_to_name_snapshot'=>$assignee->name,'last_activity_at'=>now(),'updated_at'=>now(),
            ]);
        }
    }

    private function attentionQuery(Builder $base, int $userId): Builder
    {
        return (clone $base)->where(function(Builder $q)use($userId):void{
            $q->where(function(Builder $mine)use($userId):void{
                $mine->where('assigned_to_user_id',$userId)->where(function(Builder $a):void{
                    $a->where('status','needs_followup')->orWhere('priority','urgent')
                      ->orWhere(fn(Builder $o)=>$o->whereNotNull('sla_due_at')->where('sla_due_at','<=',now()->addHours(2)));
                });
            })->orWhere(fn(Builder $inbox)=>$inbox->whereNull('assigned_to_user_id')->where('priority','urgent'));
        })->orderByRaw("CASE priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END")->orderBy('sla_due_at');
    }

    private function averageSupportResponseMinutes(?int $assigneeId=null): ?int
    {
        $query=SupportCase::query()->whereNotNull('first_response_at');
        if($assigneeId!==null)$query->where('assigned_to_user_id',$assigneeId);
        $rows=$query->latest('id')->limit(200)->get(['created_at','first_response_at']);
        if($rows->isEmpty())return null;
        return (int)round($rows->avg(fn(SupportCase $case)=>$case->created_at->diffInMinutes($case->first_response_at)));
    }

    private function notifyCriticalReportManagers(SupportTask $task): void
    {
        $metadata=$task->metadata??[];
        if(($metadata['critical_manager_notified']??false)===true)return;
        $managers=User::query()
            ->where('account_status',User::STATUS_ACTIVE)
            ->whereHas('roles',fn($q)=>$q->where('roles.key','support_manager'))
            ->get();
        foreach($managers as $manager){
            $this->notifications->create(
                $manager->id,'critical_support_report','بلاغ حرج يحتاج متابعة',
                $task->subject,'support_task',$task->id,
                ['task_id'=>$task->id,'source_id'=>$task->source_id,'severity'=>'critical']
            );
        }
        $metadata['critical_manager_notified']=true;
        $task->forceFill(['metadata'=>$metadata])->save();
    }

    private function applyAgentTypePermissions(Builder $query, User $actor): void
    {
        $types=[];
        if($actor->hasPermission('support.handle_reports'))$types=array_merge($types,['support_ticket','report','account_verification']);
        if($actor->hasPermission('listings.moderate'))$types[]='listing_review';
        $query->whereIn('source_type',array_values(array_unique($types?:['__none__'])));
    }

    private function assertCanHandleType(User $actor, string $type): void
    {
        if($this->isManager($actor))return;
        $this->assertAgent($actor);
        if($type==='listing_review'&&!$actor->hasPermission('listings.moderate'))abort(403);
        if(in_array($type,['support_ticket','report','account_verification'],true)
            &&!$actor->hasPermission('support.handle_reports'))abort(403);
    }

    private function assertAgent(User $actor): void
    {
        if(!$actor->hasRole('support_agent'))abort(403);
    }

    private function assertManager(User $actor): void
    {
        if(!$this->isManager($actor))abort(403);
    }

    private function isManager(User $actor): bool
    {
        return $actor->is_platform_owner||$actor->hasRole('super_admin')
            ||$actor->hasRole('support_manager')||$actor->hasPermission('support.manage');
    }

    private function isSupportAgent(User $actor): bool
    {
        return $actor->hasRole('support_agent')&&!$this->isManager($actor);
    }

    private function event(SupportTask $task, ?User $actor, string $event, ?string $from, ?string $to, array $metadata=[]): void
    {
        SupportTaskEvent::query()->create([
            'support_task_id'=>$task->id,'actor_user_id'=>$actor?->id,
            'actor_name_snapshot'=>$actor?->name,'event'=>$event,
            'from_status'=>$from,'to_status'=>$to,'metadata'=>$metadata?:null,'created_at'=>now(),
        ]);
    }
}
