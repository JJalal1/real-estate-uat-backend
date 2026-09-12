import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../regions/presentation/platform_regions_screen.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_workspace_models.dart';
import 'support_tasks_screen.dart';

class SupportAgentHomeScreen extends ConsumerWidget {
  const SupportAgentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardFrame(
      title: 'مركز الدعم',
      load: () => ref.read(supportWorkspaceRepositoryProvider).dashboard(),
      cards: const [
        _DashboardCardSpec('my_tasks', 'مهامي', Icons.assignment_ind_outlined, _DashboardAction.mine),
        _DashboardCardSpec('completed_today', 'المنجزة', Icons.task_alt_outlined, _DashboardAction.completed),
        _DashboardCardSpec('inbox_new', 'الوارد الجديد', Icons.inbox_outlined, _DashboardAction.inbox),
        _DashboardCardSpec('account_verifications', 'طلبات التحقق', Icons.verified_user_outlined, _DashboardAction.verifications),
        _DashboardCardSpec('listing_reviews', 'تحقيق الإعلانات', Icons.fact_check_outlined, _DashboardAction.listings),
        _DashboardCardSpec('tickets', 'التذاكر', Icons.support_agent_outlined, _DashboardAction.tickets),
        _DashboardCardSpec('reports', 'البلاغات', Icons.report_outlined, _DashboardAction.reports),
        _DashboardCardSpec('waiting_user', 'انتظار المستخدم', Icons.hourglass_bottom, _DashboardAction.waitingUser),
        _DashboardCardSpec('overdue', 'المتأخر', Icons.timer_off_outlined, _DashboardAction.overdue),
      ],
      attentionTitle: 'يحتاج انتباهك',
    );
  }
}

class SupportManagerHomeScreen extends ConsumerWidget {
  const SupportManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardFrame(
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
      cards: const [
        _DashboardCardSpec('unassigned', 'غير المسندة', Icons.inbox_outlined, _DashboardAction.inbox),
        _DashboardCardSpec('in_progress', 'جاري العمل', Icons.pending_actions_outlined, _DashboardAction.all),
        _DashboardCardSpec('overdue', 'المتأخرة', Icons.timer_off_outlined, _DashboardAction.overdueAll),
        _DashboardCardSpec('waiting_user', 'انتظار المستخدم', Icons.hourglass_bottom, _DashboardAction.waitingUserAll),
        _DashboardCardSpec('escalated', 'المصعدة', Icons.trending_up, _DashboardAction.escalated),
        _DashboardCardSpec('critical_reports', 'بلاغات حرجة', Icons.crisis_alert_outlined, _DashboardAction.criticalReports),
        _DashboardCardSpec('active_agents', 'موظفو الدعم', Icons.groups_2_outlined, _DashboardAction.team),
        _DashboardCardSpec('available_agents', 'المتاحون الآن', Icons.how_to_reg_outlined, _DashboardAction.team),
        _DashboardCardSpec('team_open', 'عبء الفريق', Icons.work_outline, _DashboardAction.all),
        _DashboardCardSpec('completed_today', 'منجز اليوم', Icons.task_alt_outlined, _DashboardAction.completed),
        _DashboardCardSpec('average_claim_minutes', 'متوسط الاستلام/د', Icons.schedule_outlined, _DashboardAction.all),
        _DashboardCardSpec('average_response_minutes', 'متوسط الرد/د', Icons.quickreply_outlined, _DashboardAction.all),
      ],
    );
  }
}

