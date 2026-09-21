import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/access_control_repository.dart';
import '../../account/data/auth_controller.dart';
import '../../account/domain/access_models.dart';
import '../../account/presentation/access_control_screen.dart';

class GeneralManagerAccountsScreen extends ConsumerStatefulWidget {
  const GeneralManagerAccountsScreen({super.key});

  @override
  ConsumerState<GeneralManagerAccountsScreen> createState() =>
      _GeneralManagerAccountsScreenState();
}

class _GeneralManagerAccountsScreenState
    extends ConsumerState<GeneralManagerAccountsScreen> {
  final _search = TextEditingController();
  List<AccessUserSummary> _users = const [];
  AccessCatalog? _catalog;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(accessControlRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.users(search: _search.text),
        repo.catalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AccessUserSummary>;
        _catalog = results[1] as AccessCatalog;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(authControllerProvider).asData?.value;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الحسابات والأدوار'),
          actions: [
            IconButton(
              tooltip: 'أدوات الصلاحيات المتقدمة',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccessControlScreen()),
              ),
              icon: const Icon(Icons.settings_suggest_outlined),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        const _DirectoryIntro(),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _load(),
                          decoration: InputDecoration(
                            labelText: 'ابحث بالاسم أو الهاتف أو البريد',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: 'بحث',
                              onPressed: _load,
                              icon: const Icon(Icons.arrow_back),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_users.length} حسابًا في النتائج',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        ..._users.map((user) => _userCard(current, user)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _userCard(dynamic current, AccessUserSummary user) {
    final adminRole = _primaryAdministrativeRole(user);
    final professional = _professionalLabel(user);
    final canManage = current?.isPlatformOwner == true && !user.isPlatformOwner;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(user.isPlatformOwner
                      ? Icons.shield_outlined
                      : adminRole == null
                          ? Icons.person_outline
                          : Icons.badge_outlined),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        user.isPlatformOwner
                            ? 'المدير العام'
                            : adminRole ?? professional ?? 'مستخدم',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if ((user.phone ?? '').trim().isNotEmpty)
                        Text(user.phone!,
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.bodySmall),
                      if (user.email.trim().isNotEmpty)
                        Text(user.email,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _StatusChip(user.accountStatus),
              ],
            ),
            if (user.roles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _visibleRoleLabels(user.roles)
                    .map((label) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(label),
                        ))
                    .toList(growable: false),
              ),
            ],
            if (professional != null && adminRole != null) ...[
              const SizedBox(height: 6),
              Text(
                'الصفة العقارية: $professional',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (canManage) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _editRole(user),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('تغيير الدور الإداري'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editStatus(user),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('حالة الحساب'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editRole(AccessUserSummary user) async {
    final catalog = _catalog;
    if (catalog == null) return;

    const managed = <String>{
      'support_agent',
      'support_manager',
      'platform_admin',
    };
    var selected = user.roles.firstWhere(
      managed.contains,
      orElse: () => 'none',
    );
    final options = catalog.roles
        .where((role) => managed.contains(role.key))
        .toList(growable: false);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('الدور الإداري لـ ${user.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'none',
                groupValue: selected,
                title: const Text('بدون دور إداري'),
                onChanged: (value) => setLocal(() => selected = value ?? 'none'),
              ),
              ...options.map((role) => RadioListTile<String>(
                    value: role.key,
                    groupValue: selected,
                    title: Text(_friendlyRole(role.key, fallback: role.nameAr)),
                    onChanged: (value) => setLocal(() => selected = value ?? 'none'),
                  )),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (accepted != true) return;

    final preserved = user.roles.where((role) => !managed.contains(role)).toList();
    if (selected != 'none') preserved.add(selected);
    await _mutate(() => ref
        .read(accessControlRepositoryProvider)
        .updateRoles(user.id, preserved.toSet().toList()));
  }

  Future<void> _editStatus(AccessUserSummary user) async {
    var status = user.accountStatus;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('حالة حساب ${user.name}'),
          content: DropdownButtonFormField<String>(
            value: status,
            decoration: const InputDecoration(labelText: 'الحالة'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('نشط')),
              DropdownMenuItem(
                  value: 'pending_verification', child: Text('قيد التحقق')),
              DropdownMenuItem(value: 'suspended', child: Text('موقوف')),
              DropdownMenuItem(value: 'banned', child: Text('محظور')),
            ],
            onChanged: (value) => setLocal(() => status = value ?? status),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await _mutate(() => ref
        .read(accessControlRepositoryProvider)
        .updateStatus(user.id, status));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await ref.read(authControllerProvider.notifier).refresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التغيير وتسجيله.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

class _DirectoryIntro extends StatelessWidget {
  const _DirectoryIntro();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.account_tree_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إدارة الناس بصورة إدارية',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      'الأدوار الأساسية تظهر بأسماء مفهومة. الصلاحيات التقنية التفصيلية موجودة في زر الأدوات المتقدمة عند الحاجة.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(switch (status) {
          'active' => 'نشط',
          'pending_verification' => 'قيد التحقق',
          'suspended' => 'موقوف',
          'banned' => 'محظور',
          _ => status,
        }),
      );
}

String? _primaryAdministrativeRole(AccessUserSummary user) {
  if (user.isPlatformOwner || user.roles.contains('super_admin')) return 'المدير العام';
  if (user.roles.contains('platform_admin')) return 'مدير إداري';
  if (user.roles.contains('support_manager')) return 'مدير دعم';
  if (user.roles.contains('support_agent')) return 'موظف دعم';
  return null;
}

String? _professionalLabel(AccessUserSummary user) => switch (user.verificationType) {
      'owner' => 'مالك عقار${user.verificationStatus == 'approved' ? ' موثق' : ''}',
      'broker' => 'دلال${user.verificationStatus == 'approved' ? ' موثق' : ''}',
      'office' => 'مكتب عقاري${user.verificationStatus == 'approved' ? ' موثق' : ''}',
      _ => null,
    };

List<String> _visibleRoleLabels(List<String> roles) {
  const hiddenTechnical = <String>{
    'permissions_manager',
    'regions_manager',
    'content_moderator',
  };
  return roles
      .where((role) => !hiddenTechnical.contains(role))
      .map((role) => _friendlyRole(role))
      .toSet()
      .toList(growable: false);
}

String _friendlyRole(String key, {String? fallback}) => switch (key) {
      'super_admin' => 'المدير العام',
      'platform_admin' => 'مدير إداري',
      'support_manager' => 'مدير دعم',
      'support_agent' => 'موظف دعم',
      'broker' => 'دلال',
      'registered_user' => 'مستخدم',
      _ => fallback ?? key,
    };
