import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

class ConversationReportsScreen extends ConsumerStatefulWidget {
  const ConversationReportsScreen({super.key});
  @override
  ConsumerState<ConversationReportsScreen> createState() =>
      _ConversationReportsScreenState();
}

class _ConversationReportsScreenState
    extends ConsumerState<ConversationReportsScreen> {
  bool _loading = true;
  String? _error;
  List<ConversationReportSummary> _items = const [];
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(messageRepositoryProvider).adminReports();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
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

  Future<void> _open(ConversationReportSummary report) async {
    final current = ref.read(authControllerProvider).valueOrNull;
    if (current?.hasPermission('conversations.review_private') != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'يمكنك مشاهدة بيانات البلاغ فقط. فتح الرسائل الخاصة يحتاج صلاحية مستقلة.')));
      return;
    }
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('فتح محتوى خاص؟'),
              content: const Text(
                  'سيتم فتح الرسائل فقط ضمن هذا البلاغ النشط، وسيتم تسجيل عملية الوصول في سجل غير قابل للتعديل.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('فتح وتسجيل الوصول'))
              ],
            ));
    if (accepted != true || !mounted) {
      return;
    }
    try {
      final content = await ref
          .read(messageRepositoryProvider)
          .openReportedContent(report.id);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text('بلاغ #${report.id}'),
                content: SizedBox(
                    width: 520,
                    child: ListView(shrinkWrap: true, children: [
                      Text(report.propertyTitle ?? 'محادثة خاصة',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      const Divider(),
                      ...content.messages.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                              tileColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              title: Text(m.senderName),
                              subtitle: Text(m.body)))),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('إغلاق'))
                ],
              ));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('بلاغات المحادثات الخاصة')),
          body: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'قائمة البلاغات تعرض بيانات البلاغ فقط. محتوى الرسائل لا يُفتح إلا من بلاغ نشط وبصلاحية conversations.review_private، وكل فتح يُسجّل.'))),
                    if (_loading)
                      const Padding(
                          padding: EdgeInsets.all(36),
                          child: Center(child: CircularProgressIndicator()))
                    else if (_error != null)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(_error!)))
                    else if (_items.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(22),
                              child: Text('لا توجد بلاغات محادثات.')))
                    else
                      ..._items.map((item) => Card(
                              child: ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: Text(item.propertyTitle ??
                                'محادثة #${item.threadId}'),
                            subtitle: Text(
                                '${item.reporterName} • ${item.reasonCode} • ${item.status}'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => _open(item),
                          ))),
                  ])),
        ));
  }
}
