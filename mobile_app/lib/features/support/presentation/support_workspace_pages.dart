import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../regions/presentation/platform_regions_screen.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_workspace_models.dart';
import 'support_tasks_screen.dart';
import 'support_team_administration_screen.dart';

class SupportAgentHomeScreen extends ConsumerWidget {
  const SupportAgentHomeScreen({this.actingAsAgent = false, this.returnToManager, super.key});
  final bool actingAsAgent;
  final VoidCallback? returnToManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardFrame(
      title: 'مركز الدعم',
      load: () {
        final repository = ref.read(supportWorkspaceRepositoryProvider);
        return actingAsAgent ? repository.agentDashboard() : repository.dashboard();
      },
      actingAsAgent: actingAsAgent,
      showHero: false,
      topAction: returnToManager == null ? null : EbrokerOutlinedButton.icon(
        onPressed: returnToManager,
        icon: const EbrokerIcon(Icons.groups_outlined),
        label: const Text('العودة إلى لوحة الفريق'),
      ),
      cards: const [
        _DashboardCardSpec('assigned', 'المهام المسندة إليك', Icons.assignment_ind_outlined, _DashboardAction.assigned),
        _DashboardCardSpec('received', 'المهام المستلمة', Icons.inbox_outlined, _DashboardAction.received),
        _DashboardCardSpec('open_tickets', 'التذاكر المفتوحة', Icons.chat_bubble_outline, _DashboardAction.openTickets),
        _DashboardCardSpec('waiting_user', 'بانتظار المستخدم', Icons.hourglass_bottom, _DashboardAction.waitingUser),
        _DashboardCardSpec('completed', 'المنجزة', Icons.task_alt_outlined, _DashboardAction.completed),
        _DashboardCardSpec('unreceived_overdue', 'المتأخر', Icons.timer_off_outlined, _DashboardAction.unreceivedOverdue),
      ],
    );
  }
}

final _managerTeamsProvider = FutureProvider.autoDispose<List<SupportTeamSummary>>((ref) {
  ref.watch(supportWorkspaceRevisionProvider);
  return ref.watch(supportWorkspaceRepositoryProvider).teams();
});

class SupportManagerHomeScreen extends ConsumerWidget {
  const SupportManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(_managerTeamsProvider).asData?.value ?? const <SupportTeamSummary>[];
    final current = teams.length == 1 ? teams.single : null;
    final name = current?.name ?? 'فريق الدعم';
    return _DashboardFrame(
      title: 'لوحة الفريق',
      load: () => ref.read(supportWorkspaceRepositoryProvider).dashboard(),
      showHero: false,
      intro: Card(child: ListTile(leading: const EbrokerIcon(Icons.groups_outlined),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: teams.isEmpty ? null : Text(
          '${teams.fold(0, (sum, team) => sum + team.availableAgents)} متاح من ${teams.fold(0, (sum, team) => sum + team.agents)} أعضاء'),
      )),
      cards: const [
        _DashboardCardSpec('unassigned', 'غير مسندة', Icons.inbox_outlined, _DashboardAction.inbox),
        _DashboardCardSpec('in_progress', 'قيد العمل', Icons.pending_actions_outlined, _DashboardAction.processing),
        _DashboardCardSpec('unreceived_overdue', 'تأخر الاستلام', Icons.timer_off_outlined, _DashboardAction.unreceivedOverdue),
        _DashboardCardSpec('intervention', 'تحتاج تدخلك', Icons.flag_outlined, _DashboardAction.intervention),
      ],
      footer: _ManagerStatistics(title: current?.governorateName == null
          ? 'إحصائيات الفريق' : 'إحصائيات ${current!.governorateName}'),
    );
  }
}

class _ManagerStatistics extends ConsumerStatefulWidget {
  const _ManagerStatistics({required this.title});
  final String title;

  @override
  ConsumerState<_ManagerStatistics> createState() => _ManagerStatisticsState();
}

