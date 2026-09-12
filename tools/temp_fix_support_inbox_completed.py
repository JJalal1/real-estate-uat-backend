from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def p(path): return ROOT/path

def read(path): return p(path).read_text()

def write(path,s): p(path).write_text(s)

def rep(path,old,new,count=1):
    s=read(path)
    if old not in s: raise SystemExit(f'missing pattern in {path}: {old[:120]!r}')
    write(path,s.replace(old,new,count))

svc='backend-api-runtime/app/Services/SupportTaskService.php'
rep(svc,"    public const ACTIVE_STATUSES = [\n        'new','in_progress','waiting_user','waiting_internal','needs_followup','escalated',\n    ];",
"    public const ACTIVE_STATUSES = [\n        'new','in_progress','waiting_user','waiting_internal','needs_followup','escalated',\n    ];\n\n    public const INBOX_STATUSES = ['new','needs_followup'];\n    public const CLOSED_STATUSES = ['completed','rejected'];")

old="""        if ($this->isSupportAgent($actor) || ($this->isManager($actor) && $actingAsAgent)) {
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
"""
new="""        if ($this->isSupportAgent($actor) || ($this->isManager($actor) && $actingAsAgent)) {
            if ($this->isSupportAgent($actor)) $this->applyAgentTypePermissions($query, $actor);
            if ($scope === 'mine') {
                $query->where('assigned_to_user_id', $actor->id)->whereIn('status', self::ACTIVE_STATUSES);
            } elseif ($scope === 'completed') {
                $query->where('assigned_to_user_id', $actor->id)->whereIn('status', self::CLOSED_STATUSES);
            } else {
                $query->whereNull('assigned_to_user_id')->whereIn('status', self::INBOX_STATUSES);
            }
        } elseif ($scope === 'mine') {
            $query->where('assigned_to_user_id', $actor->id)->whereIn('status', self::ACTIVE_STATUSES);
        } elseif ($scope === 'completed') {
            $query->whereIn('status', self::CLOSED_STATUSES);
        } elseif ($scope === 'inbox') {
            $query->whereNull('assigned_to_user_id')->whereIn('status', self::INBOX_STATUSES);
        }
"""
rep(svc,old,new)

rep(svc,
"            $this->notifications->create($assignee->id,'support_task_assigned','تم إسناد مهمة دعم إليك',$locked->subject,'support_task',$locked->id,['task_id'=>$locked->id,'source_type'=>$locked->source_type]);",
"            $this->notifications->create($assignee->id,'support_task_assigned','قام مدير الدعم بإسناد مهمة لك','تمت إضافة «'.$locked->subject.'» إلى قائمة مهامك.','support_task',$locked->id,['task_id'=>$locked->id,'source_type'=>$locked->source_type,'destination'=>'my_tasks']);")

old="""        $existing=SupportTask::query()->where('source_type','listing_review')->where('source_id',$property->id)->first();
        $status=match($property->review_status){'approved'=>'completed','rejected_blocked'=>'rejected','returned_for_correction'=>'waiting_user','under_review'=>'in_progress','submitted'=>$existing?->status==='waiting_user'?'needs_followup':($property->review_assigned_to_user_id?'in_progress':'new'),default=>'completed'};
        $release=$property->review_status==='submitted'&&$existing?->status==='waiting_user';$submitted=$property->submitted_at?:$property->updated_at?:now();$assigneeId=$release?null:$property->review_assigned_to_user_id;
        $assigneeName=$assigneeId?User::query()->whereKey($assigneeId)->value('name'):null;$govId=$this->listingGovernorateId($property);
        $task=$this->upsertTask('listing_review',$property->id,'LIST-'.$property->id,'تحقيق إعلان: '.$property->title,$property->user,$status,'normal',null,$assigneeId,$assigneeName,in_array($status,['waiting_user','completed','rejected'],true)?null:$submitted->copy()->addHours(24),$property->updated_at,['review_status'=>$property->review_status,'price'=>$property->price,'purpose'=>$property->purpose,'property_type'=>$property->type,'governorate_id'=>$govId],$release||in_array($status,['waiting_user','completed','rejected'],true));
"""
new="""        $existing=SupportTask::query()->where('source_type','listing_review')->where('source_id',$property->id)->first();
        $existingMeta=$existing?->metadata??[];
        $returnedCycle=$existing?->status==='completed'&&($existingMeta['resolution']??null)==='returned_for_correction';
        $status=match($property->review_status){
            'approved'=>'completed',
            'rejected_blocked'=>'rejected',
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
        $resolution=match($property->review_status){'approved'=>'approved','rejected_blocked'=>'rejected','returned_for_correction'=>'returned_for_correction',default=>null};
        $task=$this->upsertTask('listing_review',$property->id,'LIST-'.$property->id,'تحقق نشر إعلان: '.$property->title,$property->user,$status,'normal',null,$assigneeId,$assigneeName,$closed?null:$submitted->copy()->addHours(24),$property->updated_at,[
            'review_status'=>$property->review_status,'resolution'=>$resolution,'review_reason'=>$property->last_review_reason,
            'price'=>$property->price,'purpose'=>$property->purpose,'property_type'=>$property->type,'governorate_id'=>$govId,
        ],$release||$closed);
"""
rep(svc,old,new)

