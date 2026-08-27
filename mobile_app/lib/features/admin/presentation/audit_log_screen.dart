import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/access_control_repository.dart';
import '../../account/domain/access_models.dart';

final _auditLogProvider = FutureProvider.autoDispose<List<AuditEntry>>(
    (ref) => ref.watch(accessControlRepositoryProvider).auditLogs());

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_auditLogProvider);
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('سجل العمليات'), actions: [
            IconButton(
                onPressed: () => ref.invalidate(_auditLogProvider),
                icon: const Icon(Icons.refresh))
          ]),
          body: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(friendlyApiError(e))),
            data: (rows) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_auditLogProvider);
                await ref.read(_auditLogProvider.future);
              },
              child: rows.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 160),
                      Center(child: Text('لا توجد عمليات مسجلة.'))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        return Card(
                            child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(row.action,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text([
                            'بواسطة: ${row.actorName ?? 'النظام'}',
                            if (row.subjectType != null)
                              '${row.subjectType} #${row.subjectId ?? '-'}',
                            if (row.createdAt != null)
                              row.createdAt!.toLocal().toString()
                          ].join('\n')),
                        ));
                      },
                    ),
            ),
          ),
        ));
  }
}
