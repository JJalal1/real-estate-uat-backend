from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path):
    return (ROOT / path).read_text()


def write(path, value):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(value)


def replace_once(path, old, new):
    s = text(path)
    if old not in s:
        raise SystemExit(f"missing pattern in {path}: {old[:120]!r}")
    write(path, s.replace(old, new, 1))


def replace_between(path, start, end, new_block):
    s = text(path)
    i = s.find(start)
    if i < 0:
        raise SystemExit(f"missing start in {path}: {start!r}")
    j = s.find(end, i)
    if j < 0:
        raise SystemExit(f"missing end in {path}: {end!r}")
    write(path, s[:i] + new_block.rstrip() + "\n\n" + s[j:])


migration = r'''<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('support_teams')) {
            Schema::create('support_teams', function (Blueprint $table): void {
                $table->id();
                $table->string('code', 80)->unique();
                $table->string('name_ar', 160);
                $table->foreignId('governorate_id')->nullable()->constrained('governorates')->nullOnDelete();
                $table->foreignId('manager_user_id')->nullable()->constrained('users')->nullOnDelete();
                $table->boolean('is_fallback')->default(false)->index();
                $table->boolean('is_active')->default(true)->index();
                $table->timestamps();
                $table->index(['governorate_id', 'is_active'], 'support_teams_governorate_active_idx');
            });
        }

        if (! Schema::hasTable('support_team_members')) {
            Schema::create('support_team_members', function (Blueprint $table): void {
                $table->id();
                $table->foreignId('support_team_id')->constrained('support_teams')->cascadeOnDelete();
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->string('member_role', 24)->default('agent');
                $table->boolean('is_available')->default(true)->index();
                $table->unsignedSmallInteger('capacity')->default(10);
                $table->timestamp('joined_at')->nullable();
                $table->timestamps();
                $table->unique(['support_team_id', 'user_id'], 'support_team_members_team_user_unique');
                $table->index(['user_id', 'is_available'], 'support_team_members_user_available_idx');
            });
        }

        Schema::table('support_tasks', function (Blueprint $table): void {
            if (! Schema::hasColumn('support_tasks', 'support_team_id')) {
                $table->foreignId('support_team_id')->nullable()->after('severity')->constrained('support_teams')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'governorate_id')) {
                $table->foreignId('governorate_id')->nullable()->after('support_team_id')->constrained('governorates')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_by_user_id')) {
                $table->foreignId('escalated_by_user_id')->nullable()->after('assigned_to_name_snapshot')->constrained('users')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_at')) {
                $table->timestamp('escalated_at')->nullable()->after('escalated_by_user_id')->index();
            }
            if (! Schema::hasColumn('support_tasks', 'escalation_reason')) {
                $table->text('escalation_reason')->nullable()->after('escalated_at');
            }
            if (! Schema::hasColumn('support_tasks', 'completed_at')) {
                $table->timestamp('completed_at')->nullable()->after('last_activity_at')->index();
            }
        });

        if (! $this->hasIndex('support_tasks', 'support_tasks_team_status_idx')) {
            Schema::table('support_tasks', function (Blueprint $table): void {
                $table->index(['support_team_id', 'status', 'priority'], 'support_tasks_team_status_idx');
            });
        }

        $managerId = DB::table('user_role as ur')
            ->join('roles as r', 'r.id', '=', 'ur.role_id')
            ->where('r.key', 'support_manager')
            ->orderBy('ur.user_id')
            ->value('ur.user_id');
        $now = now();

        DB::table('support_teams')->upsert([[
            'code' => 'general-support',
            'name_ar' => 'فريق الدعم العام',
            'governorate_id' => null,
            'manager_user_id' => $managerId,
            'is_fallback' => true,
            'is_active' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ]], ['code'], ['name_ar', 'manager_user_id', 'is_fallback', 'is_active', 'updated_at']);

        if (Schema::hasTable('governorates')) {
            $rows = DB::table('governorates')->where('is_active', true)->orderBy('id')->get();
            $teams = [];
            foreach ($rows as $row) {
                $teams[] = [
                    'code' => 'gov-'.$row->code,
                    'name_ar' => 'دعم '.$row->name_ar,
                    'governorate_id' => $row->id,
                    'manager_user_id' => $managerId,
                    'is_fallback' => false,
                    'is_active' => true,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            if ($teams !== []) {
                DB::table('support_teams')->upsert(
                    $teams,
                    ['code'],
                    ['name_ar', 'governorate_id', 'manager_user_id', 'is_active', 'updated_at']
                );
            }
        }

        $fallbackId = DB::table('support_teams')->where('code', 'general-support')->value('id');
        if ($fallbackId) {
            $staff = DB::table('user_role as ur')
                ->join('roles as r', 'r.id', '=', 'ur.role_id')
                ->whereIn('r.key', ['support_agent', 'support_manager'])
                ->select('ur.user_id', 'r.key')
                ->orderBy('ur.user_id')
                ->get()
                ->groupBy('user_id');
            $members = [];
            foreach ($staff as $userId => $roles) {
                $roleKeys = $roles->pluck('key');
                $members[] = [
                    'support_team_id' => $fallbackId,
                    'user_id' => $userId,
                    'member_role' => $roleKeys->contains('support_manager') ? 'manager' : 'agent',
                    'is_available' => true,
                    'capacity' => 10,
                    'joined_at' => $now,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            if ($members !== []) {
                DB::table('support_team_members')->upsert(
                    $members,
                    ['support_team_id', 'user_id'],
                    ['member_role', 'is_available', 'capacity', 'updated_at']
                );
            }
            DB::table('support_tasks')->whereNull('support_team_id')->update([
                'support_team_id' => $fallbackId,
                'updated_at' => $now,
            ]);
        }
        DB::table('support_tasks')
            ->whereIn('status', ['completed', 'rejected'])
            ->whereNull('completed_at')
            ->update(['completed_at' => DB::raw('updated_at')]);

        if (DB::getDriverName() === 'pgsql') {
            foreach (['support_teams', 'support_team_members'] as $table) {
                DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE {$table} FROM PUBLIC");
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM anon'; END IF; IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM authenticated'; END IF; END $$;");
            }
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('support_tasks')) {
            Schema::table('support_tasks', function (Blueprint $table): void {
                foreach (['support_team_id', 'governorate_id', 'escalated_by_user_id'] as $column) {
                    if (Schema::hasColumn('support_tasks', $column)) {
                        $table->dropConstrainedForeignId($column);
                    }
                }
                foreach (['escalated_at', 'escalation_reason', 'completed_at'] as $column) {
                    if (Schema::hasColumn('support_tasks', $column)) $table->dropColumn($column);
                }
            });
        }
        Schema::dropIfExists('support_team_members');
        Schema::dropIfExists('support_teams');
    }

    private function hasIndex(string $table, string $name): bool
    {
        if (DB::getDriverName() !== 'pgsql') return false;
        return DB::table('pg_indexes')
            ->where('schemaname', 'public')
            ->where('tablename', $table)
            ->where('indexname', $name)
            ->exists();
    }
};
'''
write('backend-api-runtime/database/migrations/2026_09_12_010000_create_support_teams_and_routing.php', migration)

