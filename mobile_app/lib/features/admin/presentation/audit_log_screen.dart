import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/access_control_repository.dart';
import '../../account/domain/access_models.dart';

final _auditLogProvider = FutureProvider.autoDispose.family<List<AuditEntry>, int>(
    (ref, actor) => ref.watch(accessControlRepositoryProvider).auditLogs());

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    if (actor == null) return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    final provider = _auditLogProvider(actor);
    final state = ref.watch(provider);
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('سجل العمليات'), actions: [
            IconButton(
                tooltip: 'تحديث سجل العمليات',
                onPressed: state.isLoading ? null : () => ref.invalidate(provider),
                icon: const EbrokerIcon(Icons.refresh))
          ]),
          body: state.when(
            loading: () => const AppLoadingState(label: 'جارٍ تحميل سجل العمليات…'),
            error: (e, _) => AppErrorState(message: friendlyApiError(e), onRetry: () => ref.invalidate(provider)),
            data: (rows) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(provider);
                try { await ref.read(provider.future); } catch (_) { /* The page renders failure and retry. */ }
              },
              child: rows.isEmpty
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                      SizedBox(height: 160),
                      Center(child: Text('لا توجد عمليات مسجلة.'))
                    ])
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(14),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        return Card(
                            child: ListTile(
                          leading: const EbrokerIcon(Icons.history),
                          title: Text(row.action,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
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
