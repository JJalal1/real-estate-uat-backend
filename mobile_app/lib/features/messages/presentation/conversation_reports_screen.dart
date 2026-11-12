import 'package:flutter/material.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

class ConversationReportsScreen extends ConsumerWidget {
  const ConversationReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    return ActorBoundPage(title: 'بلاغات المحادثات الخاصة',
      builder: (_) => _ConversationReportsScreenBody(key: ValueKey((actor, epoch))));
  }
}

class _ConversationReportsScreenBody extends ConsumerStatefulWidget {
  const _ConversationReportsScreenBody({super.key});
  @override
  ConsumerState<_ConversationReportsScreenBody> createState() => _ConversationReportsScreenState();
}

class _ConversationReportsScreenState
    extends ConsumerState<_ConversationReportsScreenBody> {
  bool _loading = true;
  String? _status;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  int _total = 0;
  bool _hasMore = false;
  List<ConversationReportSummary> _items = const [];
  int _request = 0;
  int? _actor;
  int _sessionEpoch = 0;
  String? _query;

  @override
  void initState() {
    super.initState();
    _actor = ref.read(authControllerProvider).asData?.value?.id;
    _sessionEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
    ref.listenManual(authControllerProvider, (_, next) {
      final actor = next.asData?.value?.id;
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      if (!mounted || (_actor == actor && _sessionEpoch == epoch)) return;
      setState(() {
        _request++;
        _actor = actor;
        _sessionEpoch = epoch;
        _items = const [];
        _page = 0;
        _total = 0;
        _hasMore = false;
        _query = null;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _loading = actor != null;
      });
      if (actor != null) Future<void>.microtask(_load);
    });
    Future.microtask(_load);
  }

  Future<void> _load() => _fetchPage(1);

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    await _fetchPage(_page + 1, append: true);
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final query = _status ?? '';
    if (append && (_query != query || _actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_query != query || _actor != actor || _sessionEpoch != epoch) {
        _items = const [];
        _total = 0;
      }
      _actor = actor;
      _sessionEpoch = epoch;
      _query = query;
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
        epoch == Stage6SecureSessionStore.instance.sessionEpoch && query == _query;
    void discardStaleDelivery() {
      if (!mounted || request != _request) return;
      setState(() {
        _items = const [];
        _total = 0;
        _page = 0;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _pageError = null;
        _error = 'تغيرت الجلسة. أعد تحميل البلاغات.';
      });
    }
    try {
      final result = await ref.read(messageRepositoryProvider).adminReportsPage(
        page: page, status: query.isEmpty ? null : query);
      if (!current()) { discardStaleDelivery(); return; }
      setState(() {
        _items = <int, ConversationReportSummary>{
          if (append) for (final item in _items) item.id: item,
          for (final item in result.items) item.id: item,
        }.values.toList(growable: false);
        _page = result.currentPage;
        _total = result.total;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!current()) { discardStaleDelivery(); return; }
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (append && isTransientApiFailure(error)) {
          _pageError = friendlyApiError(error);
        } else {
          if (!isTransientApiFailure(error)) {
            _items = const [];
            _total = 0;
          }
          _page = 0;
          _hasMore = false;
          _error = friendlyApiError(error);
        }
      });
    }
  }

  @override
  void dispose() { _request++; super.dispose(); }

  Future<void> _open(ConversationReportSummary report) async {
    final current = ref.read(authControllerProvider).valueOrNull;
    final actor = current?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    bool sameSession() => mounted && actor == ref.read(authControllerProvider).asData?.value?.id &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    if (current?.hasPermission('conversations.review_private') != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'يمكنك مشاهدة بيانات البلاغ فقط. فتح الرسائل الخاصة يحتاج صلاحية مستقلة.')));
      return;
    }
    final accepted = await showActorDialog<bool>(
        context: context, ref: ref,
        builder: (dialogContext) => AlertDialog(
              title: const Text('فتح محتوى خاص؟'),
              content: const Text(
                  'سيتم فتح الرسائل فقط ضمن هذا البلاغ النشط، وسيتم تسجيل عملية الوصول في سجل غير قابل للتعديل.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء')),
                EbrokerFilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('فتح وتسجيل الوصول'))
              ],
            ));
    if (accepted != true || !sameSession()) {
      return;
    }
    try {
      final content = await ref
          .read(messageRepositoryProvider)
          .openReportedContent(report.id);
      if (!sameSession()) {
        return;
      }
      await showActorDialog<void>(
          context: context, ref: ref,
          builder: (dialogContext) => AlertDialog(
                title: Text('بلاغ #${report.id}'),
                content: SizedBox(
                    width: 520,
                    child: ListView(shrinkWrap: true, children: [
                      Text(report.propertyTitle ?? 'محادثة خاصة',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
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
      if (sameSession()) await _load();
    } catch (error) {
      if (sameSession()) {
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
                  key: ValueKey((_actor, _sessionEpoch, _query)),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'قائمة البلاغات تعرض بيانات البلاغ فقط. محتوى الرسائل لا يُفتح إلا من بلاغ نشط وبصلاحية conversations.review_private، وكل فتح يُسجّل.'))),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('conversation-reports-status'),
                      value: _status ?? '',
                      decoration: const InputDecoration(labelText: 'حالة البلاغ'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('كل البلاغات')),
                        DropdownMenuItem(value: 'open', child: Text('مفتوح')),
                        DropdownMenuItem(value: 'under_review', child: Text('قيد المراجعة')),
                        DropdownMenuItem(value: 'resolved', child: Text('تم الحل')),
                        DropdownMenuItem(value: 'dismissed', child: Text('مرفوض')),
                      ],
                      onChanged: (value) {
                        final status = value == '' ? null : value;
                        if (status == _status) return;
                        setState(() => _status = status);
                        _load();
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!_loading && _error == null) Text('$_total بلاغ'),
                    if (_items.isNotEmpty && (_loading || _error != null))
                      AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
                    if (_loading && _items.isEmpty)
                      const Padding(padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()))
                    else if (_error != null && _items.isEmpty)
                      AppErrorState(message: _error!, onRetry: _load)
                    else if (_items.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(22),
                        child: Text('لا توجد بلاغات محادثات.')))
                    else
                      ..._items.map((item) => Card(
                        key: ValueKey('conversation-report-${item.id}'),
                        child: ListTile(
                          leading: const EbrokerIcon(Icons.privacy_tip_outlined),
                          title: Text(item.propertyTitle ?? 'محادثة #${item.threadId}'),
                          subtitle: Text('${item.reporterName} • ${item.reasonCode} • ${item.status}'),
                          trailing: const EbrokerIcon(Icons.chevron_left),
                          onTap: () => _open(item),
                        ))),
                    if (_items.isNotEmpty && (_hasMore || _loadingMore || _pageError != null))
                      Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _pageError != null
                          ? AppRefreshStatus(loading: _loadingMore, error: _pageError, onRetry: _loadMore)
                          : Center(child: _loadingMore
                            ? const CircularProgressIndicator()
                            : OutlinedButton(key: const ValueKey('conversation-reports-more'),
                              onPressed: _loadMore, child: const Text('تحميل المزيد')))),

                  ])),
        ));
  }
}
