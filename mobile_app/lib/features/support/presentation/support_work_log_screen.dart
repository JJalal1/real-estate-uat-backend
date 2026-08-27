import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportWorkLogScreen extends ConsumerStatefulWidget {
  const SupportWorkLogScreen({super.key});
  @override
  ConsumerState<SupportWorkLogScreen> createState() =>
      _SupportWorkLogScreenState();
}

class _SupportWorkLogScreenState extends ConsumerState<SupportWorkLogScreen> {
  bool _loading = true;
  String? _error;
  int? _userId;
  List<SupportAgentItem> _agents = const [];
  List<SupportWorkLogItem> _rows = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final current = ref.read(authControllerProvider).asData?.value;
      var agents = <SupportAgentItem>[];
      if (current?.isPlatformOwner == true ||
          current?.hasPermission('support.view_team_metrics') == true) {
        agents = await ref.read(supportRepositoryProvider).agents();
      }
      final rows =
          await ref.read(supportRepositoryProvider).worklog(userId: _userId);
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('سجل عمل الدعم'), actions: [
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh))
          ]),
          body: Column(children: [
            if (_agents.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<int?>(
                    value: _userId,
                    decoration: const InputDecoration(labelText: 'الموظف'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('سجلي أنا')),
                      ..._agents.map((a) => DropdownMenuItem<int?>(
                          value: a.id,
                          child: Text('${a.name} (${a.activeCases} نشطة)')))
                    ],
                    onChanged: (value) {
                      setState(() => _userId = value);
                      _load();
                    },
                  )),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
                child: _rows.isEmpty && !_loading
                    ? const Center(
                        child: Text('لا توجد إجراءات في الفترة المحددة.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final row = _rows[i];
                          return Card(
                              child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(_label(row.action),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text([
                              if (row.actorName != null) row.actorName!,
                              if (row.subjectType != null)
                                '${row.subjectType} #${row.subjectId ?? '-'}',
                              if (row.createdAt != null)
                                row.createdAt!.toLocal().toString()
                            ].join('\n')),
                          ));
                        },
                      )),
          ]),
        ),
      );

  String _label(String action) {
    const labels = {
      'support.case_started': 'بدء معالجة حالة',
      'support.reply_added': 'رد على حالة دعم',
      'support.internal_note_added': 'إضافة ملاحظة داخلية',
      'support.status_changed': 'تغيير حالة',
      'support.case_assigned': 'إسناد حالة',
      'support.case_reopened': 'إعادة فتح حالة',
      'conversation.report_content_opened': 'فتح محتوى محادثة مبلّغ عنها',
    };
    return labels[action] ?? action;
  }
}
