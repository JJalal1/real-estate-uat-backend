import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  bool _loading = true;
  bool _unreadOnly = false;
  int? _seenRevision;
  String? _error;
  List<MessageThreadSummary> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await ref.read(messageRepositoryProvider).threads();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
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

    final unreadCount = _items.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    final visible = _unreadOnly
        ? _items.where((item) => item.unreadCount > 0).toList(growable: false)
        : _items;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'الرسائل'),
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
                  child: _InboxHeader(
                    conversations: _items.length,
                    unreadCount: unreadCount,
                    unreadOnly: _unreadOnly,
                    onUnreadChanged: (value) =>
                        setState(() => _unreadOnly = value),
                  ),
                ),
              ),
              if (_loading)
                const SliverPadding(
                  padding: EdgeInsetsDirectional.all(
                    AppLayout.compactPageGutter,
                  ),
                  sliver: SliverToBoxAdapter(child: _MessagesSkeleton()),
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
                    title: 'لا توجد محادثات بعد',
                    message:
                        'افتح عقارًا منشورًا واضغط «مراسلة» حتى تبدأ محادثة مرتبطة بالعقار.',
                    icon: Icons.forum_outlined,
                  ),
                )
              else if (visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    title: 'ما عندك رسائل غير مقروءة',
                    message: 'كل المحادثات مقروءة الآن.',
                    icon: Icons.mark_chat_read_outlined,
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
                    itemBuilder: (context, index) => _ConversationCard(
                      item: visible[index],
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ConversationScreen(
                              threadId: visible[index].id,
                            ),
                          ),
                        );
                        await _load();
                      },
                    ),
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
    required this.unreadCount,
    required this.unreadOnly,
    required this.onUnreadChanged,
  });

  final int conversations;
  final int unreadCount;
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
                      unreadCount > 0
                          ? 'عندك $unreadCount رسالة غير مقروءة'
                          : 'كل الرسائل مقروءة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(
                  unreadCount > 0
                      ? Icons.mark_chat_unread_outlined
                      : Icons.mark_chat_read_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          FilterChip(
            selected: unreadOnly,
            avatar: const Icon(Icons.mark_email_unread_outlined, size: 18),
            label: Text(
              unreadCount > 0
                  ? 'غير المقروء فقط ($unreadCount)'
                  : 'غير المقروء فقط',
            ),
            onSelected: onUnreadChanged,
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.item, required this.onTap});

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
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.s14),
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
                        fontWeight: FontWeight.w800,
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
                                      unread ? FontWeight.w800 : FontWeight.w600,
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
                          Icon(
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
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                )
              else
                Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
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
