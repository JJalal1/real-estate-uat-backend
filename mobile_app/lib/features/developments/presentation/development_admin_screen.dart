import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/data/auth_controller.dart';
import '../data/development_repository.dart';
import '../domain/development_models.dart';

class DevelopmentAdminScreen extends ConsumerStatefulWidget {
  const DevelopmentAdminScreen({super.key});

  @override
  ConsumerState<DevelopmentAdminScreen> createState() =>
      _DevelopmentAdminScreenState();
}

class _DevelopmentAdminScreenState
    extends ConsumerState<DevelopmentAdminScreen> {
  bool _loading = true;
  String? _error;
  List<DeveloperSummary> _developers = const [];
  List<DevelopmentSummary> _projects = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(developmentRepositoryProvider);
      final developers = await repo.adminDevelopers();
      final projects = await repo.adminProjects();
      if (!mounted) {
        return;
      }
      setState(() {
        _developers = developers;
        _projects = projects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
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
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: _createMenu,
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
              )
            : null,
        body: _body(canManage: canManage, canPublish: canPublish),
      ),
    );
  }

  Widget _body({required bool canManage, required bool canPublish}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'المطورون (${_developers.length})',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ..._developers.map(
          (developer) => Card(
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
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
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ..._projects.map(
          (project) => Card(
            child: ExpansionTile(
              leading: const Icon(Icons.apartment_outlined),
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
                        OutlinedButton.icon(
                          onPressed: () => _addUnit(project),
                          icon: const Icon(Icons.add_home_work_outlined),
                          label: const Text('إضافة وحدة'),
                        ),
                      if (canPublish && project.status != 'published')
                        FilledButton.tonalIcon(
                          onPressed: () => _publish(project, true),
                          icon: const Icon(Icons.public),
                          label: const Text('نشر'),
                        ),
                      if (canPublish && project.status == 'published')
                        OutlinedButton.icon(
                          onPressed: () => _publish(project, false),
                          icon: const Icon(Icons.public_off),
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
              leading: const Icon(Icons.business),
              title: const Text('إضافة مطور'),
              onTap: () => Navigator.pop(sheetContext, 'developer'),
            ),
            ListTile(
              leading: const Icon(Icons.apartment),
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
          FilledButton(
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
        SnackBar(content: Text('تعذر الحفظ: $error')),
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
            FilledButton(
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
        SnackBar(content: Text('تعذر الحفظ: $error')),
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
          FilledButton(
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
        SnackBar(content: Text('تعذر إضافة الوحدة: $error')),
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
        SnackBar(content: Text('تعذر تنفيذ العملية: $error')),
      );
    }
  }
}
