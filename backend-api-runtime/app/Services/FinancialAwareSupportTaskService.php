<?php

namespace App\Services;

use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class FinancialAwareSupportTaskService extends SupportTaskService
{
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

    public function queryFor(User $actor,array $filters): Builder
    {
        if (($filters['type']??null)==='payment_review') return $this->financialTasks->queryFor($actor,$filters);
        $base=parent::queryFor($actor,$filters);
        if (!empty($filters['type'])) return $base;
        if ($actor->hasRole('support_agent') && !$actor->hasRole('support_manager') && $actor->hasPermission('payments.review')) {
            $finance=$this->financialTasks->queryFor($actor,$filters);
            $base->getQuery()->unionAll($finance->getQuery());
        }
        return $base;
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

    public function dashboard(User $actor): array
    {
        $data=parent::dashboard($actor);
        if ($actor->hasRole('support_agent') && !$actor->hasRole('support_manager') && $actor->hasPermission('payments.review')) {
            $inbox=$this->financialTasks->queryFor($actor,['scope'=>'inbox'])->count();
            $mine=$this->financialTasks->queryFor($actor,['scope'=>'mine'])->count();
            $data['inbox_new']=($data['inbox_new']??0)+$inbox;
            $data['my_tasks']=($data['my_tasks']??0)+$mine;
            $data['payment_reviews']=$inbox+$mine;
        } elseif ($actor->hasRole('support_manager') || $actor->is_platform_owner || $actor->hasRole('super_admin')) {
            $data['payment_reviews']=SupportTask::query()->where('source_type','payment_review')->whereIn('status',self::ACTIVE_STATUSES)->count();
        }
        return $data;
    }

    public function teamMetrics(User $actor): array
    {
        $rows=parent::teamMetrics($actor);
        foreach($rows as &$row){
            $row['payment_reviews']=SupportTask::query()->where('source_type','payment_review')->where('assigned_to_user_id',$row['id'])->count();
        }
        unset($row);
        return $rows;
    }
}
