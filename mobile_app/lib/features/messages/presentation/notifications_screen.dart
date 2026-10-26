import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import '../domain/notification_destination.dart';
import 'notification_preferences_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _NotificationsBody(key: ValueKey(actor));
  }
}
class _NotificationsBody extends ConsumerStatefulWidget {
  const _NotificationsBody({super.key});
  @override
  ConsumerState<_NotificationsBody> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<_NotificationsBody> {
  bool _loading = true;
  String? _error;
  List<AppNotificationItem> _items = const [];
  bool _actionPending = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() { _request++; super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(messageRepositoryProvider).notifications();
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        if (!isTransientApiFailure(error)) _items = const [];
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
    setState(() => _items = _items.where((entry) => entry.id != item.id).toList(growable: false));

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
    final visible = _items.where((item) => !item.isRead).toList(growable: false);

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
            if (MediaQuery.textScalerOf(context).scale(14) > 20)
              AppIconButton(icon: Icons.mark_email_read_outlined, tooltip: 'قراءة الكل',
                onPressed: !_actionPending && unread > 0 ? _readAll : null)
            else
              TextButton(onPressed: !_actionPending && unread > 0 ? _readAll : null,
                child: const Text('قراءة الكل')),
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
                  child: Text(_loading || _error != null ? 'تحديثات حسابك' : unread > 0 ? '$unread إشعار جديد' : 'أنت مطّلع على كل شيء',
                    style: Theme.of(context).textTheme.bodyMedium),
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
                const SliverToBoxAdapter(
                  child: AppEmptyState(
                    title: 'أنت مطّلع على كل شيء',
                    message:
                        'بتظهر هنا الرسائل والمواعيد والتحديثات المهمة لحسابك.',
                    icon: Icons.notifications_none_rounded,
                  ),
                )
              else if (visible.isEmpty)
                const SliverToBoxAdapter(
                  child: AppEmptyState(
                    title: 'ما عندك إشعارات غير مقروءة',
                    message: 'سنُظهر هنا ما يحتاج انتباهك عند وصوله.',
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
                        const Divider(height: 1, thickness: .5),
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
    return Semantics(button: true, label: 'إشعار جديد: ${item.title}', child: Material(
      color: scheme.primary.withValues(alpha: .025),
      child: InkWell(onTap: pending ? null : onTap,
        child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(10, 16, 8, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2),
              child: EbrokerIcon(presentation.$1, size: 20, color: scheme.primary)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (item.body != null) ...[
                const SizedBox(height: 5),
                Text(item.body!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                Text(presentation.$2, style: Theme.of(context).textTheme.labelSmall),
                if (item.createdAt != null) Text(_relativeTime(item.createdAt!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ])),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 5, height: 5,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle))),
          ])),
      ),
    ));
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppSkeleton(height: 74, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 74, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s10),
        AppSkeleton(height: 74, radius: AppRadii.card),
      ],
    );
  }
}

(IconData, String, AppStatusTone) _notificationPresentation(String type) {
  if (type == 'message_received') {
    return (Icons.chat_bubble_outline, 'رسائل', AppStatusTone.info);
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
