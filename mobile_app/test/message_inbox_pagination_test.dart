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
import 'package:real_estate_mobile/features/messages/data/unread_inbox_repository.dart';
import 'package:real_estate_mobile/features/messages/presentation/messages_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_reports_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/unread_inbox_badge.dart';

import 'support/phase23_widget_tools.dart';

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
    {int last = 1, int? total, int? unreadCount}) => {
  'data': rows,
  'meta': {'current_page': page, 'last_page': last, 'total': total ?? rows.length,
    if (unreadCount != null) 'unread_count': unreadCount},
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
  phase23WidgetTest('unread badges sum message counts across pages and isolate platform notices', (tester) async {
    var cleared = false;
    final wire = _Wire((request) async {
      final page = request.queryParameters['page'] as int;
      if (cleared) return _page(1, []);
      if (request.path == '/messages/threads') {
        expect(request.queryParameters['unread_only'], 1);
        return _page(page, page == 1
            ? [_row(1, unread: 2), _row(2, unread: 2)]
            : [_row(2, unread: 2), _row(3, unread: 2)], last: 2, total: 3);
      }
      expect(request.path, '/notifications');
      return _page(page, page == 1
          ? [_row(11), {..._row(12), 'type': 'message_received'}]
          : [_row(13), _row(14)], last: 2, total: 4);
    });
    final container = await _open(tester, wire, const Scaffold(body: Row(children: [
      MessageUnreadBadge(child: Icon(Icons.chat_outlined)),
      PlatformNotificationUnreadBadge(child: Icon(Icons.notifications_outlined)),
    ])));
    final messages = find.byKey(const ValueKey('message-unread-total'));
    final notices = find.byKey(const ValueKey('platform-notification-unread-total'));
    expect(find.descendant(of: messages, matching: find.text('6')), findsOneWidget);
    expect(find.descendant(of: notices, matching: find.text('3')), findsOneWidget);
    cleared = true;
    container.read(unreadInboxRevisionProvider.notifier).state++;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(messages, findsNothing);
    expect(notices, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  phase23WidgetTest('the bell skips chat alerts and reaches a platform report on later pages', (tester) async {
    final wire = _Wire((request) async {
      final page = request.queryParameters['page'] as int;
      return _page(page, page == 1
          ? [{..._row(11, label: 'Private chat'), 'type': 'message_received'}]
          : [{..._row(12, label: 'Platform report'), 'type': 'conversation_report_closed',
              'entity_type': 'message_thread'}], last: 2, total: 2);
    });
    await _open(tester, wire, const NotificationsScreen());
    expect(find.text('Private chat'), findsNothing);
    expect(find.text('Platform report'), findsOneWidget);
    expect(wire.pages, [1, 2]);
  });

  phase23WidgetTest('reading all in the bell does not read chat alerts', (tester) async {
    final readPaths = <String>[];
    final wire = _Wire((request) async {
      if (request.method == 'POST') {
        readPaths.add(request.path);
        return {'data': <String, dynamic>{}};
      }
      if (readPaths.length == 2) return _page(1, []);
      final page = request.queryParameters['page'] as int;
      return _page(page, page == 1
          ? [_row(11), {..._row(12), 'type': 'message_received'}]
          : [_row(13)], last: 2, total: 3);
    });
    await _open(tester, wire, const NotificationsScreen());
    await tester.tap(find.text('قراءة الكل'));
    await tester.pumpAndSettle();
    expect(readPaths, ['/notifications/11/read', '/notifications/13/read']);
    expect(find.byKey(const ValueKey('notification-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsNothing);
  });

  phase23WidgetTest('platform history retains read cards and filters with the authoritative unread count', (tester) async {
    final read = {2};
    final writePaths = <String>[];
    final now = DateTime.now();
    final wire = _Wire((request) async {
      if (request.method == 'POST') {
        writePaths.add(request.path);
        if (request.path == '/notifications/history/read-all') {
          read.addAll([1, 3]);
        } else {
          read.add(3);
        }
        return {'data': <String, dynamic>{}};
      }
      final unreadOnly = request.queryParameters['unread_only'] == 1;
      final rows = [for (final id in [3, 2, 1])
        if (!unreadOnly || !read.contains(id)) {
          ..._row(id),
          'created_at': now.subtract(Duration(hours: id)).toIso8601String(),
          if (read.contains(id)) 'read_at': now.toIso8601String(),
        },
      ];
      return _page(1, rows, unreadCount: 3 - read.length);
    });
    await _open(tester, wire, const NotificationsScreen());
    final allTab = find.byKey(const ValueKey('notification-filter-all'));
    final unreadTab = find.byKey(const ValueKey('notification-filter-unread'));
    final count = find.byKey(const ValueKey('platform-history-unread-count'));
    final dot = find.byKey(const ValueKey('notification-unread-dot'));
    Finder card(int id) => find.byKey(ValueKey('notification-$id'));
    expect(tester.getSize(unreadTab).width, tester.getSize(allTab).width);
    expect(tester.getCenter(allTab).dx, greaterThan(tester.getCenter(unreadTab).dx));
    expect(tester.widget<Text>(count).data, '٢');
    expect(dot, findsNWidgets(2));
    expect(card(2), findsOneWidget);
    expect(wire.requests.single.queryParameters['platform_history'], 1);

    await tester.tap(card(3));
    await tester.pumpAndSettle();
    expect(card(3), findsOneWidget);
    expect(find.descendant(of: card(3), matching: dot), findsNothing);
    expect(tester.widget<Text>(count).data, '١');
    await tester.tap(unreadTab);
    await tester.pumpAndSettle();
    expect(wire.requests.last.queryParameters['unread_only'], 1);
    expect(card(1), findsOneWidget);
    expect(card(3), findsNothing);

    await tester.tap(find.text('قراءة الكل'));
    await tester.pumpAndSettle();
    expect(writePaths, ['/notifications/3/read', '/notifications/history/read-all']);
    expect(tester.widget<Text>(count).data, '٠');
    expect(find.text('ما عندك إشعارات غير مقروءة'), findsOneWidget);
    await tester.tap(allTab);
    await tester.pumpAndSettle();
    for (final id in [1, 2, 3]) { expect(card(id), findsOneWidget); }
    expect(dot, findsNothing);
  });

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
    phase23WidgetTest('${screen.name} page-two failure retains forty rows and retries only that page', (tester) async {
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
      phase23WidgetTest('${screen.name} page-two $status clears private rows', (tester) async {
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
      phase23WidgetTest('${screen.name} old page cannot enter ${sameActor ? 'renewed session' : 'another account'}', (tester) async {
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
        if (screen.name == 'reports') {
          expect(find.text('تغيّر الحساب'), findsOneWidget);
          expect(find.byKey(ValueKey('${screen.row}1')), findsNothing);
          final navigator = Navigator.of(tester.element(find.text('تغيّر الحساب')));
          unawaited(navigator.pushReplacement<void, void>(MaterialPageRoute<void>(builder: (_) => screen.widget)));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
        pending.complete(_page(2, [_row(999)], last: 2));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('${screen.row}999')), findsNothing);
        expect(find.byKey(ValueKey('${screen.row}1')), findsNothing);
        expect(find.byKey(ValueKey('${screen.row}700')), findsOneWidget);
      });
    }

    phase23WidgetTest('${screen.name} epoch-only old response leaves a retryable empty screen', (tester) async {
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
    phase23WidgetTest('${screen.name} refresh supersedes an in-flight second page', (tester) async {
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

  phase23WidgetTest('report status replaces pending pages without crossing the filter', (tester) async {
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

  phase23WidgetTest('late authorized report content cannot open in a renewed session', (tester) async {
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
    await tester.pumpAndSettle();
    expect(requested.isCompleted, isTrue);
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

  for (final compact in [false, true]) {
    phase23WidgetTest('unread filter requests a fresh server page (compact: $compact)', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final wire = _Wire((request) async {
        if (request.queryParameters['unread_only'] == 1) return _page(1, [_row(300)], total: 1);
        if (request.queryParameters['page'] == 2) return pending.future;
        return _page(1, [_row(1, unread: 0)], last: 2, total: 250);
      });
      await _open(tester, wire, MessagesScreen(embedded: compact, compact: compact));
      expect(find.text('محادثاتك'), compact ? findsNothing : findsOneWidget);
      expect(find.text('كل الرسائل مقروءة'), findsNothing);
      await _more(tester, 'message-threads-more');
      final filter = find.text('غير المقروء فقط');
      expect(filter.hitTestable(), findsOneWidget);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-thread-300')), findsOneWidget);
      expect(wire.requests.last.queryParameters, {'page': 1, 'per_page': 40, 'unread_only': 1});
      pending.complete(_page(2, [_row(999)], last: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-thread-999')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  phase23WidgetTest('inbox and chat keep conversation history without an unavailable listing cue', (tester) async {
    const property = 'عنوان عقار طويل في حي المطار، بجانب السوق والمدرسة والمسجد';
    const firstLine = 'أرجو إرسال تفاصيل العقار والموقع وطريقة الوصول إليه';
    const secondLine = 'والوقت المناسب لمواصلة المحادثة حول هذا العقار.';
    const history = 'رسالة محفوظة في سجل المحادثة.';
    final messageTime = DateTime.now().subtract(const Duration(days: 8));
    final row = {
      ..._row(71, label: 'عميل الاختبار', unread: 3),
      'property_id': 9,
      'property_title': property,
      'property_status': 'paused',
      'last_message_at': messageTime.toIso8601String(),
      'last_message_preview': '$firstLine\n$secondLine',
      'can_send': false,
    };
    final wire = _Wire((request) async => switch (request.path) {
      '/messages/threads' => _page(1, [row]),
      '/messages/threads/71' => {'data': {
        'thread': row,
        'messages': [{'id': 1, 'sender_user_id': 1071, 'sender_name': 'عميل الاختبار', 'body': history}],
      }},
      '/broker/activity' => _page(1, []),
      _ => throw _failure(request, 404),
    });
    await _open(tester, wire, const MessagesScreen(embedded: true, compact: true));

    final card = find.byKey(const ValueKey('message-thread-71'));
    Finder inCard(Finder widget) => find.descendant(of: card, matching: widget);
    expect(inCard(find.text('عميل الاختبار')), findsOneWidget);
    expect(inCard(find.text('${messageTime.day}/${messageTime.month}')), findsOneWidget);
    expect(inCard(find.text('3')), findsOneWidget);
    expect(inCard(find.textContaining('غير متاح')), findsNothing);
    expect(inCard(find.text(property)), findsNothing);
    final preview = tester.widget<Text>(inCard(find.text('$firstLine $secondLine')));
    expect(preview.maxLines, 1);
    expect(preview.softWrap, isFalse);
    expect(preview.overflow, TextOverflow.ellipsis);

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text(property), findsNothing);
    expect(find.text('غير متاح'), findsNothing);
    expect(find.text(history), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final all in [false, true]) {
    for (final fail in [false, true]) {
      phase23WidgetTest('epoch-only pending ${all ? 'read-all' : 'single read'} ${fail ? 'failure' : 'success'} remains retryable', (tester) async {
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

  phase23WidgetTest('reading resets legacy pagination while keeping the read receipt in all', (tester) async {
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
    expect(find.byKey(const ValueKey('notification-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('notifications-more')), findsNothing);
  });
}
