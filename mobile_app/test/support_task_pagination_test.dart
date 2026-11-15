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
import 'package:real_estate_mobile/features/support/data/support_workspace_repository.dart';
import 'package:real_estate_mobile/features/support/presentation/support_tasks_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic support $id', 'account_status': 'active',
  'roles': ['support_agent'], 'permissions': ['listings.moderate'],
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

Map<String, dynamic> _task(int id, {String? subject}) => {
  'id': id, 'source_type': 'listing_review', 'source_id': id,
  'subject': subject ?? 'Synthetic task $id', 'status': 'new',
  'priority': 'normal', 'is_mine': false, 'can_claim': false,
  'is_overdue': false,
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
      } on DioException catch (error) {
        handler.reject(error);
      }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.map((r) => r.queryParameters['page'] as int);
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

Future<ProviderContainer> _open(WidgetTester tester, _Wire wire) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: const SupportTasksScreen())));
  await tester.pumpAndSettle();
  return container;
}

Finder get _verticalList => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);

Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('support-tasks-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first,
      maxScrolls: 50);
  await tester.tap(more);
  await tester.pump();
}

void main() {
  test('task repository sends page and filters and reads the server page boundary', () async {
    final wire = _Wire((r) async => _page(2, [_task(40), _task(41)], last: 3, total: 81));
    final container = await _container(wire);
    final result = await container.read(supportWorkspaceRepositoryProvider).tasks(
      page: 2, scope: 'mine', type: 'listing_review', status: 'new',
      priority: 'urgent', severity: 'high', assigneeId: 6,
      createdFrom: DateTime.utc(2026, 11, 1), createdTo: DateTime.utc(2026, 11, 12),
      overdue: true, actingAsAgent: true);
    expect(wire.requests.single.path, '/admin/workspace/tasks');
    expect(wire.requests.single.queryParameters, {
      'page': 2, 'per_page': 40, 'scope': 'mine', 'type': 'listing_review',
      'status': 'new', 'priority': 'urgent', 'severity': 'high', 'assignee_id': 6,
      'created_from': '2026-11-01T00:00:00.000Z',
      'created_to': '2026-11-12T00:00:00.000Z', 'overdue': 1, 'acting_as_agent': 1,
    });
    expect(result.items.map((row) => row.id), [40, 41]);
    expect(result.currentPage, 2);
    expect(result.total, 81);
    expect(result.hasMore, isTrue);
  });

  test('missing or mismatched page metadata is an error rather than a false end', () async {
    var invalid = <String, dynamic>{'data': <Object>[]};
    final wire = _Wire((_) async => invalid);
    final container = await _container(wire);
    final repository = container.read(supportWorkspaceRepositoryProvider);
    await expectLater(repository.tasks(), throwsStateError);
    invalid = _page(1, []);
    await expectLater(repository.tasks(page: 2), throwsStateError);
    await expectLater(repository.tasks(page: 0), throwsArgumentError);
    await expectLater(repository.tasks(perPage: 101), throwsArgumentError);
    expect(wire.requests.length, 2);
  });

  test('waiting for credentials cannot send a page using the next account session', () async {
    final credentials = _Credentials()..pending = Completer<void>();
    final wire = _Wire((_) async => _page(1, [_task(1)]));
    final container = await _container(wire, credentials: credentials);
    final request = container.read(supportWorkspaceRepositoryProvider).tasks();
    final rejected = expectLater(request, throwsStateError);
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    credentials.pending!.complete();
    await rejected;
    expect(wire.requests, isEmpty);
  });

  test('completed page is rejected when the secure session changes before delivery', () async {
    final pending = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final wire = _Wire((_) { requested.complete(); return pending.future; });
    final container = await _container(wire);
    final request = container.read(supportWorkspaceRepositoryProvider).tasks();
    final rejected = expectLater(request, throwsStateError);
    await requested.future;
    Stage6SecureSessionStore.instance.beginSessionChange();
    pending.complete(_page(1, [_task(1)]));
    await rejected;
  });

  testWidgets('long inbox retains rows on page-two 503 and retries at the footer', (tester) async {
    var fail = true;
    final wire = _Wire((request) async {
      if (request.queryParameters['page'] == 1) {
        return _page(1, [for (var id = 1; id <= 40; id++) _task(id)], last: 2, total: 41);
      }
      if (fail) throw _failure(request, 503);
      return _page(2, [_task(40, subject: 'Updated task 40'), _task(41)], total: 41, last: 2);
    });
    await _open(tester, wire);
    expect(find.byKey(const ValueKey('support-task-1')), findsOneWidget);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2]);
    expect(find.byType(AppErrorState), findsNothing);
    await tester.scrollUntilVisible(find.text('إعادة المحاولة'), 120,
      scrollable: _verticalList.first, maxScrolls: 4);
    // ensureVisible updates scroll offset; render the new layout before hit testing.
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة').hitTestable(), findsOneWidget);
    expect(tester.state<ScrollableState>(_verticalList.first).position.pixels,
      greaterThan(1000));
    fail = false;
    await tester.tap(find.text('إعادة المحاولة').hitTestable());
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 2]);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('support-task-41')),
      200, scrollable: _verticalList.first);
    expect(find.text('Updated task 40'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-task-40')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-tasks-more')), findsNothing);
    expect(find.text('إعادة المحاولة'), findsNothing);
    await tester.drag(_verticalList.first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 2]);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('support-task-1')),
      -600, scrollable: _verticalList.first, maxScrolls: 50);
    expect(find.byKey(const ValueKey('support-task-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page-two access denial removes the retained private inbox', (tester) async {
    final wire = _Wire((request) async {
      if (request.queryParameters['page'] == 2) throw _failure(request, 403);
      return _page(1, [_task(1)], last: 2, total: 2);
    });
    await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-task-1')), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byKey(const ValueKey('support-tasks-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late page from a previous filter cannot append to the new inbox', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final wire = _Wire((request) async {
      if (request.queryParameters['page'] == 2) return pending.future;
      if (request.queryParameters['type'] == 'listing_review') return _page(1, [_task(10)]);
      return _page(1, [_task(1)], last: 2, total: 2);
    });
    await _open(tester, wire);
    await _next(tester);
    await tester.ensureVisible(find.text('تحقيق إعلانات'));
    await tester.tap(find.text('تحقيق إعلانات'));
    await tester.pump();
    pending.complete(_page(2, [_task(99)], last: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(wire.requests.last.queryParameters['type'], 'listing_review');
    expect(find.byKey(const ValueKey('support-task-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-task-1')), findsNothing);
    expect(find.byKey(const ValueKey('support-task-99')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh supersedes an in-flight next page without restoring old tasks', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var firstPage = 0;
    final wire = _Wire((request) async {
      if (request.queryParameters['page'] == 2) return pending.future;
      firstPage++;
      return firstPage == 1 ? _page(1, [_task(1)], last: 2, total: 2)
        : _page(1, [_task(10)]);
    });
    await _open(tester, wire);
    await _next(tester);
    await tester.tap(find.byTooltip('تحديث'));
    await tester.pump();
    pending.complete(_page(2, [_task(99)], last: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(find.byKey(const ValueKey('support-task-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-task-1')), findsNothing);
    expect(find.byKey(const ValueKey('support-task-99')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-session account metadata refresh keeps the loaded page', (tester) async {
    final wire = _Wire((request) async => _page(1, [_task(1)], last: 2, total: 2));
    final container = await _open(tester, wire);
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    await tester.pumpAndSettle();
    expect(wire.pages, [1]);
    expect(find.byKey(const ValueKey('support-task-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-tasks-more')), findsOneWidget);
  });

  testWidgets('load more restarts at page one if the secure session changed', (tester) async {
    var firstPage = 0;
    final wire = _Wire((request) async {
      firstPage++;
      return _page(1, [_task(firstPage)], last: 2, total: 2);
    });
    await _open(tester, wire);
    Stage6SecureSessionStore.instance.beginSessionChange();
    await _next(tester);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 1]);
    expect(find.byKey(const ValueKey('support-task-1')), findsNothing);
    expect(find.byKey(const ValueKey('support-task-2')), findsOneWidget);
  });

  for (final boundary in ['account switch', 'same-account relogin', 'same-ID token replacement']) {
    testWidgets('late page cannot cross $boundary', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var firstPage = 0;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 2) return pending.future;
        firstPage++;
        return firstPage == 1 ? _page(1, [_task(1)], last: 2, total: 2)
          : _page(1, [_task(10, subject: 'New session task')]);
      });
      final container = await _open(tester, wire);
      await _next(tester);
      final auth = container.read(authControllerProvider.notifier) as _Auth;
      if (boundary == 'same-ID token replacement') {
        Stage6SecureSessionStore.instance.beginSessionChange();
        auth.change(6);
      } else {
        auth.change(null);
        auth.change(boundary == 'same-account relogin' ? 6 : 7);
      }
      pending.complete(_page(2, [_task(99)], last: 2));
      await tester.pumpAndSettle();
      expect(find.text('New session task'), findsOneWidget);
      expect(find.byKey(const ValueKey('support-task-1')), findsNothing);
      expect(find.byKey(const ValueKey('support-task-99')), findsNothing);
      expect(wire.pages, [1, 2, 1]);
      expect(tester.takeException(), isNull);
    });
  }
}
