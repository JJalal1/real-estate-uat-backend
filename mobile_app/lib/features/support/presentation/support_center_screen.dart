import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportCenterScreen extends ConsumerStatefulWidget {
  const SupportCenterScreen({super.key});

  @override
  ConsumerState<SupportCenterScreen> createState() =>
      _SupportCenterScreenState();
}

class _SupportCenterScreenState extends ConsumerState<SupportCenterScreen> {
  bool _loading = true;
  String? _error;
  List<SupportCaseSummary> _cases = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await ref.read(supportRepositoryProvider).mine();
      if (!mounted) {
        return;
      }
      setState(() {
        _cases = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدعم وبلاغاتي')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openTicket,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('تذكرة دعم'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مركز الدعم',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'تظهر هنا تذاكر الدعم والبلاغات التي أرسلتها. الحالات المفتوحة لها مهلة خدمة 48 ساعة، وعند انتظار ردك تتوقف المهلة حتى تجيب.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorCard(message: _error!, onRetry: _load)
              else if (_cases.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('لا توجد تذاكر أو بلاغات حتى الآن.'),
                  ),
                )
              else
                ..._cases.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        item.kind == 'report'
                            ? Icons.flag_outlined
                            : Icons.support_agent_outlined,
                      ),
                      title: Text(
                        item.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${item.reference} • ${_statusLabel(item.status)}'
                        '${item.isEscalated ? ' • مصعّدة' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openDetails(item.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTicket() async {
    const categories = <String, String>{
      'account': 'الحساب',
      'listing': 'الإعلانات',
      'technical': 'مشكلة تقنية',
      'payments_future': 'المدفوعات (للمستقبل)',
      'other': 'أخرى',
    };
    var category = 'other';
    final subject = TextEditingController();
    final description = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('فتح تذكرة دعم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: categories.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => category = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subject,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                TextField(
                  controller: description,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 5000,
                  decoration: const InputDecoration(labelText: 'التفاصيل'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('فتح التذكرة'),
            ),
          ],
        ),
      ),
    );
    final subjectValue = subject.text.trim();
    final descriptionValue = description.text.trim();
    subject.dispose();
    description.dispose();
    if (accepted != true ||
        subjectValue.length < 3 ||
        descriptionValue.length < 5) {
      return;
    }
    try {
      final details = await ref.read(supportRepositoryProvider).openTicket(
            subject: subjectValue,
            description: descriptionValue,
            category: category,
          );
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      await _showDetails(details.summary.id);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openDetails(int caseId) async {
    await _showDetails(caseId);
    await _load();
  }

  Future<void> _showDetails(int caseId) async {
    try {
      var details = await ref.read(supportRepositoryProvider).details(caseId);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(details.summary.reference),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.summary.subject,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text('الحالة: ${_statusLabel(details.summary.status)}'),
                    if (details.summary.isEscalated)
                      const Text('هذه الحالة مصعّدة بسبب تجاوز SLA.'),
                    const Divider(height: 24),
                    Text(details.description),
                    const Divider(height: 24),
                    ...details.messages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.actorName ??
                                      (message.actorRole == 'requester'
                                          ? 'صاحب الطلب'
                                          : 'الدعم'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(message.body),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (!details.summary.isClosed)
                TextButton.icon(
                  onPressed: () async {
                    final body = await _replyDialog(dialogContext);
                    if (body == null) {
                      return;
                    }
                    try {
                      final next = await ref
                          .read(supportRepositoryProvider)
                          .reply(caseId, body);
                      setDialogState(() => details = next);
                    } catch (error) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(friendlyApiError(error))),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.reply_outlined),
                  label: const Text('إضافة رد'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<String?> _replyDialog(BuildContext parentContext) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: parentContext,
      builder: (context) => AlertDialog(
        title: const Text('رد على الدعم'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: 5000,
          decoration: const InputDecoration(labelText: 'الرد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    final body = controller.text.trim();
    controller.dispose();
    if (accepted != true || body.length < 2) {
      return null;
    }
    return body;
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiError(error))),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(message),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'open' => 'مفتوحة',
    'in_progress' => 'قيد المعالجة',
    'waiting_requester' => 'بانتظار ردك',
    'resolved' => 'تم الحل',
    'dismissed' => 'مغلقة',
    _ => status,
  };
}
