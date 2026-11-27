import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../messages/data/message_repository.dart';
import '../data/support_repository.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_models.dart';
import '../domain/support_workspace_models.dart';
import 'support_evidence.dart';

class SupportReportTaskScreen extends ConsumerStatefulWidget {
  const SupportReportTaskScreen(
      {super.key, required this.task, this.manager = false});

  final SupportTaskItem task;
  final bool manager;

  @override
  ConsumerState<SupportReportTaskScreen> createState() =>
      _SupportReportTaskScreenState();
}

class _SupportReportTaskScreenState
    extends ConsumerState<SupportReportTaskScreen> {
  late final AccountRequestScope _scope;
  late Future<SupportCaseDetails> _details;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    _reload();
  }

  void _reload() {
    _details =
        ref.read(supportRepositoryProvider).adminDetails(widget.task.sourceId);
    _details.ignore();
  }

  Future<String?> _ask(String title) async {
    var draft = '';
    return showActorDialog<String>(
        context: context,
        ref: ref,
        builder: (dialog) => AlertDialog(
              scrollable: true,
              title: Text(title),
              content: TextField(
                  onChanged: (value) => draft = value,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration:
                      const InputDecoration(labelText: 'السبب أو التوضيح')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () {
                      if (draft.trim().length >= 3) {
                        Navigator.pop(dialog, draft.trim());
                      }
                    },
                    child: const Text('حفظ')),
              ],
            ));
  }

  Future<void> _perform(String action, String label) async {
    if (_busy || !_scope.isCurrent) return;
    final note = await _ask(label);
    if (note == null || !mounted || !_scope.isCurrent || _busy) return;
    setState(() => _busy = true);
    try {
      if (action == 'return_to_agent') {
        await ref
            .read(supportWorkspaceRepositoryProvider)
            .resolveEscalation(widget.task.id, note);
      } else if (action == 'reply') {
        await ref
            .read(supportRepositoryProvider)
            .adminReply(widget.task.sourceId, note);
      } else {
        await ref
            .read(supportRepositoryProvider)
            .reportDecision(widget.task.sourceId, action, note);
      }
      if (!mounted || !_scope.isCurrent) return;
      ref.read(supportWorkspaceRevisionProvider.notifier).state++;
      if (action == 'return_to_agent') {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حفظ الإجراء.')));
        setState(_reload);
      }
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _busy = false);
    }
  }

  Future<void> _openEvidenceConversation(int reportId) async {
    final proceed = await showActorDialog<bool>(
        context: context,
        ref: ref,
        builder: (dialog) => AlertDialog(
              title: const Text('فتح المحادثة المرتبطة بالبلاغ'),
              content:
                  const Text('سيُسجّل فتح محتوى المحادثة الخاصة لهذا البلاغ.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('فتح المحادثة')),
              ],
            ));
    if (proceed != true || !mounted || !_scope.isCurrent) return;
    try {
      final content = await ref
          .read(messageRepositoryProvider)
          .openReportedContent(reportId);
      if (!mounted || !_scope.isCurrent) return;
      await showActorDialog<void>(
          context: context,
          ref: ref,
          builder: (dialog) => AlertDialog(
                title: const Text('المحادثة المرتبطة بالبلاغ'),
                content: SizedBox(
                    width: 480,
                    child: ListView(shrinkWrap: true, children: [
                      for (final message in content.messages)
                        ListTile(
                            title: Text(message.senderName),
                            subtitle: Text(message.body)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('إغلاق'))
                ],
              ));
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!_scope.isCurrent) return const SizedBox.shrink();
    final actor = ref.watch(authControllerProvider).asData?.value;
    return Scaffold(
      appBar: const AppAppBar(title: 'تفاصيل البلاغ'),
      body: FutureBuilder<SupportCaseDetails>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppErrorState(
                  message: friendlyApiError(snapshot.error!),
                  onRetry: () => setState(_reload));
            }
            final details = snapshot.data;
            if (details == null) {
              return const AppLoadingState(label: 'جارٍ تحميل البلاغ…');
            }
            final summary = details.summary;
            final report = details.report ?? const <String, dynamic>{};
            final privateId =
                int.tryParse('${report['conversation_report_id']}');
            final reason = switch (summary.reasonCode) {
              'fraud' || 'scam' => 'احتيال',
              'abuse' => 'إساءة',
              'harassment' => 'مضايقة',
              'spam' => 'إزعاج',
              'misleading' => 'معلومات مضللة',
              'duplicate' => 'إعلان مكرر',
              'privacy' => 'انتهاك الخصوصية',
              _ => 'سبب آخر',
            };
            final status = switch (summary.status) {
              'resolved' => 'تم التعامل معه',
              'dismissed' => 'مرفوض ومغلق',
              'waiting_requester' => 'بانتظار توضيح المبلّغ',
              _ => 'قيد المعالجة',
            };
            return ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                  child: Column(children: [
                ListTile(
                    title: Text(summary.subject,
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text('${summary.reference} · $status')),
                ListTile(
                    dense: true,
                    title: const Text('مقدّم البلاغ'),
                    trailing: Text(details.requesterName ?? 'مستخدم')),
                if (report['reported_name'] case final String name)
                  ListTile(
                      dense: true,
                      title: const Text('المبلّغ عنه'),
                      trailing: Text(name)),
                if (report['property_title'] case final String title)
                  ListTile(
                      dense: true,
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('العقار المرتبط'),
                      subtitle: Text(title)),
                if (summary.assignedToName case final name?)
                  ListTile(
                      dense: true,
                      title: const Text('الموظف المسؤول'),
                      trailing: Text(name)),
              ])),
              Card(
                  child: Column(children: [
                ListTile(
                    title: const Text('سبب البلاغ'),
                    subtitle: Text('$reason\n${details.description}')),
                if (widget.task.escalationReason case final note?)
                  ListTile(
                      title: const Text('سبب التصعيد'), subtitle: Text(note)),
              ])),
              if (!summary.isClosed &&
                  privateId != null &&
                  actor?.hasPermission('conversations.review_private') == true)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('فتح المحادثة المبلّغ عنها'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => _openEvidenceConversation(privateId))),
              for (final message in details.messages)
                if (message.attachments.isNotEmpty ||
                    message.body != details.description)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  message.isInternal
                                      ? 'ملاحظة داخلية'
                                      : message.actorName ?? 'الدعم',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (message.body != details.description)
                                Text(message.body),
                              for (final attachment in message.attachments)
                                SupportAttachmentButton(
                                    caseId: summary.id,
                                    file: attachment,
                                    staff: true),
                            ],
                          ))),
              const SizedBox(height: 8),
              if (!summary.isClosed)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (widget.manager && widget.task.status == 'escalated')
                    AppButton(
                        label: 'إعادة للموظف مع توجيه',
                        onPressed: _busy
                            ? null
                            : () => _perform(
                                'return_to_agent', 'إعادة للموظف مع توجيه')),
                  AppButton(
                      label: 'رد على المبلّغ',
                      onPressed: _busy
                          ? null
                          : () => _perform('reply', 'رد على المبلّغ')),
                  for (final (action, title) in const [
                    ('request_information', 'طلب توضيح'),
                    ('resolve', 'إغلاق البلاغ'),
                    ('dismiss', 'رفض البلاغ'),
                    ('pause_publication', 'إيقاف النشر مؤقتًا'),
                  ])
                    if (action != 'pause_publication' ||
                        report['may_manage_publication'] == true)
                      AppButton(
                          label: title,
                          style: AppButtonStyle.outlined,
                          onPressed:
                              _busy ? null : () => _perform(action, title)),
                ]),
              if (report['publication_paused_for_report'] == true &&
                  report['may_manage_publication'] == true)
                AppButton(
                    label: 'إعادة تفعيل النشر',
                    style: AppButtonStyle.outlined,
                    onPressed: _busy
                        ? null
                        : () => _perform(
                            'restore_publication', 'إعادة تفعيل النشر')),
            ]);
          }),
    );
  }
}
