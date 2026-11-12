import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportCenterScreen extends ConsumerStatefulWidget {
  const SupportCenterScreen({super.key, this.initialCaseId});

  final int? initialCaseId;

  @override
  ConsumerState<SupportCenterScreen> createState() =>
      _SupportCenterScreenState();
}

class _SupportCenterScreenState extends ConsumerState<SupportCenterScreen> {
  bool _loading = true;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = false;
  int _request = 0;
  int? _actor;
  int _sessionEpoch = 0;
  int _identityVersion = 0;
  List<SupportCaseSummary> _cases = const [];
  int? _pendingInitialCaseId;

  @override
  void initState() {
    super.initState();
    _pendingInitialCaseId = widget.initialCaseId;
    _actor = ref.read(authControllerProvider).asData?.value?.id;
    _sessionEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
    ref.listenManual(authControllerProvider, (_, next) {
      final actor = next.asData?.value?.id;
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      if (!mounted || (_actor == actor && _sessionEpoch == epoch)) return;
      setState(() {
        _request++;
        _identityVersion++;
        _actor = actor;
        _sessionEpoch = epoch;
        _cases = const [];
        _page = 0;
        _hasMore = false;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _loading = actor != null;
        _pendingInitialCaseId = null;
      });
      if (actor != null) Future<void>.microtask(_load);
    });
    Future<void>.microtask(_load);
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
    if (append && (_actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_actor != actor || _sessionEpoch != epoch) _cases = const [];
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
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    try {
      final result = await ref.read(supportRepositoryProvider).mine(page: page);
      if (!current()) return;
      setState(() {
        _cases = <int, SupportCaseSummary>{
          if (append) for (final item in _cases) item.id: item,
          for (final item in result.items) item.id: item,
        }.values.toList(growable: false);
        _page = result.currentPage;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
      final initialCaseId = _pendingInitialCaseId;
      _pendingInitialCaseId = null;
      if (initialCaseId != null && initialCaseId > 0 && current()) {
        await _showDetails(initialCaseId);
      }
    } catch (error) {
      if (!current()) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (append && isTransientApiFailure(error)) {
          _pageError = friendlyApiError(error);
        } else {
          if (!isTransientApiFailure(error)) _cases = const [];
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
    if (ref.watch(authControllerProvider).asData?.value == null) {
      return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدعم وبلاغاتي')),
        floatingActionButton: EbrokerButton(
          onPressed: _openTicket,
          icon: const EbrokerIcon(Icons.support_agent_outlined),
          child: const Text('تذكرة دعم'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: ValueKey((_actor, _sessionEpoch)),
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
                              fontWeight: FontWeight.w600,
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
              if (_cases.isNotEmpty && (_loading || _error != null))
                AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
              if (_loading && _cases.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _cases.isEmpty)
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
                    key: ValueKey('support-case-${item.id}'),
                    child: ListTile(
                      leading: EbrokerIcon(
                        item.kind == 'report'
                            ? Icons.flag_outlined
                            : Icons.support_agent_outlined,
                      ),
                      title: Text(
                        item.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${item.reference} • ${_statusLabel(item.status)}'
                        '${item.isEscalated ? ' • مصعّدة' : ''}',
                      ),
                      trailing: const EbrokerIcon(Icons.chevron_left),
                      onTap: () => _openDetails(item.id),
                    ),
                  ),
                ),
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

  Future<void> _openTicket() async {
    final actor = _actor;
    final epoch = _sessionEpoch;
    final identityVersion = _identityVersion;
    bool current() => mounted && actor != null && identityVersion == _identityVersion &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
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
    final accepted = await showActorDialog<bool>(
      ref: ref,
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
            EbrokerFilledButton(
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
    if (!current() || accepted != true ||
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
      if (!current()) {
        return;
      }
      await _load();
      if (!current()) {
        return;
      }
      await _showDetails(details.summary.id);
    } catch (error) {
      if (current()) _showError(error);
    }
  }

  Future<void> _openDetails(int caseId) async {
    final identityVersion = _identityVersion;
    final epoch = _sessionEpoch;
    await _showDetails(caseId);
    if (mounted && identityVersion == _identityVersion &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch) await _load();
  }

  Future<void> _showDetails(int caseId) async {
    final actor = _actor;
    final epoch = _sessionEpoch;
    final identityVersion = _identityVersion;
    bool current() => mounted && actor != null && identityVersion == _identityVersion &&
        actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    try {
      var details = await ref.read(supportRepositoryProvider).details(caseId);
      if (!current()) {
        return;
      }
      await showActorDialog<void>(
        ref: ref,
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                            borderRadius: BorderRadius.circular(8),
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
                                    fontWeight: FontWeight.w700,
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
                    if (body == null || !current()) {
                      return;
                    }
                    try {
                      final next = await ref
                          .read(supportRepositoryProvider)
                          .reply(caseId, body);
                      if (!current() || !dialogContext.mounted) return;
                      setDialogState(() => details = next);
                    } catch (error) {
                      if (current() && dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(friendlyApiError(error))),
                        );
                      }
                    }
                  },
                  icon: const EbrokerIcon(Icons.reply_outlined),
                  label: const Text('إضافة رد'),
                ),
              EbrokerFilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (current()) _showError(error);
    }
  }

  Future<String?> _replyDialog(BuildContext parentContext) async {
    final controller = TextEditingController();
    final accepted = await showActorDialog<bool>(
      ref: ref,
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
          EbrokerFilledButton(
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
            EbrokerOutlinedButton.icon(
              onPressed: onRetry,
              icon: const EbrokerIcon(Icons.refresh),
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
