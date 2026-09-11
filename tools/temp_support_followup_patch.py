from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def patch(path, old, new):
    p=ROOT/path
    s=p.read_text()
    if old not in s:
        raise SystemExit(f'missing pattern in {path}: {old!r}')
    p.write_text(s.replace(old,new,1))

patch('backend-api-runtime/app/Services/SupportTaskService.php',
"    private function assertAssigneeCanReceive(User $actor, SupportTask $task, User $assignee): void\n    {\n        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;$member=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('user_id',$assignee->id)->where('member_role','agent')->first();if(!$member)throw ValidationException::withMessages(['user_id'=>['الموظف ليس ضمن الفريق المسؤول عن هذه المهمة.']]);\n    }",
"    private function assertAssigneeCanReceive(User $actor, SupportTask $task, User $assignee): void\n    {\n        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;\n        $this->ensureSupportStaffMembership($assignee);\n        $member=DB::table('support_team_members')->where('support_team_id',$task->support_team_id)->where('user_id',$assignee->id)->where('member_role','agent')->first();\n        if(!$member)throw ValidationException::withMessages(['user_id'=>['الموظف ليس ضمن الفريق المسؤول عن هذه المهمة.']]);\n    }")

# New workflow tests explicitly grant the permissions that make an agent qualified.
p=ROOT/'backend-api-runtime/tests/Feature/UatSupportManagerAgentWorkflowApiTest.php'
s=p.read_text()
s=s.replace("use Illuminate\\Support\\Facades\\Hash;", "use Illuminate\\Support\\Facades\\Hash;\nuse Illuminate\\Support\\Facades\\DB;")
old="        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);\n"
new="        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$ids[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($ids);\n        if(in_array('support_agent',$roles,true)){\n            $roleId=Role::query()->where('key','support_agent')->value('id');\n            $permissionIds=DB::table('permissions')->whereIn('key',['support.handle_reports','listings.moderate'])->pluck('id');\n            foreach($permissionIds as $permissionId){DB::table('role_permission')->updateOrInsert(['role_id'=>$roleId,'permission_id'=>$permissionId],['created_at'=>now()]);}\n        }\n"
if old not in s: raise SystemExit('test helper pattern missing')
p.write_text(s.replace(old,new,1))

# Fix mobile repository payloads introduced by first patch.
p=ROOT/'mobile_app/lib/features/support/data/support_workspace_repository.dart'
s=p.read_text()
s=s.replace("data: {'note': note, if (actingAsAgent) 'acting_as_agent': true},\n      options: await _auth.requiredAuthOptions(),\n    );\n    return _task(response.data);\n  }\n\n  Future<SupportTaskItem> reopen", "data: {'note': note},\n      options: await _auth.requiredAuthOptions(),\n    );\n    return _task(response.data);\n  }\n\n  Future<SupportTaskItem> reopen",1)
# requestDocuments should include acting_as_agent.
needle="'/admin/workspace/tasks/$taskId/request-documents',\n      data: {'note': note},"
if needle not in s: raise SystemExit('request documents payload missing')
s=s.replace(needle,"'/admin/workspace/tasks/$taskId/request-documents',\n      data: {'note': note, if (actingAsAgent) 'acting_as_agent': true},",1)
p.write_text(s)

print('support follow-up patch applied')
