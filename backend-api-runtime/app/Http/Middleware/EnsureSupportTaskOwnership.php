<?php
namespace App\Http\Middleware;

use App\Models\SupportCase;
use App\Models\SupportTask;
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
        if (! Schema::hasTable('support_tasks')) return $next($request);

        $actor = $request->user();
        if (! $actor || ! $actor->hasRole('support_agent')) return $next($request);
        if ($actor->is_platform_owner || $actor->hasRole('super_admin')
            || $actor->hasRole('support_manager') || $actor->hasPermission('support.manage')) {
            return $next($request);
        }

        $path = $request->path();
        $this->tasks->syncSources();

        if (preg_match('#^api/admin/account-verifications/(\d+)/(approve|more-info|reject)$#', $path, $m)
            && $request->isMethod('post')) {
            $this->assertOwned((int) $actor->id, 'account_verification', (int) $m[1]);
        }

        if (preg_match('#^api/account-verification/users/(\d+)/documents/[^/]+$#', $path, $m)
            && $request->isMethod('get')) {
            $this->assertOwned((int) $actor->id, 'account_verification', (int) $m[1]);
        }

        if (preg_match('#^api/admin/support/cases/(\d+)$#', $path, $m)
            && $request->isMethod('get')) {
            $this->assertSupportCaseOwned((int) $actor->id, (int) $m[1]);
        }

        if (preg_match('#^api/admin/support/cases/(\d+)/(start|reply|note|status)$#', $path, $m)) {
            $this->assertSupportCaseOwned((int) $actor->id, (int) $m[1]);
        }

        return $next($request);
    }

    private function assertSupportCaseOwned(int $actorId, int $caseId): void
    {
        $case = SupportCase::query()->find($caseId);
        if (! $case) return;
        if ((int) ($case->assigned_to_user_id ?? 0) !== $actorId) {
            throw new ConflictHttpException('يجب استلام المهمة من مركز الدعم أولاً.');
        }
        $type = $case->kind === 'report' ? 'report' : 'support_ticket';
        $this->assertOwned($actorId, $type, $caseId);
    }

    private function assertOwned(int $actorId, string $type, int $sourceId): void
    {
        $task = SupportTask::query()
            ->where('source_type', $type)
            ->where('source_id', $sourceId)
            ->whereIn('status', ['new','in_progress','waiting_user','waiting_internal','needs_followup','escalated'])
            ->first();

        if (! $task) return;
        if ((int) ($task->assigned_to_user_id ?? 0) !== $actorId) {
            throw new ConflictHttpException('يجب استلام المهمة من مركز الدعم أولاً.');
        }
    }
}
