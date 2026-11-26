import 'package:flutter/material.dart';

class MessageThreadCard extends StatelessWidget {
  const MessageThreadCard({
    required this.threadId,
    required this.otherUserName,
    required this.lastMessagePreview,
    required this.lastMessageIsMine,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.onTap,
    super.key,
  });

  final int threadId;
  final String otherUserName;
  final String? lastMessagePreview;
  final bool lastMessageIsMine;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final VoidCallback onTap;

  static final _spaces = RegExp(r'\s+');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = lastMessagePreview?.replaceAll(_spaces, ' ').trim() ?? '';
    final preview =
        lastMessageIsMine && message.isNotEmpty ? 'أنت: $message' : message;
    final lastMessage = message.isEmpty ? null : lastMessageAt;
    final secondary =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Material(
      color: theme.brightness == Brightness.dark
          ? scheme.surfaceContainerLow
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(
                    otherUserName,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                  if (unreadCount > 0)
                    Badge(
                      key: ValueKey('broker-message-unread-$threadId'),
                      label: Text('$unreadCount',
                          semanticsLabel: '$unreadCount رسالة غير مقروءة'),
                      backgroundColor: const Color(0xffb91c1c),
                      textColor: Colors.white,
                    ),
                ],
              ),
              if (preview.isNotEmpty || lastMessage != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                        child: Text(
                      preview,
                      style: secondary,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (lastMessage != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        _messageDateLabel(lastMessage),
                        style: secondary?.copyWith(fontSize: 11),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _messageDateLabel(DateTime sentAt) {
    final local = sentAt.toLocal();
    final now = DateTime.now();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(local.year, local.month, local.day))
        .inDays;
    if (days >= 0 && days <= 7) {
      return const [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد'
      ][local.weekday - 1];
    }
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
}

class MessageInboxFilters extends StatelessWidget {
  const MessageInboxFilters({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Map<String?, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              key: ValueKey('broker-message-filter-${entry.key ?? 'all'}'),
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
              showCheckmark: false,
              labelStyle: theme.textTheme.labelSmall?.copyWith(
                color: selected == entry.key
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              side: BorderSide(
                color: selected == entry.key
                    ? scheme.primary.withValues(alpha: .55)
                    : scheme.outlineVariant,
              ),
              selectedColor: scheme.primaryContainer,
            ),
          ),
      ]),
    );
  }
}
