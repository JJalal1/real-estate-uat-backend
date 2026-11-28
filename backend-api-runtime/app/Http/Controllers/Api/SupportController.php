<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdvertiserRating;
use App\Models\AuditLog;
use App\Models\BrokerDealOutcome;
use App\Models\ListingComment;
use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportCaseMessage;
use App\Models\SupportCaseEvent;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\BrokerDealService;
use App\Services\PlatformSettingsService;
use App\Services\SupportCaseService;
use App\Services\SupportCaseFiles;
use App\Services\SupportHelpService;
use App\Services\SupportReportDecisions;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;
use App\Services\SupportTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use App\Models\PropertyPlatformReceivable;

class SupportController extends Controller
{
    public function __construct(
        private readonly SupportCaseService $support,
        private readonly AuditLogService $audit,
        private readonly PlatformSettingsService $settings,
        private readonly SupportTaskService $tasks,
        private readonly SupportCaseFiles $files,
        private readonly SupportHelpService $help,
        private readonly SupportReportDecisions $reports,
    ) {}

    public function mine(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $page=SupportCase::query()->where('requester_user_id',$user->id)->latest('id')->paginate(max(1,min((int)$request->input('per_page',30),50)));
        return response()->json([
            'data'=>collect($page->items())->map(fn(SupportCase $case)=>$this->summary($case))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()],
        ]);
    }

    public function help(): JsonResponse
    {
        return response()->json(['data' => $this->help->questions()]);
    }

    public function openInteraction(Request $request): JsonResponse
    {
        $v = $request->validate([
            'channel' => ['required', Rule::in(['ticket', 'human', 'assistant'])],
            'body' => ['required', 'string', 'min:2', 'max:5000'],
            'client_key' => ['required', 'uuid'],
            'attachment' => SupportCaseFiles::RULES,
        ]);
        $user = $request->user();
        $case = $this->files->withUpload($request->file('attachment'), function () use ($user, $v, $request): array {
            User::query()->lockForUpdate()->findOrFail($user->id);
            $existing = SupportCase::query()->where('requester_user_id', $user->id)
                ->where('intake_key', $v['client_key'])->first();
            if ($existing) return [$existing, null];

            $title = match ($v['channel']) {
                'assistant', 'human' => 'محادثة مع الدعم',
                default => 'طلب دعم',
            };
            $case = $this->support->create($user, 'support_ticket', $title, trim($v['body']), null,
                null, 'other', 'normal', $request, channel: $v['channel'], intakeKey: $v['client_key']);

            return [$case, $this->files->lastMessage($case)];
        });

        return response()->json(['data' => $this->detail($this->help->respond($case, $user), false)], 201);
    }

    public function handoff(Request $request, SupportCase $case): JsonResponse
    {
        return response()->json(['data' => $this->detail($this->help->handoff($case, $request->user()), false)]);
    }

    public function fileMine(Request $request, SupportCase $case, int $file): Response
    {
        abort_unless((int) $case->requester_user_id === (int) $request->user()->id, 404);

        return $this->files->response($case, $file, false);
    }

    public function fileAdmin(Request $request, SupportCase $case, int $file): Response
    {
        $this->tasks->assertCaseAccess($request->user(), $case);

        return $this->files->response($case, $file, true);
    }

    public function reportDecision(Request $request, SupportCase $case): JsonResponse
    {
        $v = $request->validate([
            'decision' => ['required', Rule::in(['request_information', 'resolve', 'dismiss', 'pause_publication', 'restore_publication'])],
            'reason' => ['required', 'string', 'min:3', 'max:2000'],
        ]);
        $case = $this->reports->decide($request->user(), $case, $v['decision'], trim($v['reason']), $request);

        return response()->json(['data' => $this->detail($case, true)]);
    }

    public function suggestReply(Request $request, SupportCase $case): JsonResponse
    {
        $this->tasks->assertCaseAccess($request->user(), $case);
        $messages = $case->messages()->reorder()->where('actor_role', 'requester')->latest('id')->limit(3)->pluck('body');
        $requester = User::query()->find($case->requester_user_id);
        $suggestion = $requester && $messages->isNotEmpty() && $case->kind !== 'report'
            ? $this->help->tryAnswer($requester, $messages->first()) : null;

        return response()->json(['data' => [
            'summary' => $messages->reverse()->map(fn ($message) => mb_substr($message, 0, 260))->implode("\n"),
            'reply' => $suggestion['body'] ?? '',
        ]]);
    }

    public function storeTicket(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $validated=$request->validate([
            'subject'=>['required','string','min:3','max:160'],
            'description'=>['required','string','min:5','max:5000'],
            'category'=>['nullable',Rule::in(['account','listing','technical','payments_future','other'])],
        ]);
        $case=$this->support->create($user,'support_ticket',trim($validated['subject']),trim($validated['description']),null,null,$validated['category']??'other','normal',$request);
        return response()->json(['message'=>'Support ticket opened.','data'=>$this->detail($case,false)],201);
    }

    public function report(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $validated=$request->validate([
            'target_type'=>['required',Rule::in(['listing','comment','rating','advertiser'])],
            'target_id'=>['required','integer','min:1'],
            'property_id'=>['nullable','integer','min:1','prohibited_unless:target_type,advertiser'],
            'reason'=>['required',Rule::in(['spam','fraud','abuse','misleading','duplicate','privacy','other'])],
            'details'=>['required','string','min:5','max:5000'],
            'attachment' => SupportCaseFiles::RULES,
        ]);
        [, $targetOwner]=$this->validateReportTarget($validated['target_type'],(int)$validated['target_id']);
        if($targetOwner!==null && (int)$targetOwner===(int)$user->id) throw ValidationException::withMessages(['target_id'=>['You cannot report your own content/account.']]);
        $propertyId = isset($validated['property_id']) ? (int) $validated['property_id'] : null;
        if ($propertyId !== null) {
            abort_unless(Property::query()->publiclyAvailable()->where('user_id', $targetOwner)->whereKey($propertyId)->exists(), 404);
        }
        $case=$this->files->withUpload($request->file('attachment'), function()use($user,$validated,$request,$propertyId): array {
            User::query()->lockForUpdate()->findOrFail($user->id);
            $duplicate=SupportCase::query()->where('kind','report')->where('requester_user_id',$user->id)
                ->where('target_type',$validated['target_type'])->where('target_id',(int)$validated['target_id'])
                ->whereNotIn('status',SupportCaseService::CLOSED_STATUSES)->latest('id')->first();
            if ($duplicate) throw new \Illuminate\Http\Exceptions\HttpResponseException(response()->json([
                'code'=>'report_already_received','message'=>'وصل بلاغك سابقًا ويمكنك متابعته من الدعم.',
                'data'=>['id'=>$duplicate->id,'reference'=>$duplicate->reference,'status'=>$duplicate->status],
            ],409));
            $priority=in_array($validated['reason'],['fraud','abuse','privacy'],true)?'high':'normal';
            $subject = match ($validated['target_type']) {
                'advertiser' => 'بلاغ عن معلن',
                'comment' => 'بلاغ عن تعليق',
                'rating' => 'بلاغ عن تقييم',
                default => 'بلاغ عن إعلان',
            };
            $case = $this->support->create($user, 'report', $subject, trim($validated['details']),
                $validated['target_type'], (int) $validated['target_id'], $validated['reason'], $priority, $request,
                contextPropertyId: $propertyId);

            return [$case, $this->files->lastMessage($case)];
        });
        return response()->json(['message'=>'Report submitted to support.','data'=>$this->detail($case,false)],201);
    }

    public function listingDecision(Request $request, Property $property): JsonResponse
    {
        abort_unless((int) $property->user_id === (int) $request->user()->id, 404);
        $review = in_array($property->review_status, ['returned_for_correction', 'rejected_duplicate'], true)
            ? $property->reviews()->where('action', $property->review_status)->latest('id')->first() : null;
        $previous = $review ? (int) ($review->metadata['previous_property_id'] ?? 0) : 0;

        return response()->json(['data' => [
            'title' => $property->title,
            'status' => $property->review_status,
            'reason' => $property->last_review_reason,
            'previous_property_id' => $previous && Property::query()->publiclyAvailable()->whereKey($previous)->exists() ? $previous : null,
            'can_request_review' => in_array($property->review_status, ['returned_for_correction', 'rejected_duplicate'], true),
        ]]);
    }

    public function reviewListingDecision(Request $request, Property $property): JsonResponse
    {
        abort_unless((int) $property->user_id === (int) $request->user()->id, 404);
        abort_unless(in_array($property->review_status, ['returned_for_correction', 'rejected_duplicate'], true), 409);

        return $this->openAppeal($request, 'listing', $property->id, 'مراجعة قرار إعلان', 'أطلب مراجعة قرار الإعلان «'.$property->title.'».');
    }

    public function reviewPublicationHold(Request $request, SupportCase $case): JsonResponse
    {
        abort_unless((int) $request->user()->support_publication_hold_case_id === (int) $case->id, 404);

        return $this->openAppeal($request, 'publication_hold', $case->id, 'مراجعة إيقاف النشر', 'أطلب مراجعة قرار إيقاف النشر.');
    }

    public function publicationHold(Request $request, SupportCase $case): JsonResponse
    {
        $decision = \App\Models\UserNotification::query()->where('user_id', $request->user()->id)
            ->where('entity_type', 'support_report_decision')->where('entity_id', $case->id)
            ->whereIn('type', ['support_publication_hold', 'support_publication_restored'])
            ->latest('id')->firstOrFail();

        return response()->json(['data' => [
            'title' => $decision->title,
            'reason' => $decision->body,
            'can_request_review' => (int) $request->user()->support_publication_hold_case_id === (int) $case->id,
        ]]);
    }

    private function openAppeal(Request $request, string $targetType, int $targetId, string $title, string $description): JsonResponse
    {
        $user = $request->user();
        $case = DB::transaction(function () use ($request, $user, $targetType, $targetId, $title, $description): SupportCase {
            User::query()->lockForUpdate()->findOrFail($user->id);
            $existing = SupportCase::query()->where('requester_user_id', $user->id)
                ->where('target_type', $targetType)->where('target_id', $targetId)->where('reason_code', 'decision_review')
                ->whereIn('status', SupportCaseService::ACTIVE_STATUSES)->first();

            return $existing ?? $this->support->create($user, 'support_ticket', $title, $description, $targetType,
                $targetId, 'decision_review', 'normal', $request, channel: 'human');
        });

        return response()->json(['data' => $this->detail($case, false)]);
    }

    public function showMine(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$case->requester_user_id===(int)$user->id,404);
        return response()->json(['data'=>$this->detail($case,false)]);
    }

    public function replyMine(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int) $case->requester_user_id === (int) $user->id, 404);
        $v = $request->validate(['body' => ['required', 'string', 'min:2', 'max:5000'], 'attachment' => SupportCaseFiles::RULES]);
        $case = $this->files->withUpload($request->file('attachment'), function () use ($user, $case, $v, $request): array {
            $updated = $this->support->requesterReply($user, $case, trim($v['body']), $request);

            return [$updated, $this->files->lastMessage($updated)];
        });

        return response()->json(['data' => $this->detail($this->help->respond($case, $user), false)]);
    }

    public function queue(Request $request): JsonResponse
    {
        $this->support->escalateOverdue($request);
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate([
            'kind'=>['nullable',Rule::in(['report','support_ticket'])],
            'status'=>['nullable',Rule::in(['open','in_progress','waiting_requester','resolved','dismissed'])],
            'priority'=>['nullable',Rule::in(['normal','high','urgent'])],
            'escalated'=>['nullable','boolean'],
            'assigned_to_me'=>['nullable','boolean'],
            'assigned_to_user_id'=>['nullable','integer','exists:users,id'],
        ]);
        $query=$this->scopedCases($actor)->latest('id');
        foreach(['kind','status','priority'] as $field) if(!empty($validated[$field])) $query->where($field,$validated[$field]);
        if(array_key_exists('escalated',$validated)) $validated['escalated']?$query->whereNotNull('escalated_at'):$query->whereNull('escalated_at');
        if(!empty($validated['assigned_to_me'])) $query->where('assigned_to_user_id',$actor->id);
        if(!empty($validated['assigned_to_user_id'])){
            if((int)$validated['assigned_to_user_id']!==(int)$actor->id && !$actor->hasPermission('support.reassign')) abort(403);
            $query->where('assigned_to_user_id',(int)$validated['assigned_to_user_id']);
        }
        $page=$query->paginate(max(1,min((int)$request->input('per_page',40),100)));
        return response()->json([
            'data'=>collect($page->items())->map(fn(SupportCase $case)=>$this->queueSummary($case))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()],
        ]);
    }

    public function showAdmin(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->tasks->assertCaseAccess($actor, $case);
        $this->assertLinkedCaseAccess($actor, $case);
        $this->audit->record($actor,'support.private_case_opened',$case,['reference'=>$case->reference,'kind'=>$case->kind],$request,$case->requester_user_id);
        return response()->json(['data'=>$this->detail($case,true)]);
    }

    public function start(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->assertLinkedCaseAccess($actor, $case);
        $case=$this->support->start($actor,$case,$request);
        return response()->json(['message'=>'Support case started.','data'=>$this->detail($case,true)]);
    }

    public function replyAdmin(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->assertLinkedCaseAccess($actor, $case);
        $validated=$request->validate(['body'=>['required','string','min:2','max:5000']]);
        $case=$this->support->staffReply($actor,$case,trim($validated['body']),$request);
        return response()->json(['message'=>'Support reply sent.','data'=>$this->detail($case,true)]);
    }

    public function note(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->assertLinkedCaseAccess($actor, $case);
        $validated=$request->validate(['body'=>['required','string','min:2','max:5000']]);
        $case=$this->support->internalNote($actor,$case,trim($validated['body']),$request);
        return response()->json(['message'=>'Internal note added.','data'=>$this->detail($case,true)]);
    }

    public function updateStatus(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->assertLinkedCaseAccess($actor, $case);
        $validated=$request->validate(['status'=>['required',Rule::in(['open','in_progress','waiting_requester','resolved','dismissed'])]]);
        $case=$this->support->setStatus($actor,$case,$validated['status'],$request);
        return response()->json(['message'=>'Support status updated.','data'=>$this->detail($case,true)]);
    }

    public function assign(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['user_id'=>['required','integer','exists:users,id']]);
        $assignee=User::query()->findOrFail((int)$validated['user_id']);
        $task = $this->tasks->caseTaskInTeam($actor, $case);
        $this->tasks->assign($actor, $task, $assignee, $request);
        $case = $case->fresh();
        return response()->json(['message'=>'Support case assigned.','data'=>$this->detail($case,true)]);
    }

    public function reopen(Request $request, SupportCase $case): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['reason'=>['required','string','min:3','max:1000']]);
        $this->tasks->caseTaskInTeam($actor, $case);
        $case=$this->support->reopen($actor,$case,trim($validated['reason']),$request);
        return response()->json(['message'=>'Support case reopened.','data'=>$this->detail($case,true)]);
    }

    public function escalate(Request $request, SupportCase $case): JsonResponse
    {
        $validated=$request->validate(['reason'=>['required','string','min:3','max:1000']]);
        $this->tasks->caseTaskInTeam($request->user(), $case);
        $updated=$this->support->escalate($request->user(),$case,(string)$validated['reason'],$request);
        return response()->json(['message'=>'Support case escalated.','data'=>$this->detail($updated,true)]);
    }

    public function agents(Request $request): JsonResponse
    {
        $actor = $request->user();
        $people = User::query()->with('roles')->where('email','<>','stage5-owner@local.invalid')->orderBy('name');
        if (!$actor->is_platform_owner && !$actor->hasRole('super_admin')) {
            $people->whereIn('id', array_column($this->tasks->teamMetrics($actor), 'id'));
        }
        $cases = $this->scopedCases($actor);
        $users=$people->get()
            ->filter(fn(User $user)=>$user->is_platform_owner || $user->hasPermission('support.handle_reports') || $user->hasPermission('support.manage'));
        return response()->json(['data'=>$users->map(fn(User $user)=>[
            'id'=>$user->id,'name'=>$user->name,'phone'=>$user->phone,'account_status'=>$user->account_status,'roles'=>$user->roleKeys(),
            'active_cases'=>(clone $cases)->where('assigned_to_user_id',$user->id)->whereIn('status',SupportCaseService::ACTIVE_STATUSES)->count(),
        ])->values()]);
    }

    public function userContext(Request $request, User $user): JsonResponse
    {
        $cases=$this->scopedCases($request->user())->where('requester_user_id',$user->id)->latest('id')->limit(30)->get();
        return response()->json(['data'=>[
            'user'=>[
                'id'=>$user->id,'name'=>$user->name,'email'=>$user->email,'phone'=>$user->phone,
                'account_status'=>$user->account_status,'account_type'=>$user->account_type,
                'broker_verification_status'=>$user->broker_verification_status,
                'has_outstanding_dues'=>PropertyPlatformReceivable::query()->where('advertiser_user_id', $user->id)->outstanding()->exists(),
                'financial_hold_active'=>false,
                'can_restore_financial_hold'=>false,
            ],
            'support_cases'=>$cases->map(fn(SupportCase $case)=>$this->summary($case))->values(),
            'counts'=>['tickets'=>$cases->where('kind','support_ticket')->count(),'reports'=>$cases->where('kind','report')->count(),'open'=>$cases->whereIn('status',SupportCaseService::ACTIVE_STATUSES)->count()],
        ]]);
    }

    public function restoreFinancialHold(): JsonResponse
    {
        return response()->json(['data' => ['restored_receivable_ids' => []]]);
    }

    public function worklog(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['user_id'=>['nullable','integer','exists:users,id'],'days'=>['nullable','integer','min:1','max:90']]);
        $userId=(int)($validated['user_id']??$actor->id);
        if($userId!==$actor->id && !$actor->hasPermission('support.view_team_metrics')) abort(403);
        $days=(int)($validated['days']??14);
        $rows=AuditLog::query()->where('actor_user_id',$userId)->where('created_at','>=',now()->subDays($days))
            ->where(function($q){$q->where('action','like','support.%')->orWhere('action','like','conversation.%')->orWhere('action','like','community.%')->orWhere('action','like','listing.%');})
            ->latest('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(AuditLog $log)=>[
            'id'=>$log->id,'action'=>$log->action,'actor_name'=>$log->actor_name_snapshot,'subject_type'=>$log->subject_type,'subject_id'=>$log->subject_id,'target_user_id'=>$log->target_user_id,'metadata'=>$log->metadata,'created_at'=>$log->created_at?->toIso8601String(),
        ])->values()]);
    }

    public function escalateOverdue(Request $request): JsonResponse
    {
        $count=$this->support->escalateOverdue($request);
        return response()->json(['message'=>'Overdue SLA scan completed.','data'=>['escalated_count'=>$count]]);
    }

    public function summaryAdmin(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->support->escalateOverdue($request);
        $warningHours=(int)$this->settings->get('support.sla_warning_hours',6);
        $active=SupportCaseService::ACTIVE_STATUSES;
        $cases = $this->scopedCases($actor);
        $data=[
            'new_tickets'=>(clone $cases)->where('kind','support_ticket')->where('status','open')->count(),
            'assigned_to_me'=>(clone $cases)->where('assigned_to_user_id',$actor->id)->whereIn('status',$active)->count(),
            'open'=>(clone $cases)->where('status','open')->count(),
            'in_progress'=>(clone $cases)->where('status','in_progress')->count(),
            'waiting_requester'=>(clone $cases)->where('status','waiting_requester')->count(),
            'escalated'=>(clone $cases)->whereNotNull('escalated_at')->whereIn('status',$active)->count(),
            'overdue_unescalated'=>(clone $cases)->whereIn('status',['open','in_progress'])->whereNull('escalated_at')->where('sla_due_at','<=',now())->count(),
            'new_reports'=>(clone $cases)->where('kind','report')->where('status','open')->count(),
            'sla_warning'=>(clone $cases)->whereIn('status',['open','in_progress'])->whereNull('escalated_at')->whereBetween('sla_due_at',[now(),now()->addHours($warningHours)])->count(),
        ];
        if($actor->hasPermission('support.view_team_metrics')){
            $agents=User::query()->with('roles')->whereIn('id', array_column($this->tasks->teamMetrics($actor), 'id'))
                ->orderBy('name')->get()
                ->filter(fn(User $u)=>$u->hasRole('support_agent')||$u->hasRole('support_manager'));
            $data['team']=$agents->map(fn(User $u)=>[
                'id'=>$u->id,'name'=>$u->name,'roles'=>$u->roleKeys(),
                'assigned_active'=>(clone $cases)->where('assigned_to_user_id',$u->id)->whereIn('status',$active)->count(),
                'actions_7d'=>AuditLog::query()->where('actor_user_id',$u->id)->where('created_at','>=',now()->subDays(7))->where('action','like','support.%')->count(),
            ])->values();
        }
        return response()->json(['data'=>$data]);
    }

    private function scopedCases(User $actor): \Illuminate\Database\Eloquent\Builder
    {
        return SupportCase::query()->whereIn('id', $this->tasks->scopedCaseTasks($actor)->select('source_id'));
    }

    private function validateReportTarget(string $type, int $id): array
    {
        return match($type){
            'listing'=>$this->listingTarget($id),
            'comment'=>$this->commentTarget($id),
            'rating'=>$this->ratingTarget($id),
            'advertiser'=>$this->advertiserTarget($id),
        };
    }

    private function listingTarget(int $id): array
    {
        $item=Property::query()->findOrFail($id);abort_unless($item->status==='published',404);return ['listing #'.$id,(int)$item->user_id];
    }
    private function commentTarget(int $id): array
    {
        $item=ListingComment::query()->findOrFail($id);abort_unless($item->status==='visible',404);return ['comment #'.$id,$item->author_user_id?(int)$item->author_user_id:null];
    }
    private function ratingTarget(int $id): array
    {
        $item=AdvertiserRating::query()->findOrFail($id);abort_unless($item->status==='visible',404);return ['rating #'.$id,(int)$item->rater_user_id];
    }
    private function advertiserTarget(int $id): array
    {
        $item = User::query()->findOrFail($id);
        abort_unless(Property::query()->where('user_id', $id)->where('status', 'published')->exists()
            || app(\App\Services\BrokerRankingService::class)->query(null, false, true)->where('users.id', $id)->exists(), 404);
        return ['advertiser #'.$id, (int) $item->id];
    }

    private function queueSummary(SupportCase $case): array
    {
        $data=$this->summary($case);
        if($case->kind==='support_ticket') $data['subject']='Support ticket';
        return $data;
    }

    private function summary(SupportCase $case): array
    {
        return [
            'id'=>$case->id,'reference'=>$case->reference,'kind'=>$case->kind,'channel'=>$case->channel,'subject'=>$case->subject === 'Conversation complaint' ? 'بلاغ عن محادثة' : $case->subject,
            'target_type'=>$case->target_type,'target_id'=>$case->target_id,'reason_code'=>$case->reason_code,
            'status'=>$case->status,'priority'=>$case->priority,'assigned_to_user_id'=>$case->assigned_to_user_id,
            'assigned_to_name'=>$case->assigned_to_name_snapshot,'sla_due_at'=>$case->sla_due_at?->toIso8601String(),
            'first_response_at'=>$case->first_response_at?->toIso8601String(),'resolved_at'=>$case->resolved_at?->toIso8601String(),
            'escalated_at'=>$case->escalated_at?->toIso8601String(),'escalation_level'=>(int)$case->escalation_level,
            'created_at'=>$case->created_at?->toIso8601String(),'last_activity_at'=>$case->last_activity_at?->toIso8601String(),
        ];
    }

    private function detail(SupportCase $case, bool $admin): array
    {
        $messages=SupportCaseMessage::query()->where('support_case_id',$case->id)->when(!$admin,fn($q)=>$q->where('is_internal',false))->orderBy('id')->get();
        $attachments = $this->files->forMessages($messages->modelKeys());
        $data=array_merge($this->summary($case),[
            'description'=>$case->description,
            'requester'=>['id'=>$case->requester_user_id,'name'=>$case->requester_name_snapshot,'email'=>$case->requester_email_snapshot],
            'messages'=>$messages->map(fn(SupportCaseMessage $message)=>[
                'id'=>$message->id,'actor_user_id'=>$message->actor_user_id,'actor_name'=>$message->actor_name_snapshot,
                'actor_role'=>$message->actor_role,'is_internal'=>(bool)$message->is_internal,'body'=>$message->body,
                'attachments'=>$attachments[$message->id] ?? [],'action_path'=>$message->action_path,
                'created_at'=>$message->created_at?->toIso8601String(),
            ])->values(),
        ]);
        if($admin){
            $events=SupportCaseEvent::query()->where('support_case_id',$case->id)->orderBy('id')->get();
            $data['events']=$events->map(fn(SupportCaseEvent $event)=>[
                'id'=>$event->id,'event'=>$event->event,'actor_name'=>$event->actor_name_snapshot,'from_status'=>$event->from_status,'to_status'=>$event->to_status,'metadata'=>$event->metadata,'created_at'=>$event->created_at?->toIso8601String(),
            ])->values();
            $data['target_preview']=$this->targetPreview($case);
            if ($case->kind === 'report') {
                $target = User::query()->find($this->reports->reportedUserId($case));
                $thread = $case->target_type === 'conversation_thread'
                    ? \App\Models\MessageThread::query()->find($case->target_id) : null;
                $propertyId = $case->context_property_id
                    ?? ($case->target_type === 'listing' ? $case->target_id : $thread?->property_id);
                $data['report'] = [
                    'reported_name' => $target?->name,
                    'property_title' => $propertyId === null ? null : Property::query()->whereKey($propertyId)->value('title'),
                    'conversation_report_id' => \App\Models\ConversationReport::query()->where('support_case_id', $case->id)->value('id'),
                    'may_manage_publication' => $target !== null && $this->reports->canManagePublication(request()->user()),
                    'publication_paused_for_report' => $target !== null && (int) $target->support_publication_hold_case_id === (int) $case->id,
                ];
            }
        }
        return $data;
    }

    private function targetPreview(SupportCase $case): ?array
    {
        if ($case->reason_code === BrokerDealService::PRICE_CONFIRMATION_REASON
            && $case->target_type === 'broker_deal_outcome' && $case->target_id) {
            $deal = BrokerDealOutcome::query()->find($case->target_id);
            if (!$deal) {
                return null;
            }

            return [
                'type' => 'broker_deal_outcome',
                'id' => $deal->id,
                'title' => $deal->snapshot['property_title'] ?? null,
                'status' => $deal->status,
                'transaction_type' => $deal->transaction_type,
                'listing_price' => $deal->snapshot['listing_price'] ?? null,
                'listing_currency' => $deal->snapshot['listing_currency'] ?? null,
                'basis_amount' => $deal->basis_amount,
                'currency' => $deal->currency,
            ];
        }
        if ($case->reason_code === 'external_listing_closure' && $case->target_type === 'property' && $case->target_id) {
            $property = Property::query()->withoutGlobalScopes()->find($case->target_id);
            return $property ? [
                'type' => 'property',
                'id' => $property->id,
                'title' => $property->title,
                'transaction_type' => $property->purpose,
            ] : null;
        }
        if($case->kind!=='report'||!$case->target_type||!$case->target_id) return null;
        return match($case->target_type){
            'listing'=>($item=Property::query()->find($case->target_id))?['type'=>'listing','id'=>$item->id,'title'=>$item->title,'status'=>$item->status,'review_status'=>$item->review_status,'owner_user_id'=>$item->user_id]:null,
            'comment'=>($item=ListingComment::query()->find($case->target_id))?['type'=>'comment','id'=>$item->id,'body'=>$item->body,'status'=>$item->status,'property_id'=>$item->property_id,'author_user_id'=>$item->author_user_id]:null,
            'rating'=>($item=AdvertiserRating::query()->find($case->target_id))?['type'=>'rating','id'=>$item->id,'rating'=>$item->rating,'comment'=>$item->comment,'status'=>$item->status,'advertiser_user_id'=>$item->advertiser_user_id,'rater_user_id'=>$item->rater_user_id]:null,
            'advertiser'=>($item=User::query()->find($case->target_id))?['type'=>'advertiser','id'=>$item->id,'name'=>$item->name,'account_status'=>$item->account_status]:null,
            default=>null,
        };
    }

    private function assertLinkedCaseAccess(User $actor, SupportCase $case): void
    {
        if (!in_array($case->reason_code, [BrokerDealService::PRICE_CONFIRMATION_REASON, 'external_listing_closure'], true)) {
            return;
        }
        $task = SupportTask::query()
            ->where('source_type', 'support_ticket')
            ->where('source_id', $case->id)
            ->firstOrFail();

        $actingAsAgent = (int)$task->assigned_to_user_id === (int)$actor->id
            && !empty($task->metadata['manager_agent_mode']);
        $visible = $this->tasks->taskFor($actor, (int)$task->id, $actingAsAgent);
        $this->tasks->assertTaskOwnership($actor, $visible);
    }
}