write('backend-api-runtime/app/Models/SupportTeam.php', r'''<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SupportTeam extends Model
{
    protected $fillable = ['code','name_ar','governorate_id','manager_user_id','is_fallback','is_active'];
    protected function casts(): array { return ['is_fallback'=>'boolean','is_active'=>'boolean']; }
    public function governorate(): BelongsTo { return $this->belongsTo(Governorate::class); }
    public function manager(): BelongsTo { return $this->belongsTo(User::class, 'manager_user_id'); }
    public function members(): HasMany { return $this->hasMany(SupportTeamMember::class); }
}
''')
write('backend-api-runtime/app/Models/SupportTeamMember.php', r'''<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SupportTeamMember extends Model
{
    protected $fillable = ['support_team_id','user_id','member_role','is_available','capacity','joined_at'];
    protected function casts(): array { return ['is_available'=>'boolean','capacity'=>'integer','joined_at'=>'datetime']; }
    public function team(): BelongsTo { return $this->belongsTo(SupportTeam::class, 'support_team_id'); }
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}
''')

replace_once('backend-api-runtime/app/Models/SupportTask.php',
"        'severity','assigned_to_user_id','assigned_to_name_snapshot',\n        'claimed_at','waiting_since','sla_due_at','source_updated_at',\n        'last_activity_at','metadata',",
"        'severity','support_team_id','governorate_id','assigned_to_user_id','assigned_to_name_snapshot',\n        'escalated_by_user_id','escalated_at','escalation_reason',\n        'claimed_at','waiting_since','sla_due_at','source_updated_at',\n        'last_activity_at','completed_at','metadata',")
replace_once('backend-api-runtime/app/Models/SupportTask.php',
"            'sla_due_at'=>'datetime','source_updated_at'=>'datetime',\n            'last_activity_at'=>'datetime','metadata'=>'array',",
"            'sla_due_at'=>'datetime','source_updated_at'=>'datetime',\n            'last_activity_at'=>'datetime','completed_at'=>'datetime',\n            'escalated_at'=>'datetime','metadata'=>'array',")
replace_once('backend-api-runtime/app/Models/SupportTask.php',
"    public function requester(): BelongsTo\n    {\n        return $this->belongsTo(User::class, 'requester_user_id');\n    }",
"    public function requester(): BelongsTo\n    {\n        return $this->belongsTo(User::class, 'requester_user_id');\n    }\n\n    public function team(): BelongsTo\n    {\n        return $this->belongsTo(SupportTeam::class, 'support_team_id');\n    }\n\n    public function governorate(): BelongsTo\n    {\n        return $this->belongsTo(Governorate::class);\n    }")

svc='backend-api-runtime/app/Services/SupportTaskService.php'
replace_between(svc, '    public function queryFor(', '    public function claim(', r'''    public function queryFor(User $actor, array $filters): Builder
    {
        if (! $this->isSupportAgent($actor) && ! $this->isManager($actor)) abort(403);
        $this->ensureWorkspaceSeeded();
        $this->ensureSupportStaffMembership($actor);
        $actingAsAgent = (bool)($filters['acting_as_agent'] ?? false);
        $query = SupportTask::query()->with(['team:id,name_ar','governorate:id,name_ar']);
        $this->applyActorTeamScope($query, $actor);
        $scope = (string)($filters['scope'] ?? 'inbox');

        if ($this->isSupportAgent($actor) || ($this->isManager($actor) && $actingAsAgent)) {
            if ($this->isSupportAgent($actor)) $this->applyAgentTypePermissions($query, $actor);
            if ($scope === 'mine') {
                $query->where('assigned_to_user_id', $actor->id);
            } else {
                $query->whereNull('assigned_to_user_id')->whereIn('status', self::ACTIVE_STATUSES);
            }
        } elseif ($scope === 'mine') {
            $query->where('assigned_to_user_id', $actor->id);
        } elseif ($scope === 'inbox') {
            $query->whereNull('assigned_to_user_id')->whereIn('status', self::ACTIVE_STATUSES);
        }

        if (!empty($filters['type'])) $query->where('source_type',$filters['type']);
        if (!empty($filters['status'])) $query->where('status',$filters['status']);
        if (!empty($filters['priority'])) $query->where('priority',$filters['priority']);
        if (!empty($filters['severity'])) $query->where('severity',$filters['severity']);
        if (!empty($filters['created_from'])) $query->where('created_at','>=',Carbon::parse($filters['created_from'])->startOfDay());
        if (!empty($filters['created_to'])) $query->where('created_at','<=',Carbon::parse($filters['created_to'])->endOfDay());
        if (!empty($filters['assignee_id']) && !$this->isSupportAgent($actor) && !$actingAsAgent) {
            $query->where('assigned_to_user_id',(int)$filters['assignee_id']);
        }
        if (($filters['overdue']??false)===true) {
            $query->whereIn('status',self::ACTIVE_STATUSES)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now());
        }

        return $query
            ->orderByRaw("CASE priority WHEN 'urgent' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END")
            ->orderByRaw('CASE WHEN sla_due_at IS NULL THEN 1 ELSE 0 END')
            ->orderBy('sla_due_at')->orderBy('created_at');
    }''')

replace_between(svc, '    public function claim(', '    public function assign(', r'''    public function claim(User $actor, SupportTask $task, Request $request, bool $actingAsAgent=false): SupportTask
    {
        $this->ensureSupportStaffMembership($actor);
        $this->assertCanHandleType($actor,$task->source_type,$actingAsAgent);
        $this->assertTaskInActorScope($actor,$task);
        $this->assertClaimCapacity($actor,$task,$actingAsAgent);
        return DB::transaction(function()use($actor,$task,$request,$actingAsAgent):SupportTask{
            $locked=SupportTask::query()->lockForUpdate()->findOrFail($task->id);
            $this->assertTaskInActorScope($actor,$locked);
            if (!$locked->isActive()) throw new ConflictHttpException('هذه المهمة مغلقة ولا يمكن استلامها.');
            if ($locked->status === 'escalated') throw new ConflictHttpException('هذه المهمة مصعّدة وتحتاج معالجة المدير قبل استئنافها.');
            if ($locked->assigned_to_user_id && (int)$locked->assigned_to_user_id!==(int)$actor->id) {
                throw new ConflictHttpException('تم استلام هذه المهمة بواسطة موظف آخر.');
            }
            $this->claimSource($actor,$locked);
            $from=$locked->status;
            $metadata=$locked->metadata??[];
            if ($actingAsAgent && $this->isManager($actor)) $metadata['manager_agent_mode']=true;
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
    }''')

