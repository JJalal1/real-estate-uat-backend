import '../../../core/offline/offline_connection.dart';
import '../data/message_outbox.dart';
import 'pending_message_card.dart';
import 'package:flutter/material.dart';
import '../../broker/presentation/broker_connections_screen.dart';
import 'message_thread_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../data/unread_inbox_repository.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({this.embedded = false, this.compact = false, super.key});
  final bool embedded;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final actor = user?.id;
    if (user?.hasMarketplaceProfessionalProfile == true) {
      return const BrokerConnectionsScreen();
    }
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _MessagesBody(key: ValueKey((actor, Stage6SecureSessionStore.instance.sessionEpoch)),
          embedded: embedded, compact: compact);
  }
}

class _MessagesBody extends ConsumerStatefulWidget {
  const _MessagesBody({required this.embedded, required this.compact, super.key});
  final bool embedded;
  final bool compact;
  @override
  ConsumerState<_MessagesBody> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<_MessagesBody> {
  bool _loading = true;
  bool _unreadOnly = false;
  int? _seenRevision;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = false;
  List<MessageThreadSummary> _items = const [];
  int _request = 0;
  int? _actor;
  int _sessionEpoch = 0;
  bool? _query;

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
        _hasMore = false;
        _query = null;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _loading = actor != null;
      });
      if (actor != null) Future<void>.microtask(_load);
    });
    ref.listenManual(offlineResumeRevisionProvider, (_, __) {
      if (mounted) Future.microtask(_load);
    });
    Future.microtask(_load);
  }

  Future<void> _load() => _fetchPage(1);

  Future<void> _refresh() {
    ref.read(unreadInboxRevisionProvider.notifier).state++;
    return _load();
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    await _fetchPage(_page + 1, append: true);
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final query = _unreadOnly;
    if (append && (_query != query || _actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_query != query || _actor != actor || _sessionEpoch != epoch) {
        _items = const [];
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
        _page = 0;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _pageError = null;
        _error = 'تغيرت الجلسة. أعد تحميل المحادثات.';
      });
    }
    try {
      final result = await ref.read(messageRepositoryProvider).threadsPage(
        page: page, unreadOnly: query);
      if (!current()) { discardStaleDelivery(); return; }
      setState(() {
        _items = <int, MessageThreadSummary>{
          if (append) for (final item in _items) item.id: item,
          for (final item in result.items) item.id: item,
        }.values.toList(growable: false);
        _page = result.currentPage;
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

  void _filterUnread(bool value) {
    if (_unreadOnly == value) return;
    setState(() => _unreadOnly = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(messageDataRevisionProvider);
    if (_seenRevision == null) {
      _seenRevision = revision;
    } else if (_seenRevision != revision) {
      _seenRevision = revision;
      Future<void>.microtask(_load);
    }

    final pending = _actor == null
        ? <PendingMessage>[]
        : ref.watch(messageOutboxProvider(_actor!)).where((message) =>
            message.status != 'sent' || (!_unreadOnly && !_items.any((thread) => thread.id == message.threadId))).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: widget.embedded ? null : const AppAppBar(title: 'الرسائل'),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: ValueKey((_actor, _sessionEpoch, _query)),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (pending.isNotEmpty)
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('رسائل هذا الجهاز',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              for (final message in pending)
                                PendingMessageCard(
                                    actor: _actor!,
                                    message: message,
                                    showTarget: true),
                            ]))),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s12,
                    AppLayout.compactPageGutter,
                    0,
                  ),
                  child: MessageInboxFilters(
                    options: const {null: 'كل الحالات', 'unread': 'غير المقروء فقط'},
                    selected: _unreadOnly ? 'unread' : null,
                    onSelected: (value) => _filterUnread(value == 'unread'),
                  ),
                ),
              ),
              if (_items.isNotEmpty && (_loading || _error != null))
                SliverToBoxAdapter(child: AppRefreshStatus(loading: _loading, error: _error, onRetry: _load)),
              if (_loading && _items.isEmpty)
                const SliverPadding(
                  padding: EdgeInsetsDirectional.all(
                    AppLayout.compactPageGutter,
                  ),
                  sliver: SliverToBoxAdapter(child: _MessagesSkeleton()),
                )
              else if (_error != null && _items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: AppErrorState(message: _error!, onRetry: _load),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: AppEmptyState(
                    title: _unreadOnly ? 'ما عندك رسائل غير مقروءة' : 'لا توجد محادثات بعد',
                    message: _unreadOnly
                        ? 'كل المحادثات مقروءة الآن.'
                        : widget.compact
                            ? 'ستظهر هنا رسائلك المرتبطة بالعقارات.'
                            : 'افتح عقارًا منشورًا واضغط «مراسلة» حتى تبدأ محادثة مرتبطة بالعقار.',
                    icon: _unreadOnly ? Icons.mark_chat_read_outlined : Icons.forum_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s12,
                    AppLayout.compactPageGutter,
                    AppSpacing.s40,
                  ),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(
                      height: AppSpacing.s8,
                    ),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return MessageThreadCard(
                        key: ValueKey('message-thread-${item.id}'),
                        threadId: item.id,
                        otherUserName: item.otherUserName,
                        lastMessagePreview: item.lastMessagePreview,
                        lastMessageIsMine: item.lastMessageIsMine,
                        lastMessageAt: item.lastMessageAt,
                        unreadCount: item.unreadCount,
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ConversationScreen(threadId: item.id),
                            ),
                          );
                          await _load();
                        },
                      );
                    },
                  ),
                ),
              if (_items.isNotEmpty && (_hasMore || _loadingMore || _pageError != null))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppLayout.compactPageGutter, 0, AppLayout.compactPageGutter, AppSpacing.s24),
                    child: _pageError != null
                        ? AppRefreshStatus(loading: _loadingMore, error: _pageError, onRetry: _loadMore)
                        : Center(child: _loadingMore
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                key: const ValueKey('message-threads-more'),
                                onPressed: _loadMore,
                                child: const Text('تحميل المزيد'),
                              )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesSkeleton extends StatelessWidget {
  const _MessagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppSkeleton(height: 76, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 76, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 76, radius: AppRadii.card),
      ],
    );
  }
}
