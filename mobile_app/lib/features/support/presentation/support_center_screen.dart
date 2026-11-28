import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';
import 'support_help_screen.dart';

class SupportCenterScreen extends ConsumerStatefulWidget {
  const SupportCenterScreen({super.key});

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
        appBar: AppBar(title: const Text('طلباتي')),
        floatingActionButton: EbrokerButton(
          onPressed: _openTicket,
          icon: const EbrokerIcon(Icons.support_agent_outlined),
          child: const Text('أرسل طلب للدعم'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: ValueKey((_actor, _sessionEpoch)),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
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

  Future<void> _openTicket() => _openPage(const SupportHelpConversationScreen());

  Future<void> _openDetails(int caseId) => _openPage(SupportHelpConversationScreen(caseId: caseId));

  Future<void> _openPage(Widget page) async {
    final actor = _actor;
    final identityVersion = _identityVersion;
    final epoch = _sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    if (actor == null || !scope.isCurrent) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      ActorBoundPage(
        title: 'الدعم',
        actorId: actor,
        sessionEpoch: epoch,
        requestScope: scope,
        builder: (_) => page,
      ),
    ));
    if (mounted && identityVersion == _identityVersion &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch) {
      await _load();
    }
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