replace_between(svc, '    public function assign(', '    public function classify(', r'''    public function assign(User $actor, SupportTask $task, User $assignee, Request $request): SupportTask
    {
        $this->assertManager($actor);
        $this->assertTaskInActorScope($actor,$task);
        if (!$assignee->hasRole('support_agent')) {
            if (!($actor->is_platform_owner || $actor->hasRole('super_admin')) || !$assignee->hasRole('support_manager')) {
                throw ValidationException::withMessages(['user_id'=>['الإسناد الإداري يكون لموظف دعم. مدير الدعم يعمل على الطلبات عبر وضع «العمل كموظف دعم».']]);
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
            unset($metadata['manager_agent_mode']);
            $locked->forceFill([
                'assigned_to_user_id'=>$assignee->id,'assigned_to_name_snapshot'=>$assignee->name,
                'claimed_at'=>$locked->claimed_at?:now(),'status'=>$next,
                'last_activity_at'=>now(),'metadata'=>$metadata,
            ])->save();
            $this->event($locked,$actor,'assigned',$from,$next,['from_user_id'=>$before,'to_user_id'=>$assignee->id]);
            $this->audit->record($actor,'support_task.assigned',$locked,['from_user_id'=>$before,'to_user_id'=>$assignee->id],$request,$locked->requester_user_id);
            $this->notifications->create($assignee->id,'support_task_assigned','تم إسناد مهمة دعم إليك',$locked->subject,'support_task',$locked->id,['task_id'=>$locked->id,'source_type'=>$locked->source_type]);
            return $locked->fresh(['team','governorate']);
        });
    }''')

replace_once(svc,
"        $this->assertManager($actor);\n        return DB::transaction(function()use($actor,$task,$priority,$severity,$request):SupportTask{",
"        $this->assertManager($actor);\n        $this->assertTaskInActorScope($actor,$task);\n        return DB::transaction(function()use($actor,$task,$priority,$severity,$request):SupportTask{")

replace_between(svc, '    public function setOperationalStatus(', '    public function escalate(', r'''    public function setOperationalStatus(User $actor, SupportTask $task, string $status, Request $request, bool $actingAsAgent=false): SupportTask
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
    }''')

replace_between(svc, '    public function escalate(', '    public function reopen(', r'''    public function escalate(User $actor, SupportTask $task, string $reason, Request $request, bool $actingAsAgent=false): SupportTask
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
    }''')

replace_once(svc,
"        $this->assertManager($actor);\n        if (!in_array($task->source_type,['support_ticket','report'],true)) {",
"        $this->assertManager($actor);\n        $this->assertTaskInActorScope($actor,$task);\n        if (!in_array($task->source_type,['support_ticket','report'],true)) {")

replace_between(svc, '    public function requestVerificationDocuments(', '    public function rejectVerification(', r'''    public function requestVerificationDocuments(User $actor, SupportTask $task, string $note, Request $request, bool $actingAsAgent=false): SupportTask
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
    }''')

replace_between(svc, '    public function rejectVerification(', '    public function assertTaskOwnership(', r'''    public function rejectVerification(User $actor, SupportTask $task, string $reason, Request $request, bool $actingAsAgent=false): SupportTask
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
    }''')

replace_between(svc, '    public function assertTaskOwnership(', '    public function teamMetrics(', r'''    public function assertTaskOwnership(User $actor, SupportTask $task): void
    {
        if ($this->isManager($actor)) {
            $this->assertTaskInActorScope($actor,$task);
            return;
        }
        if ((int)($task->assigned_to_user_id??0)!==(int)$actor->id) throw new ConflictHttpException('يجب استلام المهمة أولاً قبل تنفيذ هذا الإجراء.');
    }

    public function assertTaskExecution(User $actor, SupportTask $task, bool $actingAsAgent=false): void
    {
        $this->assertTaskInActorScope($actor,$task);
        if ($this->isManager($actor)) {
            if (!$actingAsAgent || (int)($task->assigned_to_user_id??0)!==(int)$actor->id) {
                throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» واستلم المهمة قبل تنفيذ الإجراء.');
            }
            return;
        }
        $this->assertAgent($actor);
        if ((int)($task->assigned_to_user_id??0)!==(int)$actor->id) throw new ConflictHttpException('يجب استلام المهمة أولاً قبل تنفيذ هذا الإجراء.');
    }''')

replace_between(svc, '    public function teamMetrics(', '    public function dashboard(', r'''    public function teamMetrics(User $actor): array
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
    }''')

replace_once(svc,
"    public function dashboard(User $actor): array\n    {\n        $this->syncSources();\n        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) return $this->platformDashboard();\n        if ($this->isManager($actor)) return $this->managerDashboard();",
"    public function dashboard(User $actor): array\n    {\n        $this->ensureWorkspaceSeeded();\n        $this->ensureSupportStaffMembership($actor);\n        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) return $this->platformDashboard();\n        if ($this->isManager($actor)) return $this->managerDashboard($actor);")

replace_between(svc, '    public function taskData(', '    private function agentDashboard(', r'''    public function taskData(SupportTask $task, User $actor): array
    {
        $task->loadMissing(['team:id,name_ar','governorate:id,name_ar']);
        $remaining=$task->sla_due_at?now()->diffInMinutes($task->sla_due_at,false):null;
        return [
            'id'=>$task->id,'source_type'=>$task->source_type,'source_id'=>$task->source_id,'source_reference'=>$task->source_reference,'subject'=>$task->subject,
            'requester_user_id'=>$task->requester_user_id,'requester_name'=>$task->requester_name_snapshot,'status'=>$task->status,'priority'=>$task->priority,'severity'=>$task->severity,
            'support_team_id'=>$task->support_team_id,'support_team_name'=>$task->team?->name_ar,'governorate_id'=>$task->governorate_id,'governorate_name'=>$task->governorate?->name_ar,
            'assigned_to_user_id'=>$task->assigned_to_user_id,'assigned_to_name'=>$task->assigned_to_name_snapshot,
            'created_at'=>$task->created_at?->toIso8601String(),'claimed_at'=>$task->claimed_at?->toIso8601String(),'completed_at'=>$task->completed_at?->toIso8601String(),
            'last_activity_at'=>$task->last_activity_at?->toIso8601String(),'sla_due_at'=>$task->sla_due_at?->toIso8601String(),
            'remaining_minutes'=>$remaining,'is_overdue'=>$remaining!==null&&$remaining<0,'is_mine'=>(int)($task->assigned_to_user_id??0)===(int)$actor->id,
            'can_claim'=>$task->isActive()&&!$task->assigned_to_user_id&&$task->status!=='escalated',
            'escalated_at'=>$task->escalated_at?->toIso8601String(),'escalation_reason'=>$task->escalation_reason,
            'metadata'=>$task->metadata??[],
        ];
    }''')

