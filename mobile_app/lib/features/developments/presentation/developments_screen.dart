import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/development_repository.dart';
import '../domain/development_models.dart';

class DevelopmentsScreen extends ConsumerStatefulWidget {
  const DevelopmentsScreen({super.key});
  @override
  ConsumerState<DevelopmentsScreen> createState() => _DevelopmentsScreenState();
}

class _DevelopmentsScreenState extends ConsumerState<DevelopmentsScreen> {
  final _search = TextEditingController();
  late Future<List<DevelopmentSummary>> _future;
  @override
  void initState() {
    super.initState();
    _future = ref.read(developmentRepositoryProvider).publicProjects();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = ref
          .read(developmentRepositoryProvider)
          .publicProjects(query: _search.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المشاريع والتطويرات العقارية')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: InputDecoration(
                    hintText: 'ابحث باسم المشروع أو المطور',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        onPressed: _reload, icon: const Icon(Icons.refresh)))),
          ),
          Expanded(
              child: FutureBuilder<List<DevelopmentSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تعذر التحميل - إعادة المحاولة')));
              }
              final rows = snapshot.data ?? const <DevelopmentSummary>[];
              if (rows.isEmpty) {
                return const Center(
                    child: Text('لا توجد مشاريع منشورة حالياً.'));
              }
              return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _ProjectCard(project: rows[index])));
            },
          )),
        ]),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final DevelopmentSummary project;
  @override
  Widget build(BuildContext context) {
    final developer = project.developer?.name ?? 'مطور عقاري';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/developments/${project.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.apartment_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(project.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)))
            ]),
            const SizedBox(height: 6),
            Text(developer,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (project.address != null) ...[
              const SizedBox(height: 4),
              Text(project.address!)
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text(_completion(project.completionStatus))),
              Chip(label: Text('${project.availableUnitsCount} وحدة متاحة')),
              if (project.governorateName != null)
                Chip(label: Text(project.governorateName!))
            ]),
          ]),
        ),
      ),
    );
  }

  static String _completion(String value) => switch (value) {
        'completed' => 'مكتمل',
        'under_construction' => 'قيد الإنشاء',
        _ => 'مخطط'
      };
}