class _ManagerStatisticsState extends ConsumerState<_ManagerStatistics> {
  String _period = 'today';
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    _range = _dates('today');
  }

  DateTimeRange _dates(String period) {
    final clock = DateTime.now().toUtc().add(const Duration(hours: 3));
    final today = DateTime(clock.year, clock.month, clock.day);
    return DateTimeRange(start: switch (period) {
      'week' => today.subtract(const Duration(days: 6)),
      'month' => DateTime(today.year, today.month),
      _ => today,
    }, end: today);
  }

  Future<void> _choose() async {
    final today = _dates('today').end;
    final selection = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: today, initialDateRange: _range,
      helpText: 'اختيار مدة الإحصائيات',
    );
    if (!mounted || selection == null) return;
    setState(() { _period = 'custom'; _range = selection; });
  }

  static String _date(DateTime day) => day.toIso8601String().split('T').first;

  @override
  Widget build(BuildContext context) {
    final from = _date(_range.start);
    final to = _date(_range.end);
    final result = ref.watch(_managerStatisticsProvider((from, to)));
    const periods = [('today', 'اليوم'), ('week', '٧ أيام'), ('month', 'هذا الشهر')];
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (value, title) in periods)
            EbrokerChoiceChip(label: Text(title), selected: _period == value, onSelected: (_) {
              setState(() { _period = value; _range = _dates(value); });
            }),
          EbrokerActionChip(label: const Text('اختيار مدة'),
            avatar: const EbrokerIcon(Icons.date_range_outlined, size: 16), onPressed: _choose),
        ]),
        if (_period == 'custom') Text('$from — $to', textDirection: TextDirection.ltr),
        result.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => TextButton(onPressed: () => ref.invalidate(_managerStatisticsProvider((from, to))),
            child: Text('تعذّر تحميل الإحصائيات · إعادة المحاولة')),
          data: (values) {
            final response = values['average_first_response_minutes'];
            return GridView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2,
                mainAxisExtent: 35 + 2.8 * MediaQuery.textScalerOf(context).scale(13)),
              children: [
                for (final item in [
                  ('الطلبات المرفوعة', values['received']),
                  ('أنجزها الفريق', values['completed']),
                  ('إعلانات نُشرت', values['published']),
                  ('البلاغات الواردة', values['reports']),
                  ('متوسط أول رد', response == null ? '—' : '$response دقيقة'),
                  ('إعلانات قيد المراجعة الآن', values['pending_listings']),
                ])
                  Padding(padding: const EdgeInsets.all(6), child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text(item.$1, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
                      Text('${item.$2 ?? '—'}', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  )),
              ]);
          },
        ),
      ],
    )));
  }
}