replace_between(svc, '    private function agentDashboard(', '    private function managerDashboard(', r'''    private function agentDashboard(User $actor): array
    {
        $base=SupportTask::query();$this->applyActorTeamScope($base,$actor);$this->applyAgentTypePermissions($base,$actor);
        return [
            'mode'=>'agent','inbox_new'=>(clone $base)->whereNull('assigned_to_user_id')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'my_tasks'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'account_verifications'=>(clone $base)->where('source_type','account_verification')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'listing_reviews'=>(clone $base)->where('source_type','listing_review')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'tickets'=>(clone $base)->where('source_type','support_ticket')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'reports'=>(clone $base)->where('source_type','report')->whereIn('status',self::ACTIVE_STATUSES)->count(),
            'waiting_user'=>(clone $base)->where('assigned_to_user_id',$actor->id)->where('status','waiting_user')->count(),
            'overdue'=>(clone $base)->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'attention'=>$this->attentionQuery($base,$actor->id)->limit(8)->get()->map(fn(SupportTask $t)=>$this->taskData($t,$actor))->values(),
        ];
    }''')

replace_between(svc, '    private function managerDashboard(', '    private function platformDashboard(', r'''    private function managerDashboard(User $actor): array
    {
        $active=SupportTask::query()->whereIn('status',self::ACTIVE_STATUSES);$this->applyActorTeamScope($active,$actor);
        $claimed=SupportTask::query()->whereNotNull('claimed_at');$this->applyActorTeamScope($claimed,$actor);
        $claimed=$claimed->latest('id')->limit(300)->get(['claimed_at','created_at']);
        $avg=$claimed->isEmpty()?null:(int)round($claimed->avg(fn(SupportTask $t)=>$t->created_at->diffInMinutes($t->claimed_at)));
        $team=collect($this->teamMetrics($actor));
        return [
            'mode'=>'manager','unassigned'=>(clone $active)->whereNull('assigned_to_user_id')->count(),
            'in_progress'=>(clone $active)->whereNotNull('assigned_to_user_id')->whereIn('status',['in_progress','needs_followup'])->count(),
            'overdue'=>(clone $active)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),
            'waiting_user'=>(clone $active)->where('status','waiting_user')->count(),'escalated'=>(clone $active)->where('status','escalated')->count(),
            'critical_reports'=>(clone $active)->where('source_type','report')->where('severity','critical')->count(),
            'active_agents'=>$team->where('role','support_agent')->count(),'available_agents'=>$team->where('role','support_agent')->where('is_available',true)->count(),
            'team_open'=>$team->sum('open_tasks'),'completed_today'=>$team->sum('completed_today'),
            'average_claim_minutes'=>$avg,'average_response_minutes'=>$team->whereNotNull('average_response_minutes')->avg('average_response_minutes')===null?null:(int)round($team->whereNotNull('average_response_minutes')->avg('average_response_minutes')),
        ];
    }''')

# Make legacy/source upserts route to the general/geographic team and maintain completion timestamps.
replace_once(svc,
"        $task->last_activity_at=$sourceUpdatedAt?:now();$task->metadata=array_merge($current,$metadata);$task->save();\n        if($isNew)$this->event($task,null,'created_from_source',null,$status);\n        elseif($oldStatus&&$oldStatus!==$status)$this->event($task,null,'source_status_synced',$oldStatus,$status);\n        return $task;",
"        $task->last_activity_at=$sourceUpdatedAt?:now();$task->metadata=array_merge($current,$metadata);\n        if (Schema::hasColumn('support_tasks','completed_at')) $task->completed_at=in_array($status,['completed','rejected'],true)?($task->completed_at?:now()):null;\n        $task->save();\n        if($isNew)$this->event($task,null,'created_from_source',null,$status);\n        elseif($oldStatus&&$oldStatus!==$status)$this->event($task,null,'source_status_synced',$oldStatus,$status);\n        if (Schema::hasColumn('support_tasks','support_team_id')) $task=$this->routeTask($task,$this->governorateIdFromMetadata($task->metadata??[]));\n        return $task;")

replace_once(svc,
"            SupportCase::query()->whereKey($task->source_id)->update([\n                'status'=>'in_progress','assigned_to_user_id'=>$assignee->id,",
"            $case=SupportCase::query()->find($task->source_id);\n            SupportCase::query()->whereKey($task->source_id)->update([\n                'status'=>$case?->status==='open'?'in_progress':($case?->status??'in_progress'),'assigned_to_user_id'=>$assignee->id,")

replace_between(svc, '    private function assertCanHandleType(', '    private function assertAgent(', r'''    private function assertCanHandleType(User $actor, string $type, bool $actingAsAgent=false): void
    {
        if($this->isManager($actor)){
            if(!$actingAsAgent) throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة بنفسك.');
            return;
        }
        $this->assertAgent($actor);
        if($type==='listing_review'&&!$actor->hasPermission('listings.moderate'))abort(403);
        if(in_array($type,['support_ticket','report','account_verification'],true)&&!$actor->hasPermission('support.handle_reports'))abort(403);
    }''')