rep(svc,
"        $task=$this->upsertTask('account_verification',$userId,'KYC-'.$userId,'طلب تحقق '.match($type){'owner'=>'مالك','broker'=>'دلال','office'=>'مكتب عقارات',default=>'حساب'},$user,$status,'normal',null,$existing?->assigned_to_user_id,$existing?->assigned_to_name_snapshot,$sla,$updated,['verification_type'=>$type,'governorate_id'=>$govId,'governorate'=>$details['governorate']??null],false);",
"        $resolution=match($sourceStatus){'approved'=>'approved','rejected'=>'rejected','needs_more_info'=>'documents_requested',default=>null};\n        $task=$this->upsertTask('account_verification',$userId,'KYC-'.$userId,'تحقق حساب '.match($type){'owner'=>'مالك','broker'=>'دلال','office'=>'مكتب عقارات',default=>'مستخدم'},$user,$status,'normal',null,$existing?->assigned_to_user_id,$existing?->assigned_to_name_snapshot,$sla,$updated,['verification_type'=>$type,'verification_status'=>$sourceStatus,'resolution'=>$resolution,'governorate_id'=>$govId,'governorate'=>$details['governorate']??null],false);")

rep(svc,
"        $task=$this->upsertTask($type,$case->id,$case->reference,$case->subject,$requester,$status,$priority,$severity,$case->assigned_to_user_id,$case->assigned_to_name_snapshot,$case->sla_due_at,$case->updated_at,['kind'=>$case->kind,'reason_code'=>$case->reason_code,'target_type'=>$case->target_type,'target_id'=>$case->target_id,'governorate_id'=>$govId],false);",
"        $resolution=match($case->status){'resolved'=>'resolved','dismissed'=>'dismissed','waiting_requester'=>'waiting_user',default=>null};\n        $task=$this->upsertTask($type,$case->id,$case->reference,$case->subject,$requester,$status,$priority,$severity,$case->assigned_to_user_id,$case->assigned_to_name_snapshot,$case->sla_due_at,$case->updated_at,['kind'=>$case->kind,'case_status'=>$case->status,'resolution'=>$resolution,'reason_code'=>$case->reason_code,'target_type'=>$case->target_type,'target_id'=>$case->target_id,'governorate_id'=>$govId],false);")

# dashboard inbox counts should only represent immediately actionable unassigned work
rep(svc,
"'inbox_new'=>(clone $base)->whereNull('assigned_to_user_id')->whereIn('status',self::ACTIVE_STATUSES)->count(),",
"'inbox_new'=>(clone $base)->whereNull('assigned_to_user_id')->whereIn('status',self::INBOX_STATUSES)->count(),")
rep(svc,
"'unassigned'=>(clone $active)->whereNull('assigned_to_user_id')->count(),",
"'unassigned'=>(clone $active)->whereNull('assigned_to_user_id')->whereIn('status',self::INBOX_STATUSES)->count(),")
rep(svc,
"$taskCounts=SupportTask::query()->whereIn('support_team_id',$ids)->whereIn('status',self::ACTIVE_STATUSES)->selectRaw('support_team_id, count(*) as open_tasks, sum(case when assigned_to_user_id is null then 1 else 0 end) as unassigned')",
"$taskCounts=SupportTask::query()->whereIn('support_team_id',$ids)->whereIn('status',self::ACTIVE_STATUSES)->selectRaw(\"support_team_id, count(*) as open_tasks, sum(case when assigned_to_user_id is null and status in ('new','needs_followup') then 1 else 0 end) as unassigned\")")

