import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/domain/auth_user.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_workspace_models.dart';

bool canAdministerSupportTeams(AuthUser? user) => user != null &&
    (user.isPlatformOwner || user.hasRole('super_admin') ||
      (user.hasPermission('users.manage_roles') &&
        user.hasPermission('users.manage_permissions')));

final _teamsProvider = FutureProvider.autoDispose<List<SupportTeamSummary>>(
  (ref) => ref.watch(supportWorkspaceRepositoryProvider).teams(),
);

final _membersProvider = FutureProvider.autoDispose.family<List<SupportTeamMembership>, int>(
  (ref, id) => ref.watch(supportWorkspaceRepositoryProvider).teamMemberships(id),
);

class SupportTeamAdministrationScreen extends StatelessWidget {
  const SupportTeamAdministrationScreen({super.key});

  @override
  Widget build(BuildContext context) => ActorBoundPage(
    title: 'فرق المحافظات',
    builder: (_) => const _TeamAdministration(),
  );
}

class _TeamAdministration extends ConsumerWidget {
  const _TeamAdministration();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canAdministerSupportTeams(ref.watch(authControllerProvider).asData?.value)) {
      return Scaffold(
        appBar: AppBar(title: const Text('فرق المحافظات')),
        body: const Center(child: Text('إدارة الفرق تحتاج صلاحية الأدوار والتفويض.')),
      );
    }
    final teams = ref.watch(_teamsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('فرق المحافظات')),
      body: teams.when(
        loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(
          message: friendlyApiError(error),
          onRetry: () => ref.invalidate(_teamsProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () async { await ref.refresh(_teamsProvider.future); },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              AppButton(
                label: 'إنشاء فريق',
                icon: Icons.add,
                onPressed: () => _createTeam(context, ref),
              ),
              const SizedBox(height: 12),
              for (final team in rows.where((row) => !row.isFallback))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(team.name),
                    subtitle: Text([
                      if (team.governorateName != null) team.governorateName!,
                      if (team.managerName != null) 'المدير: ${team.managerName}',
                      '${team.agents} موظف دعم',
                    ].join(' • ')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => ActorBoundPage(
                        title: team.name,
                        builder: (_) => _TeamMemberships(team: team),
                      )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createTeam(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(supportWorkspaceRepositoryProvider);
    try {
      final governorates = await repository.teamGovernorates();
      if (!context.mounted || governorates.isEmpty) return;
      var governorateId = governorates.first.id;
      var name = '';
      final key = GlobalKey<FormState>();
      final draft = await showActorDialog<(int, String)>(
        context: context,
        ref: ref,
        builder: (dialog) => AlertDialog(
          title: const Text('إنشاء فريق محافظة'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: governorateId,
                  decoration: const InputDecoration(labelText: 'المحافظة'),
                  isExpanded: true,
                  items: [
                    for (final governorate in governorates)
                      DropdownMenuItem(value: governorate.id, child: Text(governorate.nameAr)),
                  ],
                  onChanged: (id) { if (id != null) governorateId = id; },
                ),
                TextFormField(
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'اسم الفريق'),
                  onChanged: (value) => name = value.trim(),
                  validator: (_) => name.isEmpty ? 'أدخل اسم الفريق.' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (key.currentState?.validate() == true) Navigator.pop(dialog, (governorateId, name));
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (draft == null || !context.mounted) return;
      await repository.createTeam(governorateId: draft.$1, name: draft.$2);
      if (context.mounted) ref.invalidate(_teamsProvider);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _TeamMemberships extends ConsumerWidget {
  const _TeamMemberships({required this.team});
  final SupportTeamSummary team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canAdministerSupportTeams(ref.watch(authControllerProvider).asData?.value)) {
      return Scaffold(
        appBar: AppBar(title: Text(team.name)),
        body: const Center(child: Text('إدارة أعضاء الفريق تحتاج صلاحية التفويض.')),
      );
    }
    final members = ref.watch(_membersProvider(team.id));
    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: members.when(
        loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(
          message: friendlyApiError(error),
          onRetry: () => ref.invalidate(_membersProvider(team.id)),
        ),
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppButton(
              label: 'إضافة عضو',
              icon: Icons.person_add_outlined,
              onPressed: () async {
                final candidate = await showActorDialog<SupportTeamCandidate>(
                  context: context,
                  ref: ref,
                  builder: (_) => const _CandidatePicker(),
                );
                if (candidate == null || !context.mounted) return;
                SupportTeamMembership? existing;
                for (final row in rows) {
                  if (row.userId == candidate.id) existing = row;
                }
                await _editMember(context, ref, candidate.id, candidate.name, existing);
              },
            ),
            const SizedBox(height: 12),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row.name),
                  subtitle: Text([
                    if (row.manager) 'مدير الدعم',
                    if (row.agent) 'موظف دعم',
                    if (row.reviewListings) 'تحقق الإعلانات',
                    if (row.reviewPayments) 'مراجعة السداد',
                  ].join(' • ')),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editMember(context, ref, row.userId, row.name, row),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMember(BuildContext context, WidgetRef ref, int id, String name,
      SupportTeamMembership? existing) async {
    final repo = ref.read(supportWorkspaceRepositoryProvider);
    var agent = existing?.agent ?? true;
    var manager = existing?.manager ?? false;
    var payments = existing?.reviewPayments ?? false;
    var listings = existing?.reviewListings ?? false;
    final save = await showActorDialog<bool>(
      context: context,
      ref: ref,
      builder: (dialog) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(title: const Text('موظف دعم'), value: agent,
                onChanged: (value) => setLocal(() => agent = value)),
              SwitchListTile(title: const Text('مدير دعم'), value: manager,
                onChanged: (value) => setLocal(() => manager = value)),
              if (agent) ...[
                SwitchListTile(title: const Text('تحقق الإعلانات'), value: listings,
                  onChanged: (value) => setLocal(() => listings = value)),
                SwitchListTile(title: const Text('مراجعة السداد'), value: payments,
                  onChanged: (value) => setLocal(() => payments = value)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
          FilledButton(
            onPressed: agent || manager || existing != null ? () => Navigator.pop(dialog, true) : null,
            child: Text(agent || manager ? 'حفظ التفويض' : 'إلغاء التكليف'),
          ),
        ],
      )),
    );
    if (save != true || !context.mounted) return;
    try {
      await repo.setTeamMembership(team.id, id, agent: agent, manager: manager,
        reviewPayments: payments, reviewListings: listings);
      if (!context.mounted) return;
      ref.invalidate(_membersProvider(team.id));
      ref.invalidate(_teamsProvider);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _CandidatePicker extends ConsumerStatefulWidget {
  const _CandidatePicker();

  @override
  ConsumerState<_CandidatePicker> createState() => _CandidatePickerState();
}

class _CandidatePickerState extends ConsumerState<_CandidatePicker> {
  var _query = '';
  Future<List<SupportTeamCandidate>>? _results;

  void _search() {
    final query = _query.trim();
    if (query.isEmpty) return;
    setState(() {
      _results = ref.read(supportWorkspaceRepositoryProvider).teamCandidates(query);
      _results!.ignore();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('البحث عن حساب مسجّل'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            textInputAction: TextInputAction.search,
            onChanged: (value) => _query = value,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'الاسم أو رقم الهاتف أو البريد',
              suffixIcon: IconButton(tooltip: 'ابحث', icon: const Icon(Icons.search), onPressed: _search),
            ),
          ),
          if (_results != null)
            Flexible(child: FutureBuilder<List<SupportTeamCandidate>>(
              future: _results,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const AppLoadingState();
                if (snapshot.hasError) return Text(friendlyApiError(snapshot.error!));
                final rows = snapshot.data ?? const <SupportTeamCandidate>[];
                if (rows.isEmpty) return const Text('لم يُعثر على حساب مطابق.');
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    return ListTile(title: Text(row.name),
                      subtitle: Text([if (row.phone != null) row.phone!, if (row.email != null) row.email!].join(' • ')),
                      onTap: () => Navigator.pop(context, row));
                  },
                );
              },
            )),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
  );
}

void _showError(BuildContext context, Object error) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
