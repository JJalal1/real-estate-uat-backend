import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../financial/data/financial_repository.dart';
import '../../financial/domain/financial_models.dart';
import '../data/support_repository.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_models.dart';
import '../domain/support_workspace_models.dart';
import 'account_verification_support_screen.dart';

class SupportTasksScreen extends ConsumerStatefulWidget {
  const SupportTasksScreen({
    super.key,
    this.initialScope = 'inbox',
    this.initialType,
    this.initialStatus,
    this.initialSeverity,
    this.overdueOnly = false,
    this.actingAsAgent = false,
    this.title,
  });

  final String initialScope;
  final String? initialType;
  final String? initialStatus;
  final String? initialSeverity;
  final bool overdueOnly;
  final bool actingAsAgent;
  final String? title;

  @override
  ConsumerState<SupportTasksScreen> createState() => _SupportTasksScreenState();
}

class _SupportTasksScreenState extends ConsumerState<SupportTasksScreen> {
  bool _loading = true;
  String? _error;
  List<SupportTaskItem> _items = const [];
  late String _scope;
  String? _type;
  String? _status;
  String? _priority;
  String? _severity;
  DateTime? _createdFrom;
  DateTime? _createdTo;
  int? _assigneeId;
  String? _assigneeName;
  late bool _overdue;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _type = widget.initialType;
    _status = widget.initialStatus;
    _severity = widget.initialSeverity;
    _overdue = widget.overdueOnly;
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(supportWorkspaceRepositoryProvider).tasks(
            scope: _scope,
            type: _type,
            status: _status,
            priority: _priority,
            severity: _severity,
            assigneeId: _assigneeId,
            createdFrom: _createdFrom,
            createdTo: _createdTo,
            overdue: _overdue,
            actingAsAgent: widget.actingAsAgent,
          );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final manager = user?.isPlatformOwner == true ||
        user?.roles.contains('super_admin') == true ||
        user?.roles.contains('support_manager') == true ||
        user?.hasPermission('support.manage') == true;
    final managerMode = manager && !widget.actingAsAgent;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? _defaultTitle()),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.actingAsAgent)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.support_agent_outlined),
                  title: Text('أنت الآن تعمل كموظف دعم',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      'استلم الطلب أولاً ثم عالجه بنفس قواعد موظفي الدعم. الرجوع يغلق هذا الوضع.'),
                ),
              ),
            _filters(managerMode),
            Expanded(child: _body(managerMode)),
          ],
        ),
      ),
    );
  }

  String _defaultTitle() {
    if (_scope == 'mine') return 'مهامي';
    if (_scope == 'completed') return 'المهام المنجزة';
    if (_scope == 'all') return 'كل الأعمال';
    return 'الوارد الجديد';
  }

  Widget _filters(bool manager) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          children: [
            if (manager || widget.actingAsAgent)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: widget.actingAsAgent
                      ? const [
                          ButtonSegment(value: 'inbox', label: Text('الوارد')),
                          ButtonSegment(value: 'mine', label: Text('مهامي')),
                          ButtonSegment(
                              value: 'completed', label: Text('المنجزة')),
                        ]
                      : const [
                          ButtonSegment(
                              value: 'inbox', label: Text('غير مسند')),
                          ButtonSegment(value: 'mine', label: Text('مسند لي')),
                          ButtonSegment(
                              value: 'completed', label: Text('المنجزة')),
                          ButtonSegment(
                              value: 'all', label: Text('كل الأعمال')),
                        ],
                  selected: {_scope},
                  onSelectionChanged: (value) {
                    setState(() => _scope = value.first);
                    _load();
                  },
                ),
              ),
            if (manager || widget.actingAsAgent) const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _choice('الكل', _type == null, () => _setType(null)),
                  _choice('تحقق حسابات', _type == 'account_verification',
                      () => _setType('account_verification')),
                  _choice('تحقيق إعلانات', _type == 'listing_review',
                      () => _setType('listing_review')),
                  _choice('تذاكر', _type == 'support_ticket',
                      () => _setType('support_ticket')),
                  _choice(
                      'بلاغات', _type == 'report', () => _setType('report')),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterMenu(),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('متأخر فقط'),
                    avatar: const Icon(Icons.timer_off_outlined, size: 18),
                    selected: _overdue,
                    onSelected: (value) {
                      setState(() => _overdue = value);
                      _load();
                    },
                  ),
                  if (manager) ...[
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar:
                          const Icon(Icons.support_agent_outlined, size: 18),
                      label: Text(_assigneeName ?? 'الموظف'),
                      onPressed: _pickAssignee,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(_dateFilterLabel()),
                      onPressed: _pickDateRange,
                    ),
                  ],
                  if (_type != null ||
                      _status != null ||
                      _priority != null ||
                      _severity != null ||
                      _createdFrom != null ||
                      _createdTo != null ||
                      _assigneeId != null ||
                      _overdue)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _type = null;
                          _status = null;
                          _priority = null;
                          _severity = null;
                          _createdFrom = null;
                          _createdTo = null;
                          _assigneeId = null;
                          _assigneeName = null;
                          _overdue = false;
                        });
                        _load();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('مسح'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _filterMenu() => PopupMenuButton<String>(
        tooltip: 'الحالة والأولوية',
        onSelected: (value) {
          setState(() {
            if (value.startsWith('status:')) {
              final selected = value.substring(7);
              _status = selected == 'all' ? null : selected;
            } else if (value.startsWith('priority:')) {
              final selected = value.substring(9);
              _priority = selected == 'all' ? null : selected;
            } else if (value.startsWith('severity:')) {
              final selected = value.substring(9);
              _severity = selected == 'all' ? null : selected;
            }
          });
          _load();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'status:all', child: Text('كل الحالات')),
          PopupMenuItem(value: 'status:new', child: Text('جديد')),
          PopupMenuItem(value: 'status:in_progress', child: Text('قيد العمل')),
          PopupMenuItem(
              value: 'status:waiting_user', child: Text('انتظار المستخدم')),
          PopupMenuItem(
              value: 'status:waiting_internal', child: Text('انتظار داخلي')),
          PopupMenuItem(
              value: 'status:needs_followup', child: Text('يحتاج متابعة')),
          PopupMenuItem(value: 'status:escalated', child: Text('مصعّد')),
          PopupMenuItem(value: 'status:completed', child: Text('مكتمل')),
          PopupMenuItem(value: 'status:rejected', child: Text('مرفوض')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'priority:all', child: Text('كل الأولويات')),
          PopupMenuItem(value: 'priority:urgent', child: Text('عاجل')),
          PopupMenuItem(value: 'priority:normal', child: Text('عادي')),
          PopupMenuItem(value: 'priority:low', child: Text('منخفض')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'severity:all', child: Text('كل درجات الخطورة')),
          PopupMenuItem(value: 'severity:critical', child: Text('حرج')),
          PopupMenuItem(value: 'severity:high', child: Text('عالي')),
          PopupMenuItem(value: 'severity:medium', child: Text('متوسط')),
          PopupMenuItem(value: 'severity:low', child: Text('منخفض الخطورة')),
        ],
        child: Chip(
          avatar: const Icon(Icons.tune, size: 18),
          label: Text(_status == null && _priority == null && _severity == null
              ? 'الحالة والأولوية'
              : '${_statusLabel(_status)} • ${_priorityLabel(_priority)}${_severity == null ? '' : ' • ${_severityLabel(_severity!)}'}'),
        ),
      );

  Future<void> _pickAssignee() async {
    List<SupportTeamMember> team;
    try {
      team = await ref.read(supportWorkspaceRepositoryProvider).team();
    } catch (error) {
      _message(friendlyApiError(error));
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<SupportTeamMember>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فلترة حسب الموظف'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('كل الموظفين'),
                onTap: () => Navigator.pop(dialogContext),
              ),
              ...team.map(
                (member) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.support_agent)),
                  title: Text(member.name),
                  subtitle: Text(member.role == 'support_manager'
                      ? 'مدير دعم'
                      : 'موظف دعم'),
                  onTap: () => Navigator.pop(dialogContext, member),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _assigneeId = selected?.id;
      _assigneeName = selected?.name;
    });
    await _load();
  }

  String _dateFilterLabel() {
    if (_createdFrom == null || _createdTo == null) return 'التاريخ';
    String d(DateTime value) => '${value.year}/${value.month}/${value.day}';
    return '${d(_createdFrom!)} - ${d(_createdTo!)}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _createdFrom != null && _createdTo != null
          ? DateTimeRange(start: _createdFrom!, end: _createdTo!)
          : null,
      helpText: 'فلترة الأعمال حسب التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );
    if (range == null || !mounted) return;
    setState(() {
      _createdFrom = range.start;
      _createdTo = range.end;
    });
    await _load();
  }

  void _setType(String? value) {
    setState(() => _type = value);
    _load();
  }

  Widget _body(bool manager) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Icon(Icons.inbox_outlined, size: 58, color: AppTheme.textMuted),
            SizedBox(height: 14),
            Center(child: Text('لا توجد مهام مطابقة لهذه الفلاتر.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) => _TaskCard(
          task: _items[index],
          manager: manager,
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
    try {
      final claimed = await ref.read(supportWorkspaceRepositoryProvider).claim(
            task.id,
            actingAsAgent: widget.actingAsAgent,
          );
      _message('تم استلام المهمة وإضافتها إلى مهامك.');
      await _load();
      if (mounted) await _open(claimed, false);
    } catch (error) {
      _message(friendlyApiError(error));
      await _load();
    }
  }

  Future<void> _open(SupportTaskItem task, bool manager) async {
    if (manager && !widget.actingAsAgent && task.status != 'escalated') {
      _message(
          'هذه شاشة إدارة العمل. لمعالجة الطلب بنفسك استخدم «العمل كموظف دعم» واستلمه أولاً.');
      return;
    }
    if ((!manager || widget.actingAsAgent) && !task.isMine) {
      _message('استلم المهمة أولاً قبل فتح بياناتها الخاصة.');
      return;
    }
    switch (task.sourceType) {
      case 'account_verification':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountVerificationSupportScreen(
              focusUserId: task.sourceId,
            ),
          ),
        );
        break;
      case 'listing_review':
        context.push('/admin/listing-review');
        break;
      case 'support_ticket':
      case 'report':
        await _supportCaseDialog(task);
        break;
      case 'payment_review':
        await _paymentReviewDialog(task);
        break;
    }
    if (mounted) await _load();
  }

  Future<void> _paymentReviewDialog(SupportTaskItem task) async {
    FinancialPayment payment;
    try {
      payment = await ref.read(financialRepositoryProvider).adminPayment(
            task.sourceId,
            actingAsAgent: widget.actingAsAgent,
          );
    } catch (error) {
      _message(friendlyApiError(error));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('التحقق من إثبات الدفع'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.propertyTitle ?? 'العقار',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                    'المبلغ: ${payment.amount.toStringAsFixed(0)} ${payment.currency}'),
                Text('الطريقة: ${payment.paymentMethod ?? '—'}'),
                if (payment.senderName != null)
                  Text('اسم المرسل: ${payment.senderName}'),
                if (payment.senderPhone != null)
                  Text('رقم المرسل: ${payment.senderPhone}'),
                if (payment.providerReference != null)
                  Text('رقم العملية: ${payment.providerReference}'),
                const SizedBox(height: 12),
                if (payment.hasProof)
                  FutureBuilder<List<int>?>(
                    future: ref
                        .read(financialRepositoryProvider)
                        .paymentProof(
                          payment.id,
                          actingAsAgent: widget.actingAsAgent,
                        )
                        .then((response) => response.data),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final bytes = snapshot.data;
                      if (bytes == null || bytes.isEmpty) {
                        return const Text('تعذر عرض صورة الإثبات.');
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(Uint8List.fromList(bytes),
                            fit: BoxFit.contain),
                      );
                    },
                  )
                else
                  const Text('لا يوجد إثبات مرفوع.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق')),
          TextButton(
              onPressed: () async {
                final note = await _paymentReviewReason('طلب تصحيح الإثبات');
                if (note == null || !mounted) return;
                await _reviewPayment(task.sourceId, 'correction', note);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('طلب تصحيح')),
          TextButton(
              onPressed: () async {
                final note = await _paymentReviewReason('رفض الإثبات');
                if (note == null || !mounted) return;
                await _reviewPayment(task.sourceId, 'reject', note);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('رفض')),
          FilledButton(
              onPressed: () async {
                await _reviewPayment(task.sourceId, 'confirm', null);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('تأكيد الدفع')),
        ],
      ),
    );
  }

  Future<String?> _paymentReviewReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'السبب *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length >= 3) Navigator.pop(dialogContext, value);
              },
              child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _reviewPayment(
      int paymentId, String decision, String? note) async {
    try {
      await ref.read(financialRepositoryProvider).reviewPayment(
            paymentId,
            decision,
            note: note,
            actingAsAgent: widget.actingAsAgent,
          );
      _message(decision == 'confirm'
          ? 'تم تأكيد عملية الدفع.'
          : decision == 'correction'
              ? 'تم طلب تصحيح الإثبات.'
              : 'تم رفض الإثبات.');
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  Future<void> _supportCaseDialog(SupportTaskItem task) async {
    SupportCaseDetails details;
    try {
      details =
          await ref.read(supportRepositoryProvider).adminDetails(task.sourceId);
    } catch (error) {
      _message(friendlyApiError(error));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SupportCaseDialog(
        details: details,
        onReply: (text) async {
          await ref
              .read(supportRepositoryProvider)
              .adminReply(task.sourceId, text);
        },
        onInternalNote: (text) async {
          await ref
              .read(supportRepositoryProvider)
              .internalNote(task.sourceId, text);
        },
        onStatus: (status) async {
          await ref
              .read(supportRepositoryProvider)
              .setStatus(task.sourceId, status);
        },
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
                leading: const Icon(Icons.history_outlined),
                title: const Text('سجل المهمة'),
                onTap: () => Navigator.pop(sheetContext, 'history'),
              ),
              if (manager)
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: Text(task.assignedToUserId == null
                      ? 'إسناد لموظف'
                      : 'إعادة الإسناد'),
                  onTap: () => Navigator.pop(sheetContext, 'assign'),
                ),
              if (manager)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('الأولوية والخطورة'),
                  onTap: () => Navigator.pop(sheetContext, 'classify'),
                ),
              if (!manager &&
                  task.isMine &&
                  !task.isClosed &&
                  task.status != 'escalated')
                ListTile(
                  leading: const Icon(Icons.trending_up),
                  title: const Text('تصعيد لمدير الدعم'),
                  subtitle: const Text(
                      'للحالات غير الاعتيادية فقط، وليس للموافقة اليومية.'),
                  onTap: () => Navigator.pop(sheetContext, 'escalate'),
                ),
              if (manager && task.status == 'escalated')
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('معالجة التصعيد وإعادته للموظف'),
                  onTap: () =>
                      Navigator.pop(sheetContext, 'resolve_escalation'),
                ),
              if (manager && task.assignedToUserId != null && !task.isClosed)
                ListTile(
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: const Text('إعادة إلى الوارد'),
                  onTap: () => Navigator.pop(sheetContext, 'release'),
                ),
              if (manager &&
                  task.isClosed &&
                  (task.sourceType == 'support_ticket' ||
                      task.sourceType == 'report'))
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('إعادة فتح المهمة'),
                  onTap: () => Navigator.pop(sheetContext, 'reopen'),
                ),
              if (!task.isClosed &&
                  (task.sourceType == 'support_ticket' ||
                      task.sourceType == 'report') &&
                  task.isMine)
                ListTile(
                  leading: Icon(task.status == 'waiting_internal'
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
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('طلب مستند إضافي'),
                  onTap: () => Navigator.pop(sheetContext, 'documents'),
                ),
              if (task.sourceType == 'account_verification' &&
                  !task.isClosed &&
                  task.isMine)
                ListTile(
                  leading: const Icon(Icons.block_outlined),
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
                          child: Icon(Icons.history, size: 18)),
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
    final team = await ref.read(supportWorkspaceRepositoryProvider).team();
    if (!mounted) return;
    final userId = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            task.assignedToUserId == null ? 'إسناد المهمة' : 'إعادة الإسناد'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: team
                .map(
                  (member) => ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.support_agent)),
                    title: Text(member.name),
                    subtitle: Text(
                      '${member.openTasks} مفتوحة • ${member.overdueTasks} متأخرة',
                    ),
                    onTap: () => Navigator.pop(dialogContext, member.id),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (userId == null) return;
    await ref.read(supportWorkspaceRepositoryProvider).assign(task.id, userId);
    _message('تم تحديث إسناد المهمة.');
  }

  Future<void> _classify(SupportTaskItem task) async {
    String priority = task.priority;
    String? severity = task.severity;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('الأولوية والخطورة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
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
              if (task.sourceType == 'report') ...[
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await ref.read(supportWorkspaceRepositoryProvider).classify(
          task.id,
          priority: priority,
          severity: task.sourceType == 'report' ? severity : null,
        );
    _message('تم تحديث التصنيف.');
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
          FilledButton(
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
  const _TaskCard({
    required this.task,
    required this.manager,
    required this.onClaim,
    required this.onOpen,
    this.onManage,
  });

  final SupportTaskItem task;
  final bool manager;
  final VoidCallback onClaim;
  final VoidCallback onOpen;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: task.severity == 'critical' ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _typeColor(task.sourceType).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_typeIcon(task.sourceType),
                      color: _typeColor(task.sourceType)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${_taskTypeLabel(task)} • ${task.requesterName ?? 'مستخدم #${task.requesterUserId ?? task.sourceId}'}${task.supportTeamName == null ? '' : ' • ${task.supportTeamName}'}${task.governorateName == null ? '' : ' • ${task.governorateName}'}',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (onManage != null)
                  IconButton(
                    tooltip: 'إدارة المهمة',
                    onPressed: onManage,
                    icon: const Icon(Icons.more_vert),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatusPill(
                    label: _statusLabel(task.status),
                    kind: _statusKind(task.status)),
                if (task.isClosed)
                  _StatusPill(
                      label: _taskResultLabel(task),
                      kind: task.status == 'rejected' ? 2 : 1),
                _StatusPill(
                    label: _priorityLabel(task.priority),
                    kind: task.priority == 'urgent' ? 2 : 0),
                if (task.severity != null)
                  _StatusPill(
                      label: 'خطورة ${_severityLabel(task.severity!)}',
                      kind: task.severity == 'critical' ? 2 : 0),
                if (task.isOverdue) const _StatusPill(label: 'متأخر', kind: 2),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (task.createdAt != null)
                  Text('وصلت ${_timeAgo(task.createdAt!)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textMuted)),
                if (task.claimedAt != null)
                  Text('استلمت ${_timeAgo(task.claimedAt!)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textMuted)),
                if (task.completedAt != null)
                  Text('أُنجزت ${_timeAgo(task.completedAt!)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textMuted)),
                if (task.lastActivityAt != null && !task.isClosed)
                  Text('آخر تحديث ${_timeAgo(task.lastActivityAt!)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 18, color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    task.assignedToName == null
                        ? 'غير مسند'
                        : task.isMine
                            ? 'مستلم مني – ${task.assignedToName}'
                            : 'المسؤول: ${task.assignedToName}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                ),
                Text(
                  _slaText(task),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: task.isOverdue
                        ? Colors.red.shade700
                        : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (task.canClaim) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onClaim,
                      icon: const Icon(Icons.pan_tool_alt_outlined),
                      label: const Text('استلام'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: task.isClosed ? onManage : onOpen,
                    icon: Icon(task.isClosed
                        ? Icons.receipt_long_outlined
                        : Icons.open_in_new),
                    label: Text(task.isClosed
                        ? 'تفاصيل القرار'
                        : (task.canClaim && !manager ? 'بعد الاستلام' : 'فتح')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.kind});
  final String label;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final background = switch (kind) {
      1 => AppTheme.brandSoft,
      2 => Colors.red.shade50,
      3 => Colors.amber.shade50,
      _ => AppTheme.accentSoft,
    };
    final foreground = switch (kind) {
      1 => AppTheme.brandStrong,
      2 => Colors.red.shade800,
      3 => Colors.amber.shade900,
      _ => AppTheme.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: foreground)),
    );
  }
}

class _SupportCaseDialog extends StatefulWidget {
  const _SupportCaseDialog({
    required this.details,
    required this.onReply,
    required this.onInternalNote,
    required this.onStatus,
  });

  final SupportCaseDetails details;
  final Future<void> Function(String) onReply;
  final Future<void> Function(String) onInternalNote;
  final Future<void> Function(String) onStatus;

  @override
  State<_SupportCaseDialog> createState() => _SupportCaseDialogState();
}

class _SupportCaseDialogState extends State<_SupportCaseDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.details;
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
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(
                    '${d.summary.reference} • ${d.requesterName ?? 'مستخدم'}'),
                trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(d.description),
                    const SizedBox(height: 14),
                    ...d.messages.map(
                      (m) => Card(
                        color: m.isInternal ? Colors.amber.shade50 : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.actorName ?? m.actorRole,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(m.body),
                              if (m.isInternal)
                                const Text('ملاحظة داخلية',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted)),
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
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _compose(false),
                      icon: const Icon(Icons.reply),
                      label: const Text('رد'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _compose(true),
                      icon: const Icon(Icons.note_alt_outlined),
                      label: const Text('ملاحظة داخلية'),
                    ),
                    PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: _setStatus,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'in_progress', child: Text('قيد المعالجة')),
                        PopupMenuItem(
                            value: 'waiting_requester',
                            child: Text('انتظار المستخدم')),
                        PopupMenuItem(
                            value: 'resolved', child: Text('إغلاق كمحلولة')),
                        PopupMenuItem(
                            value: 'dismissed', child: Text('رفض / إغلاق')),
                      ],
                      child: const Chip(
                          label: Text('تغيير الحالة'),
                          avatar: Icon(Icons.sync_alt, size: 18)),
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

  Future<void> _compose(bool internal) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(internal ? 'ملاحظة داخلية' : 'رد على المستخدم'),
        content: TextField(controller: c, minLines: 3, maxLines: 6),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final value = c.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    c.dispose();
    if (text == null) return;
    setState(() => _busy = true);
    try {
      if (internal) {
        await widget.onInternalNote(text);
      } else {
        await widget.onReply(text);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
  return _typeLabel(task.sourceType);
}

String _taskResultLabel(SupportTaskItem task) {
  final resolution = task.metadata['resolution']?.toString();
  return switch (resolution) {
    'approved' =>
      task.sourceType == 'listing_review' ? 'تم القبول والنشر' : 'تم القبول',
    'returned_for_correction' => 'أُعيد للمراجعة والتصحيح',
    'rejected' => 'تم الرفض',
    'resolved' => 'تم الحل والإغلاق',
    'dismissed' => 'تم الرفض والإغلاق',
    'documents_requested' => 'طُلبت مستندات إضافية',
    _ => task.status == 'rejected' ? 'مرفوض' : 'منجز',
  };
}

String _typeLabel(String value) => switch (value) {
      'account_verification' => 'تحقق حساب',
      'listing_review' => 'تحقيق إعلان',
      'support_ticket' => 'تذكرة',
      'report' => 'بلاغ',
      _ => value,
    };

IconData _typeIcon(String value) => switch (value) {
      'account_verification' => Icons.verified_user_outlined,
      'listing_review' => Icons.fact_check_outlined,
      'support_ticket' => Icons.support_agent_outlined,
      'report' => Icons.report_gmailerrorred_outlined,
      _ => Icons.task_alt,
    };

Color _typeColor(String value) => switch (value) {
      'account_verification' => AppTheme.brand,
      'listing_review' => AppTheme.accent,
      'support_ticket' => Colors.deepPurple,
      'report' => Colors.deepOrange,
      _ => AppTheme.textMuted,
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

int _statusKind(String value) => switch (value) {
      'completed' => 1,
      'rejected' || 'escalated' => 2,
      'waiting_user' || 'waiting_internal' || 'needs_followup' => 3,
      _ => 0,
    };

String _priorityLabel(String? value) => switch (value) {
      null => 'كل الأولويات',
      'urgent' => 'عاجل',
      'normal' => 'عادي',
      'low' => 'منخفض',
      _ => value,
    };

String _severityLabel(String value) => switch (value) {
      'critical' => 'حرج',
      'high' => 'عالي',
      'medium' => 'متوسط',
      'low' => 'منخفض',
      _ => value,
    };

String _eventLabel(String value) => switch (value) {
      'created_from_source' => 'إنشاء المهمة',
      'claimed' => 'استلام المهمة',
      'assigned' => 'إسناد / إعادة إسناد',
      'classification_changed' => 'تحديث الأولوية والخطورة',
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

String _slaText(SupportTaskItem task) {
  final minutes = task.remainingMinutes;
  if (minutes == null) return 'SLA غير محدد';
  final absolute = minutes.abs();
  final hours = absolute ~/ 60;
  final mins = absolute % 60;
  final text = hours > 0 ? '$hours س $mins د' : '$mins د';
  return minutes < 0 ? 'متأخر $text' : 'متبقي $text';
}