ctrl='backend-api-runtime/app/Http/Controllers/Api/SupportWorkspaceController.php'
rep(ctrl,"'scope'=>['nullable',Rule::in(['inbox','mine','all'])]","'scope'=>['nullable',Rule::in(['inbox','mine','completed','all'])]")

# Flutter UI: completed segment, auto-open after claim, richer labels/results
ui='mobile_app/lib/features/support/presentation/support_tasks_screen.dart'
rep(ui,"    if (_scope == 'mine') return 'مهامي';\n    if (_scope == 'all') return 'كل الأعمال';",
"    if (_scope == 'mine') return 'مهامي';\n    if (_scope == 'completed') return 'المهام المنجزة';\n    if (_scope == 'all') return 'كل الأعمال';")
rep(ui,
"                          ButtonSegment(value: 'mine', label: Text('مهامي')),\n                        ]",
"                          ButtonSegment(value: 'mine', label: Text('مهامي')),\n                          ButtonSegment(value: 'completed', label: Text('المنجزة')),\n                        ]")
rep(ui,
"                          ButtonSegment(value: 'mine', label: Text('مسند لي')),\n                          ButtonSegment(value: 'all', label: Text('كل الأعمال')),")
# Above malformed helper: restore with proper direct replacement below if needed
s=read(ui)
# manager segment exact replacement
s=s.replace("                          ButtonSegment(value: 'mine', label: Text('مسند لي')),\n                          ButtonSegment(value: 'all', label: Text('كل الأعمال')),\n                        ],",
"                          ButtonSegment(value: 'mine', label: Text('مسند لي')),\n                          ButtonSegment(value: 'completed', label: Text('المنجزة')),\n                          ButtonSegment(value: 'all', label: Text('كل الأعمال')),\n                        ],")
# claim returns task and opens immediately
old="""      await ref.read(supportWorkspaceRepositoryProvider).claim(
            task.id,
            actingAsAgent: widget.actingAsAgent,
          );
      _message('تم استلام المهمة ونقلها إلى مهامك.');
      await _load();
"""
new="""      final claimed = await ref.read(supportWorkspaceRepositoryProvider).claim(
            task.id,
            actingAsAgent: widget.actingAsAgent,
          );
      _message('تم استلام المهمة وإضافتها إلى مهامك.');
      await _load();
      if (mounted) await _open(claimed, false);
"""
if old not in s: raise SystemExit('claim block missing')
s=s.replace(old,new,1)
# card secondary type label
s=s.replace("'${_typeLabel(task.sourceType)} • ${task.requesterName ?? 'مستخدم #${task.requesterUserId ?? task.sourceId}'}${task.supportTeamName == null ? '' : ' • ${task.supportTeamName}'}${task.governorateName == null ? '' : ' • ${task.governorateName}'}'",
"'${_taskTypeLabel(task)} • ${task.requesterName ?? 'مستخدم #${task.requesterUserId ?? task.sourceId}'}${task.supportTeamName == null ? '' : ' • ${task.supportTeamName}'}${task.governorateName == null ? '' : ' • ${task.governorateName}'}'")
# Add result pill on closed tasks
needle="""                _StatusPill(label: _statusLabel(task.status), kind: _statusKind(task.status)),
                _StatusPill(label: _priorityLabel(task.priority), kind: task.priority == 'urgent' ? 2 : 0),
"""
replace="""                _StatusPill(label: _statusLabel(task.status), kind: _statusKind(task.status)),
                if (task.isClosed)
                  _StatusPill(label: _taskResultLabel(task), kind: task.status == 'rejected' ? 2 : 1),
                _StatusPill(label: _priorityLabel(task.priority), kind: task.priority == 'urgent' ? 2 : 0),
"""
if needle not in s: raise SystemExit('status pills block missing')
s=s.replace(needle,replace,1)
# completed timestamp
s=s.replace("""                if (task.lastActivityAt != null)
                  Text('آخر تحديث ${_timeAgo(task.lastActivityAt!)}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
""",
"""                if (task.completedAt != null)
                  Text('أُنجزت ${_timeAgo(task.completedAt!)}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                if (task.lastActivityAt != null && !task.isClosed)
                  Text('آخر تحديث ${_timeAgo(task.lastActivityAt!)}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
""",1)
# no claim/open action for closed except history via manage; button says تفاصيل القرار
s=s.replace("""                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(task.canClaim && !manager ? 'بعد الاستلام' : 'فتح'),
                  ),
                ),
""",
"""                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: task.isClosed ? onManage : onOpen,
                    icon: Icon(task.isClosed ? Icons.receipt_long_outlined : Icons.open_in_new),
                    label: Text(task.isClosed ? 'تفاصيل القرار' : (task.canClaim && !manager ? 'بعد الاستلام' : 'فتح')),
                  ),
                ),
""",1)
# add helper labels before _typeLabel
helper="""
String _taskTypeLabel(SupportTaskItem task) {
  if (task.sourceType == 'account_verification') {
    final kind = task.metadata['verification_type']?.toString();
    return switch (kind) {
      'owner' => 'تحقق حساب مالك',
      'broker' => 'تحقق حساب دلال',
      'office' => 'تحقق حساب مكتب عقارات',
      _ => 'تحقق حساب',
    };
  }
  if (task.sourceType == 'listing_review') return 'تحقق نشر إعلان';
  return _typeLabel(task.sourceType);
}

String _taskResultLabel(SupportTaskItem task) {
  final resolution = task.metadata['resolution']?.toString();
  return switch (resolution) {
    'approved' => task.sourceType == 'listing_review' ? 'تم القبول والنشر' : 'تم القبول',
    'returned_for_correction' => 'أُعيد للمراجعة والتصحيح',
    'rejected' => 'تم الرفض',
    'resolved' => 'تم الحل والإغلاق',
    'dismissed' => 'تم الرفض والإغلاق',
    'documents_requested' => 'طُلبت مستندات إضافية',
    _ => task.status == 'rejected' ? 'مرفوض' : 'منجز',
  };
}

"""
marker="String _typeLabel(String value) => switch (value) {"
if marker not in s: raise SystemExit('type marker missing')
s=s.replace(marker,helper+marker,1)
write(ui,s)

