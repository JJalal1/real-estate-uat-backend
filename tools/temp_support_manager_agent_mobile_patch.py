from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def read(p): return (ROOT/p).read_text()
def write(p,s):
    x=ROOT/p;x.parent.mkdir(parents=True,exist_ok=True);x.write_text(s)
def once(p,a,b):
    s=read(p)
    if a not in s: raise SystemExit(f'missing in {p}: {a[:100]!r}')
    write(p,s.replace(a,b,1))
def between(p,a,b,n):
    s=read(p);i=s.find(a);j=s.find(b,i)
    if i<0 or j<0: raise SystemExit(f'markers missing in {p}: {a!r} {b!r}')
    write(p,s[:i]+n.rstrip()+'\n\n'+s[j:])

# Models: task routing/escalation, richer team member, team summaries.
p='mobile_app/lib/features/support/domain/support_workspace_models.dart'
s=read(p)
s=s.replace("    this.severity,\n    this.assignedToUserId,", "    this.severity,\n    this.supportTeamId,\n    this.supportTeamName,\n    this.governorateId,\n    this.governorateName,\n    this.assignedToUserId,")
s=s.replace("    this.claimedAt,\n    this.lastActivityAt,", "    this.claimedAt,\n    this.completedAt,\n    this.lastActivityAt,")
s=s.replace("    this.remainingMinutes,\n    this.metadata", "    this.remainingMinutes,\n    this.escalatedAt,\n    this.escalationReason,\n    this.metadata")
s=s.replace("  final String? severity;\n  final int? assignedToUserId;", "  final String? severity;\n  final int? supportTeamId;\n  final String? supportTeamName;\n  final int? governorateId;\n  final String? governorateName;\n  final int? assignedToUserId;")
s=s.replace("  final DateTime? claimedAt;\n  final DateTime? lastActivityAt;", "  final DateTime? claimedAt;\n  final DateTime? completedAt;\n  final DateTime? lastActivityAt;")
s=s.replace("  final int? remainingMinutes;\n  final bool isMine;", "  final int? remainingMinutes;\n  final DateTime? escalatedAt;\n  final String? escalationReason;\n  final bool isMine;")
s=s.replace("      severity: _text(json['severity']),\n      assignedToUserId:", "      severity: _text(json['severity']),\n      supportTeamId: _nullableInt(json['support_team_id']),\n      supportTeamName: _text(json['support_team_name']),\n      governorateId: _nullableInt(json['governorate_id']),\n      governorateName: _text(json['governorate_name']),\n      assignedToUserId:")
s=s.replace("      claimedAt: _date(json['claimed_at']),\n      lastActivityAt:", "      claimedAt: _date(json['claimed_at']),\n      completedAt: _date(json['completed_at']),\n      lastActivityAt:")
s=s.replace("      isMine: json['is_mine'] == true,", "      escalatedAt: _date(json['escalated_at']),\n      escalationReason: _text(json['escalation_reason']),\n      isMine: json['is_mine'] == true,")
# Team member extra fields.
s=s.replace("    required this.reports,\n    this.averageClaimMinutes,", "    required this.reports,\n    required this.isAvailable,\n    required this.capacity,\n    required this.completedToday,\n    required this.workloadPercent,\n    this.teamId,\n    this.teamName,\n    this.averageClaimMinutes,")
s=s.replace("    this.averageResponseMinutes,\n    this.lastActivityAt,", "    this.averageResponseMinutes,\n    this.averageCompletionMinutes,\n    this.lastActivityAt,")
s=s.replace("  final int reports;\n  final int? averageClaimMinutes;", "  final int reports;\n  final int? teamId;\n  final String? teamName;\n  final bool isAvailable;\n  final int capacity;\n  final int completedToday;\n  final int workloadPercent;\n  final int? averageClaimMinutes;")
s=s.replace("  final int? averageResponseMinutes;\n  final DateTime? lastActivityAt;", "  final int? averageResponseMinutes;\n  final int? averageCompletionMinutes;\n  final DateTime? lastActivityAt;")
s=s.replace("      reports: _int(json['reports']),\n      averageClaimMinutes:", "      reports: _int(json['reports']),\n      teamId: _nullableInt(json['team_id']),\n      teamName: _text(json['team_name']),\n      isAvailable: json['is_available'] != false,\n      capacity: _int(json['capacity']) == 0 ? 10 : _int(json['capacity']),\n      completedToday: _int(json['completed_today']),\n      workloadPercent: _int(json['workload_percent']),\n      averageClaimMinutes:")
s=s.replace("      averageResponseMinutes: json['average_response_minutes'] == null\n          ? null\n          : _int(json['average_response_minutes']),\n      lastActivityAt:", "      averageResponseMinutes: json['average_response_minutes'] == null\n          ? null\n          : _int(json['average_response_minutes']),\n      averageCompletionMinutes: json['average_completion_minutes'] == null\n          ? null\n          : _int(json['average_completion_minutes']),\n      lastActivityAt:")
# Add support team summary before task event.
marker='class SupportTaskEventItem {'
team=r'''class SupportTeamSummary {
  const SupportTeamSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.isFallback,
    required this.agents,
    required this.availableAgents,
    required this.openTasks,
    required this.unassigned,
    this.governorateId,
    this.governorateName,
  });

  final int id;
  final String code;
  final String name;
  final int? governorateId;
  final String? governorateName;
  final bool isFallback;
  final int agents;
  final int availableAgents;
  final int openTasks;
  final int unassigned;

  factory SupportTeamSummary.fromJson(Map<String, dynamic> json) => SupportTeamSummary(
        id: _int(json['id']),
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        governorateId: _nullableInt(json['governorate_id']),
        governorateName: _text(json['governorate_name']),
        isFallback: json['is_fallback'] == true,
        agents: _int(json['agents']),
        availableAgents: _int(json['available_agents']),
        openTasks: _int(json['open_tasks']),
        unassigned: _int(json['unassigned']),
      );
}

'''
if marker not in s: raise SystemExit('model marker missing')
s=s.replace(marker,team+marker,1)
write(p,s)

