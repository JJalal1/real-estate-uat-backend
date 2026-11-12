import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/presentation/messages_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_reports_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic actor $id', 'account_status': 'active',
  'roles': ['support_agent'],
  'permissions': ['support.handle_reports', 'conversations.review_private'],
});

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(6);
  void change(int? id) => state = AsyncData(id == null ? null : _user(id));
}

class _Credentials implements AuthRepository {
  Completer<void>? pending;
  @override
  Future<Options> requiredAuthOptions() async {
    if (pending != null) await pending!.future;
    return Options(headers: {'Authorization': 'Bearer synthetic-only'});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

Map<String, dynamic> _row(int id, {String? label, int unread = 1}) => {
  'id': id, 'other_user': {'id': id + 1000, 'name': label ?? 'Synthetic row $id'},
  'unread_count': unread, 'thread_id': id, 'reporter_name': 'Synthetic reporter',
  'reason_code': 'other', 'status': 'open', 'property_title': label ?? 'Synthetic row $id',
  'title': label ?? 'Synthetic row $id', 'type': 'synthetic_notice', 'read_at': null,
};

Map<String, dynamic> _page(int page, List<Map<String, dynamic>> rows,
    {int last = 1, int? total}) => {
  'data': rows,
  'meta': {'current_page': page, 'last_page': last, 'total': total ?? rows.length},
};

DioException _failure(RequestOptions request, int status) => DioException(
  requestOptions: request, type: DioExceptionType.badResponse,
  response: Response(requestOptions: request, statusCode: status),
);

class _Wire {
  _Wire(this.respond) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: request, statusCode: 200, data: await respond(request)));
      } on DioException catch (error) { handler.reject(error); }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.where((r) => r.queryParameters['page'] != null)
      .map((r) => r.queryParameters['page'] as int);
}

Future<ProviderContainer> _container(_Wire wire, {_Credentials? credentials}) async {
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    authRepositoryProvider.overrideWithValue(credentials ?? _Credentials()),
    dioProvider.overrideWithValue(wire.dio),
  ]);
  await container.read(authControllerProvider.future);
  addTearDown(() { container.dispose(); wire.dio.close(force: true); });
  return container;
}

const _screens = [
  (name: 'threads', widget: MessagesScreen(), more: 'message-threads-more', row: 'message-thread-', route: '/messages/threads'),
  (name: 'notifications', widget: NotificationsScreen(), more: 'notifications-more', row: 'notification-', route: '/notifications'),
  (name: 'reports', widget: ConversationReportsScreen(), more: 'conversation-reports-more', row: 'conversation-report-', route: '/admin/messages/reports'),
];

