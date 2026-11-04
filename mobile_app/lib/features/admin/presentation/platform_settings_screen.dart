import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/admin_workspace_repository.dart';
import '../domain/admin_workspace_models.dart';

class PlatformSettingsScreen extends ConsumerWidget {
  const PlatformSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorScopedPage(
    title: 'إعدادات المنصة', builder: (_) => const _PlatformSettingsForActor());
}

class _PlatformSettingsForActor extends ConsumerStatefulWidget {
  const _PlatformSettingsForActor();
  @override
  ConsumerState<_PlatformSettingsForActor> createState() =>
      _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState
    extends ConsumerState<_PlatformSettingsForActor> {
  bool _loading = true;
  bool _hasLoaded = false;
  int _generation = 0;
  bool _saving = false;
  String? _error;
  List<PlatformSettingItem> _items = const [];
  final Map<String, TextEditingController> _text = {};
  final Map<String, bool> _bool = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(adminWorkspaceRepositoryProvider).settings();
      if (!mounted || generation != _generation) return;
      for (final c in _text.values) {
        c.dispose();
      }
      _text.clear();
      _bool.clear();
      for (final item in rows) {
        if (item.valueType == 'boolean') {
          _bool[item.key] = item.value == true;
        } else {
          _text[item.key] =
              TextEditingController(text: item.value?.toString() ?? '');
        }
      }
      setState(() {
        _items = rows;
        _hasLoaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
        if (!isTransientApiFailure(error)) {
          _hasLoaded = false;
          _items = const [];
          for (final controller in _text.values) { controller.dispose(); }
          _text.clear();
          _bool.clear();
        }
      });
    }
  }

  Future<void> _save() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user?.isPlatformOwner != true &&
        user?.hasPermission('settings.manage') != true) {
      return;
    }
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{};
      for (final item in _items) {
        values[item.key] = item.valueType == 'boolean'
            ? (_bool[item.key] ?? false)
            : _text[item.key]?.text.trim();
      }
      await ref.read(adminWorkspaceRepositoryProvider).updateSettings(values);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final canManage = user?.isPlatformOwner == true ||
        user?.hasPermission('settings.manage') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعدادات المنصة'), actions: [
          IconButton(
              tooltip: 'تحديث إعدادات المنصة',
              onPressed: _loading || _saving ? null : _load,
              icon: const EbrokerIcon(Icons.refresh))
        ]),
        body: _loading && !_hasLoaded
            ? const AppLoadingState(label: 'جارٍ تحميل إعدادات المنصة…')
            : _error != null && !_hasLoaded
                ? AppErrorState(message: _error!, onRetry: _load)
                : Column(children: [
                  AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
                  Expanded(child: _items.isEmpty
                    ? AppEmptyState(title: 'لا توجد إعدادات متاحة', message: 'يمكنك تحديث الصفحة لإعادة التحقق.',
                        actionLabel: 'تحديث', onAction: _load)
                    : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Card(
                          child: ListTile(
                              leading: EbrokerIcon(Icons.security_outlined),
                              title: Text('إعدادات آمنة فقط'),
                              subtitle: Text(
                                  'لا تعرض هذه الصفحة كلمات المرور أو مفاتيح API أو بيانات البطاقات الحساسة.'))),
                      const SizedBox(height: 10),
                      for (final group in const [
                        'general',
                        'listings',
                        'support',
                        'notifications',
                      ]) ...[
                        if (_items.any((item) => item.group == group)) ...[
                          const SizedBox(height: 8),
                          Text(
                            _groupLabel(group),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          ..._items
                              .where((item) => item.group == group)
                              .map((item) => Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: item.valueType == 'boolean'
                                          ? SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: _bool[item.key] ?? false,
                                              title: Text(item.labelAr,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              onChanged: canManage
                                                  ? (value) => setState(() =>
                                                      _bool[item.key] = value)
                                                  : null,
                                            )
                                          : TextField(
                                              controller: _text[item.key],
                                              enabled: canManage,
                                              keyboardType:
                                                  item.valueType == 'integer'
                                                      ? TextInputType.number
                                                      : TextInputType.text,
                                              decoration: InputDecoration(
                                                labelText: item.labelAr,
                                                helperText: _groupLabel(group),
                                              ),
                                            ),
                                    ),
                                  )),
                        ],
                      ],
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        EbrokerFilledButton.icon(
                            onPressed: _saving || _loading ? null : _save,
                            icon: const EbrokerIcon(Icons.save_outlined),
                            label: Text(
                                _saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات')),
                      ],
                    ],
                  )),
                ]),
      ),
    );
  }

  String _groupLabel(String group) => switch (group) {
        'general' => 'إعدادات عامة وبيانات التواصل',
        'listings' => 'إعدادات الإعلانات والمراجعة',
        'support' => 'إعدادات الدعم',
        'notifications' => 'إعدادات الإشعارات والتنبيهات',
        _ => group,
      };

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }
}
