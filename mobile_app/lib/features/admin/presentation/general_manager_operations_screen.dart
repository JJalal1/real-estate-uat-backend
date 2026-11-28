import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../financial/data/financial_repository.dart';
import '../../support/data/support_workspace_repository.dart';
import '../../support/domain/support_workspace_models.dart';
import '../../support/presentation/support_team_administration_screen.dart';
import '../data/general_manager_repository.dart';
import '../domain/general_manager_insights.dart';
import 'general_manager_finance_screens.dart';

enum GeneralManagerSection { home, teams, reports, journey }

const _periods = {'day': 'اليوم', '7d': '٧ أيام', '30d': '٣٠ يومًا'};

final _operations = FutureProvider.autoDispose
    .family<GeneralManagerOperations, (String, int?)>((ref, filter) {
  return ref
      .watch(generalManagerRepositoryProvider)
      .operations(filter.$1, governorateId: filter.$2);
});

final _finance = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(financialRepositoryProvider).adminSummary(period: '30d'),
);

class GeneralManagerOperationsScreen extends ConsumerStatefulWidget {
  const GeneralManagerOperationsScreen(this.section, {super.key});
  final GeneralManagerSection section;

  @override
  ConsumerState<GeneralManagerOperationsScreen> createState() =>
      _GeneralManagerOperationsScreenState();
}

