import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import '../domain/notification_destination.dart';
import 'notification_preferences_screen.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;
  bool _unreadOnly = false;
  String? _error;
  List<AppNotificationItem> _items = const [];
  bool _actionPending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(messageRepositoryProvider).notifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _readAll() async {
    if (_actionPending) return;
    setState(() => _actionPending = true);
    try {
      await ref.read(messageRepositoryProvider).readAllNotifications();
      if (mounted) await _load();
    } catch (error) {
      _showActionError(error);
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<void> _open(AppNotificationItem item) async {
    if (_actionPending) return;
    setState(() => _actionPending = true);
    try {
      await _openDestination(item);
    } catch (error) {
      _showActionError(error);
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiError(error))),
    );
  }

  Future<void> _openDestination(AppNotificationItem item) async {
    if (!item.isRead) {
      await ref.read(messageRepositoryProvider).readNotification(item.id);
    }
    if (!mounted) return;

    final destination = notificationDestination(item);
    if (destination != null) {
      await context.push<void>(destination);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت قراءة الإشعار ولا توجد صفحة مرتبطة به.'),
        ),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => !item.isRead).length;
    final visible = _unreadOnly
        ? _items.where((item) => !item.isRead).toList(growable: false)
        : _items;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: 'الإشعارات',
          actions: [
            AppIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'تفضيلات الإشعارات',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              ),
            ),
            TextButton(
              onPressed: !_actionPending && unread > 0 ? _readAll : null,
              child: const Text('قراءة الكل'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
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
                  child: AppSurface(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unread > 0
                                    ? '$unread إشعار يحتاج انتباهك'
                                    : 'أنت مطّلع على كل شيء',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                'الإشعارات المهمة تبقى هنا، وتقدر تتحكم في الفئات الاختيارية من الإعدادات.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.s10),
                              FilterChip(
                                selected: _unreadOnly,
                                avatar: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 18,
                                ),
                                label: const Text('غير المقروء فقط'),
                                onSelected: (value) =>
                                    setState(() => _unreadOnly = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppRadii.control),
                          ),
                          child: Icon(
                            unread > 0
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_none_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_loading)
                const SliverPadding(
                  padding: EdgeInsetsDirectional.all(
                    AppLayout.compactPageGutter,
                  ),
                  sliver: SliverToBoxAdapter(child: _NotificationSkeleton()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(message: _error!, onRetry: _load),
                )
              else if (_items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    title: 'لا توجد إشعارات بعد',
                    message:
                        'بتظهر هنا الرسائل والمواعيد والتحديثات المهمة لحسابك.',
                    icon: Icons.notifications_none_rounded,
                  ),
                )
              else if (visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    title: 'ما عندك إشعارات غير مقروءة',
                    message: 'كل الإشعارات الحالية مقروءة.',
                    icon: Icons.done_all_rounded,
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
                    itemCount: visible.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s10),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return _NotificationCard(
                        item: item,
                        pending: _actionPending,
                        onTap: () => _open(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.pending,
    required this.onTap,
  });

  final AppNotificationItem item;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presentation = _notificationPresentation(item.type);
    return AppSurface(
      padding: EdgeInsets.zero,
      selected: !item.isRead,
      onTap: pending ? null : onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: !item.isRead
                    ? scheme.primaryContainer
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Icon(
                presentation.$1,
                color: !item.isRead ? scheme.primary : scheme.onSurfaceVariant,
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
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: item.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                        ),
                      ),
                      if (item.createdAt != null)
                        Text(
                          _relativeTime(item.createdAt!),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  AppStatusBadge(
                    label: presentation.$2,
                    tone: presentation.$3,
                  ),
                  if (item.body != null) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      item.body!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
          ],
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
        AppSkeleton(height: 112, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 112, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 112, radius: AppRadii.card),
      ],
    );
  }
}

(IconData, String, AppStatusTone) _notificationPresentation(String type) {
  if (type == 'message_received') {
    return (Icons.chat_bubble_outline, 'رسائل', AppStatusTone.info);
  }
  if (type.startsWith('booking_')) {
    return (Icons.calendar_month_outlined, 'معاينة', AppStatusTone.info);
  }
  if (type.startsWith('agreement_') || type.startsWith('rental_contract_')) {
    return (Icons.handshake_outlined, 'اتفاق', AppStatusTone.success);
  }
  if (type.startsWith('saved_search_') || type == 'favorite_price_changed') {
    return (Icons.saved_search_outlined, 'بحث ومفضلة', AppStatusTone.info);
  }
  if (type.startsWith('support_') || type.contains('verification')) {
    return (Icons.shield_outlined, 'مهم', AppStatusTone.warning);
  }
  return (Icons.notifications_none_rounded, 'تحديث', AppStatusTone.neutral);
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
