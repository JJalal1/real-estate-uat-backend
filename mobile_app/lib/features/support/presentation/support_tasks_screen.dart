import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../broker/data/broker_repository.dart';
import '../../reviews/domain/listing_duplicate_candidate.dart';
import '../../reviews/presentation/listing_review_workspace_screen.dart';
import '../data/support_repository.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_models.dart';
import '../domain/support_workspace_models.dart';
import 'account_verification_support_screen.dart';
import 'support_payment_review_screen.dart';
import 'support_report_task_screen.dart';
import 'support_evidence.dart';

class SupportTasksScreen extends ConsumerStatefulWidget {
  const SupportTasksScreen({
    super.key,
    this.initialScope = 'inbox',
    this.initialType,
    this.initialStatus,
    this.initialSeverity,
    this.overdueOnly = false,
    this.actingAsAgent = false,
    this.messagesOnly = false,
    this.initialTaskId,
    this.initialAssigneeId,
    this.title,
  });

  final String initialScope;
  final String? initialType;
  final String? initialStatus;
  final String? initialSeverity;
  final bool overdueOnly;
  final bool actingAsAgent;
  final bool messagesOnly;
  final int? initialTaskId;
  final int? initialAssigneeId;
  final String? title;

  @override
  ConsumerState<SupportTasksScreen> createState() => _SupportTasksScreenState();
}

