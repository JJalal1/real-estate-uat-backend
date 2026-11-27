<?php
namespace App\Services;

use App\Models\AdvertiserRating;
use App\Models\BrokerDealOutcome;
use App\Models\ListingComment;
use App\Models\ListingReview;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyPayment;
use App\Models\SupportCase;
use App\Models\SupportCaseEvent;
use App\Models\SupportTask;
use App\Models\SupportTaskEvent;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;
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

    public const INBOX_STATUSES = ['new','needs_followup'];
    public const CLOSED_STATUSES = ['completed','rejected'];
    public const WORKSPACE_BUCKETS = ['assigned', 'received', 'open_tickets', 'waiting_user', 'completed', 'unreceived_overdue'];
    public const CASE_CATEGORIES = ['support_ticket', 'report', 'support_question'];
    public const WORK_CATEGORIES = ['listing_review', 'support_ticket', 'report', 'support_question', 'payment_review', 'contact_followup'];

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
        // Payment tasks are projected immediately when proof is submitted.
    }

    public function queryFor(User $actor, array $filters): Builder
    {
        $actingAsAgent = (bool)($filters['acting_as_agent'] ?? false);
        $scope = (string)($filters['scope'] ?? 'inbox');
        $worker = $this->isSupportAgent($actor) || $actingAsAgent;
        $query = $this->visibleTaskQuery($actor, $actingAsAgent);
        if (!empty($filters['workspace_v2'])) $query->where('source_type', '!=', 'account_verification');
        $this->applyWorkspaceScope($query, $actor, $scope, $worker);

        if (!empty($filters['type'])) $query->where('source_type',$filters['type']);
        if (!empty($filters['category'])) {
            $this->filterCategory($query, $filters['category']);
        }
        if (!empty($filters['status'])) $query->where('status',$filters['status']);
        if (!empty($filters['priority'])) $query->where('priority',$filters['priority']);
        if (!empty($filters['severity'])) $query->where('severity',$filters['severity']);
        if (!empty($filters['created_from'])) $query->where('created_at','>=',Carbon::parse($filters['created_from'])->startOfDay());
        if (!empty($filters['created_to'])) $query->where('created_at','<=',Carbon::parse($filters['created_to'])->endOfDay());
        if (!empty($filters['assignee_id']) && !$this->isSupportAgent($actor) && !$actingAsAgent) {
            $query->where('assigned_to_user_id',(int)$filters['assignee_id']);
        }
        if (($filters['overdue']??false)===true) {
            if (!empty($filters['workspace_v2'])) {
                $this->filterUnreceivedOverdue($query);
            } else {
                $query->whereIn('status',self::ACTIVE_STATUSES)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now());
            }
        }

        return $query
            ->orderByRaw("CASE priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END")
            ->orderByRaw('CASE WHEN sla_due_at IS NULL THEN 1 ELSE 0 END')
            ->orderBy('sla_due_at')->orderBy('created_at')
            // Keep page boundaries stable when priority and timestamps are equal.
            ->orderBy('id');
    }

    private function applyWorkspaceScope(Builder $query, User $actor, string $scope, bool $worker): void
    {
        if ($scope === 'inbox' || ($scope === 'all' && $worker)) {
            $query->whereNull('assigned_to_user_id')->whereIn('status', self::INBOX_STATUSES);
            return;
        }
        if ($scope === 'unreceived_overdue') {
            $this->filterUnreceivedOverdue($query);
            if ($worker) {
                $query->where(fn(Builder $team) => $team->whereNull('assigned_to_user_id')->orWhere('assigned_to_user_id', $actor->id));
            }
            return;
        }
        if ($scope === 'all') return;

        if ($worker || in_array($scope, ['mine', 'assigned', 'received'], true)) {
            $query->where('assigned_to_user_id', $actor->id);
        }
        if ($scope === 'completed') {
            $query->whereIn('status', self::CLOSED_STATUSES);
            return;
        }

        $query->whereIn('status', self::ACTIVE_STATUSES);
        if ($scope === 'assigned' || $scope === 'received') {
            $this->filterAssignmentSource($query, $scope);
        }
        if ($scope === 'open_tickets') {
            $query->whereIn('source_type', ['support_ticket', 'report'])
                ->whereNotNull('claimed_at')->where('status', '!=', 'waiting_user');
        }
        if ($scope === 'waiting_user') $query->where('status', 'waiting_user');
    }

    private function filterUnreceivedOverdue(Builder $query): void
    {
        $query->whereNull('claimed_at')->where('created_at', '<=', now()->subHour())
            ->whereIn('status', [...self::INBOX_STATUSES, 'in_progress']);
    }

    private function assignmentHistory(): QueryBuilder
    {
        return DB::table('support_task_events')->select('event')
            ->whereColumn('support_task_id', 'support_tasks.id')
            ->whereIn('event', ['assigned', 'released_to_inbox'])
            ->orderByDesc('id')->limit(1);
    }

    private function filterAssignmentSource(Builder $query, string $source): void
    {
        if ($source === 'received') $query->whereNotNull('claimed_at');

        $query->where(function (Builder $assignment) use ($source): void {
            $assignment->where('metadata->assignment_source', $source)->orWhere(function (Builder $legacy) use ($source): void {
                $legacy->whereNull('metadata->assignment_source');
                if ($source === 'assigned') {
                    $legacy->where($this->assignmentHistory(), '=', 'assigned');
                } else {
                    $history = $this->assignmentHistory();
                    $legacy->whereRaw('coalesce(('.$history->toSql().'), ?) != ?', [
                        ...$history->getBindings(), '', 'assigned',
                    ]);
                }
            });
        });
    }

    private function filterCategory(Builder $query, string $category): void
    {
        $query->where(fn(Builder $byCategory) => $byCategory->where('metadata->work_category', $category)
            ->orWhere(fn(Builder $default) => $default->whereNull('metadata->work_category')->where('source_type', $category)));
    }

    public function messagesFor(User $actor, bool $actingAsAgent): Builder
    {
        return $this->visibleTaskQuery($actor, $actingAsAgent)
            ->where('assigned_to_user_id', $actor->id)
            ->whereNotNull('claimed_at')
            ->whereIn('source_type', ['support_ticket', 'report'])
            ->orderByDesc('last_activity_at')->orderByDesc('id');
    }

    public function taskFor(User $actor, int $taskId, bool $actingAsAgent): SupportTask
    {
        $query = $this->visibleTaskQuery($actor, $actingAsAgent);
        if ($this->isSupportAgent($actor) || $actingAsAgent) {
            $query->where(function (Builder $visible) use ($actor): void {
                $visible->where('assigned_to_user_id', $actor->id)
                    ->orWhere(function (Builder $inbox): void {
                        $inbox->whereNull('assigned_to_user_id')->whereIn('status', self::INBOX_STATUSES);
                    });
            });
        }

        return $query->findOrFail($taskId);
    }

    protected function visibleTaskQuery(User $actor, bool $actingAsAgent = false): Builder
    {
        abort_unless($this->isSupportAgent($actor) || $this->isManager($actor), 403);
        $this->ensureWorkspaceSeeded();
        $this->ensureSupportStaffMembership($actor);
        app(SupportTeamRoutingService::class)->refreshQueuedRouting();
        $query = SupportTask::query()->with(['team:id,name_ar', 'governorate:id,name_ar'])
            ->select('support_tasks.*')->addSelect(['legacy_assignment_event' => $this->assignmentHistory()]);
        $this->applyActorTeamScope($query, $actor, $actingAsAgent);
        if ($this->isSupportAgent($actor) || ($actingAsAgent && $actor->hasRole('support_agent'))) {
            $this->applyAgentTypePermissions($query, $actor);
        }

        return $query;
    }

    public function claim(User $actor, SupportTask $task, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->ensureSupportStaffMembership($actor);
        $this->assertCanHandleType($actor,$task->source_type,$actingAsAgent);
        $this->assertTaskInActorScope($actor,$task,$actingAsAgent);
        return DB::transaction(function()use($actor,$task,$request,$actingAsAgent):SupportTask{
            User::query()->lockForUpdate()->findOrFail($actor->id);
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskInActorScope($actor,$locked,$actingAsAgent);
            if (!$locked->isActive()) throw new ConflictHttpException('هذه المهمة مغلقة ولا يمكن استلامها.');
            if ($locked->status === 'escalated') throw new ConflictHttpException('هذه المهمة مصعّدة وتحتاج معالجة المدير قبل استئنافها.');
            if ($locked->assigned_to_user_id && (int)$locked->assigned_to_user_id!==(int)$actor->id) {
                throw new ConflictHttpException('تم استلام هذه المهمة بواسطة موظف آخر.');
            }
            if ($locked->claimed_at && (int)$locked->assigned_to_user_id === (int)$actor->id) {
                return $locked->load(['team','governorate']);
            }
            $this->assertClaimCapacity($actor,$locked,$actingAsAgent);
            $this->claimSource($actor,$locked);
            $from=$locked->status;
            $metadata=$locked->metadata??[];
            if ($actingAsAgent && $this->isManager($actor)) $metadata['manager_agent_mode']=true;
            $metadata['assignment_source'] ??= 'received';
            $locked->forceFill([
                'assigned_to_user_id'=>$actor->id,
                'assigned_to_name_snapshot'=>$actor->name,
                'claimed_at'=>$locked->claimed_at?:now(),
                'status'=>'in_progress','waiting_since'=>null,
                'last_activity_at'=>now(),'metadata'=>$metadata,
            ])->save();
            $this->event($locked,$actor,'claimed',$from,'in_progress',['acting_as_agent'=>$actingAsAgent]);
            $this->audit->record($actor,'support_task.claimed',$locked,[
                'source_type'=>$locked->source_type,'source_id'=>$locked->source_id,'acting_as_agent'=>$actingAsAgent,
            ],$request,$locked->requester_user_id);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function assign(User $actor, SupportTask $task, User $assignee, Request $request): SupportTask
    {
        $this->assertManager($actor);
        $this->assertTaskInActorScope($actor,$task);
        if (!$assignee->hasRole('support_agent')) {
            if (!($actor->is_platform_owner || $actor->hasRole('super_admin')) || !$assignee->hasRole('support_manager')) {
                throw ValidationException::withMessages(['user_id'=>['الإسناد الإداري يكون لموظف دعم. مدير الدعم يعمل على الطلبات عبر وضع «العمل كموظف دعم».']]);
            }
        }
        if ($task->source_type==='payment_review' && !$assignee->hasPermission('payments.review')) {
            throw ValidationException::withMessages(['user_id'=>['المهمة المالية تُسند لموظف دعم لديه صلاحية مراجعة المدفوعات.']]);
        }
        if ($assignee->hasRole('support_agent')) {
            $requiredPermission = $task->source_type === 'listing_review' ? 'listings.moderate' : 'support.handle_reports';
            if (!$assignee->hasPermission($requiredPermission)) {
                throw ValidationException::withMessages(['user_id'=>['الموظف غير مخوّل بمعالجة هذا النوع من المهام.']]);
            }
        }
        $this->assertAssigneeCanReceive($actor,$task,$assignee);
        return DB::transaction(function()use($actor,$task,$assignee,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskInActorScope($actor,$locked);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            $before=$locked->assigned_to_user_id;
            $this->assignSource($locked,$assignee);
            $from=$locked->status;
            $next=in_array($locked->status,['new','needs_followup'],true)?'in_progress':$locked->status;
            $metadata=$locked->metadata??[];
            if ((int)$before !== (int)$assignee->id) unset($metadata['manager_agent_mode']);
            $metadata['assignment_source']='assigned';
            $locked->forceFill([
                'assigned_to_user_id'=>$assignee->id,'assigned_to_name_snapshot'=>$assignee->name,
                'claimed_at'=>(int)$before===(int)$assignee->id?$locked->claimed_at:null,'status'=>$next,
                'last_activity_at'=>now(),'metadata'=>$metadata,
            ])->save();
            $this->event($locked,$actor,'assigned',$from,$next,['from_user_id'=>$before,'to_user_id'=>$assignee->id]);
            $this->audit->record($actor,'support_task.assigned',$locked,['from_user_id'=>$before,'to_user_id'=>$assignee->id],$request,$locked->requester_user_id);
            $this->notifications->create($assignee->id,'support_task_assigned','قام مدير الدعم بإسناد مهمة لك','تمت إضافة «'.$locked->subject.'» إلى قائمة مهامك.','support_task',$locked->id,['task_id'=>$locked->id,'source_type'=>$locked->source_type,'destination'=>'my_tasks']);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function classify(
        User $actor, SupportTask $task, ?string $priority, ?string $severity, Request $request,
        ?string $category = null, bool $actingAsAgent = false,
    ): SupportTask
    {
        $managing = $this->isManager($actor) && !$actingAsAgent;
        if (!$managing) {
            abort_if($priority !== null || $request->has('severity'), 403);
            $this->assertTaskExecution($actor, $task, $actingAsAgent);
        }

        return DB::transaction(function()use($actor,$task,$priority,$severity,$request,$category,$actingAsAgent,$managing):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            if ($managing) {
                $this->assertTaskInActorScope($actor, $locked);
            } else {
                $this->assertTaskExecution($actor, $locked, $actingAsAgent);
            }
            $metadata=$locked->metadata??[];
            if ($category !== null) {
                if (!$locked->isActive() || !in_array($locked->source_type, ['support_ticket', 'report'], true)) {
                    throw ValidationException::withMessages(['category' => ['التصنيف متاح للتذاكر والبلاغات المفتوحة.']]);
                }
                $metadata['work_category']=$category;
            }
            if ($priority !== null) $metadata['manual_classification']=true;
            $locked->forceFill([
                'priority'=>$priority ?? $locked->priority,
                'severity'=>$priority !== null || $request->has('severity') ? $severity : $locked->severity,
                'metadata'=>$metadata,'last_activity_at'=>now(),
            ])->save();
            $this->event($locked,$actor,'classification_changed',$locked->status,$locked->status,[
                'priority'=>$locked->priority,'severity'=>$locked->severity,'category'=>$category,
            ]);
            $this->audit->record($actor,'support_task.classification_changed',$locked,[
                'priority'=>$locked->priority,'severity'=>$locked->severity,'category'=>$category,
            ],$request,$locked->requester_user_id);
            return $locked->fresh();
        });
    }

    public function setOperationalStatus(User $actor, SupportTask $task, string $status, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->assertTaskExecution($actor,$task,$actingAsAgent);
        if (!in_array($task->source_type,['support_ticket','report'],true)) {
            throw ValidationException::withMessages(['task'=>['الحالة التشغيلية متاحة للتذاكر والبلاغات فقط.']]);
        }
        if (!in_array($status,['in_progress','waiting_internal'],true)) {
            throw ValidationException::withMessages(['status'=>['حالة تشغيلية غير مدعومة.']]);
        }
        return DB::transaction(function()use($actor,$task,$status,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskExecution($actor,$locked,$actingAsAgent);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            $from=$locked->status;
            $locked->forceFill(['status'=>$status,'waiting_since'=>$status==='waiting_internal'?now():null,'last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'operational_status_changed',$from,$status,['acting_as_agent'=>$actingAsAgent]);
            $this->audit->record($actor,'support_task.operational_status_changed',$locked,['from'=>$from,'to'=>$status,'acting_as_agent'=>$actingAsAgent],$request,$locked->requester_user_id);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function escalate(User $actor, SupportTask $task, string $reason, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->assertTaskExecution($actor,$task,$actingAsAgent);
        return DB::transaction(function()use($actor,$task,$reason,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskExecution($actor,$locked,$actingAsAgent);
            if (!$locked->isActive()) throw new ConflictHttpException('المهمة مغلقة.');
            if ($locked->status === 'escalated') throw new ConflictHttpException('المهمة مصعّدة بالفعل.');
            $from=$locked->status;
            $locked->forceFill([
                'status'=>'escalated','priority'=>'urgent','escalated_by_user_id'=>$actor->id,
                'escalated_at'=>now(),'escalation_reason'=>$reason,'last_activity_at'=>now(),
            ])->save();
            if (in_array($locked->source_type,['support_ticket','report'],true)) {
                $case=SupportCase::query()->lockForUpdate()->find($locked->source_id);
                if ($case) $case->forceFill(['escalated_at'=>now(),'escalation_level'=>max(1,(int)$case->escalation_level+1),'priority'=>'urgent','last_activity_at'=>now()])->save();
            }
            $this->event($locked,$actor,'escalated',$from,'escalated',['reason'=>$reason,'acting_as_agent'=>$actingAsAgent]);
            $this->audit->record($actor,'support_task.escalated',$locked,['reason'=>$reason,'acting_as_agent'=>$actingAsAgent],$request,$locked->requester_user_id);
            $this->notifyTaskManagers($locked,'مهمة دعم مصعّدة',$reason);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function reopen(User $actor, SupportTask $task, Request $request): SupportTask
    {
        $this->assertManager($actor);
        $this->assertTaskInActorScope($actor,$task);
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

    public function requestVerificationDocuments(User $actor, SupportTask $task, string $note, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->assertTaskExecution($actor,$task,$actingAsAgent);
        if ($task->source_type!=='account_verification') throw ValidationException::withMessages(['task'=>['هذه العملية خاصة بطلبات تحقق الحسابات.']]);
        return DB::transaction(function()use($actor,$task,$note,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskExecution($actor,$locked,$actingAsAgent);
            if (Schema::hasTable('account_verification_profiles')) {
                DB::table('account_verification_profiles')->where('user_id',$locked->source_id)->whereIn('status',['pending','needs_more_info'])->update(['status'=>'needs_more_info','updated_at'=>now()]);
            }
            $metadata=$locked->metadata??[];$metadata['requested_documents_note']=$note;$metadata['requested_documents_at']=now()->toIso8601String();
            $from=$locked->status;
            $locked->forceFill(['status'=>'waiting_user','waiting_since'=>now(),'sla_due_at'=>null,'metadata'=>$metadata,'last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'documents_requested',$from,'waiting_user',['note'=>$note,'acting_as_agent'=>$actingAsAgent]);
            $this->audit->record($actor,'account_verification.documents_requested',$locked,['note'=>$note,'acting_as_agent'=>$actingAsAgent],$request,$locked->requester_user_id);
            if ($locked->requester_user_id) $this->notifications->create((int)$locked->requester_user_id,'account_verification_documents_requested','مطلوب مستند إضافي',$note,'account_verification',$locked->source_id,['task_id'=>$locked->id]);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function rejectVerification(User $actor, SupportTask $task, string $reason, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->assertTaskExecution($actor,$task,$actingAsAgent);
        if ($task->source_type!=='account_verification') throw ValidationException::withMessages(['task'=>['هذه العملية خاصة بطلبات تحقق الحسابات.']]);
        return DB::transaction(function()use($actor,$task,$reason,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskExecution($actor,$locked,$actingAsAgent);
            if (Schema::hasTable('account_verification_profiles')) DB::table('account_verification_profiles')->where('user_id',$locked->source_id)->update(['status'=>'rejected','updated_at'=>now()]);
            $metadata=$locked->metadata??[];$metadata['rejection_reason']=$reason;$from=$locked->status;
            $locked->forceFill(['status'=>'rejected','metadata'=>$metadata,'completed_at'=>now(),'last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'verification_rejected',$from,'rejected',['reason'=>$reason,'acting_as_agent'=>$actingAsAgent]);
            $this->audit->record($actor,'account_verification.rejected',$locked,['reason'=>$reason,'acting_as_agent'=>$actingAsAgent],$request,$locked->requester_user_id);
            if ($locked->requester_user_id) $this->notifications->create((int)$locked->requester_user_id,'account_verification_rejected','تم رفض طلب التحقق',$reason,'account_verification',$locked->source_id,['task_id'=>$locked->id]);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function assertTaskOwnership(User $actor, SupportTask $task): void
    {
        if ($this->isManager($actor)) {
            $actingAsAgent = (int)$task->assigned_to_user_id === (int)$actor->id
                && !empty($task->metadata['manager_agent_mode']);
            $this->assertTaskInActorScope($actor,$task,$actingAsAgent);
            return;
        }
        $this->assertAgent($actor);
        $this->assertTaskInActorScope($actor,$task);
        if ((int)($task->assigned_to_user_id??0)!==(int)$actor->id || $task->isAwaitingAssignedReception()) throw new ConflictHttpException('يجب استلام المهمة أولاً قبل تنفيذ هذا الإجراء.');
    }

    public function assertTaskExecution(User $actor, SupportTask $task, bool $actingAsAgent=false): void
    {
        $this->assertTaskInActorScope($actor,$task,$actingAsAgent);
        if ($this->isManager($actor)) {
            if (!$actingAsAgent || (int)($task->assigned_to_user_id??0)!==(int)$actor->id || $task->isAwaitingAssignedReception()) {
                throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» واستلم المهمة قبل تنفيذ الإجراء.');
            }
            $this->assertCanHandleType($actor,$task->source_type,$actingAsAgent);
            return;
        }
        $this->assertCanHandleType($actor,$task->source_type,$actingAsAgent);
        if ((int)($task->assigned_to_user_id??0)!==(int)$actor->id || $task->isAwaitingAssignedReception()) throw new ConflictHttpException('يجب استلام المهمة أولاً قبل تنفيذ هذا الإجراء.');
    }

    public function teamMetrics(User $actor): array
    {
        $this->assertManager($actor);
        $this->ensureSupportStaffMemberships();
        $teamIds=$this->managedTeamIds($actor);
        if ($teamIds===[]) return [];
        $members=DB::table('support_team_members as m')
            ->join('users as u','u.id','=','m.user_id')
            ->join('support_teams as t','t.id','=','m.support_team_id')
            ->whereIn('m.support_team_id',$teamIds)->where('t.is_active',true)
            ->select('m.user_id','u.name','m.member_role','m.is_available','m.capacity','m.support_team_id','t.name_ar as team_name')
            ->orderBy('u.name')->get();
        $ids=$members->pluck('user_id')->map(fn($id)=>(int)$id)->unique()->values();
        $tasks=SupportTask::query()->whereIn('support_team_id',$teamIds)->whereIn('assigned_to_user_id',$ids)
            ->get(['assigned_to_user_id','source_type','status','priority','sla_due_at','claimed_at','completed_at','created_at','last_activity_at'])
            ->groupBy('assigned_to_user_id');
        $responses=SupportCase::query()->whereIn('assigned_to_user_id',$ids)->whereNotNull('first_response_at')
            ->latest('id')->limit(1000)->get(['assigned_to_user_id','created_at','first_response_at'])->groupBy('assigned_to_user_id');
        return $members->map(function($member)use($tasks,$responses):array{
            $rows=$tasks->get($member->user_id,collect());
            $active=$rows->whereIn('status',self::ACTIVE_STATUSES);
            $claims=$rows->filter(fn($t)=>$t->claimed_at!==null);
            $completed=$rows->filter(fn($t)=>$t->completed_at!==null);
            $responseRows=$responses->get($member->user_id,collect());
            $avgClaim=$claims->isEmpty()?null:(int)round($claims->avg(fn($t)=>Carbon::parse($t->created_at)->diffInMinutes(Carbon::parse($t->claimed_at))));
            $avgCompletion=$completed->isEmpty()?null:(int)round($completed->avg(fn($t)=>Carbon::parse($t->claimed_at?:$t->created_at)->diffInMinutes(Carbon::parse($t->completed_at))));
            $avgResponse=$responseRows->isEmpty()?null:(int)round($responseRows->avg(fn($c)=>Carbon::parse($c->created_at)->diffInMinutes(Carbon::parse($c->first_response_at))));
            $capacity=max(1,(int)$member->capacity);
            return [
                'id'=>(int)$member->user_id,'name'=>$member->name,'role'=>$member->member_role==='manager'?'support_manager':'support_agent',
                'team_id'=>(int)$member->support_team_id,'team_name'=>$member->team_name,'is_available'=>(bool)$member->is_available,'capacity'=>$capacity,
                'open_tasks'=>$active->count(),'closed_tasks'=>$rows->whereIn('status',['completed','rejected'])->count(),
                'completed_today'=>$rows->filter(fn($t)=>$t->completed_at&&Carbon::parse($t->completed_at)->isToday())->count(),
                'overdue_tasks'=>$active->filter(fn($t)=>$t->sla_due_at&&Carbon::parse($t->sla_due_at)->lte(now()))->count(),
                'urgent_tasks'=>$active->where('priority','urgent')->count(),'workload_percent'=>(int)round(min(100,$active->count()/$capacity*100)),
                'average_claim_minutes'=>$avgClaim,'average_response_minutes'=>$avgResponse,'average_completion_minutes'=>$avgCompletion,
                'tickets'=>$rows->where('source_type','support_ticket')->count(),'verifications'=>$rows->where('source_type','account_verification')->count(),
                'listing_reviews'=>$rows->where('source_type','listing_review')->count(),'reports'=>$rows->where('source_type','report')->count(),
                'last_activity_at'=>$rows->max('last_activity_at'),
            ];
        })->values()->all();
    }

    public function dashboard(User $actor, bool $actingAsAgent = false, bool $workspaceV2 = false): array
    {
        $this->ensureWorkspaceSeeded();
        $this->ensureSupportStaffMembership($actor);
        if ($actingAsAgent && $this->isManager($actor)) {
            $dashboard = $this->agentDashboard($actor, true, $workspaceV2);
        } elseif ($actor->is_platform_owner || $actor->hasRole('super_admin')) {
            $dashboard = $this->platformDashboard();
        } elseif ($this->isManager($actor)) {
            $dashboard = $this->managerDashboard($actor);
        } else {
            $this->assertAgent($actor);
            $dashboard = $this->agentDashboard($actor, false, $workspaceV2);
        }

        if (!$workspaceV2) return $dashboard;

        $base = $this->visibleTaskQuery($actor, $actingAsAgent)->where('source_type', '!=', 'account_verification');
        $worker = $this->isSupportAgent($actor) || $actingAsAgent;
        foreach (self::WORKSPACE_BUCKETS as $scope) {
            $query = clone $base;
            $this->applyWorkspaceScope($query, $actor, $scope, $worker);
            $dashboard[$scope] = $query->count();
        }
        $dashboard['governorate_ids'] = $this->governorateIds($actor, $actingAsAgent);
        $dashboard['governorate_codes'] = DB::table('governorates')
            ->whereIn('id', $dashboard['governorate_ids'])->pluck('code')->all();

        return $dashboard;
    }

    public function taskData(SupportTask $task, User $actor): array
    {
        $task->loadMissing(['team:id,name_ar','governorate:id,name_ar']);
        $remaining=$task->sla_due_at?now()->diffInMinutes($task->sla_due_at,false):null;
        $mine = (int)($task->assigned_to_user_id ?? 0) === (int)$actor->id;
        $pickupDue = !$task->claimed_at && in_array($task->status, [...self::INBOX_STATUSES, 'in_progress'], true)
            ? $task->created_at?->copy()->addHour() : null;
        $assignmentSource = null;
        if ($task->assigned_to_user_id) {
            $assignmentSource = $task->metadata['assignment_source'] ?? null;
            if ($assignmentSource === null) {
                $legacyEvent = array_key_exists('legacy_assignment_event', $task->getAttributes())
                    ? $task->legacy_assignment_event
                    : SupportTaskEvent::query()->where('support_task_id', $task->id)
                        ->whereIn('event', ['assigned', 'released_to_inbox'])->latest('id')->value('event');
                $assignmentSource = $legacyEvent === 'assigned' ? 'assigned' : ($task->claimed_at ? 'received' : null);
            }
        }
        return [
            'id'=>$task->id,'source_type'=>$task->source_type,'source_id'=>$task->source_id,'source_reference'=>$task->source_reference,'subject'=>$task->subject,
            'category'=>$task->metadata['work_category'] ?? $task->source_type, 'assignment_source'=>$assignmentSource,
            'requester_user_id'=>$task->requester_user_id,'requester_name'=>$task->requester_name_snapshot,'status'=>$task->status,'priority'=>$task->priority,'severity'=>$task->severity,
            'support_team_id'=>$task->support_team_id,'support_team_name'=>$task->team?->name_ar,'governorate_id'=>$task->governorate_id,'governorate_name'=>$task->governorate?->name_ar,
            'assigned_to_user_id'=>$task->assigned_to_user_id,'assigned_to_name'=>$task->assigned_to_name_snapshot,
            'created_at'=>$task->created_at?->toIso8601String(),'claimed_at'=>$task->claimed_at?->toIso8601String(),'completed_at'=>$task->completed_at?->toIso8601String(),
            'last_activity_at'=>$task->last_activity_at?->toIso8601String(),'sla_due_at'=>$task->sla_due_at?->toIso8601String(),
            'remaining_minutes'=>$remaining,'is_overdue'=>$remaining!==null&&$remaining<0,'is_mine'=>$mine,
            'pickup_due_at'=>$pickupDue?->toIso8601String(), 'is_unreceived_overdue'=>$pickupDue?->lte(now()) ?? false,
            'can_claim'=>$pickupDue !== null && (!$task->assigned_to_user_id || $mine),
            'escalated_at'=>$task->escalated_at?->toIso8601String(),'escalation_reason'=>$task->escalation_reason,
            'metadata'=>$task->metadata??[],
        ];
    }

    private function agentDashboard(User $actor, bool $actingAsAgent, bool $workspaceV2): array
    {
        $base=$this->visibleTaskQuery($actor, $actingAsAgent);
        if ($workspaceV2) $base->where('source_type', '!=', 'account_verification');
        return [
            'mode'=>'agent','inbox_new'=>(clone $base)->whereNull('assigned_to_user_id')->whereIn('status',self::INBOX_STATUSES)->count(),
            'my_tasks'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'account_verifications'=>(clone $base)->where('source_type','account_verification')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'listing_reviews'=>(clone $base)->where('source_type','listing_review')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'tickets'=>(clone $base)->where('source_type','support_ticket')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'reports'=>(clone $base)->where('source_type','report')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'contact_followups'=>(clone $base)->where('source_type','contact_followup')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'waiting_user'=>(clone $base)->where('assigned_to_user_id',$actor->id)->where('status','waiting_user')->count(),
            'overdue'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'attention'=>$this->attentionQuery($base,$actor->id)->limit(8)->get()->map(fn(SupportTask $t)=>$this->taskData($t,$actor))->values(),
        ];
    }

    private function managerDashboard(User $actor): array
    {
        $active=SupportTask::query()->whereIn('status',self::ACTIVE_STATUSES);$this->applyActorTeamScope($active,$actor);
        $claimed=SupportTask::query()->whereNotNull('claimed_at');$this->applyActorTeamScope($claimed,$actor);
        $claimed=$claimed->latest('id')->limit(300)->get(['claimed_at','created_at']);
        $avg=$claimed->isEmpty()?null:(int)round($claimed->avg(fn(SupportTask $t)=>$t->created_at->diffInMinutes($t->claimed_at)));
        $team=collect($this->teamMetrics($actor));
        return [
            'mode'=>'manager','unassigned'=>(clone $active)->whereNull('assigned_to_user_id')->whereIn('status',self::INBOX_STATUSES)->count(),
            'in_progress'=>(clone $active)->whereNotNull('assigned_to_user_id')->whereIn('status',['in_progress','needs_followup'])->count(),
            'overdue'=>(clone $active)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'waiting_user'=>(clone $active)->where('status','waiting_user')->count(),'escalated'=>(clone $active)->where('status','escalated')->count(),
            'contact_followups'=>(clone $active)->where('source_type','contact_followup')->count(),
            'critical_reports'=>(clone $active)->where('source_type','report')->where('severity','critical')->count(),
            'active_agents'=>$team->where('role','support_agent')->count(),'available_agents'=>$team->where('role','support_agent')->where('is_available',true)->count(),
            'team_open'=>$team->sum('open_tasks'),'completed_today'=>$team->sum('completed_today'),
            'average_claim_minutes'=>$avg,'average_response_minutes'=>$team->whereNotNull('average_response_minutes')->avg('average_response_minutes')===null?null:(int)round($team->whereNotNull('average_response_minutes')->avg('average_response_minutes')),
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
            'contact_followups'=>(clone $active)->where('source_type','contact_followup')->count(),
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
            $existingMeta=$existing?->metadata??[];
            $returnedCycle=$existing?->status==='completed'&&($existingMeta['resolution']??null)==='returned_for_correction';
            $status=match($property->review_status){
                'approved'=>'completed','rejected_blocked','rejected_duplicate'=>'rejected','returned_for_correction'=>'completed',
                'under_review'=>'in_progress',
                'submitted'=>$returnedCycle?'needs_followup':($property->review_assigned_to_user_id?'in_progress':'new'),
                default=>'completed',
            };
            $release=$property->review_status==='submitted'&&$returnedCycle;
            $closed=in_array($status,self::CLOSED_STATUSES,true);
            $submitted=$property->submitted_at?:$property->updated_at?:now();
            $assigneeId=$release?null:($property->review_assigned_to_user_id?:($closed?$existing?->assigned_to_user_id:null));
            $assigneeName=$assigneeId
                ?($existing?->assigned_to_user_id===$assigneeId?$existing?->assigned_to_name_snapshot:($assigneeNames[(int)$assigneeId]??null))
                :null;
            $resolution=match($property->review_status){
                'approved'=>'approved','rejected_blocked'=>'rejected','rejected_duplicate'=>'rejected_duplicate','returned_for_correction'=>'returned_for_correction',default=>null,
            };
            $task=$this->upsertTask(
                'listing_review',$property->id,'LIST-'.$property->id,'تحقق نشر إعلان: '.$property->title,
                $property->user,$status,'normal',null,$assigneeId,$assigneeName,
                $closed?null:$submitted->copy()->addHours(24),
                $property->updated_at,[
                    'review_status'=>$property->review_status,'resolution'=>$resolution,
                    'review_reason'=>$property->last_review_reason,'price'=>$property->price,
                    'purpose'=>$property->purpose,'property_type'=>$property->type,
                ],$release||$closed
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
            unset($current['assignment_source'], $current['manager_agent_mode']);
        }elseif($assigneeId){
            $task->assigned_to_user_id=$assigneeId;$task->assigned_to_name_snapshot=$assigneeName;
            if (!$task->isAwaitingAssignedReception()) $task->claimed_at=$task->claimed_at?:now();
        }
        if($status==='waiting_user'&&$oldStatus!=='waiting_user')$task->waiting_since=now();
        elseif($status!=='waiting_user')$task->waiting_since=null;
        $task->sla_due_at=$slaDueAt;$task->source_updated_at=$sourceUpdatedAt;
        $task->last_activity_at=$sourceUpdatedAt?:now();$task->metadata=array_merge($current,$metadata);
        if (Schema::hasColumn('support_tasks','completed_at')) $task->completed_at=in_array($status,['completed','rejected'],true)?($task->completed_at?:now()):null;
        $task->save();
        if($isNew)$this->event($task,null,'created_from_source',null,$status);
        elseif($oldStatus&&$oldStatus!==$status)$this->event($task,null,'source_status_synced',$oldStatus,$status);
        if (Schema::hasColumn('support_tasks','support_team_id')) $task=$this->routeTask($task,$this->governorateIdFromMetadata($task->metadata??[]));
        return $task;
    }

    private function claimSource(User $actor, SupportTask $task): void
    {
        if($task->source_type==='payment_review'){
            $payment=PropertyPayment::query()->lockForUpdate()->findOrFail($task->source_id);
            if(!in_array($payment->status,['proof_submitted','under_review'],true))throw new ConflictHttpException('إثبات الدفع لم يعد بانتظار التحقق.');
            if($payment->status!=='under_review')$payment->forceFill(['status'=>'under_review'])->save();
            return;
        }
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
        if($task->source_type==='payment_review'){
            PropertyPayment::query()->whereKey($task->source_id)->whereIn('status',['proof_submitted','under_review'])->update(['status'=>'under_review','updated_at'=>now()]);
            return;
        }
        if($task->source_type==='listing_review'){

            Property::query()->whereKey($task->source_id)->update([
                'review_status'=>'under_review','status'=>'pending',
                'review_assigned_to_user_id'=>$assignee->id,'review_assigned_at'=>now(),'updated_at'=>now(),
            ]);return;
        }
        if(in_array($task->source_type,['support_ticket','report'],true)){
            $case=SupportCase::query()->find($task->source_id);
            SupportCase::query()->whereKey($task->source_id)->update([
                'status'=>$case?->status==='open'?'in_progress':($case?->status??'in_progress'),'assigned_to_user_id'=>$assignee->id,
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
        if($actor->hasPermission('support.handle_reports'))$types=array_merge($types,['support_ticket','report','account_verification','contact_followup']);
        if($actor->hasPermission('listings.moderate'))$types[]='listing_review';
        if($actor->hasPermission('payments.review'))$types[]='payment_review';
        $query->whereIn('source_type',array_values(array_unique($types?:['__none__'])));
    }

    private function assertCanHandleType(User $actor, string $type, bool $actingAsAgent=false): void
    {
        if($this->isManager($actor)){
            if(!$actingAsAgent) throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة بنفسك.');
            if (!$actor->hasRole('support_agent')) return;
        }
        $this->assertAgent($actor);
        if($type==='listing_review'&&!$actor->hasPermission('listings.moderate'))abort(403);
        if($type==='payment_review'&&!$actor->hasPermission('payments.review'))abort(403);
        if(in_array($type,['support_ticket','report','account_verification','contact_followup'],true)&&!$actor->hasPermission('support.handle_reports'))abort(403);
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

    public function projectPayment(PropertyPayment|int $payment): SupportTask
    {
        return app(FinancialSupportTaskService::class)->projectPayment($payment);
    }

    public function projectSource(string $type, int $sourceId): ?SupportTask
    {
        return match($type) {
            'account_verification' => $this->projectAccountVerification($sourceId),
            'listing_review' => $this->projectListing($sourceId),
            'support_ticket', 'report' => $this->projectSupportCase($sourceId),
            'payment_review' => $this->projectPayment($sourceId),
            'contact_followup' => $this->projectContactFollowup($sourceId),
            default => null,
        };
    }

    public function projectAccountVerification(int $userId): ?SupportTask
    {
        if (!Schema::hasTable('account_verification_profiles')) return null;
        $row=DB::table('account_verification_profiles')->where('user_id',$userId)->first();
        $user=User::query()->find($userId);
        if(!$row||!$user)return null;
        $existing=SupportTask::query()->where('source_type','account_verification')->where('source_id',$userId)->first();
        $sourceStatus=(string)($row->status??'pending');$updated=isset($row->updated_at)?Carbon::parse($row->updated_at):now();
        $followup=$existing?->status==='waiting_user'&&$existing?->waiting_since&&$updated->greaterThan($existing->waiting_since);
        $status=match(true){$sourceStatus==='approved'=>'completed',$sourceStatus==='rejected'=>'rejected',$followup=>'needs_followup',$sourceStatus==='needs_more_info'=>'waiting_user',default=>$existing?->assigned_to_user_id?'in_progress':'new'};
        $details=$this->jsonMap($row->details??null);$type=(string)($row->type??'account');$created=isset($row->created_at)?Carbon::parse($row->created_at):now();
        $govId=$this->resolveGovernorateIdFromName($details['governorate']??null);
        $sla=in_array($status,['waiting_user','completed','rejected'],true)?null:($followup?now()->addHours(24):($existing?->sla_due_at?:$created->copy()->addHours(24)));
        $resolution=match($sourceStatus){'approved'=>'approved','rejected'=>'rejected','needs_more_info'=>'documents_requested',default=>null};
        $task=$this->upsertTask('account_verification',$userId,'KYC-'.$userId,'تحقق حساب '.match($type){'owner'=>'مالك','broker'=>'دلال','office'=>'مكتب عقارات',default=>'مستخدم'},$user,$status,'normal',null,$existing?->assigned_to_user_id,$existing?->assigned_to_name_snapshot,$sla,$updated,['verification_type'=>$type,'verification_status'=>$sourceStatus,'resolution'=>$resolution,'governorate_id'=>$govId,'governorate'=>$details['governorate']??null],false);
        return $this->routeTask($task,$govId);
    }

    public function projectListing(Property|int $listing, array $duplicateEvidence = []): ?SupportTask
    {
        $property=$listing instanceof Property?$listing->fresh(['user']):Property::query()->with('user')->find($listing);
        if(!$property)return null;
        $existing=SupportTask::query()->where('source_type','listing_review')->where('source_id',$property->id)->first();
        $existingMeta=$existing?->metadata??[];
        $returnedCycle=$existing?->status==='completed'&&($existingMeta['resolution']??null)==='returned_for_correction';
        $status=match($property->review_status){
            'approved'=>'completed',
            'rejected_blocked','rejected_duplicate'=>'rejected',
            'returned_for_correction'=>'completed',
            'under_review'=>'in_progress',
            'submitted'=>$returnedCycle?'needs_followup':($property->review_assigned_to_user_id?'in_progress':'new'),
            default=>'completed'
        };
        $release=$property->review_status==='submitted'&&$returnedCycle;
        $closed=in_array($status,self::CLOSED_STATUSES,true);
        $submitted=$property->submitted_at?:$property->updated_at?:now();
        $assigneeId=$release?null:($property->review_assigned_to_user_id?:($closed?$existing?->assigned_to_user_id:null));
        $assigneeName=$assigneeId?($existing?->assigned_to_user_id===$assigneeId?$existing?->assigned_to_name_snapshot:User::query()->whereKey($assigneeId)->value('name')):null;
        $govId=$this->listingGovernorateId($property);
        $resolution=match($property->review_status){'approved'=>'approved','rejected_blocked'=>'rejected','rejected_duplicate'=>'rejected_duplicate','returned_for_correction'=>'returned_for_correction',default=>null};
        if ($closed || $property->duplicate_check_status === 'pending') {
            $duplicateEvidence = [
                'duplicate_detection_source' => null,
                'duplicate_detection_reason' => null,
                'duplicate_detection_signals' => [],
            ];
        }
        $task=$this->upsertTask('listing_review',$property->id,'LIST-'.$property->id,'تحقق نشر إعلان: '.$property->title,$property->user,$status,'normal',null,$assigneeId,$assigneeName,$closed?null:$submitted->copy()->addHours(24),$property->updated_at,[
            'review_status'=>$property->review_status,'resolution'=>$resolution,'review_reason'=>$property->last_review_reason,
            'price'=>$property->price,'purpose'=>$property->purpose,'property_type'=>$property->type,'governorate_id'=>$govId,
        ] + $duplicateEvidence,$release||$closed);
        return $this->routeTask($task,$govId);
    }

    public function projectSupportCase(SupportCase|int $supportCase): ?SupportTask
    {
        $case=$supportCase instanceof SupportCase?$supportCase->fresh():SupportCase::query()->find($supportCase);if(!$case)return null;
        $type=$case->kind==='report'?'report':'support_ticket';$existing=SupportTask::query()->where('source_type',$type)->where('source_id',$case->id)->first();
        $status=match($case->status){'resolved'=>'completed','dismissed'=>'rejected','waiting_requester'=>'waiting_user','in_progress'=>$existing?->status==='waiting_user'?'needs_followup':($existing?->status==='waiting_internal'?'waiting_internal':'in_progress'),default=>$case->assigned_to_user_id?'in_progress':'new'};
        if($case->escalated_at&&!in_array($status,['completed','rejected','waiting_user'],true))$status='escalated';
        $priority=match($case->priority){'urgent','high'=>'urgent','low'=>'low',default=>'normal'};$severity=$case->kind==='report'?match($case->reason_code){'fraud','scam','impersonation','suspicious_documents','dangerous_content'=>'critical','abuse','privacy'=>'high','spam','duplicate'=>'low',default=>'medium'}:null;if($severity==='critical')$priority='urgent';
        $requester=$case->requester_user_id?User::query()->find($case->requester_user_id):null;$govId=$this->supportCaseGovernorateId($case,$requester);
        $resolution=match($case->status){'resolved'=>'resolved','dismissed'=>'dismissed','waiting_requester'=>'waiting_user',default=>null};
        $task=$this->upsertTask($type,$case->id,$case->reference,$case->subject,$requester,$status,$priority,$severity,$case->assigned_to_user_id,$case->assigned_to_name_snapshot,$case->sla_due_at,$case->updated_at,['kind'=>$case->kind,'case_status'=>$case->status,'resolution'=>$resolution,'reason_code'=>$case->reason_code,'target_type'=>$case->target_type,'target_id'=>$case->target_id,'governorate_id'=>$govId],false);
        if($type==='report'&&$severity==='critical')$this->notifyCriticalReportManagers($task);
        return $this->routeTask($task,$govId);
    }


    public function projectContactFollowup(MessageThread|int $thread, ?User $buyer=null, ?int $messageId=null): ?SupportTask
    {
        if (!Schema::hasTable('support_tasks')) return null;
        $threadModel=$thread instanceof MessageThread
            ? $thread->fresh(['property.user','participants'])
            : MessageThread::query()->with(['property.user','participants'])->find($thread);
        if(!$threadModel||!$threadModel->property)return null;

        $property=$threadModel->property;
        if(!$buyer){
            $buyer=User::query()->find((int)$threadModel->started_by_user_id);
            if(!$buyer||(int)$buyer->id===(int)$property->user_id){
                $participantId=$threadModel->participants
                    ->pluck('user_id')->map(fn($id)=>(int)$id)
                    ->first(fn(int $id)=>$id!==(int)$property->user_id);
                $buyer=$participantId?User::query()->find($participantId):null;
            }
        }
        if(!$buyer||(int)$buyer->id===(int)$property->user_id)return null;

        $govId=$this->listingGovernorateId($property);
        $task=DB::transaction(function()use($threadModel,$property,$buyer,$messageId,$govId):SupportTask{
            $task=SupportTask::query()
                ->where('source_type','contact_followup')
                ->where('source_id',$threadModel->id)
                ->lockForUpdate()
                ->first();
            $isNew=$task===null;
            $task=$task??new SupportTask();
            $wasClosed=$task->exists&&$task->isClosed();
            $from=$task->status;
            $metadata=$task->metadata??[];
            $now=now();

            $metadata['thread_id']=(int)$threadModel->id;
            $metadata['property_id']=(int)$property->id;
            $metadata['property_title']=$property->title;
            $metadata['advertiser_user_id']=(int)$property->user_id;
            $metadata['advertiser_name']=$property->user?->name;
            $metadata['buyer_user_id']=(int)$buyer->id;
            $metadata['buyer_name']=$buyer->name;
            $metadata['external_call_count']=(int)($metadata['external_call_count']??0)+1;
            $metadata['first_external_call_at']=$metadata['first_external_call_at']??$now->toIso8601String();
            $metadata['last_external_call_at']=$now->toIso8601String();
            if($messageId!==null)$metadata['last_call_message_id']=$messageId;
            $metadata['governorate_id']=$govId;

            if($isNew){
                $task->status='new';
                $task->sla_due_at=$now->copy()->addHours(48);
            }elseif($wasClosed){
                $task->status=$task->assigned_to_user_id?'needs_followup':'new';
                $task->completed_at=null;
                $task->sla_due_at=$now->copy()->addHours(48);
                $task->escalated_at=null;
                $task->escalation_reason=null;
                unset($metadata['resolution'],$metadata['overdue_notified_at'],$metadata['auto_escalated_at']);
            }elseif(!$task->sla_due_at){
                $task->sla_due_at=$now->copy()->addHours(48);
            }

            $task->source_type='contact_followup';
            $task->source_id=(int)$threadModel->id;
            $task->source_reference='CONTACT-'.$threadModel->id;
            $task->subject='متابعة تواصل عقاري: '.$property->title;
            $task->requester_user_id=$buyer->id;
            $task->requester_name_snapshot=$buyer->name;
            $task->priority=$task->priority?:'normal';
            $task->source_updated_at=$now;
            $task->last_activity_at=$now;
            $task->metadata=$metadata;
            $task->save();

            $event=$isNew?'created_from_external_call':($wasClosed?'reopened_by_external_call':'external_call_recorded');
            $this->event($task,$buyer,$event,$from,$task->status,[
                'property_id'=>$property->id,
                'message_id'=>$messageId,
                'external_call_count'=>$metadata['external_call_count'],
            ]);
            return $task;
        });

        return $this->routeTask($task,$govId)->fresh(['team','governorate']);
    }

    public function recordContactFollowupOutcome(
        User $actor,
        SupportTask $task,
        string $outcome,
        ?string $note,
        ?Carbon $nextFollowUpAt,
        Request $request,
        bool $actingAsAgent=false,
    ): SupportTask {
        $this->assertTaskExecution($actor,$task,$actingAsAgent);
        if($task->source_type!=='contact_followup'){
            throw ValidationException::withMessages(['task'=>['هذه العملية خاصة بمتابعات التواصل العقاري.']]);
        }
        $allowed=['no_answer','contacted','viewing_scheduled','viewed','negotiating','not_interested','deal_not_completed','deal_reported','needs_followup'];
        if(!in_array($outcome,$allowed,true)){
            throw ValidationException::withMessages(['outcome'=>['نتيجة المتابعة غير مدعومة.']]);
        }
        if($nextFollowUpAt&&$nextFollowUpAt->lte(now())){
            throw ValidationException::withMessages(['next_follow_up_at'=>['موعد المتابعة القادمة يجب أن يكون في المستقبل.']]);
        }

        return DB::transaction(function()use($actor,$task,$outcome,$note,$nextFollowUpAt,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskExecution($actor,$locked,$actingAsAgent);
            if($locked->source_type!=='contact_followup')throw new ConflictHttpException('المهمة ليست متابعة تواصل عقاري.');
            if(!$locked->isActive())throw new ConflictHttpException('المهمة مغلقة.');
            if($locked->status==='escalated')throw new ConflictHttpException('المهمة مصعّدة وتحتاج معالجة مدير الدعم أولاً.');

            $from=$locked->status;
            $metadata=$locked->metadata??[];
            $metadata['last_outcome']=$outcome;
            $metadata['last_followup_at']=now()->toIso8601String();
            $metadata['last_followup_by_user_id']=$actor->id;
            $metadata['followup_actions_count']=(int)($metadata['followup_actions_count']??0)+1;
            if($note!==null&&trim($note)!=='')$metadata['last_followup_note']=trim($note);
            unset($metadata['overdue_notified_at'],$metadata['auto_escalated_at']);

            $terminal=in_array($outcome,['not_interested','deal_not_completed'],true);
            $reportedDeal=$outcome==='deal_reported';
            $next=$terminal?null:($nextFollowUpAt?:now()->addHours($reportedDeal?12:($outcome==='no_answer'?24:48)));

            if($reportedDeal){
                $metadata['requires_counterparty_verification']=true;
                $metadata['deal_reported_at']=now()->toIso8601String();
            }else{
                unset($metadata['requires_counterparty_verification']);
            }
            $metadata['next_follow_up_at']=$next?->toIso8601String();
            if($terminal)$metadata['resolution']=$outcome;

            $locked->forceFill([
                'status'=>$terminal?'completed':'needs_followup',
                'priority'=>$reportedDeal?'urgent':$locked->priority,
                'sla_due_at'=>$next,
                'completed_at'=>$terminal?now():null,
                'last_activity_at'=>now(),
                'metadata'=>$metadata,
            ])->save();

            $this->event($locked,$actor,'contact_followup_outcome',$from,$locked->status,[
                'outcome'=>$outcome,
                'note'=>$note,
                'next_follow_up_at'=>$next?->toIso8601String(),
                'acting_as_agent'=>$actingAsAgent,
            ]);
            $this->audit->record($actor,'support_task.contact_followup_outcome',$locked,[
                'outcome'=>$outcome,
                'next_follow_up_at'=>$next?->toIso8601String(),
                'acting_as_agent'=>$actingAsAgent,
            ],$request,$locked->requester_user_id);

            if($reportedDeal)$this->notifyTaskManagers($locked,'صفقة محتملة تحتاج تحقق','أفاد أحد الأطراف بتمام صفقة مرتبطة بهذه المتابعة. تحقق من الطرف الآخر قبل إغلاقها.');
            return $locked->fresh(['team','governorate']);
        });
    }

    public function processContactFollowupDeadlines(): array
    {
        if(!Schema::hasTable('support_tasks'))return ['overdue_notified'=>0,'escalated'=>0];
        $tasks=SupportTask::query()
            ->where('source_type','contact_followup')
            ->whereIn('status',['new','in_progress','needs_followup','waiting_internal'])
            ->whereNotNull('sla_due_at')
            ->where('sla_due_at','<=',now())
            ->orderBy('sla_due_at')
            ->limit(500)
            ->get();

        $notified=0;$escalated=0;
        foreach($tasks as $task){
            DB::transaction(function()use($task,&$notified,&$escalated):void{
                $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
                if(!in_array($locked->status,['new','in_progress','needs_followup','waiting_internal'],true)||!$locked->sla_due_at||$locked->sla_due_at->isFuture())return;
                $metadata=$locked->metadata??[];

                if(empty($metadata['overdue_notified_at'])){
                    $from=$locked->status;
                    $metadata['overdue_notified_at']=now()->toIso8601String();
                    $locked->forceFill([
                        'status'=>'needs_followup',
                        'metadata'=>$metadata,
                        'last_activity_at'=>now(),
                    ])->save();
                    $this->event($locked,null,'contact_followup_overdue',$from,'needs_followup',[
                        'sla_due_at'=>$locked->sla_due_at->toIso8601String(),
                    ]);
                    if($locked->assigned_to_user_id){
                        $this->notifications->create(
                            (int)$locked->assigned_to_user_id,
                            'support_followup_overdue',
                            'متابعة تواصل متأخرة',
                            'تجاوزت «'.$locked->subject.'» موعد المتابعة المحدد.',
                            'support_task',
                            $locked->id,
                            ['task_id'=>$locked->id,'source_type'=>'contact_followup','destination'=>'my_tasks'],
                        );
                    }else{
                        $this->notifyTaskManagers($locked,'متابعة تواصل غير مستلمة ومتأخرة','تجاوزت المهمة موعد المتابعة ولم يستلمها موظف دعم بعد.');
                    }
                    $notified++;
                }

                if(now()->greaterThanOrEqualTo($locked->sla_due_at->copy()->addHours(24))&&empty($metadata['auto_escalated_at'])){
                    $from=$locked->status;
                    $metadata=$locked->metadata??[];
                    $metadata['auto_escalated_at']=now()->toIso8601String();
                    $locked->forceFill([
                        'status'=>'escalated',
                        'priority'=>'urgent',
                        'escalated_at'=>now(),
                        'escalation_reason'=>'تأخرت متابعة التواصل أكثر من 24 ساعة بعد موعدها.',
                        'metadata'=>$metadata,
                        'last_activity_at'=>now(),
                    ])->save();
                    $this->event($locked,null,'contact_followup_auto_escalated',$from,'escalated',[
                        'reason'=>$locked->escalation_reason,
                    ]);
                    if($locked->assigned_to_user_id){
                        $this->notifications->create(
                            (int)$locked->assigned_to_user_id,
                            'support_followup_escalated',
                            'تم تصعيد متابعة متأخرة',
                            'تجاوزت «'.$locked->subject.'» مهلة التأخير وتم تصعيدها لمدير الدعم.',
                            'support_task',
                            $locked->id,
                            ['task_id'=>$locked->id,'source_type'=>'contact_followup'],
                        );
                    }
                    $this->notifyTaskManagers($locked,'متابعة تواصل مصعّدة تلقائياً',$locked->escalation_reason);
                    $escalated++;
                }
            });
        }
        return ['overdue_notified'=>$notified,'escalated'=>$escalated];
    }

    public function resolveEscalation(User $actor, SupportTask $task, string $note, Request $request): SupportTask
    {
        $this->assertManager($actor);$this->assertTaskInActorScope($actor,$task);
        return DB::transaction(function()use($actor,$task,$note,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);$this->assertTaskInActorScope($actor,$locked);
            if($locked->status!=='escalated')throw new ConflictHttpException('المهمة ليست في حالة تصعيد.');
            $metadata=$locked->metadata??[];$metadata['escalation_resolution']=$note;$metadata['escalation_resolved_at']=now()->toIso8601String();
            $next=$locked->assigned_to_user_id?'in_progress':'new';$locked->forceFill(['status'=>$next,'metadata'=>$metadata,'last_activity_at'=>now()])->save();
            if(in_array($locked->source_type,['support_ticket','report'],true))SupportCase::query()->whereKey($locked->source_id)->update(['escalated_at'=>null,'last_activity_at'=>now(),'updated_at'=>now()]);
            $this->event($locked,$actor,'escalation_resolved','escalated',$next,['note'=>$note]);$this->audit->record($actor,'support_task.escalation_resolved',$locked,['note'=>$note],$request,$locked->requester_user_id);
            if($locked->assigned_to_user_id)$this->notifications->create((int)$locked->assigned_to_user_id,'support_escalation_resolved','تمت معالجة التصعيد',$note,'support_task',$locked->id,['task_id'=>$locked->id]);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function releaseTask(User $actor, SupportTask $task, Request $request): SupportTask
    {
        $this->assertManager($actor);$this->assertTaskInActorScope($actor,$task);
        return DB::transaction(function()use($actor,$task,$request):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);$this->assertTaskInActorScope($actor,$locked);if(!$locked->isActive())throw new ConflictHttpException('المهمة مغلقة.');
            $fromUser=$locked->assigned_to_user_id;$from=$locked->status;$next=in_array($from,['in_progress','needs_followup','waiting_internal'],true)?'new':$from;
            $this->releaseSource($locked);$metadata=$locked->metadata??[];
            unset($metadata['manager_agent_mode'], $metadata['assignment_source']);
            $locked->forceFill(['assigned_to_user_id'=>null,'assigned_to_name_snapshot'=>null,'claimed_at'=>null,'status'=>$next,'metadata'=>$metadata,'last_activity_at'=>now()])->save();
            $this->event($locked,$actor,'released_to_inbox',$from,$next,['from_user_id'=>$fromUser]);$this->audit->record($actor,'support_task.released',$locked,['from_user_id'=>$fromUser],$request,$locked->requester_user_id);
            return $locked->fresh(['team','governorate']);
        });
    }

    public function redistributeUser(User $actor, User $member, Request $request): int
    {
        $this->assertManager($actor);$teamIds=$this->managedTeamIds($actor);$tasks=SupportTask::query()->whereIn('support_team_id',$teamIds)->where('assigned_to_user_id',$member->id)->whereIn('status',self::ACTIVE_STATUSES)->get();$count=0;
        foreach($tasks as $task){$this->releaseTask($actor,$task,$request);$count++;}return $count;
    }

    public function teams(User $actor): array
    {
        abort_unless($this->isManager($actor) || $actor->hasPermission('users.manage_roles'), 403);
        $this->ensureSupportStaffMemberships();
        $ids = $actor->hasPermission('users.manage_roles')
            ? DB::table('support_teams')->where('is_active', true)->pluck('id')->all()
            : $this->managedTeamIds($actor);
        $memberCounts=DB::table('support_team_members')->whereIn('support_team_id',$ids)->where('member_role','agent')->selectRaw('support_team_id, count(*) as agents, sum(case when is_available then 1 else 0 end) as available_agents')->groupBy('support_team_id')->get()->keyBy('support_team_id');
        $taskCounts=SupportTask::query()->whereIn('support_team_id',$ids)->whereIn('status',self::ACTIVE_STATUSES)->selectRaw("support_team_id, count(*) as open_tasks, sum(case when assigned_to_user_id is null and status in ('new','needs_followup') then 1 else 0 end) as unassigned")->groupBy('support_team_id')->get()->keyBy('support_team_id');
        return DB::table('support_teams as t')->leftJoin('governorates as g', 'g.id', '=', 't.governorate_id')
            ->leftJoin('users as manager', 'manager.id', '=', 't.manager_user_id')
            ->whereIn('t.id', $ids)->where('t.is_active', true)->orderByDesc('t.is_fallback')->orderBy('g.name_ar')
            ->get(['t.id', 't.code', 't.name_ar', 't.governorate_id', 'g.name_ar as governorate_name',
                't.is_fallback', 't.manager_user_id', 'manager.name as manager_name'])
            ->map(function ($team) use ($memberCounts, $taskCounts): array {
                $members = $memberCounts->get($team->id);
                $tasks = $taskCounts->get($team->id);

                return [
                    'id' => (int) $team->id,
                    'code' => $team->code,
                    'name' => $team->name_ar,
                    'governorate_id' => $team->governorate_id ? (int) $team->governorate_id : null,
                    'governorate_name' => $team->governorate_name,
                    'is_fallback' => (bool) $team->is_fallback,
                    'manager_user_id' => $team->manager_user_id ? (int) $team->manager_user_id : null,
                    'manager_name' => $team->manager_name,
                    'agents' => (int) ($members->agents ?? 0),
                    'available_agents' => (int) ($members->available_agents ?? 0),
                    'open_tasks' => (int) ($tasks->open_tasks ?? 0),
                    'unassigned' => (int) ($tasks->unassigned ?? 0),
                ];
            })->values()->all();
    }

    public function updateTeamMember(User $actor, User $member, int $teamId, bool $available, int $capacity, Request $request): void
    {
        $this->assertManager($actor);if(!$member->hasRole('support_agent'))throw ValidationException::withMessages(['user_id'=>['يمكن إدارة توزيع موظفي الدعم فقط من هذه الشاشة.']]);
        $managed = $this->managedTeamIds($actor);
        abort_unless(in_array($teamId, $managed, true), 403);
        $this->ensureSupportStaffMembership($member);
        $capacity = max(1, min(50, $capacity));
        DB::transaction(function()use($actor,$member,$teamId,$available,$capacity,$request,$managed):void{
            User::query()->whereKey($member->id)->lockForUpdate()->firstOrFail();
            $memberships = DB::table('support_team_members')->where('user_id', $member->id)->where('member_role', 'agent');
            $current = (clone $memberships)->lockForUpdate()->pluck('support_team_id')->map(fn ($id) => (int) $id)->all();
            abort_unless($current !== [] && array_diff($current, $managed) === [], 403);
            $otherTeams = array_diff($current, [$teamId]);
            if (SupportTask::query()->whereIn('support_team_id', $otherTeams)->where('assigned_to_user_id', $member->id)
                ->whereIn('status', self::ACTIVE_STATUSES)->exists()) {
                throw new ConflictHttpException('أعد توزيع المهام المفتوحة قبل تغيير فريق الموظف.');
            }
            $managerTeams = DB::table('support_teams')->whereIn('id', $otherTeams)->where('manager_user_id', $member->id)->pluck('id')->all();
            (clone $memberships)->whereIn('support_team_id', $managerTeams)->update(['member_role' => 'manager', 'updated_at' => now()]);
            (clone $memberships)->whereIn('support_team_id', array_diff($otherTeams, $managerTeams))->delete();
            DB::table('support_team_members')->updateOrInsert(
                ['support_team_id' => $teamId, 'user_id' => $member->id],
                fn (bool $exists) => ['member_role' => 'agent', 'is_available' => $available, 'capacity' => $capacity, 'updated_at' => now()]
                    + ($exists ? [] : ['joined_at' => now(), 'created_at' => now()])
            );
            $this->audit->record($actor,'support_team.member_updated',$member,['support_team_id'=>$teamId,'is_available'=>$available,'capacity'=>$capacity],$request,$member->id);
        }, 3);
    }

    private function ensureWorkspaceSeeded(): void
    {
        if(Schema::hasTable('support_tasks')&&!SupportTask::query()->exists())$this->syncSources();
    }

    private function ensureSupportStaffMembership(User $actor): void
    {
        if(!Schema::hasTable('support_team_members')||(! $actor->hasRole('support_agent')&&!$actor->hasRole('support_manager')))return;
        if(DB::table('support_team_members')->where('user_id',$actor->id)->exists())return;$fallback=$this->fallbackTeamId();if(!$fallback)return;
        $role=$actor->hasRole('support_agent')?'agent':'manager';DB::table('support_team_members')->insertOrIgnore(['support_team_id'=>$fallback,'user_id'=>$actor->id,'member_role'=>$role,'is_available'=>true,'capacity'=>10,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        if($actor->hasRole('support_manager'))DB::table('support_teams')->where('id',$fallback)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);
    }

    private function ensureSupportStaffMemberships(): void
    {
        if(!Schema::hasTable('support_team_members'))return;$users=User::query()->whereHas('roles',fn($q)=>$q->whereIn('roles.key',['support_agent','support_manager']))->get();foreach($users as $u)$this->ensureSupportStaffMembership($u);
    }

    private function managedTeamIds(User $actor): array
    {
        return app(SupportTeamRoutingService::class)->managedTeamIds($actor);
    }

    protected function actorTeamIds(User $actor, bool $actingAsAgent = false): array
    {
        $this->ensureSupportStaffMembership($actor);
        if ($this->isManager($actor) && (!$actingAsAgent || !$actor->hasRole('support_agent'))) {
            return $this->managedTeamIds($actor);
        }

        return app(SupportTeamRoutingService::class)->memberTeamIds($actor, $actingAsAgent);
    }

    protected function applyActorTeamScope(Builder $query, User $actor, bool $actingAsAgent = false): void
    {
        if (!Schema::hasColumn('support_tasks', 'support_team_id') || $actor->is_platform_owner || $actor->hasRole('super_admin')) return;

        $query->whereIn('support_team_id', $this->actorTeamIds($actor, $actingAsAgent));
    }

    protected function assertTaskInActorScope(User $actor, SupportTask $task, bool $actingAsAgent = false): void
    {
        if (!Schema::hasColumn('support_tasks', 'support_team_id') || $actor->is_platform_owner || $actor->hasRole('super_admin')) return;

        abort_unless(in_array((int) $task->support_team_id, $this->actorTeamIds($actor, $actingAsAgent), true), 403);
    }

    public function governorateIds(User $actor, bool $actingAsAgent = false): array
    {
        if (!Schema::hasTable('support_teams')) return [];

        return DB::table('support_teams')->whereIn('id', $this->actorTeamIds($actor, $actingAsAgent))
            ->whereNotNull('governorate_id')->distinct()->pluck('governorate_id')
            ->map(fn ($id) => (int) $id)->all();
    }

    private function assertClaimCapacity(User $actor, SupportTask $task, bool $actingAsAgent): void
    {
        if ($this->isManager($actor) && !$actingAsAgent) {
            throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة.');
        }
        if ((int) $task->assigned_to_user_id === (int) $actor->id) return;

        $capacity = 10;
        if ($actor->hasRole('support_agent') && !$actor->is_platform_owner && !$actor->hasRole('super_admin')) {
            $member = DB::table('support_team_members')->where('user_id', $actor->id)
                ->where('support_team_id', $task->support_team_id)->where('member_role', 'agent')->first();
            if (!$member || !$member->is_available) {
                throw new ConflictHttpException('حالتك غير متاحة لاستلام مهام جديدة في هذا الفريق.');
            }
            $capacity = max(1, (int) $member->capacity);
        }
        $open = SupportTask::query()->where('assigned_to_user_id', $actor->id)->whereIn('status', self::ACTIVE_STATUSES)->count();
        if ($open >= $capacity) {
            throw new ConflictHttpException('وصلت للحد الحالي من المهام المفتوحة. أكمل بعض مهامك أو اطلب من المدير إعادة التوزيع.');
        }
    }

    private function assertAssigneeCanReceive(User $actor, SupportTask $task, User $assignee): void
    {
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;
        $this->ensureSupportStaffMembership($assignee);
        $member=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('user_id',$assignee->id)->where('member_role','agent')->first();
        if(!$member)throw ValidationException::withMessages(['user_id'=>['الموظف ليس ضمن الفريق المسؤول عن هذه المهمة.']]);
    }

    private function fallbackTeamId(): ?int
    {
        return app(SupportTeamRoutingService::class)->fallbackTeamId();
    }

    private function routeTask(SupportTask $task, ?int $governorateId): SupportTask
    {
        return app(SupportTeamRoutingService::class)->route($task, $governorateId);
    }

    private function governorateIdFromMetadata(array $metadata): ?int
    {
        if(!empty($metadata['governorate_id']))return (int)$metadata['governorate_id'];return $this->resolveGovernorateIdFromName($metadata['governorate']??null);
    }

    private function resolveGovernorateIdFromName(mixed $name): ?int
    {
        return app(SupportTeamRoutingService::class)->governorateIdFromName($name);
    }

    private function listingGovernorateId(Property $property): ?int
    {
        return app(SupportTeamRoutingService::class)->listingGovernorateId($property);
    }

    private function supportCaseGovernorateId(SupportCase $case, ?User $requester): ?int
    {
        $propertyId = $case->target_id ? match ($case->target_type) {
            'property', 'listing', 'property_listing' => $case->target_id,
            'comment' => ListingComment::query()->whereKey($case->target_id)->value('property_id'),
            'rating' => AdvertiserRating::query()->whereKey($case->target_id)->value('source_property_id'),
            'conversation_thread' => MessageThread::query()->whereKey($case->target_id)->value('property_id'),
            'broker_deal_outcome' => BrokerDealOutcome::query()->whereKey($case->target_id)->value('property_id'),
            default => null,
        } : null;
        $governorate = $propertyId ? app(SupportTeamRoutingService::class)
            ->listingGovernorateId(Property::query()->find($propertyId)) : null;
        if ($governorate !== null || !$requester) return $governorate;

        $governorate = $this->resolveGovernorateIdFromName($requester->marketplace_governorate);
        if ($governorate !== null || !Schema::hasTable('account_verification_profiles')) return $governorate;

        $details = DB::table('account_verification_profiles')->where('user_id', $requester->id)->value('details');

        return $this->resolveGovernorateIdFromName($this->jsonMap($details)['governorate'] ?? null);
    }

    private function jsonMap(mixed $value): array
    {
        if(is_array($value))return $value;if(is_object($value))return (array)$value;if(is_string($value)){try{$decoded=json_decode($value,true,512,JSON_THROW_ON_ERROR);return is_array($decoded)?$decoded:[];}catch(\Throwable){}}return [];
    }

    private function releaseSource(SupportTask $task): void
    {
        if($task->source_type==='payment_review'){PropertyPayment::query()->whereKey($task->source_id)->where('status','under_review')->update(['status'=>'proof_submitted','updated_at'=>now()]);return;}
        if($task->source_type==='listing_review'){Property::query()->whereKey($task->source_id)->where('review_status','under_review')->update(['review_status'=>'submitted','status'=>'pending','review_assigned_to_user_id'=>null,'review_assigned_at'=>null,'updated_at'=>now()]);return;}
        if(in_array($task->source_type,['support_ticket','report'],true)){$case=SupportCase::query()->find($task->source_id);if(!$case)return;$status=$case->status==='in_progress'?'open':$case->status;$case->forceFill(['status'=>$status,'assigned_to_user_id'=>null,'assigned_to_name_snapshot'=>null,'last_activity_at'=>now()])->save();}
    }

    public function notifyDealPriceConfirmationDue(SupportTask $task, int $dealId): bool
    {
        $this->ensureSupportStaffMemberships();
        $teamMembers = DB::table('support_team_members')->where('support_team_id', $task->support_team_id)->select('user_id');
        $teamManager = DB::table('support_teams')->where('id', $task->support_team_id)->value('manager_user_id');
        $recipients = User::query()->where('account_status', User::STATUS_ACTIVE)->where(function ($query) use ($teamMembers, $teamManager): void {
            $query->whereIn('id', $teamMembers)->orWhere('id', $teamManager)->orWhere('is_platform_owner', true)
                ->orWhereHas('roles', fn ($roles) => $roles->where('roles.key', 'super_admin'));
        })->get();
        $sent = false;
        foreach ($recipients as $recipient) {
            $manager = $this->isManager($recipient);
            if (!$recipient->hasPermission('support.handle_reports') || (!$manager && !$this->isSupportAgent($recipient))) continue;
            $scope = $manager ? 'all' : ($task->assigned_to_user_id ? 'mine' : 'inbox');
            if (!$this->queryFor($recipient, ['scope' => $scope])->whereKey($task->id)->exists()) continue;
            $notice = $this->notifications->create((int) $recipient->id, 'support_deal_confirmation_reminder',
                'تأكيد سعر الصفقة ينتظر المتابعة', 'مرّ ٢٤ ساعة على طلب تأكيد السعر. تابع العميل من الطلب نفسه.',
                'support_task', $task->id, ['task_id' => $task->id, 'source_id' => $task->source_id, 'deal_id' => $dealId],
                deliverPush: false);
            $sent = $sent || $notice !== null;
        }
        return $sent;
    }

    private function notifyTaskManagers(SupportTask $task, string $title, string $body): void
    {
        if(!Schema::hasTable('support_teams'))return;$ids=[];$manager=DB::table('support_teams')->where('id',$task->support_team_id)->value('manager_user_id');if($manager)$ids[]=(int)$manager;$memberManagers=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('member_role','manager')->pluck('user_id')->map(fn($id)=>(int)$id)->all();$ids=array_values(array_unique(array_merge($ids,$memberManagers)));foreach($ids as $id){if($id===(int)$task->assigned_to_user_id)continue;$this->notifications->create($id,'support_task_escalated',$title,$body,'support_task',$task->id,['task_id'=>$task->id,'source_type'=>$task->source_type]);}
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
