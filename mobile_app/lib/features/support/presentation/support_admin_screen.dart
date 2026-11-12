import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportAdminScreen extends ConsumerWidget {
  const SupportAdminScreen({super.key, this.initialKind, this.initialCaseId});
  final String? initialKind;
  final int? initialCaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _SupportAdminBody(key: ValueKey((actor, Stage6SecureSessionStore.instance.sessionEpoch, initialKind, initialCaseId)), initialKind: initialKind, initialCaseId: initialCaseId);
  }
}
class _SupportAdminBody extends ConsumerStatefulWidget {
  const _SupportAdminBody({this.initialKind, this.initialCaseId, super.key});
  final String? initialKind;
  final int? initialCaseId;
  @override
  ConsumerState<_SupportAdminBody> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends ConsumerState<_SupportAdminBody> {
  SupportAdminSummary? _summary;
  List<SupportCaseSummary> _items = const [];
  bool _loading = true;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = false;
  int? _actor;
  int _sessionEpoch = 0;
  late final (int?, int) _boundSession;
  int _identityVersion = 0;
  String? _kind;
  String? _status;
  bool _escalatedOnly = false;
  bool _assignedToMe = false;
  bool _initialCaseOpened = false;
  int _request = 0;
  String? _query;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _actor = ref.read(authControllerProvider).asData?.value?.id;
    _sessionEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
    _boundSession = (_actor, _sessionEpoch);
    ref.listenManual(authControllerProvider, (_, next) {
      final actor = next.asData?.value?.id;
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      if (!mounted || (_actor == actor && _sessionEpoch == epoch)) return;
      setState(() {
        _request++;
        _identityVersion++;
        _actor = actor;
        _sessionEpoch = epoch;
        _items = const [];
        _summary = null;
        _query = null;
        _page = 0;
        _hasMore = false;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _loading = actor != null;
        _initialCaseOpened = true;
      });
      if (actor != null && (actor, epoch) == _boundSession) {
        Future<void>.microtask(_load);
      }
    });
    Future.microtask(() async {
      await _load();
      await _openInitialCaseIfNeeded();
    });
  }