class _SupportTasksScreenState extends ConsumerState<SupportTasksScreen> {
  bool _loading = true;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = false;
  List<SupportTaskItem> _items = const [];
  late String _scope;
  String? _type;
  String? _category;
  String? _status;
  String? _severity;
  late bool _overdue;
  int _request = 0;
  int? _actor;
  int _sessionEpoch = 0;
  String? _query;
  bool _initialTaskOpened = false;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _type = widget.initialType;
    _status = widget.initialStatus;
    _severity = widget.initialSeverity;
    _overdue = widget.overdueOnly;
    _actor = ref.read(authControllerProvider).asData?.value?.id;
    _sessionEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
    // Observe every boundary, including logout and same-account login before
    // the next frame, so an earlier page can never enter the new inbox.
    ref.listenManual(authControllerProvider, (_, next) {
      final actor = next.asData?.value?.id;
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      if (_actor == actor && _sessionEpoch == epoch) return;
      if (!mounted) return;
      setState(() {
        _request++;
        _actor = actor;
        _sessionEpoch = epoch;
        _items = const [];
        _page = 0;
        _hasMore = false;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _loading = _actor != null;
        _query = null;
      });
      if (_actor != null) Future<void>.microtask(_load);
    });
    Future<void>.microtask(_load);
  }

  Future<void> _load() {
    final taskId = widget.initialTaskId;
    return taskId == null ? _fetchPage(1) : _loadTask(taskId);
  }

  Future<void> _loadTask(int taskId) async {
    if (!mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final request = ++_request;
    bool current() =>
        mounted &&
        request == _request &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
        actor == ref.read(authControllerProvider).asData?.value?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(supportWorkspaceRepositoryProvider);
      final item = widget.actingAsAgent
          ? await repository.agentTask(taskId)
          : await repository.task(taskId);
      if (!current()) return;
      setState(() {
        _items = [item];
        _loading = false;
      });
      if (!_initialTaskOpened) {
        _initialTaskOpened = true;
        final manager = !widget.actingAsAgent;
        if ((!item.isClosed && (manager && item.status == 'escalated' || item.isMine && !item.canClaim))
            || item.isClosed && item.isMine && const {'report', 'support_ticket'}.contains(item.sourceType)) {
          await _open(item, manager);
        }
      }
    } catch (error) {
      if (!current()) return;
      setState(() {
        if (!isTransientApiFailure(error)) _items = const [];
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    await _fetchPage(_page + 1, append: true);
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final query = '$_scope:$_type:$_category:$_status:$_severity:${widget.initialAssigneeId}:$_overdue:${widget.actingAsAgent}:${widget.messagesOnly}';
    if (append && (_query != query || _actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_query != query || _actor != actor || _sessionEpoch != epoch) {
        _items = const [];
      }
      _query = query;
      _actor = actor;
      _sessionEpoch = epoch;
      _pageError = null;
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        _page = 0;
        _hasMore = false;
        _error = null;
      }
    });
    bool current() => mounted && request == _request &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
        query == _query;
    try {
      final repository = ref.read(supportWorkspaceRepositoryProvider);
      final SupportTaskPage result;
      if (widget.messagesOnly) {
        result = await repository.messages(page: page, actingAsAgent: widget.actingAsAgent);
      } else {
        result = await repository.tasks(
            page: page,
            scope: _scope,
            type: _type,
            category: _category,
            status: _status,
            severity: _severity,
            assigneeId: widget.initialAssigneeId,
            overdue: _overdue,
            actingAsAgent: widget.actingAsAgent,
          );
      }
      if (!current()) return;
      setState(() {
        // A task can move between server pages while the queue changes. Keep
        // one row per ID and take its newest returned state.
        _items = <int, SupportTaskItem>{
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
          if (!isTransientApiFailure(error)) _items = const [];
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
    if (user == null) return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    final manager = user.isPlatformOwner == true ||
        user.roles.contains('super_admin') == true ||
        user.roles.contains('support_manager') == true ||
        user.hasPermission('support.manage') == true;
    final reviewingAssignedTask = widget.initialTaskId != null &&
        _items.any((task) => !task.isMine && !task.canClaim);
    final managerMode = manager && (!widget.actingAsAgent || reviewingAssignedTask);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? _defaultTitle()),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const EbrokerIcon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (manager && widget.actingAsAgent && !managerMode && !widget.messagesOnly)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const ListTile(
                  leading: EbrokerIcon(Icons.support_agent_outlined),
                  title: Text('أنت الآن تعمل كموظف دعم',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'استلم الطلب من الوارد أو من المهام المسندة إليك.'),
                ),
              ),
            if (widget.initialTaskId == null && !widget.messagesOnly)
              _filters(managerMode, user.hasPermission('payments.review') || managerMode),
            if (_items.isNotEmpty && (_loading || _error != null)) AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
            Expanded(child: _body(managerMode)),
          ],
        ),
      ),
    );
  }

  String _defaultTitle() {
    if (widget.messagesOnly) return 'رسائل الدعم';
    if (_scope == 'assigned') return 'المهام المسندة إليك';
    if (_scope == 'received') return 'المهام المستلمة';
    if (_scope == 'open_tickets') return 'التذاكر المفتوحة';
    if (_scope == 'waiting_user') return 'بانتظار المستخدم';
    if (_scope == 'unreceived_overdue') return 'المتأخر';
    if (_scope == 'mine') return 'مهامي';
    if (_scope == 'completed') return 'المهام المنجزة';
    if (_scope == 'all') return 'كل الأعمال';
    return 'الوارد الجديد';
  }

  Widget _filters(bool manager, bool showPayments) {
    final showState = manager && const ['all', 'active', 'completed'].contains(_scope);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(children: [
          if (showState)
            EbrokerSegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'active', label: Text('المفتوحة')),
                ButtonSegment(value: 'completed', label: Text('المنجزة')),
              ],
              selected: {_scope == 'completed' ? 'completed' : 'active'},
              onSelectionChanged: (selection) {
                setState(() => _scope = selection.first);
                _load();
              },
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _choice('الكل', _type == null && _category == null, () => _setCategory(null)),
              for (final category in _taskCategories)
                if (category != 'payment_review' || showPayments)
                  _choice(_typeLabel(category), (_category ?? _type) == category, () => _setCategory(category)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: EbrokerChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
  );

  void _setCategory(String? value) {
    setState(() {
      _type = null;
      _category = value;
    });
    _load();
  }

  Widget _body(bool manager) {
    if (_loading && _items.isEmpty) return const AppLoadingState(label: 'جارٍ تحميل طلبات الدعم…');
    if (_error != null && _items.isEmpty) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            EbrokerIcon(Icons.inbox_outlined, size: 58, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Center(child: Text(widget.messagesOnly
                ? 'لا توجد محادثات دعم مفتوحة.'
                : 'لا توجد مهام مطابقة لهذه الفلاتر.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: ValueKey(('support-tasks', _actor, _sessionEpoch, _query)),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) => index == _items.length
            ? _pageError != null || _loadingMore
                ? AppRefreshStatus(key: const ValueKey('support-tasks-page-status'),
                    loading: _loadingMore, error: _pageError, onRetry: _loadMore)
                : TextButton(key: const ValueKey('support-tasks-more'),
                    onPressed: _loading ? null : _loadMore,
                    child: const Text('المزيد من المهام'))
            : _TaskCard(
          key: ValueKey('support-task-${_items[index].id}'),
          task: _items[index],
          manager: manager,
          onAssign: () => _assign(_items[index]),
          onClaim: () => _claim(_items[index]),
          onOpen: () => _open(_items[index], manager),
          onManage: manager || _items[index].isMine
              ? () => _manage(_items[index], manager)
              : null,
        ),
      ),
    );
  }

  Future<void> _claim(SupportTaskItem task) async {
    final scope = ref.read(accountRequestScopeProvider);
    try {
      final claimed = await ref.read(supportWorkspaceRepositoryProvider).claim(
            task.id,
            actingAsAgent: widget.actingAsAgent,
          );
      if (!mounted || !scope.isCurrent) return;
      _message('تم استلام المهمة.');
      ref.read(supportWorkspaceRevisionProvider.notifier).state++;
      await _open(claimed, false);
    } catch (error) {
      if (!mounted || !scope.isCurrent) return;
      _message(friendlyApiError(error));
      await _load();
    }
  }

  Future<void> _open(SupportTaskItem task, bool manager) async {
    if (manager && !widget.actingAsAgent &&
        (task.status != 'escalated' || !const {'support_ticket', 'report'}.contains(task.sourceType)) &&
        (!task.isMine || task.canClaim)) {
      await _manage(task, true);
      return;
    }
    if ((!manager || widget.actingAsAgent) && (!task.isMine || task.canClaim)) {
      _message('استلم المهمة أولاً قبل فتح بياناتها الخاصة.');
      return;
    }
    switch (task.sourceType) {
      case 'account_verification':
        final verificationActor = ref.read(authControllerProvider).asData?.value?.id;
        final verificationEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
        final verificationScope = ref.read(accountRequestScopeProvider);
        if (verificationActor == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ActorBoundPage(title: 'تفاصيل طلب التحقق',
              actorId: verificationActor, sessionEpoch: verificationEpoch,
              requestScope: verificationScope,
              builder: (_) => AccountVerificationSupportScreen(focusUserId: task.sourceId)),
          ),
        );
        break;
      case 'listing_review':
        final actor = ref.read(authControllerProvider).asData?.value?.id;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ListingReviewCaseScreen(
              listingId: task.sourceId,
              actorId: actor,
            ),
          ),
        );
        break;
      case 'report':
        await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => SupportReportTaskScreen(task: task, manager: manager),
        ));
        break;
      case 'support_ticket':
      case 'support_question':
        await _supportCaseDialog(task);
        break;
      case 'payment_review':
        await _paymentReviewDialog(task);
        break;
    }
    if (mounted) {
      ref.read(supportWorkspaceRevisionProvider.notifier).state++;
      await _load();
    }
  }

  Future<void> _paymentReviewDialog(SupportTaskItem task) async {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => ActorBoundPage(
        title: 'مراجعة إيصال سداد',
        actorId: actor,
        sessionEpoch: epoch,
        requestScope: scope,
        builder: (_) => SupportPaymentReviewScreen(
          paymentId: task.sourceId,
          actingAsAgent: widget.actingAsAgent,
          advertiserName: task.requesterName,
        ),
      ),
    ));
    if (result != null && mounted && scope.isCurrent) _message(result);
  }

  Future<void> _supportCaseDialog(SupportTaskItem task) async {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    final support = ref.read(supportRepositoryProvider);
    final broker = ref.read(brokerRepositoryProvider);
    bool current() =>
        mounted &&
        scope.isCurrent &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    void verify() {
      if (!current()) throw StateError('ACCOUNT_CHANGED');
    }

    SupportCaseDetails details;
    try {
      details = await support.adminDetails(task.sourceId);
    } catch (error) {
      if (current()) _message(friendlyApiError(error));
      return;
    }
    if (!mounted || !current()) return;
    await showActorDialog<void>(
      context: context,
      ref: ref,
      builder: (dialogContext) => _SupportCaseDialog(
        details: details,
        onClassify: task.isClosed || !task.isMine ? null : () {
          verify();
          return _classify(task, categoryOnly: true);
        },
        onSuggest: () {
          verify();
          return support.suggestReply(task.sourceId);
        },
        onReply: (text) {
          verify();
          return support.adminReply(task.sourceId, text);
        },
        onInternalNote: (text) {
          verify();
          return support.internalNote(task.sourceId, text);
        },
        onStatus: (status) async {
          verify();
          await support.setStatus(task.sourceId, status);
        },
        onDealResolution: details.summary.targetType == 'broker_deal_outcome'
            ? (decision, note) {
                verify();
                return broker.resolveSupport(task.id, decision, note,
                    actingAsAgent: widget.actingAsAgent);
              }
            : null,
      ),
    );
  }

  Future<void> _manage(SupportTaskItem task, bool manager) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Wrap(
            children: [
              ListTile(
                leading: const EbrokerIcon(Icons.history_outlined),
                title: const Text('سجل المهمة'),
                onTap: () => Navigator.pop(sheetContext, 'history'),
              ),
              if (manager && !task.isClosed)
                ListTile(
                  leading: const EbrokerIcon(Icons.person_add_alt_1_outlined),
                  title: Text(task.assignedToUserId == null
                      ? 'إسناد لموظف'
                      : 'إعادة الإسناد'),
                  onTap: () => Navigator.pop(sheetContext, 'assign'),
                ),
              if (manager && ref.read(authControllerProvider).asData?.value?.roles.contains('support_manager') == true)
                ListTile(
                  leading: const EbrokerIcon(Icons.chat_bubble_outline),
                  title: const Text('إرسال المهمة للمدير العام'),
                  onTap: () => Navigator.pop(sheetContext, 'executive'),
                ),
              if (manager)
                ListTile(
                  leading: const EbrokerIcon(Icons.flag_outlined),
                title: const Text('تصنيف المهمة'),
                  onTap: () => Navigator.pop(sheetContext, 'classify'),
                ),
              if (!manager &&
                  task.isMine &&
                  !task.isClosed &&
                  task.status != 'escalated')
                ListTile(
                  leading: const EbrokerIcon(Icons.trending_up),
                  title: const Text('تصعيد لمدير الدعم'),
                  subtitle: const Text(
                      'للحالات غير الاعتيادية فقط، وليس للموافقة اليومية.'),
                  onTap: () => Navigator.pop(sheetContext, 'escalate'),
                ),
              if (manager && task.status == 'escalated')
                ListTile(
                  leading: const EbrokerIcon(Icons.check_circle_outline),
                  title: const Text('معالجة التصعيد وإعادته للموظف'),
                  onTap: () =>
                      Navigator.pop(sheetContext, 'resolve_escalation'),
                ),
              if (manager && task.assignedToUserId != null && !task.isClosed)
                ListTile(
                  leading: const EbrokerIcon(Icons.move_to_inbox_outlined),
                  title: const Text('إعادة إلى الوارد'),
                  onTap: () => Navigator.pop(sheetContext, 'release'),
                ),
              if (manager &&
                  task.isClosed &&
                  (task.sourceType == 'support_ticket' ||
                      task.sourceType == 'report'))
                ListTile(
                  leading: const EbrokerIcon(Icons.restart_alt),
                  title: const Text('إعادة فتح المهمة'),
                  onTap: () => Navigator.pop(sheetContext, 'reopen'),
                ),
              if (!task.isClosed &&
                  (task.sourceType == 'support_ticket' ||
                      task.sourceType == 'report') &&
                  task.isMine)
                ListTile(
                  leading: EbrokerIcon(task.status == 'waiting_internal'
                      ? Icons.play_arrow_outlined
                      : Icons.pause_circle_outline),
                  title: Text(task.status == 'waiting_internal'
                      ? 'استئناف العمل'
                      : 'تحويل إلى انتظار داخلي'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    task.status == 'waiting_internal'
                        ? 'resume'
                        : 'waiting_internal',
                  ),
                ),
              if (task.sourceType == 'account_verification' &&
                  !task.isClosed &&
                  task.isMine)
                ListTile(
                  leading: const EbrokerIcon(Icons.upload_file_outlined),
                  title: const Text('طلب مستند إضافي'),
                  onTap: () => Navigator.pop(sheetContext, 'documents'),
                ),
              if (task.sourceType == 'account_verification' &&
                  !task.isClosed &&
                  task.isMine)
                ListTile(
                  leading: const EbrokerIcon(Icons.block_outlined),
                  title: const Text('رفض طلب التحقق'),
                  onTap: () => Navigator.pop(sheetContext, 'reject'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'executive':
          final scope = ref.read(accountRequestScopeProvider);
          final thread = await ref.read(supportWorkspaceRepositoryProvider).openStaffThread(teamId: task.supportTeamId);
          if (mounted && scope.isCurrent) {
            await context.push<void>('/support/internal/${thread.id}?task=${task.id}');
          }
          break;
        case 'history':
          await _showTaskHistory(task);
          break;
        case 'assign':
          await _assign(task);
          break;
        case 'classify':
          await _classify(task);
          break;
        case 'escalate':
          final reason = await _textDialog(
              'سبب التصعيد', 'وضح لماذا تحتاج هذه الحالة تدخل مدير الدعم.');
          if (reason != null) {
            await ref.read(supportWorkspaceRepositoryProvider).escalate(
                  task.id,
                  reason,
                  actingAsAgent: widget.actingAsAgent,
                );
            _message('تم تصعيد المهمة إلى مدير الدعم.');
          }
          break;
        case 'resolve_escalation':
          final note = await _textDialog(
              'قرار التصعيد', 'اكتب القرار أو التوجيه الذي سيعود للموظف.');
          if (note != null) {
            await ref
                .read(supportWorkspaceRepositoryProvider)
                .resolveEscalation(task.id, note);
            _message('تمت معالجة التصعيد وإعادة المهمة لمسار التنفيذ.');
          }
          break;
        case 'release':
          await ref.read(supportWorkspaceRepositoryProvider).release(task.id);
          _message('تمت إعادة المهمة إلى الوارد المشترك.');
          break;
        case 'reopen':
          await ref.read(supportWorkspaceRepositoryProvider).reopen(task.id);
          _message('تمت إعادة فتح المهمة.');
          break;
        case 'waiting_internal':
          await ref
              .read(supportWorkspaceRepositoryProvider)
              .setOperationalStatus(task.id, 'waiting_internal',
                  actingAsAgent: widget.actingAsAgent);
          _message('تم تحويل المهمة إلى انتظار داخلي.');
          break;
        case 'resume':
          await ref
              .read(supportWorkspaceRepositoryProvider)
              .setOperationalStatus(task.id, 'in_progress',
                  actingAsAgent: widget.actingAsAgent);
          _message('تم استئناف العمل على المهمة.');
          break;
        case 'documents':
          final note = await _textDialog(
              'المستند المطلوب', 'اكتب بوضوح ما المستند الإضافي المطلوب.');
          if (note != null) {
            await ref.read(supportWorkspaceRepositoryProvider).requestDocuments(
                task.id, note,
                actingAsAgent: widget.actingAsAgent);
            _message('تم طلب المستند وتحويل الحالة إلى انتظار المستخدم.');
          }
          break;
        case 'reject':
          final reason =
              await _textDialog('سبب الرفض', 'اكتب سبب رفض طلب التحقق.');
          if (reason != null) {
            await ref
                .read(supportWorkspaceRepositoryProvider)
                .rejectVerification(task.id, reason,
                    actingAsAgent: widget.actingAsAgent);
            _message('تم رفض طلب التحقق مع تسجيل السبب.');
          }
          break;
      }
      await _load();
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  Future<void> _showTaskHistory(SupportTaskItem task) async {
    List<SupportTaskEventItem> events;
    try {
      events = await ref
          .read(supportWorkspaceRepositoryProvider)
          .taskEvents(task.id);
    } catch (error) {
      _message(friendlyApiError(error));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('سجل المهمة'),
        content: SizedBox(
          width: 560,
          child: events.isEmpty
              ? const Text('لا توجد إجراءات مسجلة بعد.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, index) {
                    final event = events[index];
                    final status = event.toStatus == null
                        ? ''
                        : ' • ${_statusLabel(event.toStatus)}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                          child: EbrokerIcon(Icons.history, size: 18)),
                      title: Text(_eventLabel(event.event)),
                      subtitle: Text(
                        '${event.actorName ?? 'النظام'}$status${event.createdAt == null ? '' : ' • ${_timeAgo(event.createdAt!)}'}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(SupportTaskItem task) async {
    final repo = ref.read(supportWorkspaceRepositoryProvider);
    final scope = ref.read(accountRequestScopeProvider);
    try {
      final team = (await repo.team()).where((member) => member.role == 'support_agent'
          && member.teamId == task.supportTeamId && member.isAvailable
          && (member.openTasks < member.capacity || member.id == task.assignedToUserId)).toList();
      if (!mounted || !scope.isCurrent) return;
      if (team.isEmpty) { _message('ما فيه موظف متاح لاستلام هذه المهمة الآن.'); return; }
      int? selection;
      final userId = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (context) =>
        StatefulBuilder(builder: (context, update) => Scaffold(
          appBar: const AppAppBar(title: 'إسناد المهمة'),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: ListTile(title: Text(task.subject), subtitle: Text(_statusLabel(task.status)))),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('اختر موظفًا')),
            for (final member in team)
              Card(child: RadioListTile<int>(
                value: member.id, groupValue: selection,
                title: Text(member.name),
                subtitle: Text('متاح · ${member.openTasks} من ${member.capacity} مهام'),
                onChanged: (value) => update(() => selection = value),
              )),
          ]),
          bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
            child: AppButton(label: 'تأكيد الإسناد', expand: true,
              onPressed: selection == null ? null : () => Navigator.pop(context, selection)))),
        )),
      ));
      if (userId == null || !mounted || !scope.isCurrent) return;
      await repo.assign(task.id, userId);
      if (!mounted || !scope.isCurrent) return;
      _message('تم إسناد المهمة.');
      ref.read(supportWorkspaceRevisionProvider.notifier).state++;
      await _load();
    } catch (error) {
      if (mounted && scope.isCurrent) _message(friendlyApiError(error));
    }
  }

  Future<void> _classify(SupportTaskItem task, {bool categoryOnly = false}) async {
    final scope = ref.read(accountRequestScopeProvider);
    String priority = task.priority;
    String? severity = task.severity;
    const caseCategories = ['support_ticket', 'support_question', 'report'];
    final caseTask = caseCategories.contains(task.sourceType);
    var category = caseCategories.contains(task.category) ? task.category : task.sourceType;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('تصنيف المهمة'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caseTask) DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'نوع المهمة'),
                items: [
                  for (final value in caseCategories)
                    DropdownMenuItem(value: value, child: Text(_typeLabel(value))),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => category = value);
                },
              ),
              if (!categoryOnly && caseTask) const SizedBox(height: 12),
              if (!categoryOnly) DropdownButtonFormField<String>(
                value: priority,
                decoration: const InputDecoration(labelText: 'الأولوية'),
                items: const [
                  DropdownMenuItem(value: 'urgent', child: Text('عاجل')),
                  DropdownMenuItem(value: 'normal', child: Text('عادي')),
                  DropdownMenuItem(value: 'low', child: Text('منخفض')),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => priority = value);
                },
              ),
              if (!categoryOnly && task.sourceType == 'report') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: severity ?? 'medium',
                  decoration: const InputDecoration(labelText: 'خطورة البلاغ'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('منخفض')),
                    DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                    DropdownMenuItem(value: 'high', child: Text('عالي')),
                    DropdownMenuItem(value: 'critical', child: Text('حرج')),
                  ],
                  onChanged: (value) => setLocal(() => severity = value),
                ),
              ],
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            EbrokerFilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted || !scope.isCurrent) return;
    await ref.read(supportWorkspaceRepositoryProvider).classify(
          task.id,
          priority: priority,
          severity: task.sourceType == 'report' ? severity : null,
          category: caseTask ? category : null,
          actingAsAgent: widget.actingAsAgent,
        );
    if (scope.isCurrent) _message('تم تحديث التصنيف.');
  }

  Future<String?> _textDialog(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          EbrokerFilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length >= 3) Navigator.pop(dialogContext, text);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.task, required this.manager,
    required this.onClaim, required this.onAssign, required this.onOpen, this.onManage});

  final SupportTaskItem task;
  final bool manager;
  final VoidCallback onClaim, onAssign, onOpen;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = task.category ?? task.sourceType;
    final type = _taskTypeLabel(task);
    final source = task.sourceType;
    final duplicate = source == 'listing_review' && !task.isClosed
      ? ListingDuplicateDetection.fromJson(task.metadata) : null;
    final overdue = !task.isClosed && (task.claimedAt == null ? task.isUnreceivedOverdue : task.isOverdue);
    final canAssign = manager && task.assignedToUserId == null && !task.isClosed && task.status != 'escalated';
    final subtitle = [if (!task.subject.startsWith(type)) type,
        if ((manager ? task.assignedToName : task.requesterName) case final name?) name,
        if (task.governorateName case final governorate?) governorate].join(' · ');
    final label = task.isClosed ? 'التفاصيل' : canAssign ? 'إسناد' :
      manager && task.status == 'escalated' ? 'مراجعة' : task.canClaim && !manager ? 'استلم' : 'فتح';
    final action = canAssign ? onAssign : task.canClaim && !manager ? onClaim
      : task.isClosed && !task.isMine ? onManage ?? onOpen : onOpen;
    final title = task.subject == 'Conversation complaint' ? 'بلاغ عن محادثة' : task.subject;
    final price = task.metadata['amount'];
    final currency = task.metadata['currency'];
    final status = task.isClosed ? _taskResultLabel(task)
      : overdue ? (task.claimedAt == null ? 'تأخر الاستلام' : 'تأخر المعالجة')
      : task.status == 'escalated' ? 'مصعّد إليك' : _statusLabel(task.status);

    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 17, backgroundColor: scheme.primaryContainer,
            child: EbrokerIcon(_typeIcon(category), size: 18, color: scheme.onPrimaryContainer)),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty)
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ])),
          if (onManage != null && !task.canClaim)
            IconButton(icon: const Icon(Icons.more_vert, size: 18), tooltip: 'خيارات المهمة', onPressed: onManage),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (duplicate != null) Text(duplicate.source == ListingDuplicateSource.ai ? 'تشابه رصده المساعد' : 'اشتباه تكرار',
                style: TextStyle(fontSize: 12, color: scheme.primary)),
              if (source == 'payment_review' && price is num && currency is String)
                Text(moneyLabel(price.toDouble(), currency), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (manager || task.isClosed || overdue || task.status != 'new')
                Text(status, style: TextStyle(fontSize: 12, color: overdue ? scheme.error : scheme.onSurfaceVariant)),
            ],
          )),
          EbrokerFilledButton(onPressed: action, child: Text(label)),
        ]),
      ]),
    ));
  }
}

