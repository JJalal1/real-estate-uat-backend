<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTask;
use App\Models\SupportTaskEvent;
use App\Models\User;
use App\Services\SupportTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SupportWorkspaceController extends Controller
{
    public function __construct(private readonly SupportTaskService $tasks) {}

    public function dashboard(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor = $request->user();
        return response()->json(['data'=>$this->tasks->dashboard($actor)]);
    }

    public function index(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor = $request->user();
        $v = $request->validate([
            'scope'=>['nullable',Rule::in(['inbox','mine','all'])],
            'type'=>['nullable',Rule::in(['account_verification','listing_review','support_ticket','report'])],
            'status'=>['nullable',Rule::in(['new','in_progress','waiting_user','waiting_internal','needs_followup','escalated','completed','rejected'])],
            'priority'=>['nullable',Rule::in(['urgent','normal','low'])],
            'severity'=>['nullable',Rule::in(['low','medium','high','critical'])],
            'assignee_id'=>['nullable','integer','exists:users,id'],
            'created_from'=>['nullable','date'],
            'created_to'=>['nullable','date','after_or_equal:created_from'],
            'overdue'=>['nullable','boolean'],
            'per_page'=>['nullable','integer','min:1','max:100'],
        ]);

        $page = $this->tasks->queryFor($actor, [
            ...$v,
            'overdue'=>$request->boolean('overdue'),
        ])->paginate((int)($v['per_page'] ?? 40));

        return response()->json([
            'data'=>collect($page->items())->map(
                fn(SupportTask $task)=>$this->tasks->taskData($task,$actor)
            )->values(),
            'meta'=>[
                'current_page'=>$page->currentPage(),
                'last_page'=>$page->lastPage(),
                'total'=>$page->total(),
            ],
        ]);
    }

    public function claim(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $task=$this->tasks->claim($actor,$task,$request);
        return response()->json(['message'=>'تم استلام المهمة.','data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function assign(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate(['user_id'=>['required','integer','exists:users,id']]);
        $assignee=User::query()->findOrFail((int)$v['user_id']);
        $task=$this->tasks->assign($actor,$task,$assignee,$request);
        return response()->json(['message'=>'تم إسناد المهمة.','data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function classify(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate([
            'priority'=>['required',Rule::in(['urgent','normal','low'])],
            'severity'=>['nullable',Rule::in(['low','medium','high','critical'])],
        ]);
        $task=$this->tasks->classify($actor,$task,$v['priority'],$v['severity']??null,$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function operationalStatus(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate(['status'=>['required',Rule::in(['in_progress','waiting_internal'])]]);
        $task=$this->tasks->setOperationalStatus($actor,$task,$v['status'],$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function escalate(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $task=$this->tasks->escalate($actor,$task,$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function reopen(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $task=$this->tasks->reopen($actor,$task,$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function requestDocuments(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate(['note'=>['required','string','min:3','max:1000']]);
        $task=$this->tasks->requestVerificationDocuments($actor,$task,trim($v['note']),$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function rejectVerification(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate(['reason'=>['required','string','min:3','max:1000']]);
        $task=$this->tasks->rejectVerification($actor,$task,trim($v['reason']),$request);
        return response()->json(['data'=>$this->tasks->taskData($task,$actor)]);
    }

    public function events(Request $request, SupportTask $task): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->tasks->assertTaskOwnership($actor,$task);
        $rows=SupportTaskEvent::query()->where('support_task_id',$task->id)->orderByDesc('id')->limit(200)->get();
        return response()->json(['data'=>$rows->map(fn(SupportTaskEvent $event)=>[
            'id'=>$event->id,
            'event'=>$event->event,
            'from_status'=>$event->from_status,
            'to_status'=>$event->to_status,
            'actor_user_id'=>$event->actor_user_id,
            'actor_name'=>$event->actor_name_snapshot,
            'metadata'=>$event->metadata??[],
            'created_at'=>$event->created_at?->toIso8601String(),
        ])->values()]);
    }

    public function team(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        if (!($actor->is_platform_owner || $actor->hasRole('super_admin')
            || $actor->hasRole('support_manager') || $actor->hasPermission('support.manage'))) abort(403);
        return response()->json(['data'=>$this->tasks->teamMetrics()]);
    }
}