# Dashboard: explicit completed card for agent and manager points to completed scope.
pages='mobile_app/lib/features/support/presentation/support_workspace_pages.dart'
s=read(pages)
s=s.replace("        _DashboardCardSpec('my_tasks', 'مهامي', Icons.assignment_ind_outlined, _DashboardAction.mine),\n        _DashboardCardSpec('inbox_new', 'الوارد الجديد', Icons.inbox_outlined, _DashboardAction.inbox),",
"        _DashboardCardSpec('my_tasks', 'مهامي', Icons.assignment_ind_outlined, _DashboardAction.mine),\n        _DashboardCardSpec('completed_today', 'المنجزة', Icons.task_alt_outlined, _DashboardAction.completed),\n        _DashboardCardSpec('inbox_new', 'الوارد الجديد', Icons.inbox_outlined, _DashboardAction.inbox),")
s=s.replace("_DashboardCardSpec('completed_today', 'منجز اليوم', Icons.task_alt_outlined, _DashboardAction.all),",
"_DashboardCardSpec('completed_today', 'منجز اليوم', Icons.task_alt_outlined, _DashboardAction.completed),")
# enum and action mapping
s=s.replace("enum _DashboardAction {\n  mine,\n  inbox,", "enum _DashboardAction {\n  mine,\n  completed,\n  inbox,")
# find switch action mappings by textual patterns
s=s.replace("      case _DashboardAction.mine:\n        screen = const SupportTasksScreen(initialScope: 'mine');\n        break;",
"      case _DashboardAction.mine:\n        screen = const SupportTasksScreen(initialScope: 'mine');\n        break;\n      case _DashboardAction.completed:\n        screen = const SupportTasksScreen(initialScope: 'completed', title: 'المهام المنجزة');\n        break;")
write(pages,s)