class _SupportCaseDialog extends StatefulWidget {
  const _SupportCaseDialog({
    required this.details,
    required this.onReply,
    required this.onInternalNote,
    required this.onStatus,
    this.onDealResolution,
    required this.onSuggest,
    this.onClassify,
  });

  final SupportCaseDetails details;
  final Future<SupportCaseDetails> Function(String) onReply;
  final Future<SupportCaseDetails> Function(String) onInternalNote;
  final Future<void> Function(String) onStatus;
  final Future<void> Function(String, String)? onDealResolution;
  final Future<Map<String, dynamic>> Function() onSuggest;
  final Future<void> Function()? onClassify;

  @override
  State<_SupportCaseDialog> createState() => _SupportCaseDialogState();
}

class _SupportCaseDialogState extends State<_SupportCaseDialog> {
  late SupportCaseDetails _details = widget.details;
  bool _busy = false;
  final _statusMenuKey = GlobalKey<PopupMenuButtonState<String>>();

  bool get _linkedCustomerCase =>
      _details.summary.reasonCode == 'external_listing_closure' ||
      _details.summary.reasonCode == 'deal_price_confirmation';

  String? _amount(String key, String currencyKey) {
    final amount = _details.targetPreview?[key];
    final currency = _details.targetPreview?[currencyKey];
    return amount != null && currency is String ? moneyLabel(amount, currency) : null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    final dealStatus = d.targetPreview?['status'];
    final canResolve = widget.onDealResolution != null && !d.summary.isClosed;
    final canApprove = canResolve &&
        d.summary.reasonCode == 'deal_price_confirmation' &&
        dealStatus == 'pending_customer';
    final canRetry = canResolve &&
        (dealStatus == 'disputed' ||
            (dealStatus == null && d.summary.status != 'waiting_requester'));
    final title = d.targetPreview?['title'];
    final listingPrice = _amount('listing_price', 'listing_currency');
    final reportedAmount = _amount('basis_amount', 'currency');
    final isRent = d.targetPreview?['transaction_type'] == 'rent';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
          child: Column(
            children: [
              ListTile(
                title: Text(d.summary.subject,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${d.summary.reference} • ${d.requesterName ?? 'مستخدم'}'),
                trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const EbrokerIcon(Icons.close)),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(d.description),
                    if (title is String && (_linkedCustomerCase || widget.onDealResolution != null))
                      Text('الإعلان · $title'),
                    if (listingPrice != null)
                      Text('${isRent ? 'الإيجار الشهري في الإعلان' : 'السعر في الإعلان'} · $listingPrice'),
                    if (reportedAmount != null)
                      Text('${dealStatus == 'confirmed' ? 'المبلغ المعتمد' : 'المبلغ الذي أبلغ به الدلال'} · $reportedAmount'),
                    const SizedBox(height: 14),
                    ...d.messages.map(
                      (m) => Card(
                        color: m.isInternal ? Theme.of(context).extension<AppSemanticColors>()!.warningContainer : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.actorName ?? m.actorRole,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(m.body, style: m.isInternal ? TextStyle(color: Theme.of(context).extension<AppSemanticColors>()!.onWarningContainer) : null),
                              for (final attachment in m.attachments)
                                SupportAttachmentButton(caseId: d.summary.id, file: attachment, staff: true),
                              if (m.isInternal)
                                Text('ملاحظة داخلية',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (widget.onClassify != null && !d.summary.isClosed)
                      TextButton.icon(
                        onPressed: _busy ? null : _classify,
                        icon: const EbrokerIcon(Icons.category_outlined),
                        label: const Text('تصنيف المهمة'),
                      ),
                    if (!_linkedCustomerCase || !d.summary.isClosed)
                      EbrokerFilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _compose(false),
                        icon: const EbrokerIcon(Icons.reply),
                        label: Text(_linkedCustomerCase ? 'مراسلة العميل' : 'رد'),
                      ),
                    if (canApprove)
                      EbrokerFilledButton(
                        onPressed: _busy ? null : () => _resolveBroker('approve'),
                        child: const Text('اعتماد المبلغ'),
                      ),
                    if (canRetry)
                      EbrokerFilledButton(
                        onPressed: _busy ? null : () => _resolveBroker('retry'),
                        child: const Text('طلب تأكيد العميل مجددًا'),
                      ),
                    if (canApprove || canRetry)
                      EbrokerOutlinedButton(
                        onPressed: _busy ? null : () => _resolveBroker('cancel'),
                        child: const Text('إلغاء نتيجة الصفقة'),
                      ),
                    if (!d.summary.isClosed)
                      EbrokerOutlinedButton.icon(
                        onPressed: _busy ? null : _suggest,
                        icon: const EbrokerIcon(Icons.auto_awesome_outlined),
                        label: const Text('اقتراح رد'),
                      ),
                    EbrokerOutlinedButton.icon(
                      onPressed: _busy ? null : () => _compose(true),
                      icon: const EbrokerIcon(Icons.note_alt_outlined),
                      label: Text('ملاحظة داخلية'),
                    ),
                    PopupMenuButton<String>(
                      key: _statusMenuKey,
                      tooltip: 'تغيير الحالة',
                      enabled: !_busy,
                      onSelected: _setStatus,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'in_progress', child: Text('قيد المعالجة')),
                        const PopupMenuItem(
                            value: 'waiting_requester',
                            child: Text('انتظار المستخدم')),
                        if (widget.onDealResolution == null) const PopupMenuItem(
                            value: 'resolved', child: Text('إغلاق كمحلولة')),
                        if (widget.onDealResolution == null) const PopupMenuItem(
                            value: 'dismissed', child: Text('رفض / إغلاق')),
                      ],
                      child: EbrokerOutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _statusMenuKey.currentState?.showButtonMenu(),
                        icon: const EbrokerIcon(Icons.sync_alt, size: 18),
                        label: const Text('تغيير الحالة'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _suggest() async {
    setState(() => _busy = true);
    try {
      final data = await widget.onSuggest();
      if (!mounted) return;
      final summary = data['summary']?.toString().trim() ?? '';
      final reply = data['reply']?.toString().trim() ?? '';
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        scrollable: true, title: const Text('ملخص الطلب'),
        content: Text(summary),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إغلاق')),
          if (reply.isNotEmpty)
            FilledButton(onPressed: () {
              Navigator.pop(dialog);
              _compose(false, initial: reply);
            }, child: const Text('مراجعة الرد المقترح')),
        ],
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose(bool internal, {String initial = ''}) async {
    String draft = initial;
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(internal ? 'ملاحظة داخلية' : _linkedCustomerCase ? 'مراسلة العميل' : 'رد على المستخدم'),
        content: TextFormField(initialValue: initial, onChanged: (value) => draft = value, minLines: 3, maxLines: 6),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          EbrokerFilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = internal
          ? await widget.onInternalNote(text)
          : await widget.onReply(text);
      if (!mounted) return;
      if (_linkedCustomerCase) {
        setState(() => _details = updated);
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _classify() async {
    try {
      await widget.onClassify?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }

  Future<void> _resolveBroker(String decision) async {
    String note = '';
    final form = GlobalKey<FormState>();
    final title = switch (decision) {
      'approve' => 'اعتماد المبلغ',
      'retry' => 'طلب تأكيد النتيجة',
      _ => 'إلغاء النتيجة',
    };
    final reportedAmount = _amount('basis_amount', 'currency');
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (decision == 'approve' && reportedAmount != null) ...[
          Text('اعتماد المبلغ المبلّغ عنه · $reportedAmount'),
          const SizedBox(height: 8),
        ],
        TextFormField(onChanged: (text) => note = text, minLines: 2, maxLines: 4,
          validator: (text) => (text?.trim().length ?? 0) < 5 ? 'اكتب سبب القرار.' : null,
          decoration: const InputDecoration(labelText: 'سبب القرار')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('رجوع')),
        EbrokerFilledButton(onPressed: () { if (form.currentState?.validate() == true) Navigator.pop(c, true); }, child: const Text('حفظ القرار'))]));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try { await widget.onDealResolution!(decision, note.trim()); if (mounted) Navigator.pop(context); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await widget.onStatus(status);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _taskTypeLabel(SupportTaskItem task) {
  if (task.sourceType == 'account_verification') {
    final kind = task.metadata['verification_type']?.toString();
    return switch (kind) {
      'owner' => 'تحقق حساب مالك',
      'broker' => 'تحقق حساب دلال',
      'office' => 'تحقق حساب مكتب عقارات',
      _ => 'تحقق حساب',
    };
  }
  if (task.sourceType == 'listing_review') return 'تحقق نشر إعلان';
  return _typeLabel(task.category ?? task.sourceType);
}

String _taskResultLabel(SupportTaskItem task) {
  final resolution = task.metadata['resolution']?.toString();
  return switch (resolution) {
    'approved' =>
      task.sourceType == 'listing_review' ? 'تم القبول والنشر' : 'تم القبول',
    'returned_for_correction' => 'أُعيد للمراجعة والتصحيح',
    'rejected_duplicate' => 'رُفض الإعلان لتكراره',
    'rejected' => 'تم الرفض',
    'resolved' => 'تم الحل والإغلاق',
    'dismissed' => 'تم الرفض والإغلاق',
    'documents_requested' => 'طُلبت مستندات إضافية',
    _ => task.status == 'rejected' ? 'مرفوض' : 'منجز',
  };
}

const _taskCategories = [
  'listing_review',
  'support_ticket',
  'support_question',
  'report',
  'payment_review',
];

String _typeLabel(String value) => switch (value) {
      'account_verification' => 'تحقق حساب',
      'listing_review' => 'تحقق إعلان',
      'support_ticket' => 'تذكرة',
      'support_question' => 'سؤال للدعم',
      'report' => 'بلاغ',
      'payment_review' => 'متابعة مالية',
      _ => value,
    };

IconData _typeIcon(String value) => switch (value) {
      'account_verification' => Icons.verified_user_outlined,
      'listing_review' => Icons.fact_check_outlined,
      'support_ticket' => Icons.support_agent_outlined,
      'report' => Icons.report_gmailerrorred_outlined,
      'payment_review' => Icons.payments_outlined,
      _ => Icons.task_alt,
    };

String _statusLabel(String? value) => switch (value) {
      null => 'كل الحالات',
      'new' => 'جديد',
      'in_progress' => 'قيد العمل',
      'waiting_user' => 'انتظار المستخدم',
      'waiting_internal' => 'انتظار داخلي',
      'needs_followup' => 'يحتاج متابعة',
      'escalated' => 'مصعّد',
      'completed' => 'مكتمل',
      'rejected' => 'مرفوض',
      _ => value,
    };

String _eventLabel(String value) => switch (value) {
      'created_from_source' => 'إنشاء المهمة',
      'claimed' => 'استلام المهمة',
      'assigned' => 'إسناد / إعادة إسناد',
      'classification_changed' => 'تحديث تصنيف المهمة',
      'operational_status_changed' => 'تحديث الحالة التشغيلية',
      'documents_requested' => 'طلب مستند إضافي',
      'verification_rejected' => 'رفض طلب التحقق',
      'escalated' => 'تصعيد المهمة',
      'reopened' => 'إعادة فتح المهمة',
      'source_status_synced' => 'تحديث من المصدر',
      _ => value,
    };

String _timeAgo(DateTime value) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.isNegative) return 'الآن';
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
  return 'منذ ${diff.inDays} ي';
}