# Repository contracts.
p='mobile_app/lib/features/support/data/support_workspace_repository.dart'
s=read(p)
s=s.replace("    bool overdue = false,\n  }) async {", "    bool overdue = false,\n    bool actingAsAgent = false,\n  }) async {")
s=s.replace("        if (overdue) 'overdue': 1,\n        'per_page': 100,", "        if (overdue) 'overdue': 1,\n        if (actingAsAgent) 'acting_as_agent': 1,\n        'per_page': 100,")
s=s.replace("  Future<SupportTaskItem> claim(int taskId) =>\n      _taskPost('/admin/workspace/tasks/$taskId/claim');", "  Future<SupportTaskItem> claim(int taskId, {bool actingAsAgent = false}) async {\n    final response = await _dio.post<Map<String, dynamic>>(\n      '/admin/workspace/tasks/$taskId/claim',\n      data: {if (actingAsAgent) 'acting_as_agent': true},\n      options: await _auth.requiredAuthOptions(),\n    );\n    return _task(response.data);\n  }\n\n  Future<SupportTaskItem> release(int taskId) =>\n      _taskPost('/admin/workspace/tasks/$taskId/release');")
s=s.replace("  Future<SupportTaskItem> setOperationalStatus(\n    int taskId,\n    String status,\n  ) async {", "  Future<SupportTaskItem> setOperationalStatus(\n    int taskId,\n    String status, {\n    bool actingAsAgent = false,\n  }) async {")
s=s.replace("      data: {'status': status},", "      data: {'status': status, if (actingAsAgent) 'acting_as_agent': true},",1)
s=s.replace("  Future<SupportTaskItem> escalate(int taskId) =>\n      _taskPost('/admin/workspace/tasks/$taskId/escalate');", "  Future<SupportTaskItem> escalate(\n    int taskId,\n    String reason, {\n    bool actingAsAgent = false,\n  }) async {\n    final response = await _dio.post<Map<String, dynamic>>(\n      '/admin/workspace/tasks/$taskId/escalate',\n      data: {\n        'reason': reason,\n        if (actingAsAgent) 'acting_as_agent': true,\n      },\n      options: await _auth.requiredAuthOptions(),\n    );\n    return _task(response.data);\n  }\n\n  Future<SupportTaskItem> resolveEscalation(int taskId, String note) async {\n    final response = await _dio.post<Map<String, dynamic>>(\n      '/admin/workspace/tasks/$taskId/resolve-escalation',\n      data: {'note': note},\n      options: await _auth.requiredAuthOptions(),\n    );\n    return _task(response.data);\n  }")
s=s.replace("  Future<SupportTaskItem> requestDocuments(int taskId, String note) async {", "  Future<SupportTaskItem> requestDocuments(\n    int taskId,\n    String note, {\n    bool actingAsAgent = false,\n  }) async {")
s=s.replace("      data: {'note': note},", "      data: {'note': note, if (actingAsAgent) 'acting_as_agent': true},",1)
s=s.replace("  Future<SupportTaskItem> rejectVerification(\n    int taskId,\n    String reason,\n  ) async {", "  Future<SupportTaskItem> rejectVerification(\n    int taskId,\n    String reason, {\n    bool actingAsAgent = false,\n  }) async {")
# Replace reject data occurrence following method carefully.
idx=s.find("Future<SupportTaskItem> rejectVerification")
pos=s.find("data: {'reason': reason},",idx)
if pos<0: raise SystemExit('reject data missing')
s=s[:pos]+"data: {'reason': reason, if (actingAsAgent) 'acting_as_agent': true},"+s[pos+len("data: {'reason': reason},"):]
# team APIs before _taskPost.
marker='  Future<SupportTaskItem> _taskPost(String path) async {'
addition=r'''  Future<List<SupportTeamSummary>> teams() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/teams',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <SupportTeamSummary>[];
    return rows.whereType<Map>().map((row) => SupportTeamSummary.fromJson(
      row.map((key, value) => MapEntry(key.toString(), value)),
    )).toList(growable: false);
  }

  Future<void> updateTeamMember(
    int userId, {
    required int teamId,
    required bool isAvailable,
    required int capacity,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/admin/workspace/team/members/$userId',
      data: {
        'team_id': teamId,
        'is_available': isAvailable,
        'capacity': capacity,
      },
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<int> redistributeMember(int userId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/workspace/team/members/$userId/redistribute',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is Map) return _intValue(data['released_tasks']);
    return 0;
  }

'''
if marker not in s: raise SystemExit('repo marker missing')
s=s.replace(marker,addition+marker,1)
# Add helper within repository class before final }. Use last occurrence.
last=s.rfind('\n}')
s=s[:last]+"\n\n  int _intValue(dynamic value) {\n    if (value is num) return value.toInt();\n    return int.tryParse(value?.toString() ?? '') ?? 0;\n  }"+s[last:]
write(p,s)

