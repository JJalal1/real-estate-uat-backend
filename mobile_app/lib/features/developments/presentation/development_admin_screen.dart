import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/development_repository.dart';
import '../domain/development_models.dart';

class DevelopmentAdminScreen extends ConsumerWidget {
  const DevelopmentAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorScopedPage(
    title: 'إدارة المطورين والمشاريع', builder: (_) => const _DevelopmentAdminForActor());
}

class _DevelopmentAdminForActor extends ConsumerStatefulWidget {
  const _DevelopmentAdminForActor();
  @override
  ConsumerState<_DevelopmentAdminForActor> createState() =>
      _DevelopmentAdminScreenState();
}

class _DevelopmentAdminScreenState
    extends ConsumerState<_DevelopmentAdminForActor> {
  bool _loading = true;
  bool _hasLoaded = false;
  int _generation = 0;
  String? _error;
  List<DeveloperSummary> _developers = const [];
  List<DevelopmentSummary> _projects = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(developmentRepositoryProvider);
      final developers = await repo.adminDevelopers();
      if (!mounted || generation != _generation) return;
      final projects = await repo.adminProjects();
      if (!mounted || generation != _generation) return;
      setState(() {
        _developers = developers;
        _projects = projects;
        _hasLoaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
        if (!isTransientApiFailure(error)) {
          _hasLoaded = false;
          _developers = const [];
          _projects = const [];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final canManage = user?.isPlatformOwner == true ||
        user?.hasPermission('developments.manage') == true;
    final canPublish = user?.isPlatformOwner == true ||
        user?.hasPermission('developments.publish') == true;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المطورين والمشاريع'),
          actions: [
            IconButton(tooltip: 'تحديث المطورين والمشاريع', onPressed: _loading ? null : _load, icon: const EbrokerIcon(Icons.refresh)),
          ],
        ),
        floatingActionButton: canManage
            ? EbrokerButton(
                onPressed: _createMenu,
                icon: const EbrokerIcon(Icons.add),
                child: const Text('إضافة'),
              )
            : null,
        body: _body(canManage: canManage, canPublish: canPublish),
      ),
    );
  }

  Widget _body({required bool canManage, required bool canPublish}) {
    if (_loading && !_hasLoaded) {
      return const AppLoadingState(label: 'جارٍ تحميل المطورين والمشاريع…');
    }
    if (_error != null && !_hasLoaded) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_developers.isEmpty && _projects.isEmpty) return Column(children: [
      AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
      Expanded(child: AppEmptyState(title: 'لا يوجد مطورون أو مشاريع بعد',
        message: canManage ? 'استخدم إضافة لإنشاء أول سجل.' : 'ستظهر السجلات المتاحة هنا.',
        actionLabel: 'تحديث', onAction: _load)),
    ]);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
        Text(
          'المطورون (${_developers.length})',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._developers.map(
          (developer) => Card(
            child: ListTile(
              leading: const EbrokerIcon(Icons.business_outlined),
              title: Text(developer.name),
              subtitle: Text(
                  '${developer.status} • ${developer.projectsCount} مشروع'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'المشاريع (${_projects.length})',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._projects.map(
          (project) => Card(
            child: ExpansionTile(
              leading: const EbrokerIcon(Icons.apartment_outlined),
              title: Text(project.name),
              subtitle: Text('${project.status} • ${project.unitsCount} وحدة'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canManage)
                        EbrokerOutlinedButton.icon(
                          onPressed: () => _addUnit(project),
                          icon: const EbrokerIcon(Icons.add_home_work_outlined),
                          label: const Text('إضافة وحدة'),
                        ),
                      if (canPublish && project.status != 'published')
                        EbrokerFilledButton.tonalIcon(
                          onPressed: () => _publish(project, true),
                          icon: const EbrokerIcon(Icons.public),
                          label: const Text('نشر'),
                        ),
                      if (canPublish && project.status == 'published')
                        EbrokerOutlinedButton.icon(
                          onPressed: () => _publish(project, false),
                          icon: const EbrokerIcon(Icons.public_off),
                          label: const Text('إلغاء النشر'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const EbrokerIcon(Icons.business),
              title: const Text('إضافة مطور'),
              onTap: () => Navigator.pop(sheetContext, 'developer'),
            ),
            ListTile(
              leading: const EbrokerIcon(Icons.apartment),
              title: const Text('إضافة مشروع'),
              onTap: () => Navigator.pop(sheetContext, 'project'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    if (choice == 'developer') {
      await _createDeveloper();
    } else {
      await _createProject();
    }
  }

  Future<void> _createDeveloper() async {
    final name = TextEditingController();
    final slug = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مطور جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: slug,
              decoration: const InputDecoration(labelText: 'slug بالإنجليزية'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          EbrokerFilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!mounted ||
        accepted != true ||
        name.text.trim().isEmpty ||
        slug.text.trim().isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(developmentRepositoryProvider).createDeveloper({
        'name': name.text.trim(),
        'slug': slug.text.trim().toLowerCase(),
        'status': 'active',
      });
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('تمت إضافة المطور')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _createProject() async {
    if (_developers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف مطوراً أولاً')),
      );
      return;
    }
    final name = TextEditingController();
    final slug = TextEditingController();
    var developerId = _developers.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('مشروع جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: developerId,
                items: _developers
                    .map(
                      (developer) => DropdownMenuItem<int>(
                        value: developer.id,
                        child: Text(developer.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setLocal(() => developerId = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'المطور'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المشروع'),
              ),
              TextField(
                controller: slug,
                decoration:
                    const InputDecoration(labelText: 'slug بالإنجليزية'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            EbrokerFilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        accepted != true ||
        name.text.trim().isEmpty ||
        slug.text.trim().isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(developmentRepositoryProvider).createProject({
        'developer_id': developerId,
        'name': name.text.trim(),
        'slug': slug.text.trim().toLowerCase(),
        'completion_status': 'planned',
      });
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء المشروع كمسودة')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _addUnit(DevelopmentSummary project) async {
    final code = TextEditingController();
    final title = TextEditingController();
    final area = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('وحدة في ${project.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'رمز الوحدة'),
            ),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            TextField(
              controller: area,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المساحة م²'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          EbrokerFilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) {
      return;
    }
    final parsedArea = double.tryParse(area.text.trim());
    if (code.text.trim().isEmpty ||
        title.text.trim().isEmpty ||
        parsedArea == null ||
        parsedArea <= 0) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(developmentRepositoryProvider).createUnit(project.id, {
        'code': code.text.trim(),
        'title': title.text.trim(),
        'unit_type': 'apartment',
        'area_m2': parsedArea,
        'currency': 'YER',
        'status': 'available',
      });
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('تمت إضافة الوحدة')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _publish(DevelopmentSummary project, bool publish) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(developmentRepositoryProvider);
      if (publish) {
        await repo.publish(project.id);
      } else {
        await repo.unpublish(project.id);
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(publish ? 'تم نشر المشروع' : 'تم إلغاء النشر')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }
}