class _GeneralManagerOperationsScreenState
    extends ConsumerState<GeneralManagerOperationsScreen> {
  late String _period;
  int? _province;
  List<ExecutiveTeamStats> _allTeams = [];

  @override
  void initState() {
    super.initState();
    _period = widget.section == GeneralManagerSection.home ? 'day' : '7d';
  }

  @override
  Widget build(BuildContext context) {
    final filter = (_period, _province);
    final loaded = ref.watch(_operations(filter));
    final home = widget.section == GeneralManagerSection.home;
    final data = loaded.asData?.value;
    if (data != null && _province == null) _allTeams = data.teams;
    final title = switch (widget.section) {
      GeneralManagerSection.home => 'الرئيسية',
      GeneralManagerSection.teams => 'فرق المحافظات',
      GeneralManagerSection.reports => 'التقارير',
      GeneralManagerSection.journey => 'رحلة العقار',
    };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(title: title, actions: [
          if (home)
            IconButton(
              tooltip: 'الرسائل',
              icon: Badge(
                isLabelVisible: (data?.unreadMessages ?? 0) > 0,
                label: Text('${data?.unreadMessages ?? 0}'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              onPressed: () async {
                await context.push<void>('/support/internal');
                if (mounted) ref.invalidate(_operations(filter));
              },
            )
          else
            IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(_operations(filter))),
        ]),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_finance);
            ref.invalidate(_operations(filter));
            try {
              await ref.read(_operations(filter).future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _ProvincePicker(
                  teams: _allTeams,
                  selected: _province,
                  onSelected: (value) => setState(() => _province = value),
                ),
                _PeriodPicker(
                    period: _period,
                    onSelected: (value) => setState(() => _period = value)),
              ]),
              const SizedBox(height: 14),
              if (loaded.isLoading)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()))
              else if (loaded.hasError)
                _InlineFailure(
                    error: loaded.error!,
                    onRetry: () => ref.invalidate(_operations(filter)))
              else if (data != null)
                ..._content(context, data),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, GeneralManagerOperations data) {
    switch (widget.section) {
      case GeneralManagerSection.home:
        final teams = data.teams
            .where((team) => team.members > 0 || team.count('overdue') > 0)
            .toList()
          ..sort((a, b) => b.count('overdue').compareTo(a.count('overdue')));
        final waiting =
            ref.watch(_finance).asData?.value['payments_waiting_review'];
        return [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('يحتاج قرارك',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(data.decisions == 0
                        ? 'لا توجد حالات بانتظار قرارك'
                        : '${data.decisions} حالات مصعّدة من فرق المحافظات'),
                    if (data.decisions > 0)
                      FilledButton.icon(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () async {
                            await Navigator.of(context)
                                .push<void>(MaterialPageRoute(
                              builder: (_) => _ExecutiveDecisionList(
                                  governorateId: _province),
                            ));
                            if (mounted) {
                              ref.invalidate(_operations((_period, _province)));
                            }
                          },
                          label: const Text('عرض الحالات')),
                  ],
                )),
          ),
          const SizedBox(height: 14),
          AppSectionHeader(
              title: _period == 'day' ? 'مؤشرات اليوم' : 'مؤشرات الفترة'),
          _Metrics(data.totals),
          const SizedBox(height: 16),
          const AppSectionHeader(title: 'متابعة الفرق'),
          for (final team in teams.take(3))
            _teamTile(context, team, summary: true),
          _link(
              context,
              'فرق المحافظات',
              Icons.groups_outlined,
              const GeneralManagerOperationsScreen(
                  GeneralManagerSection.teams)),
          _link(context, 'المالية', Icons.account_balance_wallet_outlined,
              const GeneralManagerFinanceWorkspaceScreen(),
              subtitle:
                  waiting == null ? null : '$waiting معاملات بانتظار التحقق'),
        ];
      case GeneralManagerSection.reports:
        return [
          const AppSectionHeader(title: 'أداء فرق المحافظات'),
          _Metrics(data.totals),
          const SizedBox(height: 12),
          for (final team in data.teams) _teamTile(context, team),
          _link(
              context,
              'رحلة العقار',
              Icons.timeline_outlined,
              const GeneralManagerOperationsScreen(
                  GeneralManagerSection.journey)),
          _link(context, 'المالية', Icons.account_balance_wallet_outlined,
              const GeneralManagerFinanceWorkspaceScreen()),
        ];
      case GeneralManagerSection.teams:
        return [
          if (data.teams.isEmpty)
            const ListTile(title: Text('لا يوجد فريق للمحافظة المختارة.')),
          for (final team in data.teams)
            Card(
                child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(team.name),
              subtitle: Text([
                team.managerName ?? 'بانتظار تعيين مدير',
                '${team.members} أعضاء',
                '${team.count('overdue')} متأخرة'
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _openTeam(team),
            )),
          _link(context, 'إعداد فرق المحافظات', Icons.person_add_alt,
              const SupportTeamAdministrationScreen()),
        ];
      case GeneralManagerSection.journey:
        return [
          const AppSectionHeader(title: 'النشاط داخل المنصة'),
          Card(
              child: Column(children: [
            for (final item in const {
              'conversations': 'المحادثات',
              'viewings': 'طلبات المعاينة',
              'agreements': 'الاتفاقات',
              'rental_contracts': 'عقود الإيجار داخل التطبيق',
            }.entries)
              ListTile(
                  title: Text(item.value),
                  trailing: Text('${data.journey[item.key] ?? 0}')),
          ])),
        ];
    }
  }

  Widget _teamTile(BuildContext context, ExecutiveTeamStats team,
      {bool summary = false}) {
    final values = summary
        ? '${team.count('overdue')} مهام متأخرة'
        : "${team.count('received')} مرفوعة · ${team.count('completed')} منجزة · ${team.count('published')} منشورة";
    return Card(
        child: ListTile(
      leading: const Icon(Icons.groups_outlined),
      title: Text(team.name),
      subtitle: Text(values),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => _openTeam(team),
    ));
  }

  Future<void> _openTeam(ExecutiveTeamStats team) async {
    final scope = ref.read(accountRequestScopeProvider);
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ActorBoundPage(
          title: team.name,
          requestScope: scope,
          builder: (_) =>
              _ExecutiveTeamDetails(initial: team, period: _period)),
    ));
    if (mounted) ref.invalidate(_operations((_period, _province)));
  }
}

class _ExecutiveTeamDetails extends ConsumerStatefulWidget {
  const _ExecutiveTeamDetails({required this.initial, required this.period});
  final ExecutiveTeamStats initial;
  final String period;

  @override
  ConsumerState<_ExecutiveTeamDetails> createState() =>
      _ExecutiveTeamDetailsState();
}

