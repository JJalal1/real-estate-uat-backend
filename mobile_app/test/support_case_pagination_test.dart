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
import 'package:real_estate_mobile/features/support/data/support_repository.dart';
import 'package:real_estate_mobile/features/support/presentation/support_admin_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_center_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic account $id', 'account_status': 'active',
  'roles': ['super_admin'], 'permissions': ['support.manage'],
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

Map<String, dynamic> _case(int id, {String? subject}) => {
  'id': id, 'reference': 'SYN-$id', 'kind': 'support_ticket',
  'subject': subject ?? 'Synthetic case $id', 'status': 'open',
  'priority': 'normal', 'escalation_level': 0,
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
          requestOptions: request, statusCode: 200,
          data: request.path == '/admin/support/summary'
            ? {'data': {'new_tickets': 7}} : await respond(request)));
      } on DioException catch (error) {
        handler.reject(error);
      }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.where((r) => r.queryParameters.containsKey('page'))
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
Future<ProviderContainer> _open(WidgetTester tester, _Wire wire, {required bool admin}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: admin
      ? const SupportAdminScreen() : const SupportCenterScreen())));
  await tester.pumpAndSettle();
  return container;
}
Finder get _verticalList => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);
Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('support-cases-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first, maxScrolls: 50);
  await tester.tap(more);
  await tester.pump();
}

