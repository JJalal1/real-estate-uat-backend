import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({this.embedded = false, super.key});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _MessagesBody(key: ValueKey((actor, Stage6SecureSessionStore.instance.sessionEpoch)), embedded: embedded);
  }
}

class _MessagesBody extends ConsumerStatefulWidget {
  const _MessagesBody({required this.embedded, super.key});
  final bool embedded;
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
  int _total = 0;
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
    final query = _unreadOnly;
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

  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(messageDataRevisionProvider);
    if (_seenRevision == null) {
      _seenRevision = revision;
    } else if (_seenRevision != revision) {
      _seenRevision = revision;
      Future<void>.microtask(_load);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: widget.embedded ? null : const AppAppBar(title: 'الرسائل'),
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            key: ValueKey((_actor, _sessionEpoch, _query)),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s12,
                    AppLayout.compactPageGutter,
                    0,
                  ),
                  child: _InboxHeader(
                    conversations: _total,
                    unreadOnly: _unreadOnly,
                    onUnreadChanged: (value) {
                      if (_unreadOnly == value) return;
                      setState(() => _unreadOnly = value);
                      _load();
                    },
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
                    message: _unreadOnly ? 'كل المحادثات مقروءة الآن.' :
                      'افتح عقارًا منشورًا واضغط «مراسلة» حتى تبدأ محادثة مرتبطة بالعقار.',
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
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s10),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _ConversationCard(
                      key: ValueKey('message-thread-${item.id}'),
                      item: item,
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ConversationScreen(
                              threadId: item.id,
                            ),
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

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({
    required this.conversations,
    required this.unreadOnly,
    required this.onUnreadChanged,
  });

  final int conversations;
  final bool unreadOnly;
  final ValueChanged<bool> onUnreadChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unreadOnly ? 'المحادثات غير المقروءة' : 'محادثاتك',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      unreadOnly ? '$conversations محادثة غير مقروءة.' :
                          '$conversations محادثة مرتبطة برحلات عقارية داخل التطبيق.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: EbrokerIcon(
                  unreadOnly
                      ? Icons.mark_chat_unread_outlined
                      : Icons.mark_chat_read_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          EbrokerFilterChip(
            selected: unreadOnly,
            avatar: const EbrokerIcon(Icons.mark_email_unread_outlined, size: 18),
            label: const Text('غير المقروء فقط'),
            onSelected: onUnreadChanged,
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.item, required this.onTap, super.key});

  final MessageThreadSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = item.unreadCount > 0;
    final firstLetter = item.otherUserName.trim().isEmpty
        ? '?'
        : item.otherUserName.trim().characters.first;

    return AppSurface(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: unread
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                child: Text(
                  firstLetter,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: unread ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.otherUserName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight:
                                      unread ? FontWeight.w700 : FontWeight.w600,
                                ),
                          ),
                        ),
                        if (item.lastMessageAt != null)
                          Text(
                            _relativeTime(item.lastMessageAt!),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                    if (item.propertyTitle != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Row(
                        children: [
                          EbrokerIcon(
                            Icons.home_work_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Expanded(
                            child: Text(
                              item.propertyTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      item.lastMessagePreview ?? 'ابدأ المحادثة حول هذا العقار.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: unread
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.normal,
                          ),
                    ),
                    if (item.isPropertyUnavailable) ...[
                      const SizedBox(height: AppSpacing.s8),
                      const AppStatusBadge(
                        label: 'الإعلان غير متاح حاليًا • المحادثة محفوظة',
                        tone: AppStatusTone.warning,
                        icon: Icons.info_outline,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              if (unread)
                Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    item.unreadCount > 99 ? '99+' : '${item.unreadCount}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                )
              else
                EbrokerIcon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
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
        AppSkeleton(height: 112, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 112, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 112, radius: AppRadii.card),
      ],
    );
  }
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'الآن';
  if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} د';
  if (difference.inHours < 24) return 'منذ ${difference.inHours} س';
  if (difference.inDays == 1) return 'أمس';
  if (difference.inDays < 7) return 'منذ ${difference.inDays} أيام';
  return '${value.toLocal().day}/${value.toLocal().month}';
}
