import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/unread_inbox_repository.dart';

class MessageUnreadBadge extends ConsumerWidget {
  const MessageUnreadBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _UnreadBadge(
        count: ref.watch(messageUnreadCountProvider),
        noun: 'رسالة غير مقروءة',
        badgeKey: const ValueKey('message-unread-total'),
        child: child,
      );
}

class PlatformNotificationUnreadBadge extends ConsumerWidget {
  const PlatformNotificationUnreadBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _UnreadBadge(
        count: ref.watch(platformNotificationUnreadCountProvider),
        noun: 'إشعار غير مقروء',
        badgeKey: const ValueKey('platform-notification-unread-total'),
        child: child,
      );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
    required this.noun,
    required this.badgeKey,
    required this.child,
  });

  final int count;
  final String noun;
  final Key badgeKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge(
      key: badgeKey,
      backgroundColor: const Color(0xffb91c1c),
      textColor: Colors.white,
      label: Text(
        count > 99 ? '99+' : '$count',
        textDirection: TextDirection.ltr,
        semanticsLabel: '$count $noun',
      ),
      child: child,
    );
  }
}