extra = r'''    public function projectSource(string $type, int $sourceId): ?SupportTask
    {
        return match($type) {
            'account_verification' => $this->projectAccountVerification($sourceId),
            'listing_review' => $this->projectListing($sourceId),
            'support_ticket', 'report' => $this->projectSupportCase($sourceId),
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
        $task=$this->upsertTask('account_verification',$userId,'KYC-'.$userId,'طلب تحقق '.match($type){'owner'=>'مالك','broker'=>'دلال','office'=>'مكتب عقارات',default=>'حساب'},$user,$status,'normal',null,$existing?->assigned_to_user_id,$existing?->assigned_to_name_snapshot,$sla,$updated,['verification_type'=>$type,'governorate_id'=>$govId,'governorate'=>$details['governorate']??null],false);
        return $this->routeTask($task,$govId);
    }

    public function projectListing(Property|int $listing): ?SupportTask
    {
        $property=$listing instanceof Property?$listing->fresh(['user']):Property::query()->with('user')->find($listing);
        if(!$property)return null;
        $existing=SupportTask::query()->where('source_type','listing_review')->where('source_id',$property->id)->first();
        $status=match($property->review_status){'approved'=>'completed','rejected_blocked'=>'rejected','returned_for_correction'=>'waiting_user','under_review'=>'in_progress','submitted'=>$existing?->status==='waiting_user'?'needs_followup':($property->review_assigned_to_user_id?'in_progress':'new'),default=>'completed'};
        $release=$property->review_status==='submitted'&&$existing?->status==='waiting_user';$submitted=$property->submitted_at?:$property->updated_at?:now();$assigneeId=$release?null:$property->review_assigned_to_user_id;
        $assigneeName=$assigneeId?User::query()->whereKey($assigneeId)->value('name'):null;$govId=$this->listingGovernorateId($property);
        $task=$this->upsertTask('listing_review',$property->id,'LIST-'.$property->id,'تحقيق إعلان: '.$property->title,$property->user,$status,'normal',null,$assigneeId,$assigneeName,in_array($status,['waiting_user','completed','rejected'],true)?null:$submitted->copy()->addHours(24),$property->updated_at,['review_status'=>$property->review_status,'price'=>$property->price,'purpose'=>$property->purpose,'property_type'=>$property->type,'governorate_id'=>$govId],$release||in_array($status,['waiting_user','completed','rejected'],true));
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
        $task=$this->upsertTask($type,$case->id,$case->reference,$case->subject,$requester,$status,$priority,$severity,$case->assigned_to_user_id,$case->assigned_to_name_snapshot,$case->sla_due_at,$case->updated_at,['kind'=>$case->kind,'reason_code'=>$case->reason_code,'target_type'=>$case->target_type,'target_id'=>$case->target_id,'governorate_id'=>$govId],false);
        if($type==='report'&&$severity==='critical')$this->notifyCriticalReportManagers($task);
        return $this->routeTask($task,$govId);
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
            $this->releaseSource($locked);$metadata=$locked->metadata??[];unset($metadata['manager_agent_mode']);
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
        $this->assertManager($actor);$this->ensureSupportStaffMemberships();$ids=$this->managedTeamIds($actor);if($ids===[])return [];
        $memberCounts=DB::table('support_team_members')->whereIn('support_team_id',$ids)->where('member_role','agent')->selectRaw('support_team_id, count(*) as agents, sum(case when is_available then 1 else 0 end) as available_agents')->groupBy('support_team_id')->get()->keyBy('support_team_id');
        $taskCounts=SupportTask::query()->whereIn('support_team_id',$ids)->whereIn('status',self::ACTIVE_STATUSES)->selectRaw('support_team_id, count(*) as open_tasks, sum(case when assigned_to_user_id is null then 1 else 0 end) as unassigned')->groupBy('support_team_id')->get()->keyBy('support_team_id');
        return DB::table('support_teams as t')->leftJoin('governorates as g','g.id','=','t.governorate_id')->whereIn('t.id',$ids)->where('t.is_active',true)->orderByDesc('t.is_fallback')->orderBy('g.name_ar')->get(['t.id','t.code','t.name_ar','t.governorate_id','g.name_ar as governorate_name','t.is_fallback'])->map(function($t)use($memberCounts,$taskCounts){$m=$memberCounts->get($t->id);$w=$taskCounts->get($t->id);return ['id'=>(int)$t->id,'code'=>$t->code,'name'=>$t->name_ar,'governorate_id'=>$t->governorate_id? (int)$t->governorate_id:null,'governorate_name'=>$t->governorate_name,'is_fallback'=>(bool)$t->is_fallback,'agents'=>(int)($m->agents??0),'available_agents'=>(int)($m->available_agents??0),'open_tasks'=>(int)($w->open_tasks??0),'unassigned'=>(int)($w->unassigned??0)];})->values()->all();
    }

    public function updateTeamMember(User $actor, User $member, int $teamId, bool $available, int $capacity, Request $request): void
    {
        $this->assertManager($actor);if(!$member->hasRole('support_agent'))throw ValidationException::withMessages(['user_id'=>['يمكن إدارة توزيع موظفي الدعم فقط من هذه الشاشة.']]);
        if(!in_array($teamId,$this->managedTeamIds($actor),true))abort(403);$capacity=max(1,min(50,$capacity));
        DB::transaction(function()use($actor,$member,$teamId,$available,$capacity,$request):void{
            DB::table('support_team_members')->where('user_id',$member->id)->where('member_role','agent')->delete();
            DB::table('support_team_members')->updateOrInsert(['support_team_id'=>$teamId,'user_id'=>$member->id],['member_role'=>'agent','is_available'=>$available,'capacity'=>$capacity,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
            $this->audit->record($actor,'support_team.member_updated',$member,['support_team_id'=>$teamId,'is_available'=>$available,'capacity'=>$capacity],$request,$member->id);
        });
    }

    private function ensureWorkspaceSeeded(): void
    {
        if(Schema::hasTable('support_tasks')&&!SupportTask::query()->exists())$this->syncSources();
    }

    private function ensureSupportStaffMembership(User $actor): void
    {
        if(!Schema::hasTable('support_team_members')||(! $actor->hasRole('support_agent')&&!$actor->hasRole('support_manager')))return;
        if(DB::table('support_team_members')->where('user_id',$actor->id)->exists())return;$fallback=$this->fallbackTeamId();if(!$fallback)return;
        $role=$actor->hasRole('support_manager')?'manager':'agent';DB::table('support_team_members')->updateOrInsert(['support_team_id'=>$fallback,'user_id'=>$actor->id],['member_role'=>$role,'is_available'=>true,'capacity'=>10,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        if($role==='manager')DB::table('support_teams')->whereKey($fallback)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);
    }

    private function ensureSupportStaffMemberships(): void
    {
        if(!Schema::hasTable('support_team_members'))return;$users=User::query()->whereHas('roles',fn($q)=>$q->whereIn('roles.key',['support_agent','support_manager']))->get();foreach($users as $u)$this->ensureSupportStaffMembership($u);
    }

    private function managedTeamIds(User $actor): array
    {
        if(!Schema::hasTable('support_teams'))return [];
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return DB::table('support_teams')->where('is_active',true)->pluck('id')->map(fn($id)=>(int)$id)->all();
        $ids=DB::table('support_teams as t')->leftJoin('support_team_members as m',function($j)use($actor){$j->on('m.support_team_id','=','t.id')->where('m.user_id','=',$actor->id)->where('m.member_role','=','manager');})->where('t.is_active',true)->where(function($q)use($actor){$q->where('t.manager_user_id',$actor->id)->orWhereNotNull('m.id');})->pluck('t.id')->map(fn($id)=>(int)$id)->unique()->values()->all();
        if($ids===[]&&$actor->hasRole('support_manager')){$fallback=$this->fallbackTeamId();if($fallback)$ids=[$fallback];}return $ids;
    }

    private function actorTeamIds(User $actor): array
    {
        if($this->isManager($actor))return $this->managedTeamIds($actor);if(!Schema::hasTable('support_team_members'))return [];
        $ids=DB::table('support_team_members')->where('user_id',$actor->id)->pluck('support_team_id')->map(fn($id)=>(int)$id)->all();if($ids===[]){$this->ensureSupportStaffMembership($actor);$ids=DB::table('support_team_members')->where('user_id',$actor->id)->pluck('support_team_id')->map(fn($id)=>(int)$id)->all();}return $ids;
    }

    private function applyActorTeamScope(Builder $query, User $actor): void
    {
        if(!Schema::hasColumn('support_tasks','support_team_id')||$actor->is_platform_owner||$actor->hasRole('super_admin'))return;$ids=$this->actorTeamIds($actor);$query->whereIn('support_team_id',$ids?:[-1]);
    }

    private function assertTaskInActorScope(User $actor, SupportTask $task): void
    {
        if(!Schema::hasColumn('support_tasks','support_team_id')||$actor->is_platform_owner||$actor->hasRole('super_admin'))return;$this->ensureSupportStaffMembership($actor);if(!in_array((int)($task->support_team_id??0),$this->actorTeamIds($actor),true))abort(403);
    }

    private function assertClaimCapacity(User $actor, SupportTask $task, bool $actingAsAgent): void
    {
        if($this->isManager($actor)&&!$actingAsAgent)throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل استلام مهمة.');
        if(!$this->isManager($actor)){
            $member=DB::table('support_team_members')->where('user_id',$actor->id)->where('support_team_id',$task->support_team_id)->first();if(!$member||!$member->is_available)throw new ConflictHttpException('حالتك غير متاحة لاستلام مهام جديدة في هذا الفريق.');$capacity=max(1,(int)$member->capacity);
        }else{$capacity=10;}
        $open=SupportTask::query()->where('assigned_to_user_id',$actor->id)->whereIn('status',self::ACTIVE_STATUSES)->count();if($open>=$capacity)throw new ConflictHttpException('وصلت للحد الحالي من المهام المفتوحة. أكمل بعض مهامك أو اطلب من المدير إعادة التوزيع.');
    }

    private function assertAssigneeCanReceive(User $actor, SupportTask $task, User $assignee): void
    {
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;$member=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('user_id',$assignee->id)->where('member_role','agent')->first();if(!$member)throw ValidationException::withMessages(['user_id'=>['الموظف ليس ضمن الفريق المسؤول عن هذه المهمة.']]);
    }

    private function fallbackTeamId(): ?int
    {
        if(!Schema::hasTable('support_teams'))return null;$id=DB::table('support_teams')->where('is_fallback',true)->where('is_active',true)->value('id');return $id?(int)$id:null;
    }

    private function routeTask(SupportTask $task, ?int $governorateId): SupportTask
    {
        if(!Schema::hasTable('support_teams')||!Schema::hasColumn('support_tasks','support_team_id'))return $task;$teamId=null;
        if($governorateId){$candidate=DB::table('support_teams')->where('governorate_id',$governorateId)->where('is_active',true)->value('id');if($candidate){$hasAgent=DB::table('support_team_members')->where('support_team_id',$candidate)->where('member_role','agent')->where('is_available',true)->exists();if($hasAgent)$teamId=(int)$candidate;}}
        $teamId=$teamId?:$this->fallbackTeamId();if(!$teamId)return $task;$task->forceFill(['support_team_id'=>$teamId,'governorate_id'=>$governorateId])->save();return $task;
    }

    private function governorateIdFromMetadata(array $metadata): ?int
    {
        if(!empty($metadata['governorate_id']))return (int)$metadata['governorate_id'];return $this->resolveGovernorateIdFromName($metadata['governorate']??null);
    }

    private function resolveGovernorateIdFromName(mixed $name): ?int
    {
        $needle=$this->normalizeArabic((string)$name);if($needle===''||!Schema::hasTable('governorates'))return null;foreach(DB::table('governorates')->where('is_active',true)->get(['id','name_ar','name_en']) as $g){foreach([$g->name_ar,$g->name_en] as $candidate){$n=$this->normalizeArabic((string)$candidate);if($n!==''&&($needle===$n||str_contains($needle,$n)||str_contains($n,$needle)))return (int)$g->id;}}return null;
    }

    private function listingGovernorateId(Property $property): ?int
    {
        if($property->geo_cell_id&&Schema::hasTable('geo_cells')){$id=DB::table('geo_cells')->where('id',$property->geo_cell_id)->value('governorate_id');if($id)return (int)$id;}return $this->resolveGovernorateIdFromName($property->address);
    }

    private function supportCaseGovernorateId(SupportCase $case, ?User $requester): ?int
    {
        if($case->target_id&&in_array($case->target_type,['property','listing','property_listing'],true)){$p=Property::query()->find($case->target_id);if($p){$id=$this->listingGovernorateId($p);if($id)return $id;}}
        if($requester&&Schema::hasTable('account_verification_profiles')){$details=DB::table('account_verification_profiles')->where('user_id',$requester->id)->value('details');$map=$this->jsonMap($details);return $this->resolveGovernorateIdFromName($map['governorate']??null);}return null;
    }

    private function jsonMap(mixed $value): array
    {
        if(is_array($value))return $value;if(is_object($value))return (array)$value;if(is_string($value)){try{$decoded=json_decode($value,true,512,JSON_THROW_ON_ERROR);return is_array($decoded)?$decoded:[];}catch(\Throwable){}}return [];
    }

    private function normalizeArabic(string $value): string
    {
        $value=mb_strtolower(trim($value));$value=preg_replace('/[\\x{064B}-\\x{065F}\\x{0670}\\x{0640}]/u','',$value)??$value;$value=strtr($value,['أ'=>'ا','إ'=>'ا','آ'=>'ا','ى'=>'ي','ؤ'=>'و','ئ'=>'ي','ة'=>'ه']);return preg_replace('/\\s+/u',' ',$value)??$value;
    }

    private function releaseSource(SupportTask $task): void
    {
        if($task->source_type==='listing_review'){Property::query()->whereKey($task->source_id)->where('review_status','under_review')->update(['review_status'=>'submitted','status'=>'pending','review_assigned_to_user_id'=>null,'review_assigned_at'=>null,'updated_at'=>now()]);return;}
        if(in_array($task->source_type,['support_ticket','report'],true)){$case=SupportCase::query()->find($task->source_id);if(!$case)return;$status=$case->status==='in_progress'?'open':$case->status;$case->forceFill(['status'=>$status,'assigned_to_user_id'=>null,'assigned_to_name_snapshot'=>null,'last_activity_at'=>now()])->save();}
    }

    private function notifyTaskManagers(SupportTask $task, string $title, string $body): void
    {
        if(!Schema::hasTable('support_teams'))return;$ids=[];$manager=DB::table('support_teams')->where('id',$task->support_team_id)->value('manager_user_id');if($manager)$ids[]=(int)$manager;$memberManagers=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('member_role','manager')->pluck('user_id')->map(fn($id)=>(int)$id)->all();$ids=array_values(array_unique(array_merge($ids,$memberManagers)));foreach($ids as $id){if($id===(int)$task->assigned_to_user_id)continue;$this->notifications->create($id,'support_task_escalated',$title,$body,'support_task',$task->id,['task_id'=>$task->id,'source_type'=>$task->source_type]);}
    }
'''
replace_once(svc, '    private function event(SupportTask $task, ?User $actor, string $event, ?string $from, ?string $to, array $metadata=[]): void', extra + "\n    private function event(SupportTask $task, ?User $actor, string $event, ?string $from, ?string $to, array $metadata=[]): void")