class _ExecutiveTeamDetailsState extends ConsumerState<_ExecutiveTeamDetails> {
  late String _period = widget.period;
  late Future<List<SupportTeamMembership>> _members = _loadMembers();
  bool _opening = false;

  Future<List<SupportTeamMembership>> _loadMembers() => ref
      .read(supportWorkspaceRepositoryProvider)
      .teamMemberships(widget.initial.id);

  Future<void> _message() async {
    setState(() => _opening = true);
    final scope = ref.read(accountRequestScopeProvider);
    try {
      final thread = await ref
          .read(supportWorkspaceRepositoryProvider)
          .openStaffThread(teamId: widget.initial.id);
      if (mounted && scope.isCurrent) {
        await context.push<void>('/support/internal/${thread.id}');
      }
    } catch (error) {
      if (mounted && scope.isCurrent) _showFailure(context, error);
    } finally {
      if (mounted && scope.isCurrent) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = (_period, widget.initial.governorateId);
    final snapshot = ref.watch(_operations(filter));
    final rows = snapshot.asData?.value.teams;
    final team =
        rows?.where((team) => team.id == widget.initial.id).firstOrNull;
    return Scaffold(
      appBar: AppAppBar(title: widget.initial.name),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
            child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
              (team ?? widget.initial).managerName ?? 'بانتظار تعيين مدير'),
          subtitle: Text('${(team ?? widget.initial).members} أعضاء'),
          trailing: IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'مراسلة مدير الفريق',
              onPressed:
                  _opening || (team ?? widget.initial).managerName == null
                      ? null
                      : _message),
        )),
        const SizedBox(height: 12),
        Wrap(children: [
          _PeriodPicker(
              period: _period,
              onSelected: (value) => setState(() => _period = value))
        ]),
        const SizedBox(height: 12),
        const AppSectionHeader(title: 'أداء الفريق'),
        if (snapshot.isLoading)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()))
        else if (snapshot.hasError)
          _InlineFailure(
              error: snapshot.error!,
              onRetry: () => ref.invalidate(_operations(filter)))
        else if (team != null) ...[
          _Metrics(team.values),
          ListTile(
              leading: const Icon(Icons.schedule),
              title: Text('${team.count('overdue')} مهام متأخرة')),
        ],
        const AppSectionHeader(title: 'أعضاء الفريق'),
        FutureBuilder<List<SupportTeamMembership>>(
          future: _members,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return _InlineFailure(
                  error: snapshot.error!,
                  onRetry: () => setState(() => _members = _loadMembers()));
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const ListTile(title: Text('لم يُعيّن أعضاء للفريق بعد.'));
            }
            return Card(
                child: Column(children: [
              for (final member in rows)
                ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(member.name),
                    subtitle: Text(member.manager
                        ? (member.agent ? 'مدير فريق وموظف دعم' : 'مدير الفريق')
                        : 'موظف دعم')),
            ]));
          },
        ),
        _link(
            context,
            'إدارة التعيينات',
            Icons.edit_outlined,
            SupportTeamAdministrationScreen(
                teamId: widget.initial.id,
                teamName: widget.initial.name), onReturn: () {
          if (!mounted) return;
          ref.invalidate(_operations(filter));
          setState(() => _members = _loadMembers());
        }),
      ]),
    );
  }
}

class _ExecutiveDecisionList extends ConsumerStatefulWidget {
  const _ExecutiveDecisionList({this.governorateId});
  final int? governorateId;

  @override
  ConsumerState<_ExecutiveDecisionList> createState() =>
      _ExecutiveDecisionListState();
}

