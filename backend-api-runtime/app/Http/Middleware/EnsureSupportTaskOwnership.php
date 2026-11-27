<?php
namespace App\Http\Middleware;

use App\Models\SupportCase;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\SupportTaskService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class EnsureSupportTaskOwnership
{
    public function __construct(private readonly SupportTaskService $tasks) {}

    public function handle(Request $request, Closure $next): Response
    {
        if (!Schema::hasTable('support_tasks')) return $next($request);
        $actor=$request->user();
        if(!$actor)return $next($request);
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return $next($request);
        if(!$actor->hasRole('support_agent')&&!$actor->hasRole('support_manager')&&!$actor->hasPermission('support.manage'))return $next($request);

        $path=$request->path();
        if(preg_match('#^api/admin/account-verifications/(\\d+)/(approve|more-info|reject)$#',$path,$m)&&$request->isMethod('post'))$this->assertOwned($actor,'account_verification',(int)$m[1]);
        if(preg_match('#^api/account-verification/users/(\\d+)/documents/[^/]+$#',$path,$m)&&$request->isMethod('get'))$this->assertOwned($actor,'account_verification',(int)$m[1]);
        if(preg_match('#^api/admin/support/cases/(\\d+)$#',$path,$m)&&$request->isMethod('get'))$this->assertSupportCaseOwned($actor,(int)$m[1]);
        if(preg_match('#^api/admin/support/cases/(\\d+)/(start|reply|note|status)$#',$path,$m))$this->assertSupportCaseOwned($actor,(int)$m[1]);
        return $next($request);
    }

    private function assertSupportCaseOwned(User $actor,int $caseId): void
    {
        $case=SupportCase::query()->find($caseId);if(!$case)return;
        $this->tasks->assertCaseAccess($actor, $case);
    }

    private function assertOwned(User $actor,string $type,int $sourceId): void
    {
        $task=SupportTask::query()->where('source_type',$type)->where('source_id',$sourceId)->whereIn('status',SupportTaskService::ACTIVE_STATUSES)->first();
        if(!$task)$task=$this->tasks->projectSource($type,$sourceId);
        if (!$task) return;
        if ((int)($task->assigned_to_user_id ?? 0) !== (int)$actor->id || $task->isAwaitingAssignedReception()) {
            throw new ConflictHttpException('يجب استلام المهمة من مركز الدعم أولاً.');
        }
        $this->tasks->assertTaskOwnership($actor, $task);
    }
}