final _managerStatisticsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, String)>((ref, dates) {
  ref.watch(supportWorkspaceRevisionProvider);
  return ref.watch(supportWorkspaceRepositoryProvider).statistics(dates.$1, dates.$2);
});

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
    _future = _load(); _future.ignore();
  }

  Future<(List<SupportTeamMember>, List<SupportTeamSummary>)> _load() async {
    final repo = ref.read(supportWorkspaceRepositoryProvider);
    final values = await Future.wait<dynamic>([repo.team(), repo.teams()]);
    return (values[0] as List<SupportTeamMember>, values[1] as List<SupportTeamSummary>);
  }

  Future<void> _refresh() async {
    setState(() { _future = _load(); _future.ignore(); });
    try { await _future; } catch (_) { /* The view renders failure and retry. */ }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الفريق وعبء العمل'),
            actions: [
              if (canAdministerSupportTeams(ref.watch(authControllerProvider).asData?.value))
                IconButton(
                  tooltip: 'فرق المحافظات',
                  icon: const EbrokerIcon(Icons.groups_outlined),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const SupportTeamAdministrationScreen()),
                  ),
                ),
              IconButton(onPressed: _refresh, icon: const EbrokerIcon(Icons.refresh)),
            ],
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
                    const _SectionHeader('الفرق'),
                    const SizedBox(height: 8),
                    if (teams.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد فرق دعم ضمن نطاقك.')))
                    else
                      ...teams.map((team) => Card(
                            child: ListTile(
                              leading: CircleAvatar(child: EbrokerIcon(team.isFallback ? Icons.all_inbox_outlined : Icons.location_on_outlined)),
                              title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      ...members.where((m) => m.role == 'support_agent').map((member) =>
                        Card(child: ListTile(
                          leading: const EbrokerIcon(Icons.person_outline),
                          title: Text(member.name),
                          subtitle: Text('${member.openTasks} مهام مفتوحة'),
                          trailing: Text(member.isAvailable ? 'متاح' : 'غير متاح'),
                          onTap: () => _openMember(member, teams),
                        ))),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> _openMember(SupportTeamMember member, List<SupportTeamSummary> teams) async {
    final scope = ref.read(accountRequestScopeProvider);
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (pageContext) => Scaffold(
        appBar: const AppAppBar(title: 'تفاصيل الموظف'),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(child: ListTile(leading: const EbrokerIcon(Icons.person_outline),
            title: Text(member.name),
            subtitle: Text('${member.teamName ?? 'موظف دعم'} · ${member.isAvailable ? 'متاح' : 'غير متاح'}'),
            trailing: TextButton.icon(icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('مراسلة'), onPressed: () async {
                try {
                  final thread = await ref.read(supportWorkspaceRepositoryProvider)
                    .openStaffThread(memberId: member.id, teamId: member.teamId);
                  if (pageContext.mounted && scope.isCurrent) {
                    await pageContext.push<void>('/support/internal/${thread.id}');
                  }
                } catch (error) {
                  if (pageContext.mounted && scope.isCurrent) {
                    ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(content: Text(friendlyApiError(error))));
                  }
                }
              }),
          )),
          Card(child: ListTile(title: const Text('المهام المفتوحة'),
            trailing: Text('${member.openTasks} من ${member.capacity}'))),
          Card(child: ListTile(leading: const Icon(Icons.list_alt_outlined), title: const Text('عرض مهامه'),
            onTap: () => Navigator.of(pageContext).push<void>(MaterialPageRoute(builder: (_) =>
              SupportTasksScreen(initialScope: 'active', initialAssigneeId: member.id, title: 'مهام ${member.name}'))))),
          Card(child: ListTile(leading: const Icon(Icons.toggle_on_outlined), title: const Text('تعديل التوفر'),
            onTap: () async {
              await _manageMember(member, teams);
              if (pageContext.mounted) Navigator.pop(pageContext);
            })),
          if (member.openTasks > 0)
            Card(child: ListTile(leading: const Icon(Icons.move_to_inbox_outlined), title: const Text('إعادة توزيع المهام'),
              onTap: () async {
                await _redistribute(member);
                if (pageContext.mounted) Navigator.pop(pageContext);
              })),
        ]),
      ),
    ));
  }

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
                  IconButton(onPressed: capacity <= 1 ? null : () => setLocal(() => capacity--), icon: const EbrokerIcon(Icons.remove_circle_outline)),
                  Text('$capacity', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(onPressed: capacity >= 50 ? null : () => setLocal(() => capacity++), icon: const EbrokerIcon(Icons.add_circle_outline)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            EbrokerFilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
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
          EbrokerFilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إعادة للوارد')),
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
    this.topAction,
    this.intro,
    this.footer,
    this.actingAsAgent = false,
    this.showHero = true,
  });

  final String title;
  final Future<SupportWorkspaceDashboard> Function() load;
  final List<_DashboardCardSpec> cards;
  final Widget? topAction;
  final Widget? intro;
  final Widget? footer;
  final bool actingAsAgent;
  final bool showHero;

  @override
  ConsumerState<_DashboardFrame> createState() => _DashboardFrameState();
}

