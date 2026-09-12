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
    public function dashboard(Request $request): JsonResponse { return response()->json(['data'=>$this->tasks->dashboard($request->user())]); }

    public function index(Request $request): JsonResponse
    {
        $actor=$request->user();$v=$request->validate([
            'scope'=>['nullable',Rule::in(['inbox','mine','completed','all'])],'type'=>['nullable',Rule::in(['account_verification','listing_review','support_ticket','report'])],
            'status'=>['nullable',Rule::in(['new','in_progress','waiting_user','waiting_internal','needs_followup','escalated','completed','rejected'])],
            'priority'=>['nullable',Rule::in(['urgent','normal','low'])],'severity'=>['nullable',Rule::in(['low','medium','high','critical'])],
            'assignee_id'=>['nullable','integer','exists:users,id'],'created_from'=>['nullable','date'],'created_to'=>['nullable','date','after_or_equal:created_from'],
            'overdue'=>['nullable','boolean'],'acting_as_agent'=>['nullable','boolean'],'per_page'=>['nullable','integer','min:1','max:100'],
        ]);
        $page=$this->tasks->queryFor($actor,[...$v,'overdue'=>$request->boolean('overdue'),'acting_as_agent'=>$request->boolean('acting_as_agent')])->paginate((int)($v['per_page']??40));
        return response()->json(['data'=>collect($page->items())->map(fn(SupportTask $task)=>$this->tasks->taskData($task,$actor))->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()]]);
    }

    public function claim(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['acting_as_agent'=>['nullable','boolean']]);$task=$this->tasks->claim($request->user(),$task,$request,(bool)($v['acting_as_agent']??false));return response()->json(['message'=>'تم استلام المهمة.','data'=>$this->tasks->taskData($task,$request->user())]); }
    public function assign(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['user_id'=>['required','integer','exists:users,id']]);$task=$this->tasks->assign($request->user(),$task,User::query()->findOrFail((int)$v['user_id']),$request);return response()->json(['message'=>'تم إسناد المهمة.','data'=>$this->tasks->taskData($task,$request->user())]); }
    public function release(Request $request, SupportTask $task): JsonResponse { $task=$this->tasks->releaseTask($request->user(),$task,$request);return response()->json(['message'=>'تمت إعادة المهمة إلى الوارد.','data'=>$this->tasks->taskData($task,$request->user())]); }
    public function classify(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['priority'=>['required',Rule::in(['urgent','normal','low'])],'severity'=>['nullable',Rule::in(['low','medium','high','critical'])]]);$task=$this->tasks->classify($request->user(),$task,$v['priority'],$v['severity']??null,$request);return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function operationalStatus(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['status'=>['required',Rule::in(['in_progress','waiting_internal'])],'acting_as_agent'=>['nullable','boolean']]);$task=$this->tasks->setOperationalStatus($request->user(),$task,$v['status'],$request,(bool)($v['acting_as_agent']??false));return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function escalate(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['reason'=>['required','string','min:3','max:1200'],'acting_as_agent'=>['nullable','boolean']]);$task=$this->tasks->escalate($request->user(),$task,trim($v['reason']),$request,(bool)($v['acting_as_agent']??false));return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function resolveEscalation(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['note'=>['required','string','min:3','max:1200']]);$task=$this->tasks->resolveEscalation($request->user(),$task,trim($v['note']),$request);return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function reopen(Request $request, SupportTask $task): JsonResponse { $task=$this->tasks->reopen($request->user(),$task,$request);return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function requestDocuments(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['note'=>['required','string','min:3','max:1000'],'acting_as_agent'=>['nullable','boolean']]);$task=$this->tasks->requestVerificationDocuments($request->user(),$task,trim($v['note']),$request,(bool)($v['acting_as_agent']??false));return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }
    public function rejectVerification(Request $request, SupportTask $task): JsonResponse { $v=$request->validate(['reason'=>['required','string','min:3','max:1000'],'acting_as_agent'=>['nullable','boolean']]);$task=$this->tasks->rejectVerification($request->user(),$task,trim($v['reason']),$request,(bool)($v['acting_as_agent']??false));return response()->json(['data'=>$this->tasks->taskData($task,$request->user())]); }

    public function events(Request $request, SupportTask $task): JsonResponse
    {
        $actor=$request->user();$this->tasks->assertTaskOwnership($actor,$task);$rows=SupportTaskEvent::query()->where('support_task_id',$task->id)->orderByDesc('id')->limit(200)->get();
        return response()->json(['data'=>$rows->map(fn(SupportTaskEvent $event)=>['id'=>$event->id,'event'=>$event->event,'from_status'=>$event->from_status,'to_status'=>$event->to_status,'actor_user_id'=>$event->actor_user_id,'actor_name'=>$event->actor_name_snapshot,'metadata'=>$event->metadata??[],'created_at'=>$event->created_at?->toIso8601String()])->values()]);
    }

    public function team(Request $request): JsonResponse { return response()->json(['data'=>$this->tasks->teamMetrics($request->user())]); }
    public function teams(Request $request): JsonResponse { return response()->json(['data'=>$this->tasks->teams($request->user())]); }
    public function updateMember(Request $request, User $user): JsonResponse { $v=$request->validate(['team_id'=>['required','integer','exists:support_teams,id'],'is_available'=>['required','boolean'],'capacity'=>['required','integer','min:1','max:50']]);$this->tasks->updateTeamMember($request->user(),$user,(int)$v['team_id'],(bool)$v['is_available'],(int)$v['capacity'],$request);return response()->json(['message'=>'تم تحديث توزيع الموظف وحالته.']); }
    public function redistributeMember(Request $request, User $user): JsonResponse { $count=$this->tasks->redistributeUser($request->user(),$user,$request);return response()->json(['message'=>'تمت إعادة الأعمال المفتوحة للوارد.','data'=>['released_tasks'=>$count]]); }
}