class _ExecutiveDecisionListState
    extends ConsumerState<_ExecutiveDecisionList> {
  int _page = 1;
  late Future<SupportTaskPage> _items = _request();

  Future<SupportTaskPage> _request() => ref
      .read(generalManagerRepositoryProvider)
      .decisions(governorateId: widget.governorateId, page: _page);

  void _selectPage(int page) => setState(() {
        _page = page;
        _items = _request();
      });

  @override
  Widget build(BuildContext context) => ActorBoundPage(
        title: 'يحتاج قرارك',
        builder: (_) => Scaffold(
          appBar: const AppAppBar(title: 'يحتاج قرارك'),
          body: FutureBuilder<SupportTaskPage>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppLoadingState();
              }
              if (snapshot.hasError) {
                return AppErrorState(
                    message: friendlyApiError(snapshot.error!),
                    onRetry: () => _selectPage(_page));
              }
              final data = snapshot.data!;
              return ListView(padding: const EdgeInsets.all(16), children: [
                if (data.items.isEmpty)
                  const ListTile(title: Text('لا توجد حالات بانتظار قرارك.')),
                for (final task in data.items)
                  Card(
                      child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(task.subject),
                    subtitle: Text(
                        [
                          task.governorateName ??
                              task.supportTeamName ??
                              'الدعم',
                          if (task.escalationReason != null)
                            task.escalationReason!
                        ].join('\n'),
                        maxLines: 4),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await context.push<void>(
                          '/admin/general-manager/decisions/${task.id}');
                      if (mounted) _selectPage(1);
                    },
                  )),
                if (data.lastPage > 1)
                  Wrap(alignment: WrapAlignment.center, children: [
                    IconButton(
                        tooltip: 'الصفحة السابقة',
                        icon: const Icon(Icons.chevron_right),
                        onPressed:
                            _page > 1 ? () => _selectPage(_page - 1) : null),
                    Text('صفحة $_page من ${data.lastPage}'),
                    IconButton(
                        tooltip: 'الصفحة التالية',
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            data.hasMore ? () => _selectPage(_page + 1) : null),
                  ]),
              ]);
            },
          ),
        ),
      );
}

class GeneralManagerDecisionScreen extends StatelessWidget {
  const GeneralManagerDecisionScreen({required this.taskId, super.key});
  final int taskId;

  @override
  Widget build(BuildContext context) => ActorBoundPage(
        title: 'تفاصيل التصعيد',
        builder: (_) => _DecisionDetails(taskId: taskId),
      );
}

class _DecisionDetails extends ConsumerStatefulWidget {
  const _DecisionDetails({required this.taskId});
  final int taskId;

  @override
  ConsumerState<_DecisionDetails> createState() => _DecisionDetailsState();
}

class _DecisionDetailsState extends ConsumerState<_DecisionDetails> {
  final _note = TextEditingController();
  late Future<(SupportTaskItem, List<SupportTaskEventItem>)> _data = _load();
  bool _saving = false;

