import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../data/unread_inbox_repository.dart';
import '../domain/message_models.dart';
import '../domain/notification_destination.dart';
import 'notification_preferences_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({this.workOnly = false, super.key});
  final bool workOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _NotificationsBody(workOnly: workOnly,
          key: ValueKey((actor, Stage6SecureSessionStore.instance.sessionEpoch, workOnly)));
  }
}
class _NotificationsBody extends ConsumerStatefulWidget {
  const _NotificationsBody({required this.workOnly, super.key});
  final bool workOnly;
  @override
  ConsumerState<_NotificationsBody> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<_NotificationsBody> {
  bool _loading = true;
  String? _error;
  String? _pageError;
  bool _loadingMore = false;
  int _page = 0;
  bool _hasMore = false;
  List<AppNotificationItem> _items = const [];
  final _legacyRead = <int, AppNotificationItem>{};
  int? _serverUnread;
  bool _showUnreadOnly = false;
  bool _actionPending = false;
  int _actionGeneration = 0;
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
        _actionGeneration++;
        _actionPending = false;
        _actor = actor;
        _sessionEpoch = epoch;
        _items = const [];
        _legacyRead.clear();
        _serverUnread = null;
        _showUnreadOnly = false;
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
    Future.microtask(_load);
  }

  Future<void> _load() => _fetchPage(1);

