from pathlib import Path
p=Path('mobile_app/lib/features/support/presentation/support_workspace_pages.dart')
s=p.read_text()
old="""    case _DashboardAction.mine:
      page = const SupportTasksScreen(initialScope: 'mine', title: 'مهامي');
      break;
    case _DashboardAction.all:
"""
new="""    case _DashboardAction.mine:
      page = const SupportTasksScreen(initialScope: 'mine', title: 'مهامي');
      break;
    case _DashboardAction.completed:
      page = const SupportTasksScreen(initialScope: 'completed', title: 'المهام المنجزة');
      break;
    case _DashboardAction.all:
"""
if old not in s: raise SystemExit('dashboard switch marker missing')
s=s.replace(old,new,1)
old="""enum _DashboardAction {
  inbox,
  mine,
  all,
"""
new="""enum _DashboardAction {
  inbox,
  mine,
  completed,
  all,
"""
if old not in s: raise SystemExit('dashboard enum marker missing')
s=s.replace(old,new,1)
p.write_text(s)
print('follow-up flutter navigation fixed')