# Support cases project themselves into the shared queue at mutation time.
case='backend-api-runtime/app/Services/SupportCaseService.php'
replace_once(case,
"    public function __construct(private readonly AuditLogService $audit, private readonly UserNotificationService $notifications, private readonly PlatformSettingsService $settings) {}",
"    public function __construct(private readonly AuditLogService $audit, private readonly UserNotificationService $notifications, private readonly PlatformSettingsService $settings, private readonly SupportTaskService $tasks) {}")
s=text(case).replace('return $case->fresh();','return $this->projected($case->fresh());').replace('return $locked->fresh();','return $this->projected($locked->fresh());')
# Project automatic SLA escalation too.
s=s.replace("                $this->event($case,null,'sla_escalated'", "                $this->tasks->projectSupportCase($case);\n                $this->event($case,null,'sla_escalated'",1)
marker='    private function message(SupportCase $case, ?User $actor, string $role, bool $internal, string $body): SupportCaseMessage'
insert="    private function projected(SupportCase $case): SupportCase\n    {\n        $this->tasks->projectSupportCase($case);\n        return $case;\n    }\n\n"
if marker not in s: raise SystemExit('missing SupportCase message marker')
s=s.replace(marker,insert+marker,1)
write(case,s)

# Listing workflow projects review state immediately; managers count as support workers and must own the task before decisions.
listing='backend-api-runtime/app/Services/ListingWorkflowService.php'
replace_once(listing,
"        private readonly UserNotificationService $notifications,\n    ) {}",
"        private readonly UserNotificationService $notifications,\n        private readonly SupportTaskService $tasks,\n    ) {}")
replace_between(listing, '    private function isSupportWorker(', '    private function review(', r'''    private function isSupportWorker(User $actor): bool
    {
        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) return false;
        return $actor->hasRole('support_agent') || $actor->hasRole('support_manager');
    }''')
