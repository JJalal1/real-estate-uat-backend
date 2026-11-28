<?php

namespace App\Services;

use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class FinancialAwareSupportTaskService extends SupportTaskService
{
    private bool $routingRefreshed = false;

    public function __construct(
        AuditLogService $audit,
        UserNotificationService $notifications,
        private readonly FinancialSupportTaskService $financialTasks,
    ) {
        parent::__construct($audit,$notifications);
    }

    public function projectPayment(\App\Models\PropertyPayment|int $payment): SupportTask
    {
        return $this->financialTasks->projectPayment($payment);
    }

    protected function visibleTaskQuery(User $actor, bool $actingAsAgent = false): Builder
    {
        $query = parent::visibleTaskQuery($actor, $actingAsAgent);
        if (!$this->routingRefreshed) {
            $this->financialTasks->refreshUnassignedRouting();
            $this->routingRefreshed = true;
        }
        return $query;
    }

    public function claim(User $actor,SupportTask $task,Request $request,bool $actingAsAgent=false): SupportTask
    {
        return $task->source_type==='payment_review'
            ?$this->financialTasks->claim($actor,$task,$request,$actingAsAgent)
            :parent::claim($actor,$task,$request,$actingAsAgent);
    }

    public function assign(User $actor,SupportTask $task,User $assignee,Request $request): SupportTask
    {
        return $task->source_type==='payment_review'
            ?$this->financialTasks->assign($actor,$task,$assignee,$request)
            :parent::assign($actor,$task,$assignee,$request);
    }

    public function releaseTask(User $actor,SupportTask $task,Request $request): SupportTask
    {
        return $task->source_type==='payment_review'
            ?$this->financialTasks->release($actor,$task,$request)
            :parent::releaseTask($actor,$task,$request);
    }

    public function dashboard(User $actor, bool $actingAsAgent = false, bool $workspaceV2 = false): array
    {
        $data = parent::dashboard($actor, $actingAsAgent, $workspaceV2);
        $filters = ['type' => 'payment_review', 'acting_as_agent' => $actingAsAgent];
        $scopes = $data['mode'] === 'agent' ? ['inbox', 'mine'] : ['all'];
        $data['payment_reviews'] = array_sum(array_map(
            fn(string $scope) => $this->queryFor($actor, [...$filters, 'scope' => $scope])
                ->whereIn('status', self::ACTIVE_STATUSES)->count(),
            $scopes,
        ));
        return $data;
    }

    public function teamMetrics(User $actor, ?string $period = null): array
    {
        $rows=parent::teamMetrics($actor, $period);
        foreach($rows as &$row){
            $row['payment_reviews']=SupportTask::query()->where('source_type','payment_review')
                ->where('support_team_id',$row['team_id'])->where('assigned_to_user_id',$row['id'])->count();
        }
        unset($row);
        return $rows;
    }
}