# Support tasks screen: explicit manager-agent mode and escalation split.
p='mobile_app/lib/features/support/presentation/support_tasks_screen.dart'
s=read(p)
s=s.replace("    this.overdueOnly = false,\n    this.title,", "    this.overdueOnly = false,\n    this.actingAsAgent = false,\n    this.title,")
s=s.replace("  final bool overdueOnly;\n  final String? title;", "  final bool overdueOnly;\n  final bool actingAsAgent;\n  final String? title;")
s=s.replace("            overdue: _overdue,\n          );", "            overdue: _overdue,\n            actingAsAgent: widget.actingAsAgent,\n          );")
s=s.replace("    final manager = user?.isPlatformOwner == true ||", "    final manager = user?.isPlatformOwner == true ||")
s=s.replace("        user?.hasPermission('support.manage') == true;\n\n    return Directionality(", "        user?.hasPermission('support.manage') == true;\n    final managerMode = manager && !widget.actingAsAgent;\n\n    return Directionality(")
s=s.replace("          children: [\n            _filters(manager),\n            Expanded(child: _body(manager)),", "          children: [\n            if (widget.actingAsAgent)\n              Material(\n                color: Theme.of(context).colorScheme.primaryContainer,\n                child: const ListTile(\n                  leading: Icon(Icons.support_agent_outlined),\n                  title: Text('أنت الآن تعمل كموظف دعم', style: TextStyle(fontWeight: FontWeight.w900)),\n                  subtitle: Text('استلم الطلب أولاً ثم عالجه بنفس قواعد موظفي الدعم. الرجوع يغلق هذا الوضع.'),\n                ),\n              ),\n            _filters(managerMode),\n            Expanded(child: _body(managerMode)),")
# manager mode filters vs acting agent: add two-scope selector for acting mode.
s=s.replace("            if (manager)\n              SingleChildScrollView(", "            if (manager || widget.actingAsAgent)\n              SingleChildScrollView(")
s=s.replace("                  segments: const [\n                    ButtonSegment(value: 'inbox', label: Text('غير مسند')),\n                    ButtonSegment(value: 'mine', label: Text('مسند لي')),\n                    ButtonSegment(value: 'all', label: Text('كل الأعمال')),\n                  ],", "                  segments: widget.actingAsAgent\n                      ? const [\n                          ButtonSegment(value: 'inbox', label: Text('الوارد')),\n                          ButtonSegment(value: 'mine', label: Text('مهامي')),\n                        ]\n                      : const [\n                          ButtonSegment(value: 'inbox', label: Text('غير مسند')),\n                          ButtonSegment(value: 'mine', label: Text('مسند لي')),\n                          ButtonSegment(value: 'all', label: Text('كل الأعمال')),\n                        ],")
s=s.replace("            if (manager) const SizedBox(height: 8),", "            if (manager || widget.actingAsAgent) const SizedBox(height: 8),")
# Claim.
s=s.replace("      await ref.read(supportWorkspaceRepositoryProvider).claim(task.id);", "      await ref.read(supportWorkspaceRepositoryProvider).claim(\n            task.id,\n            actingAsAgent: widget.actingAsAgent,\n          );")
# Open guard.
s=s.replace("    if (!manager && !task.isMine) {\n      _message('استلم المهمة أولاً قبل فتح بياناتها الخاصة.');\n      return;\n    }", "    if (manager && !widget.actingAsAgent && task.status != 'escalated') {\n      _message('هذه شاشة إدارة العمل. لمعالجة الطلب بنفسك استخدم «العمل كموظف دعم» واستلمه أولاً.');\n      return;\n    }\n    if ((!manager || widget.actingAsAgent) && !task.isMine) {\n      _message('استلم المهمة أولاً قبل فتح بياناتها الخاصة.');\n      return;\n    }")
# Manage menu: manager param passed is managerMode already. Replace manager escalation condition with worker escalation and resolve/release.
s=s.replace("              if (manager && !task.isClosed)\n                ListTile(\n                  leading: const Icon(Icons.trending_up),\n                  title: const Text('تصعيد المهمة'),\n                  onTap: () => Navigator.pop(sheetContext, 'escalate'),\n                ),", "              if (!manager && task.isMine && !task.isClosed && task.status != 'escalated')\n                ListTile(\n                  leading: const Icon(Icons.trending_up),\n                  title: const Text('تصعيد لمدير الدعم'),\n                  subtitle: const Text('للحالات غير الاعتيادية فقط، وليس للموافقة اليومية.'),\n                  onTap: () => Navigator.pop(sheetContext, 'escalate'),\n                ),\n              if (manager && task.status == 'escalated')\n                ListTile(\n                  leading: const Icon(Icons.check_circle_outline),\n                  title: const Text('معالجة التصعيد وإعادته للموظف'),\n                  onTap: () => Navigator.pop(sheetContext, 'resolve_escalation'),\n                ),\n              if (manager && task.assignedToUserId != null && !task.isClosed)\n                ListTile(\n                  leading: const Icon(Icons.move_to_inbox_outlined),\n                  title: const Text('إعادة إلى الوارد'),\n                  onTap: () => Navigator.pop(sheetContext, 'release'),\n                ),")
# Execution condition currently manager || mine; make mine only when agent-mode (manager arg false in acting mode).
s=s.replace("                  (manager || task.isMine))", "                  task.isMine)")
s=s.replace("                  (manager || task.isMine))", "                  task.isMine)")
# switch escalation/release/resolve and execution calls.
s=s.replace("        case 'escalate':\n          await ref.read(supportWorkspaceRepositoryProvider).escalate(task.id);\n          _message('تم تصعيد المهمة ورفع أولويتها.');\n          break;", "        case 'escalate':\n          final reason = await _textDialog('سبب التصعيد', 'وضح لماذا تحتاج هذه الحالة تدخل مدير الدعم.');\n          if (reason != null) {\n            await ref.read(supportWorkspaceRepositoryProvider).escalate(\n                  task.id,\n                  reason,\n                  actingAsAgent: widget.actingAsAgent,\n                );\n            _message('تم تصعيد المهمة إلى مدير الدعم.');\n          }\n          break;\n        case 'resolve_escalation':\n          final note = await _textDialog('قرار التصعيد', 'اكتب القرار أو التوجيه الذي سيعود للموظف.');\n          if (note != null) {\n            await ref.read(supportWorkspaceRepositoryProvider).resolveEscalation(task.id, note);\n            _message('تمت معالجة التصعيد وإعادة المهمة لمسار التنفيذ.');\n          }\n          break;\n        case 'release':\n          await ref.read(supportWorkspaceRepositoryProvider).release(task.id);\n          _message('تمت إعادة المهمة إلى الوارد المشترك.');\n          break;")
s=s.replace("              .setOperationalStatus(task.id, 'waiting_internal');", "              .setOperationalStatus(task.id, 'waiting_internal', actingAsAgent: widget.actingAsAgent);")
s=s.replace("              .setOperationalStatus(task.id, 'in_progress');", "              .setOperationalStatus(task.id, 'in_progress', actingAsAgent: widget.actingAsAgent);")
s=s.replace("await ref.read(supportWorkspaceRepositoryProvider).requestDocuments(task.id, note);", "await ref.read(supportWorkspaceRepositoryProvider).requestDocuments(task.id, note, actingAsAgent: widget.actingAsAgent);")
s=s.replace("await ref.read(supportWorkspaceRepositoryProvider).rejectVerification(task.id, reason);", "await ref.read(supportWorkspaceRepositoryProvider).rejectVerification(task.id, reason, actingAsAgent: widget.actingAsAgent);")
# Add team/geography info to task card subtitle if exact requester string exists.
s=s.replace("'${_typeLabel(task.sourceType)} • ${task.requesterName ?? 'مستخدم #${task.requesterUserId ?? task.sourceId}'}'", "'${_typeLabel(task.sourceType)} • ${task.requesterName ?? 'مستخدم #${task.requesterUserId ?? task.sourceId}'}${task.supportTeamName == null ? '' : ' • ${task.supportTeamName}'}${task.governorateName == null ? '' : ' • ${task.governorateName}'}'")
write(p,s)