# Backend tests for semantics
path='backend-api-runtime/tests/Feature/UatSupportCompletedInboxFlowApiTest.php'
write(path,r'''<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatSupportCompletedInboxFlowApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_waiting_user_is_not_returned_as_unassigned_inbox_work(): void
    {
        [$agent,$headers]=$this->user('inbox-agent@example.test','+967744420001',['support_agent']);
        $task=SupportTask::query()->create([
            'source_type'=>'account_verification','source_id'=>999,'subject'=>'طلب تحقق مالك','status'=>'waiting_user','priority'=>'normal',
            'assigned_to_user_id'=>$agent->id,'assigned_to_name_snapshot'=>$agent->name,'last_activity_at'=>now(),
        ]);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=inbox')->assertOk()->assertJsonPath('meta.total',0);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=mine')->assertOk()->assertJsonPath('data.0.id',$task->id);
    }

    public function test_completed_scope_keeps_executor_and_listing_return_result(): void
    {
        [$agent,$headers]=$this->user('completed-agent@example.test','+967744420002',['support_agent']);
        $task=SupportTask::query()->create([
            'source_type'=>'listing_review','source_id'=>123,'subject'=>'تحقق نشر إعلان: شقة','status'=>'completed','priority'=>'normal',
            'assigned_to_user_id'=>$agent->id,'assigned_to_name_snapshot'=>$agent->name,'claimed_at'=>now()->subMinutes(5),'completed_at'=>now(),
            'last_activity_at'=>now(),'metadata'=>['review_status'=>'returned_for_correction','resolution'=>'returned_for_correction'],
        ]);
        $this->withHeaders($headers)->getJson('/api/admin/workspace/tasks?scope=completed')->assertOk()
            ->assertJsonPath('data.0.id',$task->id)->assertJsonPath('data.0.assigned_to_user_id',$agent->id)
            ->assertJsonPath('data.0.metadata.resolution','returned_for_correction');
    }

    public function test_manager_assignment_notification_mentions_my_tasks(): void
    {
        [$agent]=$this->user('assigned-agent@example.test','+967744420003',['support_agent']);
        [$manager,$managerHeaders]=$this->user('assigned-manager@example.test','+967744420004',['support_manager']);
        $fallback=\Illuminate\Support\Facades\DB::table('support_teams')->where('is_fallback',true)->value('id');
        \Illuminate\Support\Facades\DB::table('support_team_members')->updateOrInsert(['support_team_id'=>$fallback,'user_id'=>$agent->id],['member_role'=>'agent','is_available'=>true,'capacity'=>10,'joined_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        $task=SupportTask::query()->create(['source_type'=>'support_ticket','source_id'=>777,'subject'=>'تذكرة مسندة','status'=>'new','priority'=>'normal','support_team_id'=>$fallback,'last_activity_at'=>now()]);
        $this->withHeaders($managerHeaders)->putJson('/api/admin/workspace/tasks/'.$task->id.'/assign',['user_id'=>$agent->id])->assertOk()->assertJsonPath('data.assigned_to_user_id',$agent->id);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$agent->id,'type'=>'support_task_assigned','title'=>'قام مدير الدعم بإسناد مهمة لك']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Support Flow User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);$ids=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);
        $plain='sf_'.substr(hash('sha512',$email),0,80);$user->apiTokens()->create(['name'=>'support-flow-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
''')

# Flutter regression
write('mobile_app/test/support_completed_inbox_flow_test.dart',r'''import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_app/features/support/domain/support_workspace_models.dart';

void main() {
  test('completed task keeps resolution metadata', () {
    final item = SupportTaskItem.fromJson({
      'id': 1,'source_type':'listing_review','source_id':2,'subject':'تحقق نشر إعلان','status':'completed','priority':'normal',
      'is_mine':true,'can_claim':false,'is_overdue':false,'assigned_to_user_id':7,'assigned_to_name':'موظف الدعم',
      'metadata':{'resolution':'returned_for_correction','review_status':'returned_for_correction'},
    });
    expect(item.isClosed, isTrue);
    expect(item.metadata['resolution'], 'returned_for_correction');
    expect(item.assignedToUserId, 7);
  });
}
''')
print('patched support inbox/completed flow')
