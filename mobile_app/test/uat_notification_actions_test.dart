import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/network/api_error_message.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';

class _Authenticated extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id': 1, 'name': 'حساب اصطناعي', 'account_status': 'active'});
  void logoutLocally() { state = const AsyncData(null); }
}

class _NotificationsRepository implements MessageRepository {
  Object? failure;
  Completer<void>? pending;
  int singleReads = 0;
  int allReads = 0;
  bool read = false;
  int listReads = 0;
  Completer<List<AppNotificationItem>>? pendingList;

  @override
  Future<List<AppNotificationItem>> notifications() async {
    listReads++;
    if (pendingList != null) return pendingList!.future;
    return [
        AppNotificationItem(
          id: 1,
          type: 'support_reply',
          title: 'رد فريق الدعم',
          isRead: read,
          entityType: 'support_case',
          entityId: 42,
        ),
      ];
  }

  @override
  Future<void> readNotification(int id) async {
    singleReads++;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
    read = true;
  }

  @override
  Future<void> readAllNotifications() async {
    allReads++;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
    read = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _mount(
    WidgetTester tester, _NotificationsRepository repository, {_Authenticated? auth}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const NotificationsScreen()),
    GoRoute(
      path: '/support',
      builder: (_, state) => Scaffold(
        body: Text('support-case-${state.uri.queryParameters['case']}'),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [messageRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => auth ?? _Authenticated())],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  final offline = DioException(
    requestOptions: RequestOptions(path: '/notifications/read-all'),
    type: DioExceptionType.connectionError,
  );

  testWidgets('opening a notification recovers from offline failure and retries',
      (tester) async {
    final repository = _NotificationsRepository()..failure = offline;
    await _mount(tester, repository);

    await tester.tap(find.text('رد فريق الدعم'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(friendlyApiError(offline)), findsOneWidget);
    expect(find.text('support-case-42'), findsNothing);
    expect(repository.read, isFalse);

    repository.failure = null;
    await tester.tap(find.text('رد فريق الدعم'));
    await tester.pumpAndSettle();
    expect(find.text('support-case-42'), findsOneWidget);
    expect(repository.singleReads, 2);
  });

  testWidgets('read all shows session expiry and remains available for retry',
      (tester) async {
    final request = RequestOptions(path: '/notifications/read-all');
    final expired = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<void>(requestOptions: request, statusCode: 401),
    );
    final repository = _NotificationsRepository()..failure = expired;
    await _mount(tester, repository);
    await tester.tap(find.text('قراءة الكل'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(friendlyApiError(expired)), findsOneWidget);
    expect(repository.read, isFalse);

    repository.failure = null;
    await tester.tap(find.text('قراءة الكل'));
    await tester.pumpAndSettle();
    expect(repository.allReads, 2);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
  });

  testWidgets('pending actions ignore repeated taps and completion after dispose',
      (tester) async {
    final repository = _NotificationsRepository()..pending = Completer<void>();
    await _mount(tester, repository);
    await tester.tap(find.text('قراءة الكل'));
    await tester.pump();
    await tester.tap(find.text('قراءة الكل'));
    expect(repository.allReads, 1);
    await tester.pumpWidget(const SizedBox());
    repository.pending!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('logout hides notifications and ignores an old pending list response', (tester) async {
    final auth = _Authenticated(), repo = _NotificationsRepository()..pendingList = Completer<List<AppNotificationItem>>();
    await _mount(tester, repo, auth: auth);
    expect(repo.listReads, 1);
    auth.logoutLocally(); await tester.pumpAndSettle();
    repo.pendingList!.complete([const AppNotificationItem(id: 1, type: 'support_reply', title: 'رد خاص اصطناعي', isRead: false)]);
    await tester.pumpAndSettle();
    expect(find.text('رد خاص اصطناعي'), findsNothing);
    expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