# Rebuild review helper with projection.
start='    private function review('
end='    private function snapshot('
s=text(listing);i=s.find(start);j=s.find(end,i)
if i<0 or j<0: raise SystemExit('listing review helper markers missing')
old=s[i:j]
body_start=old.find('    {')
# Use known safe helper body.
new=r'''    private function review(
        ?User $actor,
        Property $listing,
        string $action,
        ?string $from,
        ?string $to,
        ?string $reason = null,
        array $metadata = [],
    ): ListingReview {
        $review = ListingReview::query()->create([
            'listing_id' => $listing->id,
            'actor_user_id' => $actor?->id,
            'actor_name_snapshot' => $actor?->name,
            'action' => $action,
            'from_review_status' => $from,
            'to_review_status' => $to,
            'reason' => $reason,
            'listing_snapshot' => $this->snapshot($listing),
            'metadata' => $metadata,
            'created_at' => now(),
        ]);
        $this->tasks->projectListing($listing);
        return $review;
    }

'''
write(listing,s[:i]+new+s[j:])

# Account verification goes to the queue immediately on submit/status decisions.
av='backend-api-runtime/app/Http/Controllers/Api/AccountVerificationController.php'
replace_once(av,
"use App\\Services\\CloudAssetStorageService;\nuse App\\Services\\UserNotificationService;",
"use App\\Services\\CloudAssetStorageService;\nuse App\\Services\\SupportTaskService;\nuse App\\Services\\UserNotificationService;")
replace_once(av,
"        private readonly UserNotificationService $notifications,\n    ) {}",
"        private readonly UserNotificationService $notifications,\n        private readonly SupportTaskService $tasks,\n    ) {}")
replace_once(av,
"        return response()->json([\n            'message' => 'تم استلام طلب التحقق بنجاح.',",
"        $this->tasks->projectAccountVerification((int) $user->id);\n\n        return response()->json([\n            'message' => 'تم استلام طلب التحقق بنجاح.',")
replace_once(av,
"        $this->notifications->create(\n            $user->id,\n            'account_verification_approved',",
"        $this->tasks->projectAccountVerification((int) $user->id);\n        $this->notifications->create(\n            $user->id,\n            'account_verification_approved',")
replace_once(av,
"        $this->notifications->create(\n            $user->id,\n            'account_verification_more_info',",
"        $this->tasks->projectAccountVerification((int) $user->id);\n        $this->notifications->create(\n            $user->id,\n            'account_verification_more_info',")
replace_once(av,
"        $this->notifications->create(\n            $user->id,\n            'account_verification_rejected',",
"        $this->tasks->projectAccountVerification((int) $user->id);\n        $this->notifications->create(\n            $user->id,\n            'account_verification_rejected',")

# Ownership middleware: support managers no longer bypass execution; only GM/super-admin does.
write('backend-api-runtime/app/Http/Middleware/EnsureSupportTaskOwnership.php', r'''<?php
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
        if (!Schema::hasTable('support_tasks')) return $next($request);
        $actor=$request->user();
        if(!$actor)return $next($request);
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return $next($request);
        if(!$actor->hasRole('support_agent')&&!$actor->hasRole('support_manager')&&!$actor->hasPermission('support.manage'))return $next($request);

        $path=$request->path();
        if(preg_match('#^api/admin/account-verifications/(\\d+)/(approve|more-info|reject)$#',$path,$m)&&$request->isMethod('post'))$this->assertOwned((int)$actor->id,'account_verification',(int)$m[1]);
        if(preg_match('#^api/account-verification/users/(\\d+)/documents/[^/]+$#',$path,$m)&&$request->isMethod('get'))$this->assertOwned((int)$actor->id,'account_verification',(int)$m[1]);
        if(preg_match('#^api/admin/support/cases/(\\d+)$#',$path,$m)&&$request->isMethod('get'))$this->assertSupportCaseOwned((int)$actor->id,(int)$m[1]);
        if(preg_match('#^api/admin/support/cases/(\\d+)/(start|reply|note|status)$#',$path,$m))$this->assertSupportCaseOwned((int)$actor->id,(int)$m[1]);
        return $next($request);
    }

    private function assertSupportCaseOwned(int $actorId,int $caseId): void
    {
        $case=SupportCase::query()->find($caseId);if(!$case)return;
        if((int)($case->assigned_to_user_id??0)!==$actorId)throw new ConflictHttpException('يجب استلام المهمة من مركز الدعم أولاً.');
        $this->assertOwned($actorId,$case->kind==='report'?'report':'support_ticket',$caseId);
    }

    private function assertOwned(int $actorId,string $type,int $sourceId): void
    {
        $task=SupportTask::query()->where('source_type',$type)->where('source_id',$sourceId)->whereIn('status',SupportTaskService::ACTIVE_STATUSES)->first();
        if(!$task)$task=$this->tasks->projectSource($type,$sourceId);
        if($task&&(int)($task->assigned_to_user_id??0)!==$actorId)throw new ConflictHttpException('يجب استلام المهمة من مركز الدعم أولاً.');
    }
}
''')

