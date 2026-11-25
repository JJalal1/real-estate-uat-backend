import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/offline/offline_connection.dart';
import '../../account/data/auth_controller.dart';
import '../domain/message_models.dart';
import 'message_repository.dart';

final unreadInboxRevisionProvider = StateProvider<int>((ref) => 0);

final messageUnreadCountProvider =
    Provider.autoDispose<int>((ref) => _watchCount(ref, _InboxKind.messages));

final platformNotificationUnreadCountProvider = Provider.autoDispose<int>(
    (ref) => _watchCount(ref, _InboxKind.platformNotifications));

enum _InboxKind { messages, platformNotifications }

typedef _InboxScope = (int actor, int sessionEpoch, _InboxKind kind);

int _watchCount(Ref ref, _InboxKind kind) {
  final actor = ref.watch(authControllerProvider).asData?.value?.id;
  if (actor == null) return 0;
  final scope = (actor, Stage6SecureSessionStore.instance.sessionEpoch, kind);
  final count = ref.watch(_unreadCountProvider(scope));
  return count.hasError ? 0 : count.valueOrNull ?? 0;
}

final _unreadCountProvider =
    FutureProvider.autoDispose.family<int, _InboxScope>(
  (ref, scope) async {
    ref.watch(unreadInboxRevisionProvider);
    ref.watch(offlineResumeRevisionProvider);
    if (scope.$3 == _InboxKind.messages) ref.watch(messageDataRevisionProvider);
    final offline = ref.watch(offlineConnectionProvider.select((value) =>
        value == OfflineConnection.offline ||
        value == OfflineConnection.unavailable));
    if (offline) return 0;

    final repository = ref.watch(messageRepositoryProvider);
    var disposed = false;
    ref.onDispose(() => disposed = true);

    bool current() =>
        !disposed && Stage6SecureSessionStore.instance.sessionEpoch == scope.$2;

    switch (scope.$3) {
      case _InboxKind.messages:
        return _countAcrossPages<MessageThreadSummary>(
          (page) => repository.threadsPage(
              page: page, perPage: 250, unreadOnly: true),
          (item) => MapEntry(item.id, item.unreadCount),
          current,
        );
      case _InboxKind.platformNotifications:
        final probe = await repository.notificationsPage(
            perPage: 1, platformHistory: true, unreadOnly: true);
        if (!current()) return 0;
        final reported = probe.unreadCount;
        if (reported != null) return reported;
        // Older servers ignore the history flags. Use their unread pages
        // while applying the same platform and age boundaries on-device.
        final now = DateTime.now();
        return _countAcrossPages<AppNotificationItem>(
          (page) => repository.notificationsPage(page: page, perPage: 200),
          (item) => MapEntry(
              item.id, item.isRecentPlatformNotification(now) && !item.isRead ? 1 : 0),
          current,
        );
    }
  },
);

Future<int> _countAcrossPages<T>(
  Future<MessageInboxPage<T>> Function(int page) loadPage,
  MapEntry<int, int> Function(T item) countItem,
  bool Function() current,
) async {
  final counts = <int, int>{};
  var page = await loadPage(1);
  final lastPage = page.lastPage;
  while (current()) {
    counts.addEntries(page.items.map(countItem));
    if (!page.hasMore || page.currentPage >= lastPage) {
      return counts.values.fold<int>(0, (sum, count) => sum + count);
    }
    page = await loadPage(page.currentPage + 1);
  }
  return 0;
}