  Future<(SupportTaskItem, List<SupportTaskEventItem>)> _load() async {
    final scope = ref.read(accountRequestScopeProvider);
    final item = await ref
        .read(generalManagerRepositoryProvider)
        .decision(widget.taskId);
    scope.verify();
    final events = await ref
        .read(supportWorkspaceRepositoryProvider)
        .taskEvents(widget.taskId);
    scope.verify();
    return (item, events);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final note = _note.text.trim();
    if (note.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب توجيهًا لمدير الفريق.')));
      return;
    }
    final scope = ref.read(accountRequestScopeProvider);
    setState(() => _saving = true);
    try {
      await ref
          .read(generalManagerRepositoryProvider)
          .resolveDecision(widget.taskId, note);
      if (!mounted || !scope.isCurrent) return;
      ref.invalidate(_operations);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أُرسل القرار إلى فريق الدعم.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted && scope.isCurrent) _showFailure(context, error);
    } finally {
      if (mounted && scope.isCurrent) setState(() => _saving = false);
    }
  }

  String _eventName(String event) => switch (event) {
        'escalated_to_executive' => 'رفع الحالة للمدير العام',
        'escalation_resolved' => 'أُرسل قرار التصعيد للفريق',
        'escalated' => 'تصعيد لمدير الفريق',
        'created' => 'استُلمت الحالة',
        'assigned' => 'أُسندت المهمة',
        'claimed' => 'استلم الموظف المهمة',
        'completed' => 'أُنجزت المهمة',
        'released_to_inbox' => 'عادت إلى الوارد',
        _ => 'تحديث على الحالة',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppAppBar(title: 'تفاصيل التصعيد'),
        body: FutureBuilder<(SupportTaskItem, List<SupportTaskEventItem>)>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoadingState();
            }
            if (snapshot.hasError) {
              return AppErrorState(
                  message: friendlyApiError(snapshot.error!),
                  onRetry: () => setState(() => _data = _load()));
            }
            final (task, events) = snapshot.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 8, children: [
                if (task.awaitingExecutiveDecision)
                  const Chip(label: Text('بانتظار قرارك')),
                Chip(label: Text('حالة ${task.sourceReference ?? task.id}')),
              ]),
              Text(task.subject, style: Theme.of(context).textTheme.titleLarge),
              Text(
                  task.supportTeamName ?? task.governorateName ?? 'فريق الدعم'),
              const SizedBox(height: 12),
              Card(
                  child: ListTile(
                      title: const Text('سبب التصعيد'),
                      subtitle: Text(task.escalationReason ?? 'غير مسجّل'))),
              const SizedBox(height: 12),
              const AppSectionHeader(title: 'سجل الحالة'),
              for (final event in events)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_eventName(event.event)),
                  subtitle: Text([
                    if (event.actorName != null) event.actorName!,
                    if (event.createdAt != null)
                      MaterialLocalizations.of(context)
                          .formatShortDate(event.createdAt!.toLocal()),
                    if (event.metadata['note'] != null)
                      event.metadata['note'].toString()
                  ].join('\n')),
                ),
              if (task.awaitingExecutiveDecision) ...[
                const Divider(),
                Text(
                    'إعادة إلى ${task.supportTeamName ?? 'الفريق المسؤول'} مع التوجيه'),
                const SizedBox(height: 8),
                TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1200,
                    decoration:
                        const InputDecoration(labelText: 'قرارك لمدير الفريق')),
                FilledButton.icon(
                    onPressed: _saving ? null : _resolve,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('إرسال القرار لمدير الفريق')),
              ],
            ]);
          },
        ),
      );
}

class _ProvincePicker extends StatelessWidget {
  const _ProvincePicker(
      {required this.teams, required this.selected, required this.onSelected});
  final List<ExecutiveTeamStats> teams;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final team in teams)
        if (team.governorateId != null)
          team.governorateId!: team.governorateName ?? team.name
    };
    return PopupMenuButton<int>(
      tooltip: 'المحافظة',
      initialValue: selected ?? 0,
      onSelected: (id) => onSelected(id == 0 ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 0, child: Text('كل المحافظات')),
        for (final entry in names.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Chip(
          avatar: const Icon(Icons.place_outlined, size: 18),
          label: Text(names[selected] ?? 'كل المحافظات')),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.onSelected});
  final String period;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'الفترة',
        initialValue: period,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final entry in _periods.entries)
            PopupMenuItem(value: entry.key, child: Text(entry.value))
        ],
        child: Chip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(_periods[period]!)),
      );
}

class _Metrics extends StatelessWidget {
  const _Metrics(this.metrics);
  final Map<String, dynamic> metrics;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14);
        final width = constraints.maxWidth < 300 || scale > 21
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final metric in const {
            'received': 'طلبات مرفوعة',
            'completed': 'مهام منجزة',
            'published': 'إعلانات منشورة'
          }.entries)
            SizedBox(
                width: width,
                child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${metrics[metric.key] ?? 0}',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            Text(metric.value),
                          ]),
                    ))),
        ]);
      });
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListTile(
      title: Text(friendlyApiError(error)),
      trailing: IconButton(
          tooltip: 'إعادة المحاولة',
          icon: const Icon(Icons.refresh),
          onPressed: onRetry));
}

Widget _link(BuildContext context, String title, IconData icon, Widget page,
        {String? subtitle, VoidCallback? onReturn}) =>
    Card(
        child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_left),
      onTap: () async {
        await Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => page));
        if (context.mounted) onReturn?.call();
      },
    ));

void _showFailure(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
