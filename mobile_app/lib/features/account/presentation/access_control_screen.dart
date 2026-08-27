import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/access_control_repository.dart';
import '../data/auth_controller.dart';
import '../domain/access_models.dart';
import '../domain/auth_user.dart';

class AccessControlScreen extends ConsumerStatefulWidget {
  const AccessControlScreen({super.key});

  @override
  ConsumerState<AccessControlScreen> createState() =>
      _AccessControlScreenState();
}

class _AccessControlScreenState extends ConsumerState<AccessControlScreen> {
  final _searchController = TextEditingController();
  AccessCatalog? _catalog;
  List<AccessUserSummary> _users = const [];
  List<AuditEntry> _audit = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final current = ref.read(authControllerProvider).asData?.value;
    if (current == null || !current.canAccessAdminPanel) {
      setState(() {
        _loading = false;
        _error = 'ليس لديك صلاحية لفتح لوحة الإدارة.';
      });
      return;
    }
    try {
      final repo = ref.read(accessControlRepositoryProvider);
      final catalog = current.hasPermission('users.view')
          ? await repo.catalog()
          : const AccessCatalog(roles: [], permissions: []);
      final users = current.hasPermission('users.view')
          ? await repo.users(search: _searchController.text)
          : <AccessUserSummary>[];
      final audit = current.hasPermission('audit.view')
          ? await repo.auditLogs()
          : <AuditEntry>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _users = users;
        _audit = audit;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
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
          title: const Text('الأدوار والصلاحيات'),
          actions: [
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 48),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _load,
                              child: const Text('إعادة المحاولة')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        _CurrentAccessCard(user: current),
                        if (current?.hasPermission('users.view') == true) ...[
                          const SizedBox(height: 18),
                          Text('المستخدمون',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _load(),
                            decoration: InputDecoration(
                              labelText: 'بحث بالاسم أو الهاتف أو البريد',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                onPressed: _load,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._users.map((user) => _userCard(current!, user)),
                        ],
                        if (current?.hasPermission('audit.view') == true) ...[
                          const SizedBox(height: 18),
                          Text('آخر سجل النشاط',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          if (_audit.isEmpty)
                            const Card(
                                child: ListTile(
                                    title: Text('لا توجد أحداث مسجلة بعد.'))),
                          ..._audit.take(25).map(_auditTile),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _userCard(AuthUser current, AccessUserSummary user) {
    final canManageTarget = !user.isPlatformOwner || current.isPlatformOwner;
    final canRoles =
        canManageTarget && current.hasPermission('users.manage_roles');
    final canPermissions =
        canManageTarget && current.hasPermission('users.manage_permissions');
    final canStatus = !user.isPlatformOwner &&
        canManageTarget &&
        current.hasPermission('users.manage_status');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                    child: Icon(user.isPlatformOwner
                        ? Icons.shield
                        : Icons.person_outline)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(user.email,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _StatusChip(status: user.accountStatus),
              ],
            ),
            if (user.roles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: user.roles
                      .map((role) => Chip(label: Text(_roleName(role))))
                      .toList()),
            ],
            if (canRoles || canPermissions || canStatus) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canRoles)
                    OutlinedButton.icon(
                      onPressed: () => _editRoles(user),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('الأدوار'),
                    ),
                  if (canPermissions)
                    OutlinedButton.icon(
                      onPressed: () => _editPermissions(user),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('الصلاحيات'),
                    ),
                  if (canStatus)
                    OutlinedButton.icon(
                      onPressed: () => _editStatus(user),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('الحالة'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _auditTile(AuditEntry entry) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.history),
          title: Text(_actionName(entry.action),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text([
            if ((entry.actorName ?? '').isNotEmpty)
              'بواسطة: ${entry.actorName}',
            if (entry.createdAt != null) entry.createdAt!.toLocal().toString(),
          ].join('\n')),
        ),
      );

  Future<void> _editRoles(AccessUserSummary user) async {
    final catalog = _catalog;
    if (catalog == null) {
      return;
    }
    final current = ref.read(authControllerProvider).asData?.value;
    final selected = user.roles.toSet();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('أدوار ${user.name}'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: catalog.roles
                  .map((role) => CheckboxListTile(
                        value: selected.contains(role.key),
                        title: Text(role.nameAr),
                        subtitle: Text(role.key),
                        onChanged: role.key == 'registered_user' ||
                                (role.key == 'super_admin' &&
                                    current?.isPlatformOwner != true) ||
                                (user.isPlatformOwner &&
                                    role.key == 'super_admin')
                            ? null
                            : (value) => setLocal(() => value == true
                                ? selected.add(role.key)
                                : selected.remove(role.key)),
                      ))
                  .toList(),
            ),
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
    if (accepted != true) {
      return;
    }
    await _runMutation(() => ref
        .read(accessControlRepositoryProvider)
        .updateRoles(user.id, selected.toList()));
  }

  Future<void> _editPermissions(AccessUserSummary user) async {
    final catalog = _catalog;
    if (catalog == null) {
      return;
    }
    final effects = <String, String>{
      for (final permission in catalog.permissions) permission.key: 'inherit',
    };
    for (final override in user.permissionOverrides) {
      effects[override.permissionKey] = override.effect;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('صلاحيات ${user.name}'),
          content: SizedBox(
            width: 520,
            height: 460,
            child: ListView(
              children: catalog.permissions
                  .map((permission) => ListTile(
                        title: Text(permission.nameAr),
                        subtitle: Text(permission.key),
                        trailing: DropdownButton<String>(
                          value: effects[permission.key],
                          items: const [
                            DropdownMenuItem(
                                value: 'inherit', child: Text('حسب الدور')),
                            DropdownMenuItem(
                                value: 'allow', child: Text('سماح مباشر')),
                            DropdownMenuItem(
                                value: 'deny', child: Text('منع مباشر')),
                          ],
                          onChanged: user.isPlatformOwner
                              ? null
                              : (value) => setLocal(() =>
                                  effects[permission.key] = value ?? 'inherit'),
                        ),
                      ))
                  .toList(),
            ),
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
    if (accepted != true) {
      return;
    }
    await _runMutation(() => ref
        .read(accessControlRepositoryProvider)
        .updatePermissionOverrides(user.id, effects));
  }

  Future<void> _editStatus(AccessUserSummary user) async {
    var status = user.accountStatus;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('حالة ${user.name}'),
          content: DropdownButtonFormField<String>(
            value: status,
            decoration: const InputDecoration(labelText: 'حالة الحساب'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('نشط')),
              DropdownMenuItem(
                  value: 'pending_verification', child: Text('قيد التحقق')),
              DropdownMenuItem(value: 'suspended', child: Text('موقوف')),
              DropdownMenuItem(value: 'banned', child: Text('محظور')),
            ],
            onChanged: user.isPlatformOwner
                ? null
                : (value) => setLocal(() => status = value ?? status),
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
    if (accepted != true) {
      return;
    }
    await _runMutation(() => ref
        .read(accessControlRepositoryProvider)
        .updateStatus(user.id, status));
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    try {
      await action();
      await ref.read(authControllerProvider.notifier).refresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ التغيير وتسجيله في سجل النشاط.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }

  String _roleName(String key) {
    for (final role in _catalog?.roles ?? const <AccessRole>[]) {
      if (role.key == key) {
        return role.nameAr;
      }
    }
    return key;
  }

  String _actionName(String action) => switch (action) {
        'auth.login_succeeded' => 'تسجيل دخول ناجح',
        'auth.login_failed' => 'محاولة دخول فاشلة',
        'auth.logout' => 'تسجيل خروج',
        'access.roles_changed' => 'تغيير الأدوار',
        'access.permission_overrides_changed' => 'تغيير الصلاحيات',
        'account.status_changed' => 'تغيير حالة حساب',
        'listing.created' => 'إنشاء إعلان',
        'listing.updated' => 'تعديل إعلان',
        'listing.deleted' => 'حذف إعلان',
        'regions.governorate_created' => 'إنشاء محافظة',
        'regions.governorate_updated' => 'تعديل محافظة',
        'regions.cell_created' => 'إنشاء خلية جغرافية',
        'regions.cell_updated' => 'تعديل خلية جغرافية',
        'brokers.assignment_created' => 'تعيين دلال لخلية',
        'brokers.assignment_replaced' => 'استبدال دلال الخلية',
        'brokers.assignment_ended' => 'إنهاء تعيين دلال',
        _ => action,
      };
}

class _CurrentAccessCard extends StatelessWidget {
  const _CurrentAccessCard({required this.user});
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                user!.isPlatformOwner
                    ? 'مالك التطبيق — Super Admin'
                    : 'صلاحيات حسابك',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: user!.roles
                    .map((role) => Chip(label: Text(role)))
                    .toList()),
            const SizedBox(height: 8),
            Text('${user!.permissions.length} صلاحية فعالة',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Chip(
          label: Text(switch (status) {
        'active' => 'نشط',
        'pending_verification' => 'قيد التحقق',
        'suspended' => 'موقوف',
        'banned' => 'محظور',
        _ => status,
      }));
}