  void _chooseFilter(bool unreadOnly) {
    if (_actionPending || _showUnreadOnly == unreadOnly) return;
    setState(() => _showUnreadOnly = unreadOnly);
    _load();
  }

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
    final query = _showUnreadOnly;
    if (append && (_query != query || _actor != actor || _sessionEpoch != epoch)) {
      await _fetchPage(1);
      return;
    }
    final request = ++_request;
    setState(() {
      if (_actor != actor || _sessionEpoch != epoch) {
        _legacyRead.clear();
        _serverUnread = null;
      }
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
        _legacyRead.clear();
        _serverUnread = null;
        _page = 0;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _pageError = null;
        _error = 'تغيرت الجلسة. أعد تحميل الإشعارات.';
      });
    }
    try {
      final repo = ref.read(messageRepositoryProvider);
      final now = DateTime.now();
      Future<NotificationPage> loadPage(int number) => widget.workOnly
        ? repo.workNotificationsPage(page: number, unreadOnly: query)
        : repo.notificationsPage(
        page: number, platformHistory: true, unreadOnly: query,
      );
      List<AppNotificationItem> visible(NotificationPage page) => page.items.where((item) =>
          item.isPlatformNotification && (!query || !item.isRead) &&
          (page.unreadCount != null || item.isRecentPlatformNotification(now))).toList();

      var result = await loadPage(page);
      var platformItems = visible(result);
      final lastPage = result.lastPage;
      while (current() && platformItems.isEmpty && result.hasMore && result.currentPage < lastPage) {
        result = await loadPage(result.currentPage + 1);
        platformItems = visible(result);
      }
      if (!current()) { discardStaleDelivery(); return; }
      setState(() {
        _serverUnread = result.unreadCount;
        _legacyRead.removeWhere((_, item) => !item.isRecentPlatformNotification(now));
        final items = <int, AppNotificationItem>{
          if (append) for (final item in _items) item.id: item,
          for (final item in platformItems) item.id: item,
          if (result.unreadCount == null && !query) ..._legacyRead,
        };
        _items = items.values.toList();
        if (result.unreadCount == null && !query && _legacyRead.isNotEmpty) {
          _items.sort((a, b) => b.id.compareTo(a.id));
        }
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
            _legacyRead.clear();
            _serverUnread = null;
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

  bool _sameSession(int? actor, int epoch) => mounted &&
      actor == ref.read(authControllerProvider).asData?.value?.id &&
      epoch == Stage6SecureSessionStore.instance.sessionEpoch;

  void _finishAction(int generation, int? actor, int epoch) {
    if (!mounted || generation != _actionGeneration) return;
    final stale = !_sameSession(actor, epoch) &&
        _sessionEpoch != Stage6SecureSessionStore.instance.sessionEpoch;
    setState(() {
      _actionPending = false;
      if (stale) {
        _request++;
        _items = const [];
        _legacyRead.clear();
        _serverUnread = null;
        _page = 0;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _pageError = null;
        _error = 'تغيرت الجلسة. أعد تحميل الإشعارات.';
      }
    });
  }

  Future<void> _readAll() async {
    if (_actionPending || _loading || _loadingMore) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final generation = ++_actionGeneration;
    setState(() => _actionPending = true);
    final marked = <AppNotificationItem>[];
    var allRead = false;
    try {
      final repo = ref.read(messageRepositoryProvider);
      if (_serverUnread != null || widget.workOnly) {
        if (widget.workOnly) {
          await repo.readAllWorkNotifications();
        } else {
          await repo.readAllPlatformNotifications();
        }
        marked.addAll(_items.where((item) => !item.isRead));
        allRead = true;
        return;
      }

      final now = DateTime.now();
      bool eligible(AppNotificationItem item) => !item.isRead && item.isRecentPlatformNotification(now);
      final unread = {for (final item in _items.where(eligible)) item.id: item};
      // The old bulk action also marks chat alerts. Snapshot platform rows
      // before marking the first one because reads change unread pagination.
      if (_hasMore) {
        var page = await repo.notificationsPage(perPage: 200);
        final lastPage = page.lastPage;
        while (_sameSession(actor, epoch)) {
          unread.addEntries(page.items.where(eligible).map((item) => MapEntry(item.id, item)));
          if (!page.hasMore || page.currentPage >= lastPage) break;
          page = await repo.notificationsPage(page: page.currentPage + 1, perPage: 200);
        }
      }
      for (final item in unread.values) {
        if (!_sameSession(actor, epoch)) return;
        await repo.readNotification(item.id);
        marked.add(item);
      }
    } catch (error) {
      if (_sameSession(actor, epoch)) _showActionError(error);
    } finally {
      if (_sameSession(actor, epoch)) {
        if (marked.isNotEmpty || allRead) _applyReadReceipts(marked, allRead: allRead);
        await _refresh();
      }
      _finishAction(generation, actor, epoch);
    }
  }

  Future<void> _open(AppNotificationItem item, {String? destination}) async {
    if (_actionPending) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final generation = ++_actionGeneration;
    setState(() => _actionPending = true);
    try {
      await _openDestination(item, actor, epoch, destination);
    } catch (error) {
      if (_sameSession(actor, epoch)) _showActionError(error);
    } finally {
      _finishAction(generation, actor, epoch);
    }
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiError(error))),
    );
  }

  Future<void> _openDestination(AppNotificationItem item, int? actor, int epoch, String? route) async {
    if (!item.isRead) {
      await ref.read(messageRepositoryProvider).readNotification(item.id);
    }
    if (!mounted || !_sameSession(actor, epoch)) return;
    if (!item.isRead) {
      _applyReadReceipts([item]);
      ref.read(unreadInboxRevisionProvider.notifier).state++;
    }

    final destination = route ?? notificationDestination(item);
    if (destination != null) {
      await context.push<void>(destination);
    } else if (_sameSession(actor, epoch)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت قراءة الإشعار ولا توجد صفحة مرتبطة به.'),
        ),
      );
    }
    if (_sameSession(actor, epoch)) await _load();
  }

  void _applyReadReceipts(List<AppNotificationItem> marked, {bool allRead = false}) {
    final read = {for (final item in marked) item.id: item.withReadReceipt()};
    setState(() {
      _request++;
      if (_serverUnread == null) {
        _legacyRead.addAll(read);
      } else {
        final count = _serverUnread! - read.length;
        _serverUnread = allRead || count < 0 ? 0 : count;
      }
      _items = [for (final item in _items)
        if (!_showUnreadOnly || !read.containsKey(item.id)) read[item.id] ?? item];
      _page = 0;
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _pageError = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _serverUnread ?? _items.where((item) => !item.isRead).length;
    final canReadAll = !_actionPending && !_loading && !_loadingMore && unread > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: widget.workOnly ? 'إشعارات العمل' : 'الإشعارات',
          actions: [
            if (widget.workOnly)
              AppIconButton(icon: Icons.tune, tooltip: 'تفضيلات الإشعارات',
                onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => const NotificationPreferencesScreen(),
                ))),
            if (MediaQuery.textScalerOf(context).scale(14) > 20)
              AppIconButton(icon: Icons.mark_email_read_outlined, tooltip: 'قراءة الكل',
                onPressed: canReadAll ? _readAll : null)
            else
              TextButton(onPressed: canReadAll ? _readAll : null,
                child: const Text('قراءة الكل')),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: ValueKey((_actor, _sessionEpoch, _showUnreadOnly)),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s12,
                    AppLayout.compactPageGutter,
                    AppSpacing.s12,
                  ),
                  child: _NotificationTabs(
                    unreadOnly: _showUnreadOnly,
                    unread: unread,
                    onSelected: _actionPending ? null : _chooseFilter,
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
                  sliver: SliverToBoxAdapter(child: _NotificationSkeleton()),
                )
              else if (_error != null && _items.isEmpty)
                SliverToBoxAdapter(
                  child: AppErrorState(message: _error!, onRetry: _load),
                )
              else if (_items.isEmpty)
                SliverToBoxAdapter(
                  child: AppEmptyState(
                    title: _showUnreadOnly ? 'ما عندك إشعارات غير مقروءة' : 'لا توجد إشعارات حديثة',
                    message: _showUnreadOnly ? 'تجد إشعاراتك السابقة في «الكل».'
                        : 'تظهر هنا إشعارات المنصة لآخر سبعة أيام.',
                    icon: Icons.notifications_none_rounded,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    0,
                    AppLayout.compactPageGutter,
                    AppSpacing.s40,
                  ),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _NotificationCard(
                        key: ValueKey('notification-${item.id}'),
                        item: item,
                        pending: _actionPending,
                        onTap: () => _open(item),
                        onOpenPrevious: item.previousPropertyId == null ? null : () => _open(
                          item, destination: '/properties/${item.previousPropertyId}',
                        ),
                        onReviewSupport: item.isListingReviewDecision ? () => _open(
                          item, destination: '/support/listing-decision/${item.entityId}',
                        ) : null,
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
                                key: const ValueKey('notifications-more'),
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

class _NotificationTabs extends StatelessWidget {
  const _NotificationTabs({required this.unreadOnly, required this.unread, required this.onSelected});

  final bool unreadOnly;
  final int unread;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const radius = BorderRadius.all(Radius.circular(13));

    Widget tab(bool unreadTab, String label, String key) {
      final selected = unreadTab == unreadOnly;
      final color = selected ? scheme.primary : scheme.onSurfaceVariant;
      return Expanded(child: Semantics(
        selected: selected, button: true,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            key: ValueKey(key),
            borderRadius: radius,
            onTap: onSelected == null ? null : () => onSelected!(unreadTab),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Center(child: Wrap(
                  spacing: 7,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(
                      color: color, fontWeight: FontWeight.w700)),
                    if (unreadTab) Text(arabicDigits('$unread'), key: const ValueKey('platform-history-unread-count'),
                        style: theme.textTheme.bodySmall?.copyWith(color: color)),
                  ],
                )),
              ),
            ),
          ),
        ),
      ));
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.surface), borderRadius: radius),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: IntrinsicHeight(child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [tab(false, 'الكل', 'notification-filter-all'),
            tab(true, 'غير المقروءة', 'notification-filter-unread')],
        )),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.pending,
    required this.onTap,
    this.onOpenPrevious,
    this.onReviewSupport,
    super.key,
  });

  final AppNotificationItem item;
  final bool pending;
  final VoidCallback onTap;
  final VoidCallback? onOpenPrevious;
  final VoidCallback? onReviewSupport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !item.isRead;
    final color = unread ? scheme.primary : scheme.onSurface;
    final unreadFill = theme.brightness == Brightness.light
        ? const Color(0xFFDCEFED) : Color.alphaBlend(scheme.primary.withValues(alpha: .14), scheme.surface);
    final iconFill = unread ? scheme.primary.withValues(alpha: .09) : scheme.surfaceContainerHigh;
    const radius = BorderRadius.all(Radius.circular(12));
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 18;
    final reviewDecision = item.isListingReviewDecision;
    final isAvailabilityReminder = item.type == 'broker_availability_due';
    final title = isAvailabilityReminder ? 'حدّث إعلاناتك' : item.title;
    final body = isAvailabilityReminder
        ? 'حان موعد تحديث إعلاناتك. افتح التحديثات من لوحة الدلال.'
        : item.body;
    final time = item.createdAt == null ? null : Text(_relativeTime(item.createdAt!),
        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant));
    return Semantics(
      button: true,
      label: unread ? 'غير مقروء: $title' : 'مقروء: $title',
      child: Material(
        color: unread ? unreadFill : scheme.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: pending ? null : onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 10, 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: iconFill, borderRadius: BorderRadius.circular(8)),
                child: Icon(_notificationIcon(item), size: 16, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (unread) ...[
                    Container(key: const ValueKey('notification-unread-dot'), width: 6, height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                  ],
                  Flexible(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                ]),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(body, maxLines: reviewDecision ? null : 2,
                    overflow: reviewDecision ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                if (onOpenPrevious != null || onReviewSupport != null)
                  Wrap(children: [
                    if (onOpenPrevious != null)
                      TextButton(onPressed: pending ? null : onOpenPrevious,
                        child: const Text('عرض الإعلان المشابه')),
                    if (onReviewSupport != null)
                      TextButton(onPressed: pending ? null : onReviewSupport,
                        child: const Text('مراجعة الدعم')),
                  ]),
                if (largeText && time != null) Align(alignment: AlignmentDirectional.centerEnd, child: time),
              ])),
              if (!largeText && time != null) ...[const SizedBox(width: 8), time],
            ]),
          ),
        ),
      ),
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppSkeleton(height: 54, radius: AppRadii.card),
        SizedBox(height: 7),
        AppSkeleton(height: 54, radius: AppRadii.card),
        SizedBox(height: 7),
        AppSkeleton(height: 54, radius: AppRadii.card),
      ],
    );
  }
}