# Workspace pages: manager button + richer team management.
p='mobile_app/lib/features/support/presentation/support_workspace_pages.dart'
s=read(p)
# Manager dashboard additional cards and top action.
old="""    return _DashboardFrame(
      title: 'إدارة الدعم',
      load: () => ref.read(supportWorkspaceRepositoryProvider).dashboard(),
      cards: const ["""
new="""    return _DashboardFrame(
      title: 'إدارة الدعم',
      load: () => ref.read(supportWorkspaceRepositoryProvider).dashboard(),
      topAction: FilledButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SupportTasksScreen(
              initialScope: 'inbox',
              title: 'الوارد — وضع موظف دعم',
              actingAsAgent: true,
            ),
          ),
        ),
        icon: const Icon(Icons.support_agent_outlined),
        label: const Text('العمل كموظف دعم'),
      ),
      cards: const ["""
if old not in s: raise SystemExit('manager dashboard header missing')
s=s.replace(old,new,1)
s=s.replace("        _DashboardCardSpec('active_agents', 'موظفو الدعم',", "        _DashboardCardSpec('active_agents', 'موظفو الدعم',")
s=s.replace("        _DashboardCardSpec('active_agents', 'موظفو الدعم', Icons.groups_2_outlined, _DashboardAction.team),", "        _DashboardCardSpec('active_agents', 'موظفو الدعم', Icons.groups_2_outlined, _DashboardAction.team),\n        _DashboardCardSpec('available_agents', 'المتاحون الآن', Icons.how_to_reg_outlined, _DashboardAction.team),\n        _DashboardCardSpec('team_open', 'عبء الفريق', Icons.work_outline, _DashboardAction.all),\n        _DashboardCardSpec('completed_today', 'منجز اليوم', Icons.task_alt_outlined, _DashboardAction.all),")
# Replace SupportTeamScreen class completely.
start='class SupportTeamScreen extends ConsumerStatefulWidget {';end='class PlatformReviewsScreen extends StatelessWidget {'
newclass=r'''class SupportTeamScreen extends ConsumerStatefulWidget {
  const SupportTeamScreen({super.key});

  @override
  ConsumerState<SupportTeamScreen> createState() => _SupportTeamScreenState();
}

class _SupportTeamScreenState extends ConsumerState<SupportTeamScreen> {
  late Future<(List<SupportTeamMember>, List<SupportTeamSummary>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<SupportTeamMember>, List<SupportTeamSummary>)> _load() async {
    final repo = ref.read(supportWorkspaceRepositoryProvider);
    final values = await Future.wait<dynamic>([repo.team(), repo.teams()]);
    return (values[0] as List<SupportTeamMember>, values[1] as List<SupportTeamSummary>);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الفريق وعبء العمل'),
            actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
          ),
          body: FutureBuilder<(List<SupportTeamMember>, List<SupportTeamSummary>)>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return _ErrorState(error: snapshot.error!, onRetry: _refresh);
              final members = snapshot.data?.$1 ?? const <SupportTeamMember>[];
              final teams = snapshot.data?.$2 ?? const <SupportTeamSummary>[];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  children: [
                    const _HeroHeader(mode: 'manager'),
                    const SizedBox(height: 14),
                    const _SectionHeader('الفرق'),
                    const SizedBox(height: 8),
                    if (teams.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد فرق دعم ضمن نطاقك.')))
                    else
                      ...teams.map((team) => Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Icon(team.isFallback ? Icons.all_inbox_outlined : Icons.location_on_outlined)),
                              title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text('${team.availableAgents}/${team.agents} متاح • ${team.openTasks} مفتوحة • ${team.unassigned} غير مستلمة'),
                              trailing: team.isFallback ? const Chip(label: Text('وارد عام')) : null,
                            ),
                          )),
                    const SizedBox(height: 18),
                    const _SectionHeader('الموظفون'),
                    const SizedBox(height: 8),
                    if (members.where((m) => m.role == 'support_agent').isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد موظفو دعم ضمن فرقك.')))
                    else
                      ...members.where((m) => m.role == 'support_agent').map((member) => _TeamMemberCard(
                            member: member,
                            teams: teams,
                            onManage: () => _manageMember(member, teams),
                            onRedistribute: member.openTasks > 0 ? () => _redistribute(member) : null,
                          )),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> _manageMember(SupportTeamMember member, List<SupportTeamSummary> teams) async {
    if (teams.isEmpty) return;
    var teamId = member.teamId ?? teams.first.id;
    var available = member.isAvailable;
    var capacity = member.capacity.clamp(1, 50);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('إدارة ${member.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: teams.any((t) => t.id == teamId) ? teamId : teams.first.id,
                decoration: const InputDecoration(labelText: 'الفريق / النطاق'),
                items: teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (value) { if (value != null) setLocal(() => teamId = value); },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('متاح لاستلام مهام جديدة'),
                value: available,
                onChanged: (value) => setLocal(() => available = value),
              ),
              Row(
                children: [
                  const Expanded(child: Text('الحد الأقصى للمهام المفتوحة')),
                  IconButton(onPressed: capacity <= 1 ? null : () => setLocal(() => capacity--), icon: const Icon(Icons.remove_circle_outline)),
                  Text('$capacity', style: const TextStyle(fontWeight: FontWeight.w900)),
                  IconButton(onPressed: capacity >= 50 ? null : () => setLocal(() => capacity++), icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(supportWorkspaceRepositoryProvider).updateTeamMember(
            member.id,
            teamId: teamId,
            isAvailable: available,
            capacity: capacity,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الفريق وحالة الموظف.')));
      await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _redistribute(SupportTeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة توزيع الأعمال؟'),
        content: Text('ستعود جميع المهام المفتوحة المسندة إلى ${member.name} إلى الوارد المشترك ليتم استلامها من موظف متاح.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إعادة للوارد')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await ref.read(supportWorkspaceRepositoryProvider).redistributeMember(member.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إعادة $count مهمة إلى الوارد.')));
      await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.member, required this.teams, required this.onManage, this.onRedistribute});
  final SupportTeamMember member;
  final List<SupportTeamSummary> teams;
  final VoidCallback onManage;
  final VoidCallback? onRedistribute;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(child: Icon(member.isAvailable ? Icons.support_agent : Icons.person_off_outlined)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(member.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text('${member.teamName ?? 'فريق الدعم'} • ${member.isAvailable ? 'متاح' : 'غير متاح'}', style: const TextStyle(color: AppTheme.textMuted)),
                ])),
                Chip(label: Text('${member.openTasks}/${member.capacity}')),
              ]),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: (member.workloadPercent.clamp(0, 100)) / 100),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                _MetricChip('مفتوحة', member.openTasks),
                _MetricChip('متأخرة', member.overdueTasks),
                _MetricChip('عاجلة', member.urgentTasks),
                _MetricChip('منجز اليوم', member.completedToday),
              ]),
              const SizedBox(height: 8),
              Text('الاستلام: ${member.averageClaimMinutes ?? '—'} د • الرد: ${member.averageResponseMinutes ?? '—'} د • الإنجاز: ${member.averageCompletionMinutes ?? '—'} د', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: onManage, icon: const Icon(Icons.manage_accounts_outlined), label: const Text('إدارة الموظف'))),
                if (onRedistribute != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonalIcon(onPressed: onRedistribute, icon: const Icon(Icons.move_to_inbox_outlined), label: const Text('إعادة توزيع'))),
                ],
              ]),
            ],
          ),
        ),
      );
}
'''
i=s.find(start);j=s.find(end,i)
if i<0 or j<0: raise SystemExit('team class markers missing')
s=s[:i]+newclass+'\n\n'+s[j:]
# Dashboard frame topAction.
s=s.replace("    this.attentionTitle,\n  });", "    this.attentionTitle,\n    this.topAction,\n  });",1)
s=s.replace("  final String? attentionTitle;\n", "  final String? attentionTitle;\n  final Widget? topAction;\n",1)
# Insert top action after hero header. Find first body hero sequence.
needle="                  _HeroHeader(mode: dashboard.mode),\n"
if needle not in s: raise SystemExit('hero insert marker missing')
s=s.replace(needle,needle+"                  if (widget.topAction != null) ...[\n                    const SizedBox(height: 10),\n                    SizedBox(width: double.infinity, child: widget.topAction!),\n                  ],\n",1)
write(p,s)