void main() {
  test('case repositories preserve filters, page metadata and endpoint size limits', () async {
    final wire = _Wire((r) async => _page(2, [_case(31)], last: 3, total: 70));
    final container = await _container(wire);
    final repository = container.read(supportRepositoryProvider);
    final mine = await repository.mine(page: 2);
    expect(wire.requests.last.path, '/support/cases/mine');
    expect(wire.requests.last.queryParameters, {'page': 2, 'per_page': 30});
    expect(mine.currentPage, 2);
    expect(mine.total, 70);
    expect(mine.hasMore, isTrue);
    final admin = await repository.adminCases(page: 2, kind: 'report', status: 'open',
      escalated: true, assignedToMe: true, assignedToUserId: 6);
    expect(wire.requests.last.path, '/admin/support/cases');
    expect(wire.requests.last.queryParameters, {'page': 2, 'per_page': 40,
      'kind': 'report', 'status': 'open', 'escalated': 1,
      'assigned_to_me': 1, 'assigned_to_user_id': 6});
    expect(admin.items.single.id, 31);
    await expectLater(repository.mine(perPage: 51), throwsArgumentError);
    await expectLater(repository.adminCases(perPage: 101), throwsArgumentError);
    await expectLater(repository.mine(page: 0), throwsArgumentError);
    expect(wire.pages, [2, 2]);
  });

  for (final admin in [false, true]) {
    final surface = admin ? 'admin cases' : 'my cases';
    test('$surface rejects missing and mismatched metadata', () async {
      var body = <String, dynamic>{'data': <Object>[]};
      final wire = _Wire((_) async => body);
      final container = await _container(wire);
      final repository = container.read(supportRepositoryProvider);
      await expectLater(admin ? repository.adminCases() : repository.mine(), throwsStateError);
      body = _page(1, []);
      await expectLater(admin ? repository.adminCases(page: 2) : repository.mine(page: 2), throwsStateError);
    });

    test('$surface does not send a request after credentials cross account boundary', () async {
      final credentials = _Credentials()..pending = Completer<void>();
      final wire = _Wire((_) async => _page(1, [_case(1)]));
      final container = await _container(wire, credentials: credentials);
      final repository = container.read(supportRepositoryProvider);
      final request = admin ? repository.adminCases() : repository.mine();
      final rejected = expectLater(request, throwsStateError);
      (container.read(authControllerProvider.notifier) as _Auth).change(7);
      credentials.pending!.complete();
      await rejected;
      expect(wire.requests, isEmpty);
    });

    test('$surface details cannot acquire replacement-session credentials', () async {
      final credentials = _Credentials()..pending = Completer<void>();
      final wire = _Wire((_) async => {'data': {..._case(1), 'description': 'Private details'}});
      final container = await _container(wire, credentials: credentials);
      final repository = container.read(supportRepositoryProvider);
      final rejected = expectLater(admin ? repository.adminDetails(1) : repository.details(1), throwsStateError);
      Stage6SecureSessionStore.instance.beginSessionChange();
      credentials.pending!.complete();
      await rejected;
      expect(wire.requests, isEmpty);
    });

    testWidgets('$surface retries page two in place, deduplicates and stops at the end', (tester) async {
      final size = admin ? 40 : 30;
      var fail = true;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 1) {
          return _page(1, [for (var id = 1; id <= size; id++) _case(id)], last: 2, total: size + 1);
        }
        if (fail) throw _failure(request, 503);
        return _page(2, [_case(size, subject: 'Updated last case'), _case(size + 1)], last: 2, total: size + 1);
      });
      await _open(tester, wire, admin: admin);
      await _next(tester);
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2]);
      expect(find.byType(AppErrorState), findsNothing);
      await tester.scrollUntilVisible(find.text('إعادة المحاولة'), 120,
        scrollable: _verticalList.first, maxScrolls: 5);
      // ensureVisible updates scroll offset; render the new layout before hit testing.
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(_verticalList.first).position.pixels, greaterThan(1000));
      expect(find.text('إعادة المحاولة').hitTestable(), findsOneWidget);
      fail = false;
      await tester.tap(find.text('إعادة المحاولة').hitTestable());
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      await tester.scrollUntilVisible(find.byKey(ValueKey('support-case-${size + 1}')),
        200, scrollable: _verticalList.first);
      expect(find.text('Updated last case'), findsOneWidget);
      expect(find.byKey(ValueKey('support-case-$size')), findsOneWidget);
      expect(find.byKey(const ValueKey('support-cases-more')), findsNothing);
      await tester.drag(_verticalList.first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      if (admin) expect(wire.requests.where((r) => r.path.endsWith('/summary')).length, 1);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('support-case-1')),
        -600, scrollable: _verticalList.first, maxScrolls: 50);
      expect(find.byKey(const ValueKey('support-case-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$surface clears retained rows on page-two denial', (tester) async {
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 2) throw _failure(request, 403);
        return _page(1, [_case(1)], last: 2, total: 2);
      });
      await _open(tester, wire, admin: admin);
      await _next(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('support-case-1')), findsNothing);
      expect(find.byKey(const ValueKey('support-cases-more')), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$surface discards page two when refresh completes first', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var firstPage = 0;
      final wire = _Wire((request) async {
        if (request.queryParameters['page'] == 2) return pending.future;
        firstPage++;
        return firstPage == 1 ? _page(1, [_case(1)], last: 2, total: 2)
          : _page(1, [_case(10)]);
      });
      await _open(tester, wire, admin: admin);
      await _next(tester);
      final refresh = tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      await refresh;
      pending.complete(_page(2, [_case(99)], last: 2));
      await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 1]);
      expect(find.byKey(const ValueKey('support-case-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('support-case-1')), findsNothing);
      expect(find.byKey(const ValueKey('support-case-99')), findsNothing);
    });

    for (final boundary in ['account switch', 'same-account relogin', 'same-ID token replacement']) {
      testWidgets('$surface never opens late private details across $boundary', (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        final wire = _Wire((request) async {
          if (request.path.endsWith('/cases/1')) return pending.future;
          return _page(1, [_case(1)]);
        });
        final container = await _open(tester, wire, admin: admin);
        final row = find.byKey(const ValueKey('support-case-1'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pump();
        expect(wire.requests.where((r) => r.path.endsWith('/cases/1')).length, 1);
        final auth = container.read(authControllerProvider.notifier) as _Auth;
        if (boundary == 'same-ID token replacement') {
          Stage6SecureSessionStore.instance.beginSessionChange();
          auth.change(6);
        } else {
          auth.change(null);
          auth.change(boundary == 'same-account relogin' ? 6 : 7);
        }
        pending.complete({'data': {..._case(1), 'description': 'Private previous-session details'}});
        await tester.pumpAndSettle();
        expect(find.text('Private previous-session details'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$surface hides an already open dialog on same-ID session replacement', (tester) async {
      final wire = _Wire((request) async => request.path.endsWith('/cases/1')
        ? {'data': {..._case(1), 'description': 'Private open-session details'}}
        : _page(1, [_case(1)]));
      final container = await _open(tester, wire, admin: admin);
      final row = find.byKey(const ValueKey('support-case-1'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Private open-session details'), findsOneWidget);
      Stage6SecureSessionStore.instance.beginSessionChange();
      (container.read(authControllerProvider.notifier) as _Auth).change(6);
      await tester.pumpAndSettle();
      expect(find.text('Private open-session details'), findsNothing);
      expect(find.text('تغيّر الحساب'), findsOneWidget);
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$surface keeps loaded rows for same-session account metadata', (tester) async {
      final wire = _Wire((_) async => _page(1, [_case(1)], last: 2, total: 2));
      final container = await _open(tester, wire, admin: admin);
      (container.read(authControllerProvider.notifier) as _Auth).change(6);
      await tester.pumpAndSettle();
      expect(wire.pages, [1]);
      expect(find.byKey(const ValueKey('support-case-1')), findsOneWidget);
    });

    for (final boundary in ['account switch', 'same-account relogin', 'same-ID token replacement']) {
      testWidgets('$surface rejects a late page across $boundary', (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        var firstPage = 0;
        final wire = _Wire((request) async {
          if (request.queryParameters['page'] == 2) return pending.future;
          firstPage++;
          return firstPage == 1 ? _page(1, [_case(1)], last: 2, total: 2)
            : _page(1, [_case(10)]);
        });
        final container = await _open(tester, wire, admin: admin);
        await _next(tester);
        final auth = container.read(authControllerProvider.notifier) as _Auth;
        if (boundary == 'same-ID token replacement') {
          Stage6SecureSessionStore.instance.beginSessionChange();
          auth.change(6);
        } else {
          auth.change(null);
          auth.change(boundary == 'same-account relogin' ? 6 : 7);
        }
        pending.complete(_page(2, [_case(99)], last: 2));
        await tester.pumpAndSettle();
        expect(wire.pages, [1, 2, 1]);
        expect(find.byKey(const ValueKey('support-case-10')), findsOneWidget);
        expect(find.byKey(const ValueKey('support-case-1')), findsNothing);
        expect(find.byKey(const ValueKey('support-case-99')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('admin filter change discards an earlier page two', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final wire = _Wire((request) async {
      if (request.queryParameters['page'] == 2) return pending.future;
      return request.queryParameters['kind'] == 'report' ? _page(1, [_case(10)])
        : _page(1, [_case(1)], last: 2, total: 2);
    });
    await _open(tester, wire, admin: true);
    await _next(tester);
    final filter = find.byType(DropdownButtonFormField<String?>).first;
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('البلاغات').last);
    await tester.pump();
    pending.complete(_page(2, [_case(99)], last: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(wire.requests.where((r) => r.queryParameters.containsKey('page')).last.queryParameters['kind'], 'report');
    expect(find.byKey(const ValueKey('support-case-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-case-99')), findsNothing);
  });
}