IconData _notificationIcon(AppNotificationItem item) {
  final type = item.type;
  if (type == 'broker_availability_due') return Icons.sync_rounded;
  if (item.entityType == 'property_platform_receivable') return Icons.account_balance_wallet_outlined;
  if (type == 'listing_approved' || type == 'listing_published') return Icons.home_outlined;
  if (type == 'listing_updated') return Icons.description_outlined;
  if (item.entityType == 'broker_deal_outcome' && type.contains('confirm')) return Icons.check_rounded;
  if (type == 'listing_duplicate_rejected') {
    return Icons.content_copy_outlined;
  }
  if (type.startsWith('agreement_') || type.startsWith('rental_contract_')) {
    return Icons.handshake_outlined;
  }
  if (type.startsWith('saved_search_') || type == 'favorite_price_changed') {
    return Icons.saved_search_outlined;
  }
  if (type.startsWith('support_') || type.contains('verification')) {
    return Icons.shield_outlined;
  }
  return item.entityType == 'property' ? Icons.description_outlined : Icons.notifications_none_rounded;
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'الآن';
  if (difference.inMinutes == 1) return 'قبل دقيقة';
  if (difference.inMinutes == 2) return 'قبل دقيقتين';
  if (difference.inMinutes < 60) return 'قبل ${arabicDigits('${difference.inMinutes}')} د';
  if (difference.inHours == 1) return 'قبل ساعة';
  if (difference.inHours == 2) return 'قبل ساعتين';
  if (difference.inHours < 24) return 'قبل ${arabicDigits('${difference.inHours}')} س';
  if (difference.inDays == 1) return 'أمس';
  if (difference.inDays == 2) return 'قبل يومين';
  return 'قبل ${arabicDigits('${difference.inDays}')} أيام';
}