# App shell manager gets messages and clearer team label.
p='mobile_app/lib/features/app_shell/presentation/app_shell_screen.dart'
s=read(p)
s=s.replace("            SupportTeamScreen(),\n            AccountScreen(),", "            SupportTeamScreen(),\n            Stage6AuthGate(child: MessagesScreen()),\n            AccountScreen(),",1)
s=s.replace("            _NavItemData(label: 'لوحة الدعم', icon: Icons.space_dashboard_outlined),\n            _NavItemData(label: 'الأعمال', icon: Icons.view_list_outlined),\n            _NavItemData(label: 'الفريق', icon: Icons.groups_2_outlined),\n            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),", "            _NavItemData(label: 'لوحة الفريق', icon: Icons.space_dashboard_outlined),\n            _NavItemData(label: 'الأعمال', icon: Icons.view_list_outlined),\n            _NavItemData(label: 'الفريق', icon: Icons.groups_2_outlined),\n            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),\n            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),",1)
write(p,s)

# Regression test for explicit manager mode / routing model contract.
write('mobile_app/test/support_manager_agent_workflow_test.dart', r'''import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_app/features/support/domain/support_workspace_models.dart';

void main() {
  test('support task parses team and escalation context', () {
    final task = SupportTaskItem.fromJson({
      'id': 7,
      'source_type': 'support_ticket',
      'source_id': 4,
      'subject': 'طلب دعم',
      'status': 'escalated',
      'priority': 'urgent',
      'support_team_id': 2,
      'support_team_name': 'دعم صنعاء',
      'governorate_id': 1,
      'governorate_name': 'صنعاء',
      'is_mine': true,
      'can_claim': false,
      'is_overdue': false,
      'escalation_reason': 'حالة غير اعتيادية',
    });
    expect(task.supportTeamName, 'دعم صنعاء');
    expect(task.governorateName, 'صنعاء');
    expect(task.escalationReason, 'حالة غير اعتيادية');
  });

  test('support team member parses capacity and workload', () {
    final member = SupportTeamMember.fromJson({
      'id': 6,
      'name': 'موظف دعم',
      'role': 'support_agent',
      'open_tasks': 4,
      'closed_tasks': 10,
      'overdue_tasks': 1,
      'urgent_tasks': 1,
      'tickets': 3,
      'verifications': 2,
      'listing_reviews': 5,
      'reports': 1,
      'is_available': true,
      'capacity': 8,
      'completed_today': 3,
      'workload_percent': 50,
      'team_id': 1,
      'team_name': 'فريق الدعم العام',
    });
    expect(member.capacity, 8);
    expect(member.workloadPercent, 50);
    expect(member.isAvailable, isTrue);
  });
}
''')

print('mobile support workflow patch applied')