class _DashboardFrameState extends ConsumerState<_DashboardFrame> {
  late Future<SupportWorkspaceDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load(); _future.ignore();
    ref.listenManual(supportWorkspaceRevisionProvider, (_, __) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() { _future = widget.load(); _future.ignore(); });
    try { await _future; } catch (_) { /* The view renders failure and retry. */ }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const EbrokerIcon(Icons.refresh))],
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
                  if (widget.showHero) _HeroHeader(mode: dashboard.mode),
                  if (widget.intro != null) widget.intro!,
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 67 + 2.7 * MediaQuery.textScalerOf(context).scale(14),
                      crossAxisSpacing: 9,
                      mainAxisSpacing: 9,
                    ),
                    itemCount: widget.cards.length,
                    itemBuilder: (_, index) {
                      final spec = widget.cards[index];
                      return _DashboardCard(
                        spec: spec,
                        count: dashboard.count(spec.key),
                        onTap: () async {
                          await _openAction(context, spec.action, actingAsAgent: widget.actingAsAgent);
                          if (mounted) await _refresh();
                        },
                      );
                    },
                  ),
                  if (widget.footer != null) ...[
                    const SizedBox(height: 12),
                    widget.footer!,
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

Future<void> _openAction(BuildContext context, _DashboardAction action, {bool actingAsAgent = false}) async {
  Widget? page;
  switch (action) {
    case _DashboardAction.inbox:
      page = const SupportTasksScreen(initialScope: 'inbox', title: 'الوارد الجديد');
      break;
    case _DashboardAction.assigned:
      page = SupportTasksScreen(initialScope: 'assigned', title: 'المهام المسندة إليك', actingAsAgent: actingAsAgent);
      break;
    case _DashboardAction.received:
      page = SupportTasksScreen(initialScope: 'received', title: 'المهام المستلمة', actingAsAgent: actingAsAgent);
      break;
    case _DashboardAction.openTickets:
      page = SupportTasksScreen(initialScope: 'open_tickets', title: 'التذاكر المفتوحة', actingAsAgent: actingAsAgent);
      break;
    case _DashboardAction.completed:
      page = SupportTasksScreen(initialScope: 'completed', title: 'المهام المنجزة', actingAsAgent: actingAsAgent);
      break;
    case _DashboardAction.all:
      page = const SupportTasksScreen(initialScope: 'all', title: 'كل الأعمال');
      break;
    case _DashboardAction.processing:
      page = const SupportTasksScreen(initialScope: 'processing', title: 'قيد العمل');
      break;
    case _DashboardAction.intervention:
      page = const SupportTasksScreen(initialScope: 'intervention', title: 'تحتاج تدخلك');
      break;
    case _DashboardAction.waitingUser:
      page = SupportTasksScreen(initialScope: 'waiting_user', title: 'بانتظار المستخدم', actingAsAgent: actingAsAgent);
      break;
    case _DashboardAction.unreceivedOverdue:
      page = SupportTasksScreen(initialScope: 'unreceived_overdue', title: 'المتأخر', actingAsAgent: actingAsAgent);
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
      await context.push<void>('/admin/access');
      return;
    case _DashboardAction.regions:
      page = const PlatformRegionsScreen();
      break;
    case _DashboardAction.services:
      await context.push<void>('/services');
      return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page!));
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
            const Text('ملخص اليوم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    final urgent = const {'critical_reports', 'overdue', 'unreceived_overdue'}.contains(spec.key);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  EbrokerIcon(spec.icon, color: urgent && count > 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                  const Spacer(),
                  Flexible(child: Text('$count', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: urgent && count > 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface))),
                ],
              ),
              Flexible(child: Text(spec.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.$1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
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
              const EbrokerIcon(Icons.error_outline, size: 48),
              const SizedBox(height: 10),
              Text(friendlyApiError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              EbrokerFilledButton.icon(onPressed: onRetry, icon: const EbrokerIcon(Icons.refresh), label: const Text('إعادة المحاولة')),
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
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600));
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
          leading: CircleAvatar(backgroundColor: AppTheme.brandSoft, child: EbrokerIcon(icon, color: AppTheme.brandStrong)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: const EbrokerIcon(Icons.chevron_left),
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
  assigned,
  received,
  openTickets,
  completed,
  all,
  processing,
  intervention,
  waitingUser,
  unreceivedOverdue,
  overdueAll,
  waitingUserAll,
  escalated,
  criticalReports,
  team,
  listingsAll,
  verificationsAll,
  users,
  regions,
  services,
}