Future<ProviderContainer> _open(WidgetTester tester, _Wire wire, Widget screen) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: screen)));
  await tester.pumpAndSettle();
  return container;
}
Finder get _vertical => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);
Future<void> _show(WidgetTester tester, Finder finder, {double delta = 600}) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: _vertical.first, maxScrolls: 70);
  await tester.pumpAndSettle();
}
Future<void> _more(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _show(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

void main() {
  test('all three repositories preserve route, page, filters and metadata', () async {
    final wire = _Wire((_) async => _page(2, [_row(41)], last: 3, total: 81));
    final container = await _container(wire);
    final repository = container.read(messageRepositoryProvider);
    final threads = await repository.threadsPage(page: 2, unreadOnly: true);
    final notifications = await repository.notificationsPage(page: 2);
    final reports = await repository.adminReportsPage(page: 2, status: 'under_review');
    expect(wire.requests.map((r) => r.path), _screens.map((s) => s.route));
    expect(wire.requests.map((r) => r.queryParameters), [
      {'page': 2, 'per_page': 40, 'unread_only': 1},
      {'page': 2, 'per_page': 40},
      {'page': 2, 'per_page': 40, 'status': 'under_review'},
    ]);
    for (final result in [threads, notifications, reports]) {
      expect(result.currentPage, 2); expect(result.hasMore, isTrue); expect(result.total, 81);
    }
  });

  test('invalid page metadata and bounds do not silently claim the end', () async {
    var response = <String, dynamic>{'data': <Object>[]};
    final wire = _Wire((_) async => response);
    final container = await _container(wire);
    final repo = container.read(messageRepositoryProvider);
    await expectLater(repo.threadsPage(), throwsStateError);
    await expectLater(repo.notificationsPage(), throwsStateError);
    await expectLater(repo.adminReportsPage(), throwsStateError);
    response = _page(1, []);
    await expectLater(repo.threadsPage(page: 2), throwsStateError);
    await expectLater(repo.notificationsPage(page: 0), throwsArgumentError);
    await expectLater(repo.adminReportsPage(perPage: 201), throwsArgumentError);
    await expectLater(repo.threadsPage(perPage: 251), throwsArgumentError);
    expect(wire.requests.length, 4);
  });

  for (final kind in ['threads', 'notifications', 'reports']) {
    test('$kind pending credentials cannot acquire a replacement session', () async {
      final credentials = _Credentials()..pending = Completer<void>();
      final wire = _Wire((_) async => _page(1, []));
      final container = await _container(wire, credentials: credentials);
      final repo = container.read(messageRepositoryProvider);
      final request = switch (kind) {
        'threads' => repo.threadsPage(), 'notifications' => repo.notificationsPage(),
        _ => repo.adminReportsPage(),
      };
      final rejected = expectLater(request, throwsStateError);
      Stage6SecureSessionStore.instance.beginSessionChange();
      credentials.pending!.complete();
      await rejected;
      expect(wire.requests, isEmpty);
    });
  }

  for (final screen in _screens) {
    testWidgets('${screen.name} page-two failure retains forty rows and retries only that page', (tester) async {
      var fail = true;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 1) {
          return _page(1, [for (var id = 1; id <= 40; id++) _row(id)], last: 2, total: 41);
        }
        if (fail) throw _failure(request, 503);
        return _page(2, [_row(40, label: 'Updated synthetic 40'), _row(41)], last: 2, total: 41);
      });
      await _open(tester, wire, screen.widget);
      expect(find.byKey(ValueKey('${screen.row}1')), findsOneWidget);
      await _more(tester, screen.more);
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2]);
      expect(find.byType(AppErrorState), findsNothing);
      await _show(tester, find.text('إعادة المحاولة'), delta: 200);
      expect(find.text('إعادة المحاولة').hitTestable(), findsOneWidget);
      expect(tester.state<ScrollableState>(_vertical.first).position.pixels, greaterThan(1000));
      fail = false;
      await tester.tap(find.text('إعادة المحاولة').hitTestable());
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      await _show(tester, find.byKey(ValueKey('${screen.row}41')), delta: 200);
      expect(find.byKey(ValueKey('${screen.row}40')), findsOneWidget);
      expect(find.text('Updated synthetic 40'), findsWidgets);
      expect(find.byKey(ValueKey(screen.more)), findsNothing);
      await tester.drag(_vertical.first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      await _show(tester, find.byKey(ValueKey('${screen.row}1')), delta: -600);
      expect(find.byKey(ValueKey('${screen.row}1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final status in [401, 403]) {
      testWidgets('${screen.name} page-two $status clears private rows', (tester) async {
        final wire = _Wire((request) async {
          if (request.queryParameters['page'] == 2) throw _failure(request, status);
          return _page(1, [_row(1)], last: 2, total: 2);
        });
        await _open(tester, wire, screen.widget);
        await _more(tester, screen.more); await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('${screen.row}1')), findsNothing);
        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.byKey(ValueKey(screen.more)), findsNothing);
      });
    }

    for (final sameActor in [false, true]) {
      testWidgets('${screen.name} old page cannot enter ${sameActor ? 'renewed session' : 'another account'}', (tester) async {
        final pending = Completer<Map<String, dynamic>>(); var first = true;
        final wire = _Wire((request) async {
          if (request.queryParameters['page'] == 2) return pending.future;
          final id = first ? 1 : 700; first = false;
          return _page(1, [_row(id)], last: id == 1 ? 2 : 1, total: id == 1 ? 2 : 1);
        });
        final container = await _open(tester, wire, screen.widget);
        await _more(tester, screen.more);
        Stage6SecureSessionStore.instance.beginSessionChange();
        (container.read(authControllerProvider.notifier) as _Auth).change(sameActor ? 6 : 7);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
        pending.complete(_page(2, [_row(999)], last: 2));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('${screen.row}999')), findsNothing);
        expect(find.byKey(ValueKey('${screen.row}1')), findsNothing);
        expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
      });
    }

    testWidgets('${screen.name} epoch-only old response leaves a retryable empty screen', (tester) async {
      final pending = Completer<Map<String, dynamic>>(); var next = false;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 2) return pending.future;
        return _page(1, [_row(next ? 700 : 1)], last: next ? 1 : 2, total: 2);
      });
      await _open(tester, wire, screen.widget);
      await _more(tester, screen.more);
      Stage6SecureSessionStore.instance.beginSessionChange(); next = true;
      pending.complete(_page(2, [_row(999)], last: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('${screen.row}999')), findsNothing);
      expect(find.byKey(ValueKey('${screen.row}1')), findsNothing);
      await _show(tester, find.text('إعادة المحاولة'));
      await tester.tap(find.text('إعادة المحاولة').hitTestable()); await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
      expect(wire.pages, [1, 2, 1]);
    });
  }

  for (final screen in _screens) {
    testWidgets('${screen.name} refresh supersedes an in-flight second page', (tester) async {
      final pending = Completer<Map<String, dynamic>>(); var first = true;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 2) return pending.future;
        final id = first ? 1 : 700; first = false;
        return _page(1, [_row(id)], last: id == 1 ? 2 : 1, total: 2);
      });
      await _open(tester, wire, screen.widget);
      await _more(tester, screen.more);
      unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
      await tester.pumpAndSettle();
      pending.complete(_page(2, [_row(999)], last: 2)); await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 1]);
      expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
      expect(find.byKey(ValueKey('${screen.row}999')), findsNothing);
      expect(find.byKey(ValueKey(screen.more)), findsNothing);
    });
  }

  testWidgets('report status replaces pending pages without crossing the filter', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final wire = _Wire((request) async {
      if (request.queryParameters['status'] == 'resolved') return _page(1, [_row(300)]);
      if (request.queryParameters['page'] == 2) return pending.future;
      return _page(1, [_row(1)], last: 2, total: 2);
    });
    await _open(tester, wire, const ConversationReportsScreen());
    await _more(tester, 'conversation-reports-more');
    await tester.tap(find.byKey(const ValueKey('conversation-reports-status')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('تم الحل').last); await tester.pumpAndSettle();
    expect(wire.requests.last.queryParameters, {'page': 1, 'per_page': 40, 'status': 'resolved'});
    pending.complete(_page(2, [_row(999)], last: 2)); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conversation-report-300')), findsOneWidget);
    expect(find.byKey(const ValueKey('conversation-report-999')), findsNothing);
  });

  testWidgets('late authorized report content cannot open in a renewed session', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final wire = _Wire((request) async {
      if (request.path.endsWith('/content')) { requested.complete(); return pending.future; }
      return _page(1, [_row(1)]);
    });
    final container = await _open(tester, wire, const ConversationReportsScreen());
    await tester.tap(find.byKey(const ValueKey('conversation-report-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فتح وتسجيل الوصول'));
    await tester.pump(); await requested.future;
    Stage6SecureSessionStore.instance.beginSessionChange();
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    await tester.pumpAndSettle();
    pending.complete({'data': {'report': _row(1), 'messages': [
      {'id': 1, 'sender_user_id': 2, 'sender_name': 'Synthetic private sender', 'body': 'PRIVATE OLD SESSION CONTENT'},
    ]}});
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE OLD SESSION CONTENT'), findsNothing);
    expect(find.text('بلاغ #1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unread filter requests a fresh server page before claiming empty', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final wire = _Wire((request) async {
      if (request.queryParameters['unread_only'] == 1) return _page(1, [_row(300)], total: 1);
      if (request.queryParameters['page'] == 2) return pending.future;
      return _page(1, [_row(1, unread: 0)], last: 2, total: 250);
    });
    await _open(tester, wire, const MessagesScreen());
    expect(find.text('كل الرسائل مقروءة'), findsNothing);
    await _more(tester, 'message-threads-more');
    await tester.tap(find.text('غير المقروء فقط')); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-thread-300')), findsOneWidget);
    expect(wire.requests.last.queryParameters, {'page': 1, 'per_page': 40, 'unread_only': 1});
    pending.complete(_page(2, [_row(999)], last: 2)); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-thread-999')), findsNothing);
  });

  for (final all in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets('epoch-only pending ${all ? 'read-all' : 'single read'} ${fail ? 'failure' : 'success'} remains retryable', (tester) async {
        final pending = Completer<Map<String, dynamic>>(); var fresh = false; var postCount = 0;
        final wire = _Wire((request) async {
          if (request.method == 'POST') {
            postCount++;
            if (postCount == 1) {
              await pending.future;
              if (fail) throw _failure(request, 503);
            }
            return {'data': <String, dynamic>{}};
          }
          return _page(1, [_row(fresh ? 700 : 1)]);
        });
        await _open(tester, wire, const NotificationsScreen());
        await tester.tap(all ? find.text('قراءة الكل') : find.byKey(const ValueKey('notification-1')));
        await tester.pump();
        Stage6SecureSessionStore.instance.beginSessionChange(); fresh = true;
        pending.complete({'data': <String, dynamic>{}}); await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('notification-1')), findsNothing);
        expect(find.text('تمت قراءة الإشعار ولا توجد صفحة مرتبطة به.'), findsNothing);
        await _show(tester, find.text('إعادة المحاولة'));
        await tester.tap(find.text('إعادة المحاولة').hitTestable()); await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('notification-700')), findsOneWidget);
        await tester.tap(all ? find.text('قراءة الكل') : find.byKey(const ValueKey('notification-700')));
        await tester.pumpAndSettle();
        expect(postCount, 2, reason: 'The old action must release only its own busy state');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('reading a notification resets its unread dataset to page one', (tester) async {
    var read = false;
    final wire = _Wire((request) async {
      if (request.method == 'POST') { read = true; return {'data': <String, dynamic>{}}; }
      if (read) return _page(1, [_row(2)], total: 1);
      return _page(1, [_row(1)], last: 2, total: 2);
    });
    await _open(tester, wire, const NotificationsScreen());
    await tester.tap(find.byKey(const ValueKey('notification-1'))); await tester.pumpAndSettle();
    expect(wire.requests.map((r) => r.path), ['/notifications', '/notifications/1/read', '/notifications']);
    expect(wire.pages, [1, 1]);
    expect(find.byKey(const ValueKey('notification-1')), findsNothing);
    expect(find.byKey(const ValueKey('notification-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('notifications-more')), findsNothing);
  });
}
