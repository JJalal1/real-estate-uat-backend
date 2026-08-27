import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportAdminScreen extends ConsumerStatefulWidget {
  const SupportAdminScreen({super.key, this.initialKind});
  final String? initialKind;

  @override
  ConsumerState<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends ConsumerState<SupportAdminScreen> {
  SupportAdminSummary? _summary;
  List<SupportCaseSummary> _items = const [];
  bool _loading = true;
  String? _error;
  String? _kind;
  String? _status;
  bool _escalatedOnly = false;
  bool _assignedToMe = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(supportRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.adminSummary(),
        repo.adminCases(
            kind: _kind,
            status: _status,
            escalated: _escalatedOnly ? true : null,
            assignedToMe: _assignedToMe),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = results[0] as SupportAdminSummary;
        _items = results[1] as List<SupportCaseSummary>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final canReassign = user?.isPlatformOwner == true ||
        user?.hasPermission('support.reassign') == true;
    final canReopen = user?.isPlatformOwner == true ||
        user?.hasPermission('support.reopen') == true;
    final canEscalate = user?.isPlatformOwner == true ||
        user?.hasPermission('support.escalate') == true;
    final canModerate = user?.isPlatformOwner == true ||
        user?.hasPermission('content.moderate') == true;
    final canReviewListings = user?.isPlatformOwner == true ||
        user?.hasPermission('listings.moderate') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
            title:
                Text(_kind == 'report' ? 'البلاغات' : 'طلبات الدعم والبلاغات'),
            actions: [
              IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh))
            ]),
        body: _loading && _summary == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                      children: [
                        if (_summary != null) _summaryCard(_summary!),
                        const SizedBox(height: 8),
                        _filters(),
                        if (_loading) const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        if (_items.isEmpty && !_loading)
                          const Card(
                              child: ListTile(
                                  title: Text('لا توجد حالات مطابقة.'))),
                        ..._items.map((item) => Card(
                                child: ListTile(
                              leading: Icon(item.kind == 'report'
                                  ? Icons.report_outlined
                                  : Icons.support_agent_outlined),
                              title: Text(item.subject,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${item.reference}\n${_statusLabel(item.status)} • ${_priorityLabel(item.priority)}${item.assignedToName == null ? '' : ' • ${item.assignedToName}'}'),
                              isThreeLine: true,
                              trailing: item.isEscalated
                                  ? const Icon(Icons.priority_high)
                                  : const Icon(Icons.chevron_left),
                              onTap: () => _openCase(item.id,
                                  canReassign: canReassign,
                                  canReopen: canReopen,
                                  canEscalate: canEscalate,
                                  canModerate: canModerate,
                                  canReviewListings: canReviewListings),
                            ))),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _summaryCard(SupportAdminSummary s) => Card(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          _Metric(label: 'جديدة', value: s.newTickets),
          _Metric(label: 'مسندة لي', value: s.assignedToMe),
          _Metric(label: 'مفتوحة', value: s.open),
          _Metric(label: 'قيد المعالجة', value: s.inProgress),
          _Metric(label: 'انتظار المستخدم', value: s.waitingRequester),
          _Metric(label: 'بلاغات جديدة', value: s.newReports),
          _Metric(label: 'SLA قريب', value: s.slaWarning),
          _Metric(label: 'متأخرة', value: s.overdueUnescalated),
        ]),
      ));

  Widget _filters() => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField<String?>(
                value: _kind,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(
                      value: 'support_ticket', child: Text('طلبات الدعم')),
                  DropdownMenuItem(value: 'report', child: Text('البلاغات'))
                ],
                onChanged: (v) {
                  setState(() => _kind = v);
                  _load();
                },
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: DropdownButtonFormField<String?>(
                value: _status,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('كل الحالات')),
                  DropdownMenuItem(value: 'open', child: Text('مفتوح')),
                  DropdownMenuItem(
                      value: 'in_progress', child: Text('قيد المعالجة')),
                  DropdownMenuItem(
                      value: 'waiting_requester',
                      child: Text('بانتظار المستخدم')),
                  DropdownMenuItem(
                      value: 'resolved', child: Text('مغلق - تم الحل')),
                  DropdownMenuItem(
                      value: 'dismissed', child: Text('مغلق - مرفوض'))
                ],
                onChanged: (v) {
                  setState(() => _status = v);
                  _load();
                },
              )),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilterChip(
                  selected: _assignedToMe,
                  label: const Text('المسندة لي'),
                  onSelected: (v) {
                    setState(() => _assignedToMe = v);
                    _load();
                  }),
              FilterChip(
                  selected: _escalatedOnly,
                  label: const Text('المصعّدة فقط'),
                  onSelected: (v) {
                    setState(() => _escalatedOnly = v);
                    _load();
                  }),
            ]),
          ])));

  Future<void> _openCase(int caseId,
      {required bool canReassign,
      required bool canReopen,
      required bool canEscalate,
      required bool canModerate,
      required bool canReviewListings}) async {
    try {
      var details =
          await ref.read(supportRepositoryProvider).adminDetails(caseId);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (context, setDialogState) {
                Future<void> refresh(Future<SupportCaseDetails> action) async {
                  try {
                    details = await action;
                    setDialogState(() {});
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(friendlyApiError(e))),
                      );
                    }
                  }
                }

                return AlertDialog(
                  title: Text(details.summary.reference),
                  content: SizedBox(
                      width: 650,
                      child: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(details.summary.subject,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                                'الحالة: ${_statusLabel(details.summary.status)} • الأولوية: ${_priorityLabel(details.summary.priority)}'),
                            if (details.summary.assignedToName != null)
                              Text(
                                  'المسؤول: ${details.summary.assignedToName}'),
                            if (details.requesterName != null)
                              Text('المستخدم: ${details.requesterName}'),
                            if (details.requesterEmail != null)
                              Text('البريد: ${details.requesterEmail}'),
                            if (details.summary.kind == 'report') ...[
                              const Divider(height: 24),
                              Text(
                                  'سبب البلاغ: ${details.summary.reasonCode ?? '-'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              if (details.targetPreview != null)
                                _TargetPreview(data: details.targetPreview!),
                            ],
                            const Divider(height: 24),
                            Text(details.description),
                            const Divider(height: 24),
                            Text('المراسلات',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900)),
                            ...details.messages.map((m) => Card(
                                color: m.isInternal
                                    ? Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer
                                    : null,
                                child: ListTile(
                                  title: Text(
                                      '${m.actorName ?? 'النظام'}${m.isInternal ? ' • ملاحظة داخلية' : ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  subtitle: Text(m.body),
                                ))),
                            if (details.events.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text('سجل الحالة',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900)),
                              ...details.events.map((e) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.history),
                                  title: Text(_eventLabel(e.event)),
                                  subtitle: Text([
                                    if (e.actorName != null) e.actorName!,
                                    if (e.fromStatus != null ||
                                        e.toStatus != null)
                                      '${e.fromStatus ?? '-'} ← ${e.toStatus ?? '-'}',
                                    if (e.createdAt != null)
                                      e.createdAt!.toLocal().toString()
                                  ].join(' • ')))),
                            ],
                          ]))),
                  actions: [
                    if (canModerate &&
                        details.summary.kind == 'report' &&
                        details.targetPreview?['type'] == 'comment')
                      TextButton(
                          onPressed: () async {
                            final reason = await _textDialog(
                                dialogContext, 'سبب إخفاء التعليق');
                            if (reason != null) {
                              await ref
                                  .read(supportRepositoryProvider)
                                  .hideComment(
                                      details.summary.targetId!, reason);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم إخفاء التعليق وتسجيل الإجراء.')),
                                );
                              }
                            }
                          },
                          child: const Text('إخفاء التعليق')),
                    if (canModerate &&
                        details.summary.kind == 'report' &&
                        details.targetPreview?['type'] == 'rating')
                      TextButton(
                          onPressed: () async {
                            final reason = await _textDialog(
                                dialogContext, 'سبب إخفاء التقييم');
                            if (reason != null) {
                              await ref
                                  .read(supportRepositoryProvider)
                                  .hideRating(
                                      details.summary.targetId!, reason);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم إخفاء التقييم وتسجيل الإجراء.')),
                                );
                              }
                            }
                          },
                          child: const Text('إخفاء التقييم')),
                    if (canReviewListings &&
                        details.summary.kind == 'report' &&
                        details.targetPreview?['type'] == 'listing')
                      TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            context.push('/admin/listing-review');
                          },
                          child: const Text('فتح مراجعة الإعلانات')),
                    if (!details.summary.isClosed &&
                        !details.summary.isEscalated &&
                        canEscalate)
                      TextButton(
                          onPressed: () async {
                            final reason = await _textDialog(
                                dialogContext, 'سبب تصعيد الحالة لمدير الدعم');
                            if (reason != null) {
                              await refresh(
                                ref
                                    .read(supportRepositoryProvider)
                                    .escalate(caseId, reason),
                              );
                            }
                          },
                          child: const Text('تصعيد')),
                    if (canReassign)
                      TextButton(
                          onPressed: () async {
                            final agent = await _chooseAgent(dialogContext);
                            if (agent != null) {
                              await refresh(
                                ref
                                    .read(supportRepositoryProvider)
                                    .assign(caseId, agent),
                              );
                            }
                          },
                          child: const Text('إسناد')),
                    if (details.summary.isClosed && canReopen)
                      TextButton(
                          onPressed: () async {
                            final reason = await _textDialog(
                                dialogContext, 'سبب إعادة الفتح');
                            if (reason != null) {
                              await refresh(
                                ref
                                    .read(supportRepositoryProvider)
                                    .reopen(caseId, reason),
                              );
                            }
                          },
                          child: const Text('إعادة فتح')),
                    if (!details.summary.isClosed &&
                        details.summary.status == 'open')
                      TextButton(
                          onPressed: () => refresh(ref
                              .read(supportRepositoryProvider)
                              .start(caseId)),
                          child: const Text('بدء المعالجة')),
                    if (!details.summary.isClosed)
                      TextButton(
                          onPressed: () async {
                            final body = await _textDialog(
                                dialogContext, 'الرد على المستخدم');
                            if (body != null) {
                              await refresh(
                                ref
                                    .read(supportRepositoryProvider)
                                    .adminReply(caseId, body),
                              );
                            }
                          },
                          child: const Text('رد')),
                    if (!details.summary.isClosed)
                      TextButton(
                          onPressed: () async {
                            final body = await _textDialog(
                                dialogContext, 'ملاحظة داخلية');
                            if (body != null) {
                              await refresh(
                                ref
                                    .read(supportRepositoryProvider)
                                    .internalNote(caseId, body),
                              );
                            }
                          },
                          child: const Text('ملاحظة داخلية')),
                    if (!details.summary.isClosed)
                      PopupMenuButton<String>(
                        onSelected: (status) => refresh(ref
                            .read(supportRepositoryProvider)
                            .setStatus(caseId, status)),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'in_progress',
                              child: Text('قيد المعالجة')),
                          PopupMenuItem(
                              value: 'waiting_requester',
                              child: Text('بانتظار المستخدم')),
                          PopupMenuItem(
                              value: 'resolved',
                              child: Text('إغلاق - تم الحل')),
                          PopupMenuItem(
                              value: 'dismissed', child: Text('إغلاق - رفض'))
                        ],
                        child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('تغيير الحالة')),
                      ),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('إغلاق')),
                  ],
                );
              }));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  Future<int?> _chooseAgent(BuildContext context) async {
    try {
      final agents = await ref.read(supportRepositoryProvider).agents();
      if (!context.mounted) {
        return null;
      }
      return showDialog<int>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
                title: const Text('إسناد إلى موظف دعم'),
                children: agents
                    .map((a) => ListTile(
                        title: Text(a.name),
                        subtitle: Text('${a.activeCases} حالة نشطة'),
                        onTap: () => Navigator.pop(dialogContext, a.id)))
                    .toList(),
              ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
      return null;
    }
  }

  Future<String?> _textDialog(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) {
                        Navigator.pop(dialogContext, value);
                      }
                    },
                    child: const Text('حفظ'))
              ],
            ));
    controller.dispose();
    return result;
  }

  String _statusLabel(String value) =>
      const {
        'open': 'مفتوح',
        'in_progress': 'قيد المعالجة',
        'waiting_requester': 'بانتظار المستخدم',
        'resolved': 'مغلق - تم الحل',
        'dismissed': 'مغلق - مرفوض'
      }[value] ??
      value;
  String _priorityLabel(String value) =>
      const {'normal': 'عادية', 'high': 'عالية', 'urgent': 'عاجلة'}[value] ??
      value;
  String _eventLabel(String value) =>
      const {
        'created': 'إنشاء الحالة',
        'assigned': 'إسناد الحالة',
        'started': 'بدء المعالجة',
        'staff_reply': 'رد موظف الدعم',
        'requester_reply': 'رد المستخدم',
        'internal_note': 'ملاحظة داخلية',
        'status_changed': 'تغيير الحالة',
        'reopened': 'إعادة فتح',
        'escalated': 'تصعيد',
        'manual_escalated': 'تصعيد يدوي',
        'sla_escalated': 'تصعيد SLA'
      }[value] ??
      value;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) =>
      Chip(avatar: CircleAvatar(child: Text('$value')), label: Text(label));
}

class _TargetPreview extends StatelessWidget {
  const _TargetPreview({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final type = data['type']?.toString() ?? '';
    final rows = <String>[];
    if (type == 'listing') {
      rows.addAll([
        'الإعلان: ${data['title'] ?? '#${data['id']}'}',
        'الحالة: ${data['status'] ?? '-'} / ${data['review_status'] ?? '-'}',
      ]);
    }
    if (type == 'comment') {
      rows.addAll([
        'التعليق: ${data['body'] ?? ''}',
        'الحالة: ${data['status'] ?? '-'}',
      ]);
    }
    if (type == 'rating') {
      rows.addAll([
        'التقييم: ${data['rating'] ?? '-'}',
        if ((data['comment']?.toString() ?? '').isNotEmpty)
          'التعليق: ${data['comment']}',
      ]);
    }
    if (type == 'advertiser') {
      rows.addAll([
        'المعلن: ${data['name'] ?? '#${data['id']}'}',
        'حالة الحساب: ${data['account_status'] ?? '-'}',
      ]);
    }
    return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows.map(Text.new).toList())));
  }
}
