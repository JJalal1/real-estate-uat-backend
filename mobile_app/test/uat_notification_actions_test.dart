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
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';

class _Authenticated extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id': 1, 'name': 'حساب اصطناعي', 'account_status': 'active'});
  void logoutLocally() { state = const AsyncData(null); }
}

class _NotificationsRepository implements MessageRepository {
  _NotificationsRepository({this.notification});

  final AppNotificationItem? notification;
  Object? failure;
  Completer<void>? pending;
  int singleReads = 0;
  bool read = false;
  int listReads = 0;
  Completer<List<AppNotificationItem>>? pendingList;

  @override
  Future<List<AppNotificationItem>> notifications() async {
    listReads++;
    if (pendingList != null) return pendingList!.future;
    final custom = notification;
    if (custom != null) return read ? const [] : [custom];
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
  Future<NotificationPage> notificationsPage({int page = 1, int perPage = 40,
      bool platformHistory = false, bool unreadOnly = false}) async {
    final rows = (await notifications()).where((item) => !item.isRead).toList(growable: false);
    return NotificationPage(items: rows, currentPage: page, lastPage: page, total: rows.length);
  }
  @override
  Future<void> readNotification(int id) async {
    singleReads++;
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
    GoRoute(
      path: '/properties/:id',
      builder: (_, state) => Scaffold(
        body: Text('property-${state.pathParameters['id']}'),
      ),
    ),
    GoRoute(
      path: '/support/listing-decision/:id',
      builder: (_, state) => Scaffold(
        body: Text('decision-${state.pathParameters['id']}'),
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
    requestOptions: RequestOptions(path: '/notifications/1/read'),
    type: DioExceptionType.connectionError,
  );

  testWidgets('publication opens the approved listing by its notification entity', (tester) async {
    final repository = _NotificationsRepository(notification: AppNotificationItem.fromJson({
      'id': 2,
      'type': 'listing_approved',
      'title': 'تم اعتماد إعلانك ونشره',
      'entity_type': 'property',
      'entity_id': 107,
      'data': {'review_status': 'approved'},
    }));
    await _mount(tester, repository);
    await tester.tap(find.text('تم اعتماد إعلانك ونشره'));
    await tester.pumpAndSettle();
    expect(find.text('property-107'), findsOneWidget);
    expect(repository.singleReads, 1);
  });

  testWidgets('duplicate rejection displays the exact reason and opens the previous listing', (tester) async {
    const reason = 'سبق نشره من قبلك. تطابقت الوحدة والمبنى مع الإعلان السابق.';
    final repository = _NotificationsRepository(notification: AppNotificationItem.fromJson({
      'id': 1,
      'type': 'listing_duplicate_rejected',
      'title': 'رُفض الإعلان لتكراره',
      'body': reason,
      'entity_type': 'property',
      'entity_id': 107,
      'data': {'previous_property_id': 106, 'previous_listing_same_owner': true},
    }));
    await _mount(tester, repository);
    expect(find.text(reason), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'عرض الإعلان المشابه'));
    await tester.pumpAndSettle();
    expect(find.text('property-106'), findsOneWidget);
    expect(find.text('property-107'), findsNothing);
    expect(repository.singleReads, 1);
  });

  testWidgets('a similarity correction also opens the affected listing decision for support', (tester) async {
    final repository = _NotificationsRepository(notification: AppNotificationItem.fromJson({
      'id': 1, 'type': 'listing_returned_for_correction', 'title': 'أُعيد إعلانك',
      'body': 'رقم الوحدة يحتاج إلى توضيح.', 'entity_type': 'property', 'entity_id': 107,
      'data': {'previous_property_id': 106},
    }));
    await _mount(tester, repository);
    expect(find.widgetWithText(TextButton, 'عرض الإعلان المشابه'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'مراجعة الدعم'));
    await tester.pumpAndSettle();
    expect(find.text('decision-107'), findsOneWidget);
    expect(repository.singleReads, 1);
  });

  test('duplicate rejection does not link to the rejected listing', () {
    final malformed = AppNotificationItem.fromJson({
      'type': 'listing_duplicate_rejected',
      'entity_type': 'property',
      'entity_id': 107,
      'data': {'previous_property_id': 107},
    });
    expect(notificationDestination(malformed), isNull);
  });

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
    final request = RequestOptions(path: '/notifications/1/read');
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
    expect(repository.singleReads, 2);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
  });

  testWidgets('pending actions ignore repeated taps and completion after dispose',
      (tester) async {
    final repository = _NotificationsRepository()..pending = Completer<void>();
    await _mount(tester, repository);
    await tester.tap(find.text('قراءة الكل'));
    await tester.pump();
    await tester.tap(find.text('قراءة الكل'));
    expect(repository.singleReads, 1);
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