# Workspace controller with team management, explicit manager-agent mode and escalation resolution.
write('backend-api-runtime/app/Http/Controllers/Api/SupportWorkspaceController.php', r'''<?php
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
            'scope'=>['nullable',Rule::in(['inbox','mine','all'])],'type'=>['nullable',Rule::in(['account_verification','listing_review','support_ticket','report'])],
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
''')

routes='backend-api-runtime/routes/support_workspace.php'
rs=text(routes)
rs=rs.replace("Route::post('/tasks/{task}/claim', [SupportWorkspaceController::class, 'claim']);", "Route::post('/tasks/{task}/claim', [SupportWorkspaceController::class, 'claim']);\nRoute::post('/tasks/{task}/release', [SupportWorkspaceController::class, 'release']);")
rs=rs.replace("Route::post('/tasks/{task}/escalate', [SupportWorkspaceController::class, 'escalate']);", "Route::post('/tasks/{task}/escalate', [SupportWorkspaceController::class, 'escalate']);\nRoute::post('/tasks/{task}/resolve-escalation', [SupportWorkspaceController::class, 'resolveEscalation']);")
rs=rs.replace("Route::get('/team', [SupportWorkspaceController::class, 'team']);", "Route::get('/team', [SupportWorkspaceController::class, 'team']);\nRoute::get('/teams', [SupportWorkspaceController::class, 'teams']);\nRoute::put('/team/members/{user}', [SupportWorkspaceController::class, 'updateMember']);\nRoute::post('/team/members/{user}/redistribute', [SupportWorkspaceController::class, 'redistributeMember']);")
write(routes,rs)

# Backend acceptance coverage.
write('backend-api-runtime/tests/Feature/UatSupportManagerAgentWorkflowApiTest.php', r'''<?php
namespace Tests\Feature;

use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatSupportManagerAgentWorkflowApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_new_support_case_reaches_shared_inbox_without_read_time_sync(): void
    {
        [, $requesterHeaders]=$this->user('direct-requester@example.test','+967744410001');
        [, $agentHeaders]=$this->user('direct-agent@example.test','+967744410002',['support_agent']);
        $case=$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'طلب يصل مباشرة','description'=>'يجب إنشاء مهمة الدعم فور إنشاء الطلب دون انتظار فتح الوارد.','category'=>'technical'])->assertCreated();
        $caseId=(int)$case->json('data.id');
        $this->assertDatabaseHas('support_tasks',['source_type'=>'support_ticket','source_id'=>$caseId,'status'=>'new']);
        $this->withHeaders($agentHeaders)->getJson('/api/admin/workspace/tasks?scope=inbox&type=support_ticket')->assertOk()->assertJsonPath('meta.total',1)->assertJsonPath('data.0.source_id',$caseId);
    }

    public function test_agent_escalates_owned_task_and_manager_resolves_without_becoming_approval_gate(): void
    {
        [, $requesterHeaders]=$this->user('escalate-requester@example.test','+967744410011');
        [$agent,$agentHeaders]=$this->user('escalate-agent@example.test','+967744410012',['support_agent']);
        [, $managerHeaders]=$this->user('escalate-manager@example.test','+967744410013',['support_manager']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'حالة غير اعتيادية','description'=>'حالة تحتاج قرار إداري استثنائي فقط.','category'=>'technical'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_type','support_ticket')->where('source_id',$caseId)->firstOrFail();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertOk()->assertJsonPath('data.assigned_to_user_id',$agent->id);
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/escalate",['reason'=>'تعارض يحتاج قرار مدير الدعم.'])->assertOk()->assertJsonPath('data.status','escalated');
        $this->withHeaders($managerHeaders)->getJson('/api/admin/workspace/dashboard')->assertOk()->assertJsonPath('data.escalated',1);
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/resolve-escalation",['note'=>'تمت مراجعة الاستثناء، أكمل الإجراء المعتاد.'])->assertOk()->assertJsonPath('data.status','in_progress')->assertJsonPath('data.assigned_to_user_id',$agent->id);
    }

    public function test_support_manager_must_explicitly_act_as_agent_before_claiming_work(): void
    {
        [, $requesterHeaders]=$this->user('mode-requester@example.test','+967744410021');
        [$manager,$managerHeaders]=$this->user('mode-manager@example.test','+967744410022',['support_manager']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'ضغط وارد','description'=>'مدير الدعم يساعد الفريق فقط عبر الوضع الواضح.','category'=>'other'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_id',$caseId)->where('source_type','support_ticket')->firstOrFail();
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertStatus(409);
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim",['acting_as_agent'=>true])->assertOk()->assertJsonPath('data.assigned_to_user_id',$manager->id);
        $this->assertDatabaseHas('support_task_events',['support_task_id'=>$task->id,'event'=>'claimed','actor_user_id'=>$manager->id]);
    }

    public function test_manager_controls_team_availability_capacity_and_can_return_work_to_inbox(): void
    {
        [, $requesterHeaders]=$this->user('team-requester@example.test','+967744410031');
        [$agent,$agentHeaders]=$this->user('team-agent@example.test','+967744410032',['support_agent']);
        [, $managerHeaders]=$this->user('team-manager@example.test','+967744410033',['support_manager']);
        $teams=$this->withHeaders($managerHeaders)->getJson('/api/admin/workspace/teams')->assertOk();$teamId=(int)$teams->json('data.0.id');
        $this->withHeaders($managerHeaders)->putJson("/api/admin/workspace/team/members/{$agent->id}",['team_id'=>$teamId,'is_available'=>false,'capacity'=>3])->assertOk();
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'مهمة للفريق','description'=>'اختبار حالة توفر الموظف والحد التشغيلي.','category'=>'other'])->assertCreated()->json('data.id');
        $task=SupportTask::query()->where('source_id',$caseId)->where('source_type','support_ticket')->firstOrFail();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertStatus(409);
        $this->withHeaders($managerHeaders)->putJson("/api/admin/workspace/team/members/{$agent->id}",['team_id'=>$teamId,'is_available'=>true,'capacity'=>3])->assertOk();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/{$task->id}/claim")->assertOk();
        $this->withHeaders($managerHeaders)->postJson("/api/admin/workspace/team/members/{$agent->id}/redistribute")->assertOk()->assertJsonPath('data.released_tasks',1);
        $this->assertDatabaseHas('support_tasks',['id'=>$task->id,'assigned_to_user_id'=>null,'status'=>'new']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Support Workflow User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);$ids=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);
        $plain='sw_'.substr(hash('sha512',$email),0,80);$user->apiTokens()->create(['name'=>'support-workflow-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
''')

print('backend support workflow patch applied')