class PlatformAdminHomeScreen extends ConsumerWidget {
  const PlatformAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardFrame(
      title: 'لوحة الإدارة',
      load: () => ref.read(supportWorkspaceRepositoryProvider).dashboard(),
      cards: const [
        _DashboardCardSpec('users', 'المستخدمون', Icons.people_alt_outlined, _DashboardAction.users),
        _DashboardCardSpec('pending_listing_reviews', 'إعلانات قيد المراجعة', Icons.fact_check_outlined, _DashboardAction.listingsAll),
        _DashboardCardSpec('pending_verifications', 'طلبات التحقق', Icons.verified_user_outlined, _DashboardAction.verificationsAll),
        _DashboardCardSpec('open_support_tasks', 'أعمال الدعم', Icons.support_agent_outlined, _DashboardAction.all),
        _DashboardCardSpec('support_agents', 'موظفو الدعم', Icons.groups_2_outlined, _DashboardAction.team),
        _DashboardCardSpec('support_managers', 'مديرو الدعم', Icons.supervisor_account_outlined, _DashboardAction.team),
        _DashboardCardSpec('average_claim_minutes', 'متوسط الاستلام/د', Icons.schedule_outlined, _DashboardAction.all),
        _DashboardCardSpec('average_response_minutes', 'متوسط الرد/د', Icons.quickreply_outlined, _DashboardAction.all),
        _DashboardCardSpec('critical_reports', 'بلاغات حرجة', Icons.crisis_alert_outlined, _DashboardAction.criticalReports),
        _DashboardCardSpec('overdue', 'حالات متأخرة', Icons.timer_off_outlined, _DashboardAction.overdueAll),
        _DashboardCardSpec('escalated', 'حالات مصعدة', Icons.trending_up, _DashboardAction.escalated),
        _DashboardCardSpec('bookings', 'الحجوزات', Icons.calendar_month_outlined, _DashboardAction.bookings),
        _DashboardCardSpec('regions', 'المناطق', Icons.map_outlined, _DashboardAction.regions),
        _DashboardCardSpec('service_orders', 'الخدمات', Icons.home_repair_service_outlined, _DashboardAction.services),
      ],
    );
  }
}

