<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyPayment;
use App\Models\SupportTask;
use App\Models\SupportTaskEvent;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class FinancialSupportTaskService
{
    private bool $routingRefreshed = false;

    public function __construct(
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
        private readonly SupportTeamRoutingService $routing,
    ) {}

    public function projectPayment(PropertyPayment|int $payment): SupportTask
    {
        $paymentId = $payment instanceof PropertyPayment ? $payment->id : $payment;

        return DB::transaction(function () use ($paymentId): SupportTask {
            $taskQuery = SupportTask::query()->where('source_type', 'payment_review')->where('source_id', $paymentId);
            $existing = (clone $taskQuery)->lockForUpdate()->first();
            $payment = PropertyPayment::query()->lockForUpdate()->findOrFail($paymentId);
            // A concurrent first projection may have created the row while the payment lock was pending.
            $existing ??= $taskQuery->lockForUpdate()->first();
            $property = Property::query()->find($payment->property_id);
            $payerName = User::query()->whereKey($payment->payer_user_id)->value('name');
            $status = match ($payment->status) {
                'proof_submitted' => in_array($existing?->status, ['waiting_user', 'needs_followup'], true)
                    ? 'needs_followup'
                    : ($existing?->assigned_to_user_id ? 'in_progress' : 'new'),
                'under_review' => 'in_progress',
                'correction_required' => 'waiting_user',
                'confirmed' => 'completed',
                'rejected', 'cancelled' => 'rejected',
                default => 'new',
            };
            $resolution = match ($payment->status) {
                'confirmed' => 'payment_confirmed',
                'rejected' => 'payment_rejected',
                'correction_required' => 'correction_requested',
                'cancelled' => 'cancelled',
                default => null,
            };
            $oldStatus = $existing?->status;
            $task = $existing ?? new SupportTask();
            $governorateId = $task->governorate_id;
            $teamId = $task->support_team_id;
            if (! $teamId || (! $task->assigned_to_user_id && in_array($status, SupportTaskService::INBOX_STATUSES, true))) {
                $governorateId = $this->routing->listingGovernorateId($property);
                $teamId = $this->routing->teamId($governorateId);
            }

            $task->forceFill([
                'source_type' => 'payment_review',
                'source_id' => $payment->id,
                'source_reference' => $payment->reference,
                'subject' => 'مراجعة إيصال سداد: '.($property?->title ?: $payment->reference),
                'requester_user_id' => $payment->payer_user_id,
                'requester_name_snapshot' => $payerName,
                'status' => $status,
                'priority' => $task->priority ?? 'normal',
                'support_team_id' => $teamId,
                'governorate_id' => $governorateId,
                'waiting_since' => $status === 'waiting_user' ? ($task->waiting_since ?? now()) : null,
                'sla_due_at' => in_array($status, ['completed', 'rejected', 'waiting_user'], true)
                    ? null
                    : ($task->sla_due_at ?? now()->addHours(24)),
                'source_updated_at' => $payment->updated_at,
                'last_activity_at' => $payment->updated_at ?? now(),
                'completed_at' => in_array($status, ['completed', 'rejected'], true) ? ($task->completed_at ?? now()) : null,
                'metadata' => array_merge($task->metadata ?? [], [
                    'payment_reference' => $payment->reference,
                    'payment_status' => $payment->status,
                    'resolution' => $resolution,
                    'amount' => (float) $payment->required_amount,
                    'currency' => $payment->currency,
                    'payment_method_id' => $payment->payment_method_id,
                    'property_id' => $payment->property_id,
                    'advertiser_user_id' => $payment->advertiser_user_id,
                    'submitted_at' => $payment->submitted_at?->toIso8601String(),
                ]),
            ])->save();

            if (! $existing) {
                $this->event($task, null, 'created_from_payment', null, $status);
            } elseif ($oldStatus !== $status) {
                $this->event($task, null, 'payment_status_synced', $oldStatus, $status);
            }

            return $task->fresh(['team', 'governorate']);
        }, 3);
    }

    public function refreshUnassignedRouting(): void
    {
        if ($this->routingRefreshed) {
            return;
        }
        $this->routingRefreshed = true;

        $this->unroutedPaymentTasks()->chunkById(100, function ($tasks): void {
            $propertyIds = PropertyPayment::query()->whereKey($tasks->pluck('source_id')->all())->pluck('property_id', 'id');
            $properties = Property::query()->whereKey($propertyIds->values()->unique()->all())->get()->keyBy('id');
            foreach ($tasks as $task) {
                $property = $properties->get($propertyIds->get($task->source_id));
                $governorateId = $this->routing->listingGovernorateId($property);
                if ($governorateId !== null && ($teamId = $this->routing->teamId($governorateId)) !== null) {
                    $this->unroutedPaymentTasks()->whereKey($task->id)->update([
                        'support_team_id' => $teamId,
                        'governorate_id' => $governorateId,
                    ]);
                }
            }
        });
    }

    private function unroutedPaymentTasks(): Builder
    {
        return SupportTask::query()->where('source_type', 'payment_review')
            ->whereNull('assigned_to_user_id')->whereNull('governorate_id')
            ->whereIn('status', SupportTaskService::INBOX_STATUSES);
    }

    public function claim(User $actor,SupportTask $task,Request $request,bool $actingAsAgent=false): SupportTask
    {
        $this->assertPaymentTask($task);
        $this->assertReviewer($actor, $actingAsAgent);
        $this->assertTeamScope($actor, $task, $actingAsAgent);

        return DB::transaction(function () use ($actor, $task, $request, $actingAsAgent): SupportTask {
            $locked = SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTeamScope($actor, $locked, $actingAsAgent);
            if (! $locked->isActive() || $locked->status === 'escalated') {
                throw new ConflictHttpException('لا يمكن استلام المهمة في حالتها الحالية.');
            }
            if ($locked->assigned_to_user_id && (int) $locked->assigned_to_user_id !== (int) $actor->id) {
                throw new ConflictHttpException('المهمة محجوزة لموظف دعم آخر.');
            }
            if ($locked->claimed_at) {
                return $locked;
            }
            $payment = PropertyPayment::query()->whereKey($locked->source_id)->lockForUpdate()->firstOrFail();
            if (! in_array($payment->status, ['proof_submitted', 'under_review'], true)) {
                throw new ConflictHttpException('إثبات الدفع ليس جاهزًا للمراجعة.');
            }

            $from = $locked->status;
            $metadata = $locked->metadata ?? [];
            $metadata['assignment_source'] = ($metadata['assignment_source'] ?? null) === 'assigned' ? 'assigned' : 'received';
            $metadata['payment_status'] = 'under_review';
            $locked->forceFill([
                'assigned_to_user_id' => $actor->id,
                'assigned_to_name_snapshot' => $actor->name,
                'claimed_at' => now(),
                'status' => 'in_progress',
                'waiting_since' => null,
                'last_activity_at' => now(),
                'metadata' => $metadata,
            ])->save();
            $payment->forceFill(['status' => 'under_review'])->save();
            $this->event($locked, $actor, 'claimed', $from, 'in_progress');
            $this->audit->record($actor, 'support_task.payment_claimed', $locked, [], $request, $locked->requester_user_id);

            return $locked->fresh(['team', 'governorate']);
        });
    }

    public function assign(User $actor,SupportTask $task,User $assignee,Request $request): SupportTask
    {
        $this->assertPaymentTask($task);
        $this->assertManager($actor);
        $this->assertTeamScope($actor, $task);
        abort_unless($assignee->isActive() && $assignee->hasRole('support_agent') && $assignee->hasPermission('payments.review'), 422, 'المهمة المالية تُسند لموظف دعم لديه صلاحية مراجعة المدفوعات.');
        $this->ensureSupportMembership($assignee);

        return DB::transaction(function () use ($actor, $task, $assignee, $request): SupportTask {
            $locked = SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTeamScope($actor, $locked);
            if (! $locked->isActive()) {
                throw new ConflictHttpException('المهمة مغلقة.');
            }
            $member = DB::table('support_team_members')->where('support_team_id', $locked->support_team_id)
                ->where('user_id', $assignee->id)->where('member_role', 'agent')->where('is_available', true)->exists();
            abort_unless($member, 422, 'الموظف غير متاح في فريق هذه المهمة.');

            $from = $locked->status;
            $before = $locked->assigned_to_user_id;
            $next = in_array($from, SupportTaskService::INBOX_STATUSES, true) ? 'in_progress' : $from;
            $metadata = $locked->metadata ?? [];
            $metadata['assignment_source'] = 'assigned';
            $locked->forceFill([
                'assigned_to_user_id' => $assignee->id,
                'assigned_to_name_snapshot' => $assignee->name,
                'claimed_at' => (int) $before === (int) $assignee->id ? $locked->claimed_at : null,
                'status' => $next,
                'last_activity_at' => now(),
                'metadata' => $metadata,
            ])->save();
            $this->event($locked, $actor, 'assigned', $from, $next, ['from_user_id' => $before, 'to_user_id' => $assignee->id]);
            $this->audit->record($actor, 'support_task.payment_assigned', $locked, ['to_user_id' => $assignee->id], $request, $locked->requester_user_id);
            $this->notifications->create($assignee->id, 'support_task_assigned', 'قام مدير الدعم بإسناد مهمة لك', 'تمت إضافة «'.$locked->subject.'» إلى قائمة مهامك.', 'support_task', $locked->id, ['task_id' => $locked->id, 'source_type' => 'payment_review', 'destination' => 'my_tasks']);

            return $locked->fresh(['team', 'governorate']);
        });
    }

    public function release(User $actor,SupportTask $task,Request $request): SupportTask
    {
        $this->assertPaymentTask($task);
        $this->assertManager($actor);
        $this->assertTeamScope($actor, $task);

        return DB::transaction(function () use ($actor, $task, $request): SupportTask {
            $locked = SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTeamScope($actor, $locked);
            if (! $locked->isActive()) {
                throw new ConflictHttpException('المهمة مغلقة.');
            }

            $from = $locked->status;
            $before = $locked->assigned_to_user_id;
            $next = in_array($from, ['in_progress', 'waiting_internal', 'needs_followup'], true) ? 'new' : $from;
            $metadata = $locked->metadata ?? [];
            unset($metadata['assignment_source']);
            if ($next === 'new' && PropertyPayment::query()->whereKey($locked->source_id)->where('status', 'under_review')
                ->update(['status' => 'proof_submitted', 'updated_at' => now()])) {
                $metadata['payment_status'] = 'proof_submitted';
            }
            $locked->forceFill([
                'assigned_to_user_id' => null,
                'assigned_to_name_snapshot' => null,
                'claimed_at' => null,
                'status' => $next,
                'last_activity_at' => now(),
                'metadata' => $metadata,
            ])->save();
            $this->event($locked, $actor, 'released_to_inbox', $from, $next, ['from_user_id' => $before]);
            $this->audit->record($actor, 'support_task.payment_released', $locked, ['from_user_id' => $before], $request, $locked->requester_user_id);

            $property = Property::query()->find($metadata['property_id'] ?? null);

            return $this->routing->route($locked, $this->routing->listingGovernorateId($property))->loadMissing(['team', 'governorate']);
        });
    }

    private function assertReviewer(User $actor,bool $actingAsAgent): void
    {
        if($this->isManager($actor)){
            if(!$actingAsAgent&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin'))throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة مالية.');
            if(!$actor->hasPermission('payments.review')&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin'))abort(403);
            return;
        }
        abort_unless($actor->hasRole('support_agent')&&$actor->hasPermission('payments.review'),403);
    }

    private function ensureSupportMembership(User $actor): void
    {
        if(!Schema::hasTable('support_team_members')||!Schema::hasTable('support_teams'))return;
        $isManager=$actor->hasRole('support_manager');
        $isAgent=$actor->hasRole('support_agent');
        if(!$isManager&&!$isAgent)return;
        if(DB::table('support_team_members')->where('user_id',$actor->id)->exists())return;
        $fallbackId = $this->routing->fallbackTeamId();
        if(!$fallbackId)return;
        DB::table('support_team_members')->insertOrIgnore([
            'support_team_id' => $fallbackId,
            'user_id' => $actor->id,
            'member_role' => $isAgent ? 'agent' : 'manager',
            'is_available' => true,
            'capacity' => 10,
            'joined_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        if ($isManager) {
            DB::table('support_teams')->where('id',$fallbackId)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);
        }
    }

    private function assertManager(User $actor):void{abort_unless($this->isManager($actor),403);}
    private function isManager(User $actor):bool{return $actor->is_platform_owner||$actor->hasRole('super_admin')||$actor->hasRole('support_manager')||$actor->hasPermission('support.manage');}
    private function assertPaymentTask(SupportTask $task):void{abort_unless($task->source_type==='payment_review',422,'هذه ليست مهمة تحقق دفع.');}
    private function assertTeamScope(User $actor, SupportTask $task, bool $actingAsAgent = false): void
    {
        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) {
            return;
        }
        $this->ensureSupportMembership($actor);
        $managerScope = $this->isManager($actor) && (! $actingAsAgent || ! $actor->hasRole('support_agent'));
        $teamIds = $managerScope
            ? $this->routing->managedTeamIds($actor)
            : $this->routing->memberTeamIds($actor, agentsOnly: true);
        abort_unless(in_array((int) $task->support_team_id, $teamIds, true), 403);
    }
    private function event(SupportTask $task,?User $actor,string $event,?string $from,?string $to,array $metadata=[]):void{SupportTaskEvent::query()->create(['support_task_id'=>$task->id,'actor_user_id'=>$actor?->id,'actor_name_snapshot'=>$actor?->name,'event'=>$event,'from_status'=>$from,'to_status'=>$to,'metadata'=>$metadata?:null,'created_at'=>now()]);}
}