  Future<void> _load() => _fetchPage(1);

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    await _fetchPage(_page + 1, append: true);
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final query = '$_kind:$_status:$_escalatedOnly:$_assignedToMe';
    if (append && (_query != query || _actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_query != query || _actor != actor || _sessionEpoch != epoch) {
        _items = const [];
      }
      if (_actor != actor || _sessionEpoch != epoch) _summary = null;
      _query = query;
      _actor = actor;
      _sessionEpoch = epoch;
      _pageError = null;
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _page = 0;
        _hasMore = false;
      }
    });
    bool current() => mounted && request == _request &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch && query == _query;
    try {
      final repo = ref.read(supportRepositoryProvider);
      final results = await Future.wait<dynamic>([
        if (!append) repo.adminSummary(),
        repo.adminCases(page: page,
            kind: _kind,
            status: _status,
            escalated: _escalatedOnly ? true : null,
            assignedToMe: _assignedToMe),
      ]);
      if (!current()) return;
      final result = results.last as SupportCasePage;
      setState(() {
        if (!append) _summary = results.first as SupportAdminSummary;
        _items = <int, SupportCaseSummary>{
          if (append) for (final item in _items) item.id: item,
          for (final item in result.items) item.id: item,
        }.values.toList(growable: false);
        _page = result.currentPage;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!current()) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (append && isTransientApiFailure(error)) {
          _pageError = friendlyApiError(error);
        } else {
          if (!isTransientApiFailure(error)) { _items = const []; _summary = null; }
          _page = 0;
          _hasMore = false;
          _error = friendlyApiError(error);
        }
      });
    }
  }

  @override
  void dispose() { _request++; super.dispose(); }

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
                  tooltip: 'تحديث طلبات الدعم',
                  onPressed: _loading ? null : _load,
                  icon: const EbrokerIcon(Icons.refresh))
            ]),
        body: _loading && _summary == null
            ? const AppLoadingState(label: 'جارٍ تحميل طلبات الدعم…')
            : _error != null && _items.isEmpty
                ? AppErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      key: ValueKey((_actor, _sessionEpoch, _query)),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                      children: [
                        if (_summary != null) _summaryCard(_summary!),
                        const SizedBox(height: 8),
                        _filters(),
                        if (_loading || _error != null) AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
                        const SizedBox(height: 8),
                        if (_items.isEmpty && !_loading && _error == null)
                          const Card(
                              child: ListTile(
                                  title: Text('لا توجد حالات مطابقة.'))),
                        ..._items.map((item) => Card(
                                key: ValueKey('support-case-${item.id}'),
                                child: ListTile(
                              leading: EbrokerIcon(item.kind == 'report'
                                  ? Icons.report_outlined
                                  : Icons.support_agent_outlined),
                              title: Text(item.subject,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${item.reference}\n${_statusLabel(item.status)} • ${_priorityLabel(item.priority)}${item.assignedToName == null ? '' : ' • ${item.assignedToName}'}'),
                              isThreeLine: true,
                              trailing: item.isEscalated
                                  ? const EbrokerIcon(Icons.priority_high)
                                  : const EbrokerIcon(Icons.chevron_left),
                              onTap: () => _openCase(item.id,
                                  canReassign: canReassign,
                                  canReopen: canReopen,
                                  canEscalate: canEscalate,
                                  canModerate: canModerate,
                                  canReviewListings: canReviewListings),
                            ))),
                        if (_hasMore)
                          _loadingMore || _pageError != null
                            ? AppRefreshStatus(loading: _loadingMore, error: _pageError,
                                onRetry: _loadMore)
                            : Center(child: TextButton(
                                key: const ValueKey('support-cases-more'),
                                onPressed: _loading ? null : _loadMore,
                                child: const Text('المزيد من الحالات'))),
                      ],
                    ),
                  ),
      ),
    );
  }

  Future<void> _openInitialCaseIfNeeded() async {
    final caseId = widget.initialCaseId;
    if (_initialCaseOpened || caseId == null || !mounted) return;
    _initialCaseOpened = true;
    final user = ref.read(authControllerProvider).asData?.value;
    await _openCase(
      caseId,
      canReassign: user?.isPlatformOwner == true ||
          user?.hasPermission('support.reassign') == true,
      canReopen: user?.isPlatformOwner == true ||
          user?.hasPermission('support.reopen') == true,
      canEscalate: user?.isPlatformOwner == true ||
          user?.hasPermission('support.escalate') == true,
      canModerate: user?.isPlatformOwner == true ||
          user?.hasPermission('content.moderate') == true,
      canReviewListings: user?.isPlatformOwner == true ||
          user?.hasPermission('listings.moderate') == true,
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
                isExpanded: true,
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
                isExpanded: true,
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
              EbrokerFilterChip(
                  selected: _assignedToMe,
                  label: const Text('المسندة لي'),
                  onSelected: (v) {
                    setState(() => _assignedToMe = v);
                    _load();
                  }),
              EbrokerFilterChip(
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
    final actor = _actor;
    final epoch = _sessionEpoch;
    final identityVersion = _identityVersion;
    bool current() => mounted && actor != null && identityVersion == _identityVersion &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    try {
      var details =
          await ref.read(supportRepositoryProvider).adminDetails(caseId);
      if (!current()) {
        return;
      }
      await showActorDialog<void>(
          ref: ref,
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (context, setDialogState) {
                Future<void> refresh(Future<SupportCaseDetails> action) async {
                  try {
                    final updated = await action;
                    if (!current() || !dialogContext.mounted) return;
                    details = updated;
                    setDialogState(() {});
                  } catch (e) {
                    if (current() && dialogContext.mounted) {
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
                                    fontSize: 17, fontWeight: FontWeight.w600)),
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
                                      fontWeight: FontWeight.w600)),
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
                                    ?.copyWith(fontWeight: FontWeight.w600)),
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
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(m.body),
                                ))),
                            if (details.events.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text('سجل الحالة',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              ...details.events.map((e) => ListTile(
                                  dense: true,
                                  leading: const EbrokerIcon(Icons.history),
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
                            if (reason != null && current()) {
                              await ref
                                  .read(supportRepositoryProvider)
                                  .hideComment(
                                      details.summary.targetId!, reason);
                              if (current() && dialogContext.mounted) {
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
                            if (reason != null && current()) {
                              await ref
                                  .read(supportRepositoryProvider)
                                  .hideRating(
                                      details.summary.targetId!, reason);
                              if (current() && dialogContext.mounted) {
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
                            if (reason != null && current()) {
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
                            if (agent != null && current()) {
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
                            if (reason != null && current()) {
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
                          onPressed: () {
                            if (current()) refresh(ref.read(supportRepositoryProvider).start(caseId));
                          },
                          child: const Text('بدء المعالجة')),
                    if (!details.summary.isClosed)
                      TextButton(
                          onPressed: () async {
                            final body = await _textDialog(
                                dialogContext, 'الرد على المستخدم');
                            if (body != null && current()) {
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
                            if (body != null && current()) {
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
                        onSelected: (status) {
                          if (current()) refresh(ref.read(supportRepositoryProvider).setStatus(caseId, status));
                        },
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
                    EbrokerFilledButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('إغلاق')),
                  ],
                );
              }));
      if (current()) await _load();
    } catch (e) {
      if (current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  Future<int?> _chooseAgent(BuildContext context) async {
    final actor = _actor;
    final epoch = _sessionEpoch;
    final identityVersion = _identityVersion;
    bool current() => mounted && context.mounted && identityVersion == _identityVersion &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    try {
      final agents = await ref.read(supportRepositoryProvider).agents();
      if (!current()) {
        return null;
      }
      return showActorDialog<int>(
          ref: ref,
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
      if (current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
      return null;
    }
  }

  Future<String?> _textDialog(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showActorDialog<String>(
        ref: ref,
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
                EbrokerFilledButton(
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