class SupportTeamScreen extends ConsumerStatefulWidget {
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


class PlatformReviewsScreen extends StatelessWidget {
  const PlatformReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المراجعات'),
            bottom: const TabBar(
              tabs: [Tab(text: 'الإعلانات'), Tab(text: 'التحقق')],
            ),
          ),
          body: const TabBarView(
            children: [
              SupportTasksScreen(
                initialScope: 'all',
                initialType: 'listing_review',
                title: 'مراجعات الإعلانات',
              ),
              SupportTasksScreen(
                initialScope: 'all',
                initialType: 'account_verification',
                title: 'طلبات التحقق',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlatformOperationsScreen extends ConsumerWidget {
  const PlatformOperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المنصة')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const _SectionHeader('إدارة وتشغيل المنصة'),
            _OperationTile(
              icon: Icons.map_outlined,
              title: 'المناطق والخريطة',
              subtitle: 'المحافظات والمديريات وإدارة المناطق حسب الصلاحية',
              enabled: user?.isPlatformOwner == true || user?.hasPermission('regions.manage') == true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PlatformRegionsScreen()),
              ),
            ),
            _OperationTile(
              icon: Icons.calendar_month_outlined,
              title: 'الحجوزات والمعاينات',
              subtitle: 'الطلبات والمواعيد والحالات وإعادة الجدولة',
              onTap: () => context.push('/bookings'),
            ),
            _OperationTile(
              icon: Icons.home_repair_service_outlined,
              title: 'الخدمات والمدفوعات',
              subtitle: 'طلبات الخدمات وحالة الدفع دون بيانات بطاقات حساسة',
              onTap: () => context.push('/services'),
            ),
            _OperationTile(
              icon: Icons.notifications_outlined,
              title: 'التنبيهات والإشعارات',
              onTap: () => context.push('/notifications'),
            ),
            const SizedBox(height: 18),
            const _SectionHeader('الحوكمة'),
            _OperationTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'المستخدمون والأدوار والصلاحيات وسجل التدقيق',
              subtitle: 'كل تغيير حساس يمر عبر صلاحيات Backend ويظهر في Audit Log',
              enabled: user?.canAccessAdminPanel == true,
              onTap: () => context.push('/admin/access'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardFrame extends ConsumerStatefulWidget {
  const _DashboardFrame({
    required this.title,
    required this.load,
    required this.cards,
    this.attentionTitle,
    this.topAction,
  });

  final String title;
  final Future<SupportWorkspaceDashboard> Function() load;
  final List<_DashboardCardSpec> cards;
  final String? attentionTitle;
  final Widget? topAction;

  @override
  ConsumerState<_DashboardFrame> createState() => _DashboardFrameState();
}

class _DashboardFrameState extends ConsumerState<_DashboardFrame> {
  late Future<SupportWorkspaceDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh))],
        ),
        body: FutureBuilder<SupportWorkspaceDashboard>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return _ErrorState(error: snapshot.error!, onRetry: _refresh);
            final dashboard = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _HeroHeader(mode: dashboard.mode),
                  if (widget.topAction != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: widget.topAction!),
                  ],
                  if (dashboard.mode == 'platform') ...[
                    const SizedBox(height: 14),
                    _PlatformDailySummary(dashboard: dashboard),
                  ],
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.55,
                      crossAxisSpacing: 9,
                      mainAxisSpacing: 9,
                    ),
                    itemCount: widget.cards.length,
                    itemBuilder: (_, index) {
                      final spec = widget.cards[index];
                      return _DashboardCard(
                        spec: spec,
                        count: dashboard.count(spec.key),
                        onTap: () => _openAction(context, spec.action),
                      );
                    },
                  ),
                  if (widget.attentionTitle != null) ...[
                    const SizedBox(height: 22),
                    _SectionHeader(widget.attentionTitle!),
                    const SizedBox(height: 8),
                    if (dashboard.attention.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('لا توجد عناصر عاجلة تحتاج انتباهك الآن.'),
                        ),
                      )
                    else
                      ...dashboard.attention.map(
                        (task) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Icon(_attentionIcon(task.sourceType))),
                            title: Text(task.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${_attentionType(task.sourceType)} • ${_attentionStatus(task.status)}'),
                            trailing: task.isOverdue
                                ? const Badge(label: Text('متأخر'))
                                : const Icon(Icons.chevron_left),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SupportTasksScreen(
                                  initialScope: task.isMine ? 'mine' : 'inbox',
                                  initialType: task.sourceType,
                                  title: 'تفاصيل المهام',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

void _openAction(BuildContext context, _DashboardAction action) {
  Widget? page;
  switch (action) {
    case _DashboardAction.inbox:
      page = const SupportTasksScreen(initialScope: 'inbox', title: 'الوارد الجديد');
      break;
    case _DashboardAction.mine:
      page = const SupportTasksScreen(initialScope: 'mine', title: 'مهامي');
      break;
    case _DashboardAction.all:
      page = const SupportTasksScreen(initialScope: 'all', title: 'كل الأعمال');
      break;
    case _DashboardAction.verifications:
      page = const SupportTasksScreen(initialScope: 'inbox', initialType: 'account_verification', title: 'طلبات التحقق');
      break;
    case _DashboardAction.listings:
      page = const SupportTasksScreen(initialScope: 'inbox', initialType: 'listing_review', title: 'تحقيق الإعلانات');
      break;
    case _DashboardAction.tickets:
      page = const SupportTasksScreen(initialScope: 'inbox', initialType: 'support_ticket', title: 'التذاكر');
      break;
    case _DashboardAction.reports:
      page = const SupportTasksScreen(initialScope: 'inbox', initialType: 'report', title: 'البلاغات');
      break;
    case _DashboardAction.waitingUser:
      page = const SupportTasksScreen(initialScope: 'mine', initialStatus: 'waiting_user', title: 'انتظار المستخدم');
      break;
    case _DashboardAction.overdue:
      page = const SupportTasksScreen(initialScope: 'mine', overdueOnly: true, title: 'المتأخر');
      break;
    case _DashboardAction.overdueAll:
      page = const SupportTasksScreen(initialScope: 'all', overdueOnly: true, title: 'الحالات المتأخرة');
      break;
    case _DashboardAction.waitingUserAll:
      page = const SupportTasksScreen(initialScope: 'all', initialStatus: 'waiting_user', title: 'انتظار المستخدم');
      break;
    case _DashboardAction.escalated:
      page = const SupportTasksScreen(initialScope: 'all', initialStatus: 'escalated', title: 'الحالات المصعدة');
      break;
    case _DashboardAction.criticalReports:
      page = const SupportTasksScreen(
        initialScope: 'all',
        initialType: 'report',
        initialSeverity: 'critical',
        title: 'البلاغات الحرجة',
      );
      break;
    case _DashboardAction.team:
      page = const SupportTeamScreen();
      break;
    case _DashboardAction.listingsAll:
      page = const SupportTasksScreen(initialScope: 'all', initialType: 'listing_review', title: 'مراجعات الإعلانات');
      break;
    case _DashboardAction.verificationsAll:
      page = const SupportTasksScreen(initialScope: 'all', initialType: 'account_verification', title: 'طلبات التحقق');
      break;
    case _DashboardAction.users:
      context.push('/admin/access');
      return;
    case _DashboardAction.bookings:
      context.push('/bookings');
      return;
    case _DashboardAction.regions:
      page = const PlatformRegionsScreen();
      break;
    case _DashboardAction.services:
      context.push('/services');
      return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page!));
}

class _PlatformDailySummary extends StatelessWidget {
  const _PlatformDailySummary({required this.dashboard});

  final SupportWorkspaceDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final today = dashboard.today;
    int value(String key) {
      final raw = today[key];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ملخص اليوم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip('مستخدم جديد', value('new_users')),
                _MetricChip('طلب تحقق', value('verification_requests')),
                _MetricChip('إعلان للمراجعة', value('listing_reviews')),
                _MetricChip('مهمة دعم جديدة', value('new_support_tasks')),
                _MetricChip('بلاغ حرج', value('critical_reports')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.spec, required this.count, required this.onTap});
  final _DashboardCardSpec spec;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = spec.key == 'critical_reports' || spec.key == 'overdue';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(spec.icon, color: urgent && count > 0 ? Colors.red.shade700 : AppTheme.brandStrong),
                  const Spacer(),
                  Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: urgent && count > 0 ? Colors.red.shade800 : AppTheme.textStrong)),
                ],
              ),
              Text(spec.label, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final data = switch (mode) {
      'manager' => ('لوحة تشغيل الفريق', 'راقب العمل المتأخر والمصعّد وحالة الموظفين دون تعطيل نظام الاستلام المشترك.'),
      'platform' => ('صورة تشغيلية للمنصة', 'نظرة عليا على المستخدمين والمراجعات والدعم والعمليات، مع التدخل عند الحاجة فقط.'),
      _ => ('ابدأ بالأهم', 'الوارد غير المسند مشترك بين الموظفين. بعد الاستلام تنتقل المهمة إلى مهامك وتصبح مسؤولاً عنها.'),
    };
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppTheme.brand, AppTheme.brandStrong]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.$1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(data.$2, style: const TextStyle(color: Colors.white70, height: 1.45)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 10),
              Text(friendlyApiError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label $value'));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900));
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          enabled: enabled,
          leading: CircleAvatar(backgroundColor: AppTheme.brandSoft, child: Icon(icon, color: AppTheme.brandStrong)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: const Icon(Icons.chevron_left),
          onTap: enabled ? onTap : null,
        ),
      );
}

