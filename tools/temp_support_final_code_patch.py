from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def patch(path, old, new):
    p = ROOT / path
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'missing pattern in {path}: {old!r}')
    p.write_text(s.replace(old, new, 1))

patch(
    'backend-api-runtime/app/Services/SupportTaskService.php',
    "DB::table('support_teams')->whereKey($fallback)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);",
    "DB::table('support_teams')->where('id',$fallback)->whereNull('manager_user_id')->update(['manager_user_id'=>$actor->id,'updated_at'=>now()]);",
)

patch(
    'mobile_app/test/support_manager_agent_workflow_test.dart',
    "package:real_estate_app/features/support/domain/support_workspace_models.dart",
    "package:real_estate_mobile/features/support/domain/support_workspace_models.dart",
)

patch(
    'mobile_app/lib/features/support/presentation/support_workspace_pages.dart',
    "String _workspaceTime(DateTime value) {\n  final local = value.toLocal();\n  String two(int n) => n.toString().padLeft(2, '0');\n  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';\n}\n\n",
    "",
)

print('final support workflow code patch applied')