class _DashboardCardSpec {
  const _DashboardCardSpec(this.key, this.label, this.icon, this.action);
  final String key;
  final String label;
  final IconData icon;
  final _DashboardAction action;
}

enum _DashboardAction {
  inbox,
  mine,
  all,
  verifications,
  listings,
  tickets,
  reports,
  waitingUser,
  overdue,
  overdueAll,
  waitingUserAll,
  escalated,
  criticalReports,
  team,
  listingsAll,
  verificationsAll,
  users,
  bookings,
  regions,
  services,
}

String _attentionType(String type) => switch (type) {
      'account_verification' => 'تحقق حساب',
      'listing_review' => 'تحقيق إعلان',
      'support_ticket' => 'تذكرة',
      'report' => 'بلاغ',
      _ => type,
    };

String _attentionStatus(String status) => switch (status) {
      'new' => 'جديد',
      'in_progress' => 'قيد العمل',
      'waiting_user' => 'انتظار المستخدم',
      'needs_followup' => 'يحتاج متابعة',
      'escalated' => 'مصعّد',
      _ => status,
    };

IconData _attentionIcon(String type) => switch (type) {
      'account_verification' => Icons.verified_user_outlined,
      'listing_review' => Icons.fact_check_outlined,
      'support_ticket' => Icons.support_agent_outlined,
      'report' => Icons.report_outlined,
      _ => Icons.task_alt,
    };
